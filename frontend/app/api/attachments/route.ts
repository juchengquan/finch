import { NextResponse } from 'next/server';
import { randomUUID, createHash } from 'node:crypto';
import { writeFile, mkdir, rename, unlink } from 'node:fs/promises';
import path from 'node:path';
import { withWrite } from '@/lib/db/core/server';
import {
  insertAttachment,
  countAttachmentsForTransaction,
  resolveAttachmentTarget,
} from '@/lib/db/queries/attachments';
import { resolveAttachmentPath } from '@/lib/db/core/paths';
import { detectFile, processBytes } from '@/lib/attachments/process';

// Multipart upload route for receipt photos / PDFs. RECEIPT_PHOTOS_PLAN §5.1.
// Body: multipart/form-data with parts:
//   - `transactionId` (text)
//   - `file`          (binary)
// Response: { state: ProjectedState } on success; { error } on failure.
// Returns 200 with the fresh projected state (same shape as /api/mutate) so
// the client can adopt the new attachments slice without a second request.

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

function maxBytes(): number {
  const v = Number(process.env.FINCH_ATTACHMENT_MAX_BYTES);
  return Number.isFinite(v) && v > 0 ? v : 50 * 1024 * 1024; // 50 MB default
}

function maxPerTx(): number {
  const v = Number(process.env.FINCH_ATTACHMENT_MAX_PER_TX);
  return Number.isFinite(v) && v > 0 ? v : 20;
}

class HttpError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
  }
}

export async function POST(req: Request) {
  try {
    const form = await req.formData();

    const transactionId = form.get('transactionId');
    const file = form.get('file');

    // Validation ladder #1: shape of the multipart body.
    if (typeof transactionId !== 'string' || !transactionId) {
      throw new HttpError(400, 'Missing transactionId');
    }
    if (!(file instanceof File)) {
      throw new HttpError(400, 'Missing file');
    }
    if (file.size === 0) {
      throw new HttpError(400, 'File is empty');
    }
    if (file.size > maxBytes()) {
      throw new HttpError(
        413,
        `File exceeds the ${(maxBytes() / 1024 / 1024).toFixed(0)} MB limit`,
      );
    }

    // Validation ladder #2: magic-byte sniff. Defends against renamed
    // extensions (a .exe relabelled to .jpg). Plan §10.
    const rawBuf = Buffer.from(await file.arrayBuffer());
    const detected = await detectFile(rawBuf);
    if (!detected) {
      throw new HttpError(400, 'Unsupported file type — images and PDFs only');
    }

    // Validation ladder #3: the rest needs DB access (does the txn exist?
    // are we under the per-tx cap?). Bundle with the insert in withWrite so
    // a failure here triggers ROLLBACK and the file write below never runs.
    const state = await withWrite(async (exec) => {
      // Resolve the client's transactionId (account-posting id or entry id)
      // to the owning entry + ledger. The legacy `transactions` table is gone;
      // resolveAttachmentTarget looks up postings → entries (§4.2).
      const target = await resolveAttachmentTarget(exec, transactionId);
      if (!target) {
        throw new HttpError(404, 'Transaction not found');
      }
      const { entryId, ledgerId } = target;

      const existingCount = await countAttachmentsForTransaction(exec, transactionId);
      if (existingCount >= maxPerTx()) {
        throw new HttpError(400, `Maximum ${maxPerTx()} attachments per transaction`);
      }

      // Process bytes (image → JPEG with EXIF stripped + orientation applied;
      // PDF passthrough). Outside-of-DB CPU work, but still inside the
      // serialized write — receipts uploads aren't a high-concurrency path.
      const processed = await processBytes(rawBuf, detected.kind);

      // Compose paths + integrity hash.
      const id = randomUUID();
      const sha256 = createHash('sha256').update(processed.bytes).digest('hex');
      // path.posix.join keeps the rel_path forward-slashed for cross-platform
      // pack interop (PACK_FORMAT_PLAN); the on-disk path uses the OS sep
      // via resolveAttachmentPath.
      const relPath = path.posix.join('attachments', entryId, `${id}.${processed.outExt}`);
      const absPath = resolveAttachmentPath(relPath);
      if (!absPath) {
        // Defense-in-depth — should never trip with a server-built rel_path.
        throw new HttpError(500, 'Path resolution failed');
      }
      const tmpPath = `${absPath}.tmp`;

      // Atomic file write: tmp → fsync (via writeFile) → rename. If anything
      // fails between writeFile and the DB insert, unlink the tmp/abs path
      // so we don't leak an orphan into a ROLLBACK.
      await mkdir(path.dirname(absPath), { recursive: true });
      await writeFile(tmpPath, processed.bytes);
      try {
        await rename(tmpPath, absPath);
      } catch (err) {
        await unlink(tmpPath).catch(() => {});
        throw err;
      }

      try {
        await insertAttachment(exec, {
          id,
          ledgerId,
          transactionId: entryId,
          kind: processed.outKind,
          relPath,
          mimeType: processed.outMime,
          byteSize: processed.bytes.length,
          sha256,
          originalFilename: file.name || null,
        });
      } catch (err) {
        // Roll back the file write since the DB row won't be there.
        await unlink(absPath).catch(() => {});
        throw err;
      }
    });

    return NextResponse.json(state);
  } catch (err) {
    if (err instanceof HttpError) {
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    const message = err instanceof Error ? err.message : 'Upload failed';
    console.error('POST /api/attachments failed', err);
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
