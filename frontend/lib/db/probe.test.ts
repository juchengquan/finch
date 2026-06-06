// Step 1 (probe) from plans/FILE_BACKED_DB_PLAN.md §7. Runs under Bun.
//
// Key finding from the integration probe: **better-sqlite3 does NOT load
// under Bun 1.3.x** (tracks oven-sh/bun#4290 — ERR_DLOPEN_FAILED). The
// fallback is bun:sqlite, which Bun bundles natively and exposes the same
// sync prepare-and-run shape as better-sqlite3. The two are API-compatible
// enough that the same `execForSync` shim drives both:
//
//   - Tests under Bun  →  bun:sqlite (this file).
//   - Production server under Node  →  better-sqlite3 (probed by the
//     standalone script scripts/probe-bs3.mjs run under Node).
//
// This file validates that the existing applySchema + migrate + queries
// layer works against ANY sync SQLite engine (so the swap isn't blocked on
// engine choice). The standalone Node script validates better-sqlite3's
// specific contract — WAL mode, VACUUM INTO, recovery — that bun:sqlite
// either skips (no WAL for in-memory) or doesn't expose identically.

import { test, expect } from 'bun:test';
import { Database } from 'bun:sqlite';
import { applySchema, migrate, SCHEMA_VERSION } from '@/lib/db/schema';
import { seedDatabase } from '@/lib/db/seed';
import { insertTxRow } from '@/lib/db/queries/transactions';
import { listAccounts } from '@/lib/db/queries/accounts';
import type { Exec, Row, SqlBind } from '@/lib/db/repo';

// ---------------------------------------------------------------------------
// The async Exec shim — same shape we'd write for better-sqlite3. Both
// runtimes expose `prepare(sql)` → statement, `statement.all(...binds)` for
// SELECTs, `statement.run(...binds)` for writes. The multi-statement SCHEMA
// string goes through the engine's batch-exec path (`db.exec(sql)` on
// bun:sqlite; same call on better-sqlite3).
// ---------------------------------------------------------------------------
function execForBunSqlite(db: Database): Exec {
  return async (sql: string, bind?: SqlBind) => {
    const looksMulti = (!bind || bind.length === 0) && /;\s*[^\s;]/.test(sql);
    if (looksMulti) {
      db.exec(sql);
      return [];
    }
    const stmt = db.prepare(sql);
    const args = (bind ?? []) as never[];
    // bun:sqlite returns rows when `all` is called on a SELECT; for a write
    // statement, `all`/`get` would also work and return [] so we keep the
    // call uniform here.
    const out = stmt.all(...args) as Row[];
    return out;
  };
}

test('probe (bun:sqlite): the sync-exec shim drives the existing schema + queries unchanged', async () => {
  const db = new Database(':memory:');
  const exec = execForBunSqlite(db);

  // Same boot sequence FILE_BACKED_DB_PLAN §3.1 prescribes. Most of these
  // PRAGMAs are no-ops on :memory: (WAL needs a file; cache_size and
  // synchronous still apply) — the point is they don't throw.
  db.exec('PRAGMA foreign_keys = ON');
  db.exec('PRAGMA temp_store = MEMORY');
  db.exec('PRAGMA cache_size = -8000');

  await applySchema(exec);
  await migrate(exec, { fresh: true });

  // The metadata row carries the current version stamp.
  const [meta] = (await exec('SELECT schema_version FROM db_metadata WHERE id = 1')) as { schema_version: string }[];
  expect(meta.schema_version).toBe(SCHEMA_VERSION);
});

test('probe (bun:sqlite): seedDatabase + a real insertTxRow round-trip works end-to-end', async () => {
  const db = new Database(':memory:');
  const exec = execForBunSqlite(db);
  db.exec('PRAGMA foreign_keys = ON');
  await applySchema(exec);
  await seedDatabase(exec);

  // listAccounts via the real query path.
  const accounts = await listAccounts(exec, 'personal');
  expect(accounts.length).toBeGreaterThan(0);

  // insertTxRow is the consolidated write path. If it works through the
  // shim, the ~10 prod call sites fanning into it work too.
  const id = await insertTxRow(exec, {
    ledgerId: 'personal',
    accountId: accounts[0].id,
    date: '2026-05-15',
    amount: -42.5,
    description: 'sync-engine probe',
    kind: 'expense',
  });
  const [row] = (await exec('SELECT description, amount FROM transactions WHERE id = ?', [id])) as {
    description: string;
    amount: number;
  }[];
  expect(row.description).toBe('sync-engine probe');
  expect(row.amount).toBe(-42.5);
});

test('probe (bun:sqlite): per-mutation latency under the shim is acceptable', async () => {
  const db = new Database(':memory:');
  const exec = execForBunSqlite(db);
  db.exec('PRAGMA foreign_keys = ON');
  await applySchema(exec);
  await seedDatabase(exec);
  const accounts = await listAccounts(exec, 'personal');

  // Warm up.
  for (let i = 0; i < 5; i++) {
    await insertTxRow(exec, {
      ledgerId: 'personal', accountId: accounts[0].id,
      date: '2026-05-15', amount: -1, description: `warm-${i}`, kind: 'expense',
    });
  }
  const N = 50;
  const t0 = performance.now();
  for (let i = 0; i < N; i++) {
    await insertTxRow(exec, {
      ledgerId: 'personal', accountId: accounts[0].id,
      date: '2026-05-15', amount: -1, description: `probe-${i}`, kind: 'expense',
    });
  }
  const perOp = (performance.now() - t0) / N;
  // For diagnostic visibility in the probe report; the assertion is generous
  // because :memory: is unrealistic for the prod target (an on-disk WAL DB).
  console.log(`probe(bun:sqlite): insertTxRow avg ${perOp.toFixed(2)} ms/op (N=${N})`);
  expect(perOp).toBeLessThan(50);
});
