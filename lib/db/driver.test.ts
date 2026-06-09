// Pins for the cross-runtime SQLite shim (lib/db/driver.ts). The Exec shim
// has to decide — without asking the SQL parser — whether a statement is a
// query (route to .all()) or a write (route to .run()). Getting it wrong
// throws on better-sqlite3 ("This statement does not return data. Use run()
// instead") and silently returns [] on bun:sqlite, which is a
// test-green-but-prod-red trap. These tests run under bun:sqlite today, but
// the assertions are about *behaviour* (no throw, return value shape), so the
// same suite catches the bug on better-sqlite3 once a Node test runner is
// available.

import { test, expect } from 'bun:test';
import { openDb, execFor, applyPragmaBootstrap } from './core/driver';
import { applySchema } from './core/schema';
import { freshDb } from './core/test-utils';

test('execFor: PRAGMA setter goes through .run() (no "use run() instead" error)', async () => {
  // The repro for the 500s in /api/state, /api/mutate, /api/db-info. The
  // 2026-06-06 migration step `PRAGMA foreign_keys = OFF` was being routed
  // to .all() by the prefix heuristic, which better-sqlite3 rejects. The
  // fix consults stmt.reader first; this test pins the no-throw contract
  // that the migration relies on.
  const { exec, close } = await freshDb();
  try {
    // Setter form: `PRAGMA name = value` does not return rows.
    await expect(exec('PRAGMA foreign_keys = OFF')).resolves.toEqual([]);
    // Restore for the rest of the suite / future opens.
    await expect(exec('PRAGMA foreign_keys = ON')).resolves.toEqual([]);
  } finally {
    close();
  }
});

test('execFor: PRAGMA getter (table_info) still returns rows through .all()', async () => {
  // The getter form `PRAGMA name` (no `=`) returns rows. Make sure the
  // reader-based routing didn't accidentally turn every PRAGMA into a no-op.
  const { exec, close } = await freshDb();
  try {
    const rows = await exec("PRAGMA table_info('entries')");
    expect(Array.isArray(rows)).toBe(true);
    expect(rows.length).toBeGreaterThan(0);
    expect(rows.some((r) => String(r.name) === 'id')).toBe(true);
  } finally {
    close();
  }
});

test('execFor: SELECT still returns rows', async () => {
  const { exec, close } = await freshDb();
  try {
    const rows = await exec('SELECT 1 AS n');
    expect(rows).toEqual([{ n: 1 }]);
  } finally {
    close();
  }
});

test('execFor: write statements (INSERT/UPDATE/DELETE/ALTER) return []', async () => {
  // Each write must go through .run() and produce an empty result rowset,
  // regardless of whether better-sqlite3's reader flag or the prefix
  // heuristic made the routing decision. A regression to the prefix-only
  // path would re-break this for PRAGMA setters.
  const { exec, close } = await freshDb();
  try {
    // ALTER is the simplest write that doesn't need a seed row.
    expect(await exec('ALTER TABLE categories RENAME TO categories_tmp')).toEqual([]);
    expect(await exec('ALTER TABLE categories_tmp RENAME TO categories')).toEqual([]);
  } finally {
    close();
  }
});

test('execFor: multi-statement batch is routed through db.exec() (not prepared)', async () => {
  // The canonical SCHEMA string and the PRAGMA bootstrap qualify. They
  // shouldn't go through the per-statement prepare path because each
  // statement is independent — e.g. a `; ` in the middle would otherwise
  // confuse the prepared statement.
  const driver = await openDb(':memory:');
  const exec = execFor(driver);
  try {
    await exec('CREATE TABLE t (id INTEGER PRIMARY KEY); CREATE INDEX i_t ON t(id);');
    const rows = await exec("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 't'");
    expect(rows).toEqual([{ name: 't' }]);
  } finally {
    driver.close();
  }
});

test('execFor: applyPragmaBootstrap + applySchema together produce a usable DB', async () => {
  // Sanity end-to-end: bootstrap → schema → the tables exist. If the
  // shim mishandles the PRAGMA setters in the bootstrap, the subsequent
  // FK-using CREATE TABLE statements will fail.
  const driver = await openDb(':memory:');
  const exec = execFor(driver);
  try {
    applyPragmaBootstrap(driver);
    await applySchema(exec);
    const tables = await exec("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name");
    const names = tables.map((r) => String(r.name));
    // Spot-check the core tables the queries/ layer depends on.
    expect(names).toContain('entries');
    expect(names).toContain('postings');
    expect(names).toContain('accounts');
    expect(names).toContain('categories');
  } finally {
    driver.close();
  }
});

test('execFor: a single-statement PRAGMA setter actually executes (every engine build)', async () => {
  // Regression pin for the CI-only cutover failures: the bun:sqlite fallback
  // used to route PRAGMA setters through `.all()`, which executes them on the
  // macOS build but NOT on the Linux build — the migration dances' FK toggles
  // silently no-opped there. Setters must go through `.run()`.
  const driver = await openDb(':memory:');
  const exec = execFor(driver);
  try {
    applyPragmaBootstrap(driver); // foreign_keys = ON
    expect(await exec('PRAGMA foreign_keys')).toEqual([{ foreign_keys: 1 }]);
    await exec('PRAGMA foreign_keys = OFF'); // single statement → prepare path
    expect(await exec('PRAGMA foreign_keys')).toEqual([{ foreign_keys: 0 }]);
    await exec('PRAGMA foreign_keys = ON');
    expect(await exec('PRAGMA foreign_keys')).toEqual([{ foreign_keys: 1 }]);
  } finally {
    driver.close();
  }
});

test('applyPragmaBootstrap pins modern ALTER semantics on every engine build', async () => {
  // The bun:sqlite DEFAULT for legacy_alter_table differs by BUILD (macOS ON,
  // Linux OFF), which made the cutover's rebuild dances pass locally and fail
  // in CI. The bootstrap pins it OFF so every environment — including this
  // test suite — runs the strict re-parse semantics; the dances opt into
  // legacy mode around their RENAMEs explicitly.
  const driver = await openDb(':memory:');
  const exec = execFor(driver);
  try {
    applyPragmaBootstrap(driver);
    expect(await exec('PRAGMA legacy_alter_table')).toEqual([{ legacy_alter_table: 0 }]);
  } finally {
    driver.close();
  }
});
