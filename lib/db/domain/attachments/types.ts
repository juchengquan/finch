// lib/db/domain/attachments/types.ts — public row + input/patch shapes for
// the attachments domain. Keep this file free of SQL imports — it should
// be safe to import from any layer (UI components, route handlers, app_state)
// without pulling in the DB driver.

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
