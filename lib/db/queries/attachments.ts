// Receipt attachments — pointer rows only. RECEIPT_PHOTOS_PLAN §2.
//
// Bytes are stored on the server filesystem under the FINCH_DB_DIR-rooted
// `attachments/` directory; this module only handles the pointer rows in
// the DB. The file-aware callers are the upload route (`/api/attachments`),
// the serve route (`GET /api/attachments/:id`), and the `removeAttachment`
// mutation — all of which look up `rel_path` via `getAttachmentFile`
// before reading/unlinking the file on disk.
//
// Table flip: transaction_attachments → entry_attachments (DOUBLE_ENTRY_PLAN §7).
// Any function that takes a `transactionId` (= account-posting id from the
// client) resolves it via `resolveEntryRef` first so the API routes keep
// their existing contract unchanged.

import type { Exec } from '../core/repo';
import { resolveEntryRef } from '../core/entries';

/** Client-projected attachment shape. `rel_path` is **deliberately omitted**
 *  so the client cannot construct a file URL; clients reach the bytes via
 *  GET /api/attachments/:id. */
export interface Attachment {
  id: string;
  ledgerId: string;
  // transactionId carries the account-posting id as projected by state.ts;
  // the entry→posting remap lives in state.ts's projection.
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
      ? `SELECT id, ledger_id, entry_id, kind, mime_type, byte_size,
                sha256, original_filename, created_at
           FROM entry_attachments
           WHERE ledger_id = ?
           ORDER BY created_at`
      : `SELECT id, ledger_id, entry_id, kind, mime_type, byte_size,
                sha256, original_filename, created_at
           FROM entry_attachments
           ORDER BY ledger_id, created_at`,
    ledgerId ? [ledgerId] : [],
  );
  return rows.map(rowToAttachment);
}

/** Server-side variant of `listAttachments` that includes `rel_path`. Used by
 *  the pack-export path (PACK_FORMAT_PLAN §4). Never sent to the client. */
export async function listAttachmentFiles(exec: Exec): Promise<AttachmentFile[]> {
  const rows = await exec(
    `SELECT * FROM entry_attachments ORDER BY ledger_id, created_at`,
  );
  return rows.map((r) => ({ ...rowToAttachment(r), relPath: String(r.rel_path) }));
}

/** Full row including `rel_path` for the serve route + the deletion path.
 *  Returns null when no row matches the id. */
export async function getAttachmentFile(exec: Exec, id: string): Promise<AttachmentFile | null> {
  const rows = await exec('SELECT * FROM entry_attachments WHERE id = ?', [id]);
  if (!rows.length) return null;
  const r = rows[0];
  return { ...rowToAttachment(r), relPath: String(r.rel_path) };
}

/** Rel-paths of every attachment on one transaction (by posting-or-entry id).
 *  Resolves via resolveEntryRef so API routes that send account-posting ids
 *  keep working unchanged. Used by deleteTransaction to collect file paths
 *  BEFORE the FK CASCADE fires. */
export async function getAttachmentRelPathsForTransaction(
  exec: Exec,
  transactionId: string,
): Promise<string[]> {
  const ref = await resolveEntryRef(exec, transactionId);
  if (!ref) return [];
  const rows = await exec(
    'SELECT rel_path FROM entry_attachments WHERE entry_id = ?',
    [ref.entryId],
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
    'SELECT rel_path FROM entry_attachments WHERE ledger_id = ?',
    [ledgerId],
  );
  return rows.map((r) => String(r.rel_path));
}

/** Count attachments on one transaction (for the per-tx cap check at upload).
 *  Resolves account-posting id to entry id via resolveEntryRef. */
export async function countAttachmentsForTransaction(
  exec: Exec,
  transactionId: string,
): Promise<number> {
  const ref = await resolveEntryRef(exec, transactionId);
  if (!ref) return 0;
  const rows = await exec(
    'SELECT COUNT(*) AS n FROM entry_attachments WHERE entry_id = ?',
    [ref.entryId],
  );
  return Number(rows[0]?.n ?? 0);
}

/** Insert a new attachment row. Called by the upload route AFTER the file is
 *  durably on disk; this row insert is the commit point for the upload.
 *  `transactionId` is forwarded from the client (may be account-posting id);
 *  we resolve to entry_id via resolveEntryRef. */
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
  const ref = await resolveEntryRef(exec, p.transactionId);
  const entryId = ref?.entryId ?? p.transactionId;
  await exec(
    `INSERT INTO entry_attachments
       (id, ledger_id, entry_id, kind, rel_path, mime_type, byte_size,
        sha256, original_filename, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))`,
    [
      p.id,
      p.ledgerId,
      entryId,
      p.kind,
      p.relPath,
      p.mimeType,
      p.byteSize,
      p.sha256,
      p.originalFilename,
    ],
  );
}

/** Resolve the client's transaction ref (account-posting id or entry id) to
 *  the owning entry + its ledger. Null when nothing matches. Used by the
 *  upload route to validate existence and get ledgerId before the file write.
 *  (The entry→posting remap lives in state.ts's projection.) */
export async function resolveAttachmentTarget(
  exec: Exec,
  transactionId: string,
): Promise<{ entryId: string; ledgerId: string } | null> {
  const ref = await resolveEntryRef(exec, transactionId);
  if (!ref) return null;
  const [e] = await exec('SELECT id, ledger_id FROM entries WHERE id = ?', [ref.entryId]);
  if (!e) return null;
  return { entryId: String(e.id), ledgerId: String(e.ledger_id) };
}

/** Delete one attachment row. The caller is responsible for unlinking the
 *  file at `rel_path` — look it up via `getAttachmentFile` first. */
export async function deleteAttachment(exec: Exec, id: string): Promise<void> {
  await exec('DELETE FROM entry_attachments WHERE id = ?', [id]);
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
    // entry_attachments stores entry_id; state.ts's projection remaps this
    // to the account-posting id so Attachment.transactionId matches Tx.id.
    transactionId: String(r.entry_id),
    kind,
    mimeType: String(r.mime_type),
    byteSize: Number(r.byte_size),
    sha256: String(r.sha256),
    originalFilename: r.original_filename == null ? null : String(r.original_filename),
    createdAt: String(r.created_at),
  };
}
