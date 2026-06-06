// Test-only DB helpers. Each test file used to hand-roll its own sqlite-wasm
// bootstrap; this is the shared landing pad for the new file-backed driver,
// pointed at `:memory:` for speed. Production reads/writes go through
// `lib/db/server.ts`; nothing here is allowed in non-test code.

import { openDb, execFor, applyPragmaBootstrap, type SqliteDriver } from './driver';
import { applySchema } from './schema';
import { seedDatabase } from './seed';
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
