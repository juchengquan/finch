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
// the version. The migration chain's 06-05 entry closes that gap with an
// idempotent ADD COLUMN (no-op on files that already carry the column).

async function staleAccounts(exec: Exec, opts: { withColumn: boolean }): Promise<void> {
  await exec(`CREATE TABLE ledgers (id TEXT PRIMARY KEY)`);
  await exec(`INSERT INTO ledgers (id) VALUES ('l1')`);

  await exec(
    `CREATE TABLE accounts (
       id                      TEXT PRIMARY KEY,
       ledger_id               TEXT NOT NULL REFERENCES ledgers(id),
       group_id                TEXT,
       name                    TEXT NOT NULL,
       type                    TEXT NOT NULL,
       currency                TEXT NOT NULL DEFAULT 'SGD',
       current_balance         REAL NOT NULL DEFAULT 0,
       opening_balance         REAL NOT NULL DEFAULT 0,
       ${opts.withColumn ? 'opening_balance_base REAL NOT NULL DEFAULT 0,' : ''}
       color                   TEXT,
       sort_order              INTEGER NOT NULL DEFAULT 0,
       include_in_net_worth    INTEGER NOT NULL DEFAULT 1,
       is_active               INTEGER NOT NULL DEFAULT 1,
       archived_at             TEXT,
       last_reconciled_at      TEXT,
       last_reconciled_balance REAL,
       created_at              TEXT NOT NULL,
       updated_at              TEXT NOT NULL
     )`,
  );
  await exec(
    `CREATE TABLE db_metadata (
       id INTEGER PRIMARY KEY, app_name TEXT, schema_version TEXT,
       app_version TEXT, created_at TEXT, updated_at TEXT
     )`,
  );
  await exec(
    `INSERT INTO db_metadata (id,app_name,schema_version,app_version,created_at,updated_at)
     VALUES (1,'finch','2026-06-04T23:59:59Z','0.1.0','seed','seed')`,
  );
}

test('migrate is idempotent when opening_balance_base already exists (no duplicate-column error)', async () => {
  const exec = await db();
  await staleAccounts(exec, { withColumn: true });
  await exec(
    `INSERT INTO accounts (id,ledger_id,name,type,currency,opening_balance,opening_balance_base,created_at,updated_at)
     VALUES ('a','l1','Acct','savings','SGD',100,42,'2026-01-01','2026-01-01')`,
  );

  await migrate(exec, { fresh: false }); // must not throw — 06-05 ADD is idempotent

  const postCols = await cols(exec, 'accounts');
  expect(postCols).toContain('opening_balance_base');
  const [m] = await exec(`SELECT schema_version FROM db_metadata WHERE id = 1`);
  expect(m.schema_version).toBe(SCHEMA_VERSION);
});
