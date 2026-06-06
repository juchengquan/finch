#!/usr/bin/env node
// Step 1 (probe) from plans/FILE_BACKED_DB_PLAN.md §7 — better-sqlite3
// half. Run under plain Node (NOT Bun: oven-sh/bun#4290 makes
// better-sqlite3 unloadable today).
//
// Usage:  node scripts/probe-bs3.mjs
//
// Reports findings to stdout. Exits non-zero on any failure.
//
// Why a standalone script rather than a node:test file? Two reasons:
//   1. The rest of the repo's tests run under Bun. Bringing in a second
//      test runner just for this one probe is heavier than the probe needs.
//   2. The probe runs by hand at integration time — once, to verify the
//      plan's assumptions before committing to the architecture (and again
//      after upgrading better-sqlite3 / Node). It's deliberately not in CI.

import Database from 'better-sqlite3';
import { strict as assert } from 'node:assert';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

const RESULTS = [];
function probe(name, fn) {
  process.stdout.write(`  ${name} … `);
  try {
    const t0 = performance.now();
    fn();
    const ms = (performance.now() - t0).toFixed(1);
    process.stdout.write(`OK (${ms} ms)\n`);
    RESULTS.push({ name, ok: true });
  } catch (err) {
    process.stdout.write(`FAIL\n    ${err.message}\n`);
    RESULTS.push({ name, ok: false, err: err.message });
  }
}

const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'finch-bs3-probe-'));
console.log(`probe: better-sqlite3 vs Node ${process.version}`);
console.log(`probe: tmp dir ${tmpRoot}`);
console.log('');

// ---------------------------------------------------------------------------

probe('1. better-sqlite3 loads under Node', () => {
  const db = new Database(':memory:');
  const row = db.prepare('SELECT 1 + 1 AS two').get();
  assert.equal(row.two, 2);
  db.close();
});

probe('2. WAL mode engages on a file-backed DB and the *-wal sidecar materialises on commit', () => {
  const file = path.join(tmpRoot, 'wal.db');
  const db = new Database(file);
  const before = db.pragma('journal_mode', { simple: true });
  assert.equal(String(before).toLowerCase(), 'delete');
  const after = db.pragma('journal_mode = WAL', { simple: true });
  assert.equal(String(after).toLowerCase(), 'wal');
  db.prepare('CREATE TABLE t (id INTEGER)').run();
  db.prepare('INSERT INTO t (id) VALUES (?)').run(1);
  assert.ok(fs.existsSync(`${file}-wal`), '-wal sidecar should exist after a commit');
  assert.ok(fs.existsSync(`${file}-shm`), '-shm sidecar should exist while the DB is open');
  db.close();
});

probe('3. Recommended PRAGMA bootstrap applies cleanly', () => {
  const db = new Database(path.join(tmpRoot, 'bootstrap.db'));
  db.pragma('journal_mode = WAL');
  db.pragma('synchronous = NORMAL');
  db.pragma('foreign_keys = ON');
  db.pragma('temp_store = MEMORY');
  db.pragma('cache_size = -8000');
  assert.equal(String(db.pragma('journal_mode', { simple: true })).toLowerCase(), 'wal');
  assert.equal(Number(db.pragma('synchronous', { simple: true })), 1, 'NORMAL = 1');
  assert.equal(Number(db.pragma('foreign_keys', { simple: true })), 1);
  assert.equal(Number(db.pragma('temp_store', { simple: true })), 2, 'MEMORY = 2');
  assert.equal(Number(db.pragma('cache_size', { simple: true })), -8000);
  db.close();
});

probe('4. Multi-statement SCHEMA strings run via db.exec (the path the SHIM uses)', () => {
  const db = new Database(path.join(tmpRoot, 'multi.db'));
  db.pragma('foreign_keys = ON');
  // A trimmed slice of the canonical SCHEMA shape — two CREATE TABLEs +
  // a CREATE INDEX, all in one string with semicolons.
  db.exec(`
    CREATE TABLE a (id TEXT PRIMARY KEY, name TEXT NOT NULL);
    CREATE TABLE b (id TEXT PRIMARY KEY, a_id TEXT REFERENCES a(id));
    CREATE INDEX idx_b_a ON b(a_id);
  `);
  const tables = db
    .prepare("SELECT name FROM sqlite_master WHERE type IN ('table','index') ORDER BY name")
    .all()
    .map((r) => r.name);
  assert.deepEqual(
    tables.sort(),
    ['a', 'b', 'idx_b_a', 'sqlite_autoindex_a_1', 'sqlite_autoindex_b_1'].sort(),
  );
  db.close();
});

