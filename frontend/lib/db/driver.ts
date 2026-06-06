// Cross-runtime SQLite driver. Picks the native engine for the current runtime
// and exposes a minimal shape both ship with. The `Exec` shim (`execFor` below)
// keeps the async query layer running unchanged through either engine.
//
// Engines:
//   - bun:sqlite (Bun, built-in) — used when bun test / bun dev runs the server.
//   - better-sqlite3 (Node, native binding) — production server runtime.
//
// Both expose synchronous `prepare → all/run`, `exec(sql)` for multi-statement
// strings, and a compatible enough `close()`. PRAGMA setting goes through
// the universal `exec('PRAGMA …')` rather than each engine's bespoke
// `pragma()` shape, so the same code drives both.
//
// See plans/FILE_BACKED_DB_PLAN.md §2.3 for the verified findings + §8.2 for
// why we settled on this two-engine pair instead of one.

import type { Exec, Row, SqlBind } from './repo';

/** The slice of either driver we depend on. Keep it tight — engine-specific
 *  features (pragma()/wal_checkpoint(...)) go through `exec(sql)`. */
export interface SqliteDriver {
  exec(sql: string): void;
  prepare(sql: string): SqliteStatement;
  close(): void;
}

export interface SqliteStatement {
  all(...binds: unknown[]): Row[];
  run(...binds: unknown[]): unknown;
}

/** Open a file-backed (or `:memory:`) SQLite database. The returned driver
 *  is sync; callers wrap it with `execFor` to get the async `Exec` shape the
 *  query layer expects. */
export async function openDb(file: string): Promise<SqliteDriver> {
  const bunVersion = (process as { versions?: { bun?: string } }).versions?.bun;
  if (bunVersion) {
    const { Database } = await import('bun:sqlite');
    return new Database(file) as unknown as SqliteDriver;
  }
  const mod = (await import('better-sqlite3')) as unknown as {
    default: new (path: string) => SqliteDriver;
  };
  return new mod.default(file);
}

/** Return the name of the SQLite engine actually loaded, for diagnostics. */
export function driverName(): 'bun:sqlite' | 'better-sqlite3' {
  return (process as { versions?: { bun?: string } }).versions?.bun
    ? 'bun:sqlite'
    : 'better-sqlite3';
}

/** Wrap the sync driver in the async `Exec` shape the existing query layer
 *  uses. The shim routes a query SQL (SELECT / PRAGMA / EXPLAIN / WITH …
 *  SELECT) through `.all()` and everything else through `.run()` — both
 *  engines speak this dialect. Multi-statement schema strings (the canonical
 *  `SCHEMA`) skip prepare entirely via the engine's `exec(sql)` batch path. */
export function execFor(db: SqliteDriver): Exec {
  return async (sql: string, bind?: SqlBind) => {
    const looksMulti = (!bind || bind.length === 0) && /;\s*[^\s;]/.test(sql);
    if (looksMulti) {
      db.exec(sql);
      return [];
    }
    const stmt = db.prepare(sql);
    const args = (bind ?? []) as unknown[];
    // Heuristic: anything starting with SELECT / PRAGMA / EXPLAIN / WITH …
    // returns rows. better-sqlite3's `.all()` throws on writer statements;
    // bun:sqlite's `.all()` returns []. Using the heuristic keeps both happy.
    if (/^\s*(SELECT|PRAGMA|EXPLAIN|WITH)\b/i.test(sql)) {
      return stmt.all(...args) as Row[];
    }
    stmt.run(...args);
    return [];
  };
}

/** The PRAGMA bootstrap from FILE_BACKED_DB_PLAN §3.1. Idempotent;
 *  re-asserted on every connection because foreign_keys / journal_mode are
 *  per-connection in SQLite. */
export function applyPragmaBootstrap(db: SqliteDriver): void {
  db.exec(`
    PRAGMA journal_mode = WAL;
    PRAGMA synchronous  = NORMAL;
    PRAGMA foreign_keys = ON;
    PRAGMA temp_store   = MEMORY;
    PRAGMA cache_size   = -8000;
  `);
}
