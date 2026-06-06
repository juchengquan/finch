// Resolved server-side filesystem paths for the DB and its companion folders.
//
// Kept separate from `lib/db/server.ts` so test runtimes (bun) can import these
// helpers without pulling in the `better-sqlite3`-bound server module.
// RECEIPT_PHOTOS_PLAN §3.1.

import path from 'node:path';

/** Directory housing the SQLite file + WAL sidecars + the attachments folder.
 *  Matches the resolution `lib/db/server.ts` uses internally; this is the
 *  exported, dep-free version. */
export function dbDir(): string {
  return process.env.FINCH_DB_DIR || path.join(process.cwd(), '.data');
}

/** Filesystem root for receipt attachments. Created lazily on first upload. */
export function attachmentsDir(): string {
  return path.join(dbDir(), 'attachments');
}

/** Resolve a stored `rel_path` (e.g. `attachments/<txn>/<id>.jpg`) to its
 *  absolute on-disk path, **guarding against path traversal** — the resolved
 *  path MUST live under `attachmentsDir()`. Returns null when the guard fails
 *  (the route layer should refuse to serve / unlink such a path). */
export function resolveAttachmentPath(relPath: string): string | null {
  const root = attachmentsDir();
  const abs = path.resolve(dbDir(), relPath);
  if (abs !== root && !abs.startsWith(root + path.sep)) return null;
  return abs;
}