probe('5. db.transaction(fn) wrapping (the new withWrite shape from §3.2)', () => {
  const db = new Database(path.join(tmpRoot, 'txn.db'));
  db.pragma('journal_mode = WAL');
  db.exec('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)');
  const insert = db.prepare('INSERT INTO t (v) VALUES (?)');
  const txn = db.transaction((rows) => {
    for (const v of rows) insert.run(v);
  });
  txn(['a', 'b', 'c']);
  const count = db.prepare('SELECT COUNT(*) AS c FROM t').get().c;
  assert.equal(count, 3);
  // Rollback on throw.
  try {
    db.transaction(() => {
      insert.run('d');
      throw new Error('boom');
    })();
  } catch {
    /* expected */
  }
  assert.equal(db.prepare('SELECT COUNT(*) AS c FROM t').get().c, 3);
  db.close();
});

probe('6. SIGKILL-equivalent close + reopen recovers committed state via WAL', () => {
  const file = path.join(tmpRoot, 'recover.db');
  {
    const db = new Database(file);
    db.pragma('journal_mode = WAL');
    db.exec('CREATE TABLE t (id INTEGER PRIMARY KEY)');
    db.prepare('INSERT INTO t (id) VALUES (?)').run(42);
    // Close without an explicit checkpoint — frames sit in -wal, just like
    // a real crash between commit and the lazy auto-checkpoint.
    db.close();
  }
  {
    const db = new Database(file);
    const row = db.prepare('SELECT id FROM t WHERE id = 42').get();
    assert.equal(row.id, 42, 'committed row must survive the close-and-reopen');
    db.close();
  }
});

probe('7. VACUUM INTO produces a single-file snapshot that opens cleanly elsewhere', () => {
  const file = path.join(tmpRoot, 'vacuum.db');
  const snap = path.join(tmpRoot, 'snap.db');
  const db = new Database(file);
  db.pragma('journal_mode = WAL');
  db.exec('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)');
  for (let i = 0; i < 100; i++) db.prepare('INSERT INTO t (v) VALUES (?)').run(`row-${i}`);
  db.prepare('VACUUM INTO ?').run(snap);
  db.close();
  assert.ok(fs.existsSync(snap));
  const ro = new Database(snap, { readonly: true });
  assert.equal(ro.prepare('SELECT COUNT(*) AS c FROM t').get().c, 100);
  ro.close();
});

probe('8. wal_checkpoint(TRUNCATE) drains the WAL into the main DB file', () => {
  const file = path.join(tmpRoot, 'ckpt.db');
  const db = new Database(file);
  db.pragma('journal_mode = WAL');
  db.exec('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)');
  for (let i = 0; i < 50; i++) db.prepare('INSERT INTO t (v) VALUES (?)').run(`row-${i}`);
  const walBefore = fs.statSync(`${file}-wal`).size;
  assert.ok(walBefore > 0, '-wal should carry frames before the checkpoint');
  db.pragma('wal_checkpoint(TRUNCATE)');
  const walAfter = fs.statSync(`${file}-wal`).size;
  assert.equal(walAfter, 0, '-wal should be truncated after TRUNCATE checkpoint');
  db.close();
});

probe('9. Per-mutation latency on a file-backed WAL DB', () => {
  const db = new Database(path.join(tmpRoot, 'perf.db'));
  db.pragma('journal_mode = WAL');
  db.pragma('synchronous = NORMAL');
  db.exec('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)');
  const insert = db.prepare('INSERT INTO t (v) VALUES (?)');
  // Warm up.
  for (let i = 0; i < 100; i++) insert.run(`warm-${i}`);
  const N = 1000;
  const t0 = performance.now();
  for (let i = 0; i < N; i++) insert.run(`probe-${i}`);
  const perOp = (performance.now() - t0) / N;
  console.log(`    │ insert-only avg: ${perOp.toFixed(3)} ms/op (N=${N})`);
  // Plan §10 budget: single-digit ms on a 10 MB DB. Bare inserts on a fresh
  // DB should be well under that.
  assert.ok(perOp < 5, `expected < 5 ms/op, got ${perOp.toFixed(3)}`);
  db.close();
});

// ---------------------------------------------------------------------------

console.log('');
const fails = RESULTS.filter((r) => !r.ok);
if (fails.length > 0) {
  console.log(`probe: ${fails.length} failure(s) — see above.`);
  process.exit(1);
}
console.log(`probe: ${RESULTS.length} / ${RESULTS.length} OK.`);
console.log(`probe: better-sqlite3 ${process.versions.node ? `+ Node ${process.version}` : ''} is viable per FILE_BACKED_DB_PLAN §10.`);

// Best-effort cleanup; the OS will eventually GC tmp files anyway.
try {
  fs.rmSync(tmpRoot, { recursive: true });
} catch {
  /* ignore */
}
