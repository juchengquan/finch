// A live, queryable SQLite connection held open for the session. Unlike
// lib/db/sqlite.ts (which opens a DB only momentarily to (de)serialise the
// store), this keeps the connection so the app can run SQL reads/writes against
// it. The bytes are still persisted to OPFS/file by the backup provider.

import { getSqlite3, execFor, type OO1DB } from './sqlite';
import { applySchema } from './schema';
import { seedDatabase } from './seed';
import type { Exec } from './repo';

export interface LiveDb {
  exec: Exec;
  /** Serialise the whole database to portable `.db` bytes (for OPFS/file). */
  export: () => Uint8Array;
  close: () => void;
}

async function newMemoryDb(): Promise<{ sqlite3: Awaited<ReturnType<typeof getSqlite3>>; db: OO1DB }> {
  const sqlite3 = await getSqlite3();
  const db = new sqlite3.oo1.DB(':memory:') as unknown as OO1DB;
  return { sqlite3, db };
}

function wrap(sqlite3: Awaited<ReturnType<typeof getSqlite3>>, db: OO1DB): LiveDb {
  return {
    exec: execFor(db),
    export: () => sqlite3.capi.sqlite3_js_db_export(db as never),
    close: () => db.close(),
  };
}

/** Create a fresh database with the full schema and seed data. */
export async function createLiveDb(): Promise<LiveDb> {
  const { sqlite3, db } = await newMemoryDb();
  const live = wrap(sqlite3, db);
  await applySchema(live.exec);
  await seedDatabase(live.exec);
  return live;
}

/** Open a live database from previously-exported `.db` bytes (e.g. from OPFS). */
export async function openLiveDb(bytes: Uint8Array): Promise<LiveDb> {
  const sqlite3 = await getSqlite3();
  const db = new sqlite3.oo1.DB() as unknown as OO1DB;
  const p = sqlite3.wasm.allocFromTypedArray(bytes);
  const rc = sqlite3.capi.sqlite3_deserialize(
    db.pointer!,
    'main',
    p,
    bytes.length,
    bytes.length,
    sqlite3.capi.SQLITE_DESERIALIZE_FREEONCLOSE | sqlite3.capi.SQLITE_DESERIALIZE_RESIZEABLE,
  );
  if (rc) throw new Error(`Could not open database (code ${rc})`);
  // Make sure newer schema objects (indexes/triggers) exist on older files.
  const live = wrap(sqlite3, db);
  await applySchema(live.exec);
  return live;
}
