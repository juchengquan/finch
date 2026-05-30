// Thin client for the server database API. The server owns the authoritative
// SQLite file; the store is a mirror hydrated from these calls.

import type { ProjectedState } from '@/lib/db/repo';

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

export async function fetchDbInfo(): Promise<{ path: string }> {
  const res = await fetch(api('db-info'), { cache: 'no-store' });
  if (!res.ok) throw new Error(`GET /api/db-info ${res.status}`);
  return (await res.json()) as { path: string };
}
