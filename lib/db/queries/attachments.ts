// Receipt attachments — pointer rows only. RECEIPT_PHOTOS_PLAN §2.
//
// Bytes are stored on the server filesystem under the FINCH_DB_DIR-rooted
// `attachments/` directory; this module only handles the pointer rows in
// the DB. The file-aware callers are the upload route (`/api/attachments`),
// the serve route (`GET /api/attachments/:id`), and the `removeAttachment`
// mutation — all of which look up `rel_path` via `getAttachmentFile`
// before reading/unlinking the file on disk.

import type { Exec } from '@/lib/db/repo';

/** Client-projected attachment shape. `rel_path` is **deliberately omitted**
 *  so the client cannot construct a file URL; clients reach the bytes via
 *  GET /api/attachments/:id. */
export interface Attachment {
  id: string;
  ledgerId: string;
  transactionId: string;
  kind: 'image' | 'pdf';
  mimeType: string;
  byteSize: number;
  sha256: string;
  originalFilename: string | null;
  createdAt: string;
}

/** Server-side row including `rel_path`. Never sent to the client. */
export interface AttachmentFile extends Attachment {
  relPath: string;
}

/** List attachments for the projection. Optionally scope to a ledger. */
export async function listAttachments(exec: Exec, ledgerId?: string): Promise<Attachment[]> {
  const rows = await exec(
    ledgerId
      ? `SELECT id, ledger_id, transaction_id, kind, mime_type, byte_size,
                sha256, original_filename, created_at
           FROM transaction_attachments
           WHERE ledger_id = ?
           ORDER BY created_at`
      : `SELECT id, ledger_id, transaction_id, kind, mime_type, byte_size,
                sha256, original_filename, created_at
           FROM transaction_attachments
           ORDER BY ledger_id, created_at`,
    ledgerId ? [ledgerId] : [],
  );
  return rows.map(rowToAttachment);
}

/** Server-side variant of `listAttachments` that includes `rel_path`. Used by
 *  the pack-export path (PACK_FORMAT_PLAN §4). Never sent to the client. */
export async function listAttachmentFiles(exec: Exec): Promise<AttachmentFile[]> {
  const rows = await exec(
    `SELECT * FROM transaction_attachments ORDER BY ledger_id, created_at`,
  );
  return rows.map((r) => ({ ...rowToAttachment(r), relPath: String(r.rel_path) }));
}

/** Full row including `rel_path` for the serve route + the deletion path.
 *  Returns null when no row matches the id. */
export async function getAttachmentFile(exec: Exec, id: string): Promise<AttachmentFile | null> {
  const rows = await exec('SELECT * FROM transaction_attachments WHERE id = ?', [id]);
  if (!rows.length) return null;
  const r = rows[0];
  return { ...rowToAttachment(r), relPath: String(r.rel_path) };
}

/** Rel-paths of every attachment on one transaction. Used by deleteTransaction
 *  to collect file paths *before* the FK CASCADE drops the rows, so the
 *  caller can unlink them after COMMIT. */
export async function getAttachmentRelPathsForTransaction(
  exec: Exec,
  transactionId: string,
): Promise<string[]> {
  const rows = await exec(
    'SELECT rel_path FROM transaction_attachments WHERE transaction_id = ?',
    [transactionId],
  );
  return rows.map((r) => String(r.rel_path));
}

/** Rel-paths of every attachment in one ledger. Mirrors the per-transaction
 *  helper, for the future "delete ledger" cascade. */
export async function getAttachmentRelPathsForLedger(
  exec: Exec,
  ledgerId: string,
): Promise<string[]> {
  const rows = await exec(
    'SELECT rel_path FROM transaction_attachments WHERE ledger_id = ?',
    [ledgerId],
  );
  return rows.map((r) => String(r.rel_path));
}

/** Count attachments on one transaction (for the per-tx cap check at upload). */
export async function countAttachmentsForTransaction(
  exec: Exec,
  transactionId: string,
): Promise<number> {
  const rows = await exec(
    'SELECT COUNT(*) AS n FROM transaction_attachments WHERE transaction_id = ?',
    [transactionId],
  );
  return Number(rows[0]?.n ?? 0);
}

/** Insert a new attachment row. Called by the upload route AFTER the file is
 *  durably on disk; this row insert is the commit point for the upload. */
export interface InsertAttachmentParams {
  id: string;
  ledgerId: string;
  transactionId: string;
  kind: 'image' | 'pdf';
  relPath: string;
  mimeType: string;
  byteSize: number;
  sha256: string;
  originalFilename: string | null;
}

export async function insertAttachment(exec: Exec, p: InsertAttachmentParams): Promise<void> {
  await exec(
    `INSERT INTO transaction_attachments
       (id, ledger_id, transaction_id, kind, rel_path, mime_type, byte_size,
        sha256, original_filename, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))`,
    [
      p.id,
      p.ledgerId,
      p.transactionId,
      p.kind,
      p.relPath,
      p.mimeType,
      p.byteSize,
      p.sha256,
      p.originalFilename,
    ],
  );
}

/** Delete one attachment row. The caller is responsible for unlinking the
 *  file at `rel_path` — look it up via `getAttachmentFile` first. */
export async function deleteAttachment(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM transaction_attachments WHERE id = ?', [id]);
}

// ---------------------------------------------------------------------------
// Row mapper
// ---------------------------------------------------------------------------

function rowToAttachment(r: Record<string, unknown>): Attachment {
  const kind = String(r.kind);
  if (kind !== 'image' && kind !== 'pdf') {
    throw new Error(`Invalid attachment kind: ${kind}`);
  }
  return {
    id: String(r.id),
    ledgerId: String(r.ledger_id),
    transactionId: String(r.transaction_id),
    kind,
    mimeType: String(r.mime_type),
    byteSize: Number(r.byte_size),
    sha256: String(r.sha256),
    originalFilename: r.original_filename == null ? null : String(r.original_filename),
    createdAt: String(r.created_at),
  };
}
