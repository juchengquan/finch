// lib/db/domain/_shared/attachment-cleanup.ts — best-effort attachment-file
// cleanup. Called AFTER the DB row(s) are gone: if the unlink fails the
// orphan is harmless.
import { unlink } from 'node:fs/promises';
import { resolveAttachmentPath } from '../../core/paths';

/** Best-effort attachment-file cleanup. Called AFTER the DB row(s) are gone:
 *  if the unlink fails (missing file, EBUSY on Windows in dev, etc.) the
 *  orphan is harmless — `lib/db/queries/attachments.ts` will never surface a
 *  row pointing at it again, and a future vacuum can sweep it. The opposite
 *  order (unlink first, then delete) would risk a phantom DB row pointing
 *  at a missing file. RECEIPT_PHOTOS_PLAN §3.3. */
export async function unlinkAttachmentFiles(relPaths: string[]): Promise<void> {
  if (!relPaths.length) return;
  for (const rel of relPaths) {
    const abs = resolveAttachmentPath(rel);
    if (!abs) continue;
    await unlink(abs).catch(() => {});
  }
}
