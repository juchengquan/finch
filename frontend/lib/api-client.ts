// Thin client for the server database API. The server owns the authoritative
// SQLite file; the store is a mirror hydrated from these calls.

import type { ProjectedState } from './db/core/repo';
import { fromWireError } from '@/lib/i18n-error';
import type { DbInfoResponse } from '@/app/api/db-info/route';
import { BASE_PATH } from '@/lib/base-path';
import { API_REQUEST_HEADER } from '@/lib/api-guard';

function api(path: string) {
  return `${BASE_PATH}/api/${path}`;
}

/** fetch() for `/api/<path>`: adds the base path and the header proxy.ts
 *  requires on state-changing requests (lib/api-guard.ts). Every client call
 *  to the API goes through here. */
export function apiFetch(path: string, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  headers.set(API_REQUEST_HEADER, '1');
  return fetch(api(path), { ...init, headers });
}

export async function fetchState(): Promise<ProjectedState> {
  const res = await apiFetch('state', { cache: 'no-store' });
  if (!res.ok) throw new Error(`GET /api/state ${res.status}`);
  return (await res.json()) as ProjectedState;
}

export async function mutate(action: string, args?: Record<string, unknown>): Promise<ProjectedState> {
  const res = await apiFetch('mutate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, args }),
  });
  if (!res.ok) throw await responseError(res, `${res.status}`);
  return (await res.json()) as ProjectedState;
}

/** The Error a failed API response carries: `{ error: { message, code?, params? } }`
 *  (lib/api-error.ts), decoded by fromWireError so `toast.error(err.message)`
 *  works and `.code`/`.params` are there for callers that translate. A body
 *  that isn't JSON gives `fallback`. */
export async function responseError(res: Response, fallback: string): Promise<Error> {
  try {
    const body = (await res.json()) as { error?: unknown };
    if (body?.error != null) return fromWireError(body.error);
  } catch {
    // not JSON
  }
  return new Error(fallback);
}

export async function fetchDbInfo(): Promise<DbInfoResponse> {
  const res = await apiFetch('db-info', { cache: 'no-store' });
  if (!res.ok) throw new Error(`GET /api/db-info ${res.status}`);
  return (await res.json()) as DbInfoResponse;
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
  const res = await apiFetch('attachments', { method: 'POST', body: form });
  if (!res.ok) throw await responseError(res, `${res.status}`);
  return (await res.json()) as ProjectedState;
}

/** Browser URL that serves the bytes of one attachment, with the stored
 *  mime + the original filename in Content-Disposition. */
export function attachmentUrl(id: string): string {
  return api(`attachments/${encodeURIComponent(id)}`);
}
