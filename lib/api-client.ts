// Thin client for the server database API. The server owns the authoritative
// SQLite file; the store is a mirror hydrated from these calls.

import type { ProjectedState } from '@/lib/db/repo';
import { fromWireError } from '@/lib/i18n-error';

const base = process.env.NODE_ENV === 'development' ? '' : (process.env.NEXT_PUBLIC_BASE_PATH || '/finch');

function api(path: string) {
  return `${base}/api/${path}`;
}

export async function fetchState(): Promise<ProjectedState> {
  const res = await fetch(api('state'), { cache: 'no-store' });
  if (!res.ok) throw new Error(`GET /api/state ${res.status}`);
  return (await res.json()) as ProjectedState;
}

export async function mutate(action: string, args?: Record<string, unknown>): Promise<ProjectedState> {
  const res = await fetch(api('mutate'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, args }),
  });
  if (!res.ok) {
    // Errors may arrive as { error: string } (legacy throws / route layer
    // problems) or { error: { code, params, message } } (I18nError from a
    // migrated mutation site). I18N_PLAN §4.4 — fromWireError keeps
    // existing `toast.error(err.message)` callers working AND attaches
    // .code/.params for callers that opt into client-side localisation.
    let wire: unknown = `${res.status}`;
    try {
      const body = (await res.json()) as { error?: unknown };
      if (body?.error != null) wire = body.error;
    } catch {
      // non-JSON error body
    }
    throw fromWireError(wire);
  }
  return (await res.json()) as ProjectedState;
}

export async function fetchDbInfo(): Promise<{ path: string }> {
  const res = await fetch(api('db-info'), { cache: 'no-store' });
  if (!res.ok) throw new Error(`GET /api/db-info ${res.status}`);
  return (await res.json()) as { path: string };
}

/** Upload a receipt attachment (image / PDF) for a transaction. POSTs
 *  multipart/form-data to `/api/attachments`; the server processes the
 *  bytes (EXIF strip + JPEG transcode for images; passthrough for PDFs),
 *  writes the file under FINCH_DB_DIR, inserts the pointer row, and
 *  returns the fresh ProjectedState — same shape as `/api/mutate`.
 *  RECEIPT_PHOTOS_PLAN §5.1. */
export async function uploadAttachment(
  transactionId: string,
  file: File,
): Promise<ProjectedState> {
  const form = new FormData();
  form.append('transactionId', transactionId);
  form.append('file', file, file.name);
  const res = await fetch(api('attachments'), { method: 'POST', body: form });
  if (!res.ok) {
    let message = `${res.status}`;
    try {
      const body = (await res.json()) as { error?: string };
      if (body?.error) message = body.error;
    } catch {
      // non-JSON error body
    }
    throw new Error(message);
  }
  return (await res.json()) as ProjectedState;
}

/** Browser URL that serves the bytes of one attachment, with the stored
 *  mime + the original filename in Content-Disposition. */
export function attachmentUrl(id: string): string {
  return api(`attachments/${encodeURIComponent(id)}`);
}
