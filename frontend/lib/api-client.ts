// Thin client for the server database API. The server owns the authoritative
// SQLite file; the store is a mirror hydrated from these calls.

import type { PersistState } from '@/lib/db/repo';

export async function fetchState(): Promise<PersistState> {
  const res = await fetch('/api/state', { cache: 'no-store' });
  if (!res.ok) throw new Error(`GET /api/state ${res.status}`);
  return (await res.json()) as PersistState;
}

export async function mutate(action: string, args?: Record<string, unknown>): Promise<PersistState> {
  const res = await fetch('/api/mutate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, args }),
  });
  if (!res.ok) throw new Error(`POST /api/mutate (${action}) ${res.status}`);
  return (await res.json()) as PersistState;
}

export async function fetchDbInfo(): Promise<{ path: string }> {
  const res = await fetch('/api/db-info', { cache: 'no-store' });
  if (!res.ok) throw new Error(`GET /api/db-info ${res.status}`);
  return (await res.json()) as { path: string };
}
