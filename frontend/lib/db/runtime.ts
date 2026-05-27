// A live, in-memory relational DB the UI can query, rebuilt from the current
// store state. The store stays the working source of truth; this is the
// queryable projection of it (the same relational shape that gets persisted to
// the OPFS file). Components read through it via components/db-provider.tsx.

import { getSqlite3, execFor, type OO1DB } from './sqlite';
import { applySchema } from './schema';
import { buildState } from './state';
import type { LiveDb } from './client';
import type { PersistState } from './repo';

/** Build a fresh live DB containing the given store state. */
export async function buildLiveDb(state: PersistState): Promise<LiveDb> {
  const sqlite3 = await getSqlite3();
  const db = new sqlite3.oo1.DB(':memory:') as unknown as OO1DB;
  const live: LiveDb = {
    exec: execFor(db),
    export: () => sqlite3.capi.sqlite3_js_db_export(db as never),
    close: () => db.close(),
  };
  await applySchema(live.exec);
  await buildState(live.exec, state);
  return live;
}
