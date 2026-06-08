// Test-only DB helpers. Each test file used to hand-roll its own sqlite-wasm
// bootstrap; this is the shared landing pad for the new file-backed driver,
// pointed at `:memory:` for speed. Production reads/writes go through
// `lib/db/server.ts`; nothing here is allowed in non-test code.

import { afterEach } from 'bun:test';
import { openDb, execFor, applyPragmaBootstrap, type SqliteDriver } from './driver';
import { applySchema } from './schema';
import { seedDatabase } from './seed';
import { auditLedger } from './entries';
import type { Exec } from './repo';

export interface TestDb {
  exec: Exec;
  driver: SqliteDriver;
  /** Convenience for tests that want to drop the connection mid-run; tests
   *  that fall through without calling this leak a per-test in-memory DB,
   *  which the OS reclaims when the process exits. */
  close: () => void;
}

/** Raw in-memory DB with the PRAGMA bootstrap applied but NO schema. For
 *  tests that need to stage a partial pre-migration shape themselves (e.g.
 *  `migrate.test.ts` simulates a pre-#66 database). */
export async function bareDb(): Promise<TestDb> {
  const driver = await openDb(':memory:');
  applyPragmaBootstrap(driver);
  return { exec: execFor(driver), driver, close: () => driver.close() };
}

/** A bare in-memory DB with the canonical schema applied. No seed. */
export async function freshDb(): Promise<TestDb> {
  const db = await bareDb();
  await applySchema(db.exec);
  return db;
}

/** A fully seeded in-memory DB — the equivalent of opening a brand-new
 *  finch.sqlite3 file at first boot. Matches what `server.ts`'s `open()` does
 *  on a fresh file. */
export async function seededDb(): Promise<TestDb> {
  const db = await freshDb();
  await seedDatabase(db.exec);
  return db;
}

// ---------------------------------------------------------------------------
// Audit-clean hook (opt-in safety net)
// ---------------------------------------------------------------------------
// Tests that mutate the ledger want a safety net: an `afterEach` that runs
// `auditLedger` and fails the test if any drift snuck in. `seededAndAudited`
// is the seeded-DB equivalent that ALSO stashes the exec for the hook to
// audit. Tests that intentionally leave the ledger in a half-valid state
// (e.g. testing the rules engine's error paths) should keep using `seededDb`
// directly — that is the escape hatch.
//
// The hook is registered once at module load. Bun's `afterEach` scopes hooks
// to the importing test file, and modules are cached per process, so the
// hook fires for the first file that imports this module. Other files get
// the function but not the audit. This matches the pattern that originally
// lived in `mutations.test.ts`; cross-file scope is a known limitation, not
// a regression.

let _lastAuditedExec: Exec | null = null;

export async function seededAndAudited(): Promise<Exec> {
  const { exec } = await seededDb();
  _lastAuditedExec = exec;
  return exec;
}

afterEach(async () => {
  if (!_lastAuditedExec) return;
  const exec = _lastAuditedExec;
  _lastAuditedExec = null;
  const problems = await auditLedger(exec);
  if (problems.length > 0) {
    const summary = problems
      .slice(0, 5)
      .map((p) => `${p.code}${p.entryId ? ` (entry ${p.entryId})` : ''}: ${p.detail}`)
      .join('\n  ');
    throw new Error(
      `auditLedger reported ${problems.length} problem${problems.length === 1 ? '' : 's'} at end of test:\n  ${summary}${problems.length > 5 ? '\n  …' : ''}`,
    );
  }
});
