import { test, expect } from 'bun:test';
import { migrate, SCHEMA_VERSION } from '@/lib/db/schema';
import { bareDb } from '@/lib/db/test-utils';
import type { Exec } from '@/lib/db/repo';

const db = async (): Promise<Exec> => (await bareDb()).exec;

const cols = async (exec: Exec, table: string) =>
  (await exec(`PRAGMA table_info(${table})`)).map((r) => String(r.name));

// A database created in the window between the baseline and #66 (the
// unrealized-FX work) carries the *baseline* schema_version yet lacks the
// accounts.opening_balance_base column — #66 added the column without bumping
// the version. These two tests pin both halves of the recovery:
//   1. such a file gets the column added on the next migrate(), and
//   2. a file that already has the column (the common case) is untouched —
//      the additive ALTER is idempotent rather than erroring "duplicate column".

async function staleAccounts(exec: Exec, opts: { withColumn: boolean }): Promise<void> {
  await exec(
    `CREATE TABLE accounts (
       id TEXT PRIMARY KEY,
       opening_balance REAL NOT NULL DEFAULT 0
       ${opts.withColumn ? ', opening_balance_base REAL NOT NULL DEFAULT 0' : ''}
     )`,
  );
  await exec(
    `CREATE TABLE db_metadata (
       id INTEGER PRIMARY KEY, app_name TEXT, schema_version TEXT,
       app_version TEXT, created_at TEXT, updated_at TEXT
     )`,
  );
  // Recorded at the pre-#66 baseline, which is strictly < SCHEMA_VERSION now.
  await exec(
    `INSERT INTO db_metadata (id,app_name,schema_version,app_version,created_at,updated_at)
     VALUES (1,'finch','2026-06-01T20:00:00Z','0.1.0','seed','seed')`,
  );
}

test('migrate adds opening_balance_base to a pre-#66 database and re-stamps the version', async () => {
  const exec = await db();
  await staleAccounts(exec, { withColumn: false });
  await exec(`INSERT INTO accounts (id, opening_balance) VALUES ('a', 100)`);
  expect(await cols(exec, 'accounts')).not.toContain('opening_balance_base');

  await migrate(exec, { fresh: false });

  expect(await cols(exec, 'accounts')).toContain('opening_balance_base');
  const [row] = await exec(`SELECT opening_balance_base FROM accounts WHERE id = 'a'`);
  expect(Number(row.opening_balance_base)).toBe(0);
  const [m] = await exec(`SELECT schema_version FROM db_metadata WHERE id = 1`);
  expect(m.schema_version).toBe(SCHEMA_VERSION);
});

test('migrate is idempotent when opening_balance_base already exists (no duplicate-column error)', async () => {
  const exec = await db();
  await staleAccounts(exec, { withColumn: true });
  await exec(`INSERT INTO accounts (id, opening_balance, opening_balance_base) VALUES ('a', 100, 42)`);

  await migrate(exec, { fresh: false }); // must not throw

  const [row] = await exec(`SELECT opening_balance_base FROM accounts WHERE id = 'a'`);
  expect(Number(row.opening_balance_base)).toBe(42); // existing value left untouched
  const [m] = await exec(`SELECT schema_version FROM db_metadata WHERE id = 1`);
  expect(m.schema_version).toBe(SCHEMA_VERSION);
});
