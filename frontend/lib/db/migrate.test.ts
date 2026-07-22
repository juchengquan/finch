import { test, expect } from 'bun:test';
import { migrate, SCHEMA_VERSION } from './core/schema';
import { bareDb } from './core/test-utils';
import type { Exec } from './core/repo';

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

// #533 dropped counterparties.ledger_id from the baseline without a migration:
// pre-07-20 databases keep the per-ledger table and every NEW-merchant insert
// fails its NOT NULL constraint. Those files were also already re-stamped to
// 2026-07-22 by the later entries — the 07-23 rebuild must still fire.

async function stalePerLedgerCounterparties(exec: Exec): Promise<void> {
  await exec(`CREATE TABLE ledgers (id TEXT PRIMARY KEY)`);
  await exec(`INSERT INTO ledgers (id) VALUES ('l1')`);
  await exec(
    `CREATE TABLE counterparties (
       id            TEXT PRIMARY KEY,
       ledger_id     TEXT NOT NULL REFERENCES ledgers(id),
       name          TEXT NOT NULL COLLATE NOCASE,
       is_verified   INTEGER NOT NULL DEFAULT 0,
       created_at    TEXT NOT NULL,
       updated_at    TEXT NOT NULL
     )`,
  );
  await exec(
    `INSERT INTO counterparties (id,ledger_id,name,is_verified,created_at,updated_at)
     VALUES ('cp1','l1','Blue Bottle',1,'2026-01-01','2026-01-01')`,
  );
  await exec(
    `CREATE TABLE db_metadata (
       id INTEGER PRIMARY KEY, app_name TEXT, schema_version TEXT,
       app_version TEXT, created_at TEXT, updated_at TEXT
     )`,
  );
  await exec(
    `INSERT INTO db_metadata (id,app_name,schema_version,app_version,created_at,updated_at)
     VALUES (1,'finch','2026-07-22T00:00:00Z','0.1.0','seed','seed')`,
  );
}

test('migrate rebuilds a stale per-ledger counterparties table (drops ledger_id, keeps rows)', async () => {
  const exec = await db();
  await stalePerLedgerCounterparties(exec);
  await migrate(exec, { fresh: false });

  expect(await cols(exec, 'counterparties')).not.toContain('ledger_id');
  const rows = await exec(`SELECT id,name,is_verified FROM counterparties`);
  expect(rows).toHaveLength(1);
  expect(rows[0].id).toBe('cp1');
  expect(rows[0].name).toBe('Blue Bottle');
  // The failing insert from the bug report now succeeds.
  await exec(
    `INSERT INTO counterparties (id,name,is_verified,created_at,updated_at)
     VALUES ('cp2','Gym Membership',0,datetime('now'),datetime('now'))`,
  );
  expect(await exec(`SELECT COUNT(*) AS n FROM counterparties`)).toEqual([{ n: 2 }]);
});

test('counterparties rebuild is a no-op on an already-global table (idempotent re-run)', async () => {
  const exec = await db();
  await stalePerLedgerCounterparties(exec);
  await migrate(exec, { fresh: false });
  await migrate(exec, { fresh: false });   // second run: guard sees no ledger_id

  expect(await cols(exec, 'counterparties')).not.toContain('ledger_id');
  expect(await exec(`SELECT COUNT(*) AS n FROM counterparties`)).toEqual([{ n: 1 }]);
});
