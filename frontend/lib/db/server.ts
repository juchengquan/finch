import fs from 'node:fs/promises';
import path from 'node:path';
import { getSqlite3, execFor, type OO1DB } from './sqlite';
import { applySchema, migrate } from './schema';
import { seedDatabase } from './seed';
import { projectState } from './state';
import type { Exec, ProjectedState } from './repo';

// The authoritative database: a single in-memory SQLite connection held by the
// Node server for the life of the process, loaded from a file on startup and
// written back to that file after every change. The file location comes from
// env vars so it can point at persistent storage:
//   FINCH_DB_DIR   directory (default: <cwd>/.data)
//   FINCH_DB_FILE  filename  (default: finch.sqlite3)

function dbFile(): { dir: string; full: string } {
  const dir = process.env.FINCH_DB_DIR || path.join(process.cwd(), '.data');
  const file = process.env.FINCH_DB_FILE || 'finch.sqlite3';
  return { dir, full: path.join(dir, file) };
}

interface ServerDb {
  exec: Exec;
  persist: () => Promise<void>;
  file: string;
}

let _db: Promise<ServerDb> | null = null;

async function open(): Promise<ServerDb> {
  const sqlite3 = await getSqlite3();
  const { dir, full } = dbFile();
  await fs.mkdir(dir, { recursive: true });

  let bytes: Uint8Array | null = null;
  try {
    const buf = await fs.readFile(full);
    if (buf.byteLength > 0) bytes = new Uint8Array(buf);
  } catch {
    // No file yet — first run.
  }

  let db: OO1DB;
  if (bytes) {
    db = new sqlite3.oo1.DB() as unknown as OO1DB;
    const p = sqlite3.wasm.allocFromTypedArray(bytes);
    const rc = sqlite3.capi.sqlite3_deserialize(
      db.pointer!,
      'main',
      p,
      bytes.length,
      bytes.length,
      sqlite3.capi.SQLITE_DESERIALIZE_FREEONCLOSE | sqlite3.capi.SQLITE_DESERIALIZE_RESIZEABLE,
    );
    if (rc) throw new Error(`Could not open ${full} (code ${rc})`);
    await applySchema(execFor(db)); // ensure newer objects exist on older files
    await migrate(execFor(db), { fresh: false }); // apply column migrations to old files
  } else {
    db = new sqlite3.oo1.DB(':memory:') as unknown as OO1DB;
    const exec = execFor(db);
    await applySchema(exec);
    await seedDatabase(exec);
    await migrate(exec, { fresh: true }); // stamp the version on the new file
  }

  const exec = execFor(db);
  const persist = async () => {
    const out = sqlite3.capi.sqlite3_js_db_export(db as never);
    // Write atomically: temp file then rename, so a crash can't truncate the db.
    const tmp = `${full}.tmp`;
    await fs.writeFile(tmp, Buffer.from(out));
    await fs.rename(tmp, full);
  };
  await persist(); // make sure the file exists from the first boot
  return { exec, persist, file: full };
}

/** The shared server database, opened once per process. */
export function getServerDb(): Promise<ServerDb> {
  if (!_db) _db = open();
  return _db;
}

/** Read the full app state from the server database. */
export async function readState(): Promise<ProjectedState> {
  const { exec } = await getServerDb();
  return projectState(exec);
}

/** Run a write against the server database, persist to file, return new state. */
export async function withWrite(fn: (exec: Exec) => Promise<void>): Promise<ProjectedState> {
  const db = await getServerDb();
  await fn(db.exec);
  await db.persist();
  return projectState(db.exec);
}
