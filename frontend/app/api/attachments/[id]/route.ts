import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { Readable } from 'node:stream';
import { getServerDb } from '@/lib/db/core/server';
import { getAttachmentFile } from '@/lib/db/queries/attachments';
import { resolveAttachmentPath } from '@/lib/db/core/paths';

// Serve route for receipt attachments. RECEIPT_PHOTOS_PLAN §5.2.
//
// Looks up the pointer row by id, applies the path-traversal guard, stats
// the on-disk file, then streams the bytes back with the stored mime type
// and the original filename in Content-Disposition. WAL-mode reads are
// snapshot-consistent without a mutex, so this bypasses the serialize() the
// mutation path needs.

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

// Strip characters that would break the Content-Disposition header. Spec
// allows quoted strings but not CR/LF/quote inside; we collapse them to '_'.
function safeFilename(name: string): string {
  return name.replace(/[\r\n"\\]/g, '_');
}

function fallbackFilename(id: string, kind: 'image' | 'pdf'): string {
  return `attachment-${id}.${kind === 'pdf' ? 'pdf' : 'jpg'}`;
}

export async function GET(
  _req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    const { id } = await params;
    if (!id) return new Response('Missing id', { status: 400 });

    const db = await getServerDb();
    const row = await getAttachmentFile(db.exec, id);
    if (!row) return new Response('Not found', { status: 404 });

    // Defense-in-depth: even though rel_path is composed server-side at
    // upload time, the resolver refuses anything that escapes the
    // attachments root before any fs call (§5.2 + §10 path-traversal risk).
    const abs = resolveAttachmentPath(row.relPath);
    if (!abs) return new Response('Forbidden', { status: 403 });

    // Stat first — the row may outlive the file in rare crash windows; treat
    // a missing file the same as a missing row, with a 404.
    let actualSize: number;
    try {
      const s = await stat(abs);
      if (!s.isFile()) return new Response('Not found', { status: 404 });
      actualSize = s.size;
    } catch {
      return new Response('Not found', { status: 404 });
    }

    const filename = safeFilename(row.originalFilename || fallbackFilename(row.id, row.kind));

    // Stream rather than buffer: receipts can be ~50 MB and a single user
    // can have several open viewers/tabs at once.
    const nodeStream = createReadStream(abs);
    // Readable.toWeb returns Node's `stream/web` ReadableStream; TS sees the
    // global Web `ReadableStream` as a distinct type. They're the same
    // runtime object — cast via `unknown` is the standard Node 22+ workaround.
    const webStream = Readable.toWeb(nodeStream) as unknown as ReadableStream<Uint8Array>;

    return new Response(webStream, {
      status: 200,
      headers: {
        'Content-Type': row.mimeType,
        'Content-Length': String(actualSize),
        'Content-Disposition': `inline; filename="${filename}"`,
        // Receipts are personal; never let an intermediate cache hold them.
        'Cache-Control': 'private, max-age=0, must-revalidate',
      },
    });
  } catch (err) {
    console.error('GET /api/attachments/[id] failed', err);
    return new Response('Server error', { status: 500 });
  }
}
