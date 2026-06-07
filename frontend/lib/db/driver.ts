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

/** Strip string literals, line comments, and block comments before checking
 *  for "real" semicolons. Without this, a SQL like
 *  `GROUP_CONCAT(name, '; ')` would look multi-statement to a naive regex. */
function looksMultiStatement(sql: string): boolean {
  const stripped = sql
    .replace(/'(?:[^']|'')*'/g, '') // single-quoted strings; SQLite escapes ' as ''
    .replace(/--[^\n]*/g, '') // line comments
    .replace(/\/\*[\s\S]*?\*\//g, ''); // block comments
  // A real terminator followed by more non-whitespace content = multi-statement.
  return /;\s*\S/.test(stripped);
}

/** Wrap the sync driver in the async `Exec` shape the existing query layer
 *  uses. Routes single-statement SQL through `prepare` (query → `.all()`,
 *  write → `.run()`); multi-statement schema strings (only the canonical
 *  `SCHEMA` string and the PRAGMA bootstrap qualify) take the engine's
 *  `db.exec(sql)` batch path. */
export function execFor(db: SqliteDriver): Exec {
  return async (sql: string, bind?: SqlBind) => {
    if ((!bind || bind.length === 0) && looksMultiStatement(sql)) {
      db.exec(sql);
      return [];
    }
    const stmt = db.prepare(sql);
    const args = (bind ?? []) as unknown[];
    // Ask the engine whether the prepared statement returns data. better-sqlite3
    // exposes a `reader` flag (true for SELECT / PRAGMA-getter / EXPLAIN /
    // RETURNING-bearing writes, false for INSERT / UPDATE / DELETE / DDL /
    // PRAGMA-setter); the engine's own answer is the ground truth, so the
    // PRAGMA-setter pitfall (`.all()` throws "This statement does not return
    // data. Use run() instead") can't trip us up. bun:sqlite doesn't expose
    // `reader`, so fall through to the prefix heuristic for that engine.
    const reader = (stmt as { reader?: boolean }).reader;
    if (reader === true) {
      return stmt.all(...args) as Row[];
    }
    if (reader === false) {
      stmt.run(...args);
      return [];
    }
    // Fallback heuristic for engines without `reader` (bun:sqlite).
    // PRAGMA *setters* (`PRAGMA foreign_keys = OFF`) MUST go through `.run()`:
    // whether `.all()` also executes a setter is engine-BUILD-specific —
    // macOS bun:sqlite does, the Linux build does not, which silently
    // no-opped the cutover dances' FK toggles in CI (FK-constrained DROPs and
    // RENAMEs then failed mid-dance). `.run()` executes on every build.
    if (/^\s*PRAGMA\b/i.test(sql) && sql.includes('=')) {
      stmt.run(...args);
      return [];
    }
    // Anything starting with SELECT / EXPLAIN / WITH returns rows, as does a
    // PRAGMA *getter* (`PRAGMA foreign_keys`, `PRAGMA table_info(…)`); the
    // remaining statements are writes.
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
    PRAGMA legacy_alter_table = OFF;
    PRAGMA temp_store   = MEMORY;
    PRAGMA cache_size   = -8000;
  `);
  // legacy_alter_table is pinned OFF (modern ALTER semantics: RENAME re-parses
  // every trigger/view) because the DEFAULT differs by bun:sqlite BUILD —
  // macOS ships ON, Linux ships OFF — which made the cutover's rebuild dances
  // pass locally and fail in CI. Pinning it here makes every environment run
  // the strict semantics; the dances explicitly toggle it ON around their
  // RENAMEs (see CATEGORIES_UPGRADE / ACCOUNTS_DROP_OPENING_COLUMNS).
}
