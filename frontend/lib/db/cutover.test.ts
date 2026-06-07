import { test, expect } from 'bun:test';
import { bareDb } from '@/lib/db/test-utils';
import { moveLegacyData, dropLegacyTables } from '@/lib/db/cutover';
import { auditLedger, ensureSystemCategories } from '@/lib/db/entries';
import { applyEntriesSchema } from '@/lib/db/entries-schema';
import { ENTRY_ATTACHMENTS_DDL, ENTRIES_FTS_DDL } from '@/lib/db/schema';
import type { Exec } from '@/lib/db/repo';

// ---------------------------------------------------------------------------
// Legacy DDL (exact copy from git show 7791506:frontend/lib/db/schema.ts)
// Only the tables the cutover reads/writes are included; FTS is skipped since
// moveLegacyData never reads transactions_fts. applyEntriesSchema is run after
// this DDL so entry_tags, entries/postings, and the upgraded categories exist.
// ---------------------------------------------------------------------------
const LEGACY_SCHEMA = `
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS ledgers (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  base_currency TEXT NOT NULL DEFAULT 'SGD',
  is_default    INTEGER NOT NULL DEFAULT 0,
  color         TEXT,
  tagline       TEXT,
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS account_groups (
  id         TEXT PRIMARY KEY,
  ledger_id  TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS accounts (
  id                   TEXT PRIMARY KEY,
  ledger_id            TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  group_id             TEXT REFERENCES account_groups(id) ON DELETE SET NULL,
  name                 TEXT NOT NULL,
  type                 TEXT NOT NULL CHECK(type IN ('savings','credit_card','investment','cash','fx','virtual')),
  currency             TEXT NOT NULL DEFAULT 'SGD',
  current_balance      REAL NOT NULL DEFAULT 0,
  opening_balance      REAL NOT NULL DEFAULT 0,
  opening_balance_base REAL NOT NULL DEFAULT 0,
  color                TEXT,
  sort_order           INTEGER NOT NULL DEFAULT 0,
  include_in_net_worth INTEGER NOT NULL DEFAULT 1,
  is_active            INTEGER NOT NULL DEFAULT 1,
  archived_at          TEXT,
  last_reconciled_at      TEXT,
  last_reconciled_balance REAL,
  created_at           TEXT NOT NULL,
  updated_at           TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS categories (
  id         TEXT PRIMARY KEY,
  ledger_id  TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  parent_id  TEXT REFERENCES categories(id) ON DELETE SET NULL,
  name       TEXT NOT NULL,
  kind       TEXT NOT NULL CHECK(kind IN ('expense','income','transfer')),
  icon       TEXT,
  color      TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_cat_parent ON categories(parent_id) WHERE parent_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS tags (
  id         TEXT PRIMARY KEY,
  ledger_id  TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  color      TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS transaction_tags (
  transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
  tag_id         TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (transaction_id, tag_id)
);

CREATE TABLE IF NOT EXISTS counterparties (
  id                TEXT PRIMARY KEY,
  ledger_id         TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name              TEXT NOT NULL COLLATE NOCASE,
  is_verified       INTEGER NOT NULL DEFAULT 0,
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS transfer_groups (
  id            TEXT PRIMARY KEY,
  ledger_id     TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  from_currency TEXT NOT NULL,
  to_currency   TEXT NOT NULL,
  exchange_rate REAL,
  notes         TEXT,
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS transactions (
  id                 TEXT PRIMARY KEY,
  ledger_id          TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  account_id         TEXT NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  date               TEXT NOT NULL,
  time               TEXT,
  amount             REAL NOT NULL,
  amount_base        REAL NOT NULL,
  exchange_rate      REAL NOT NULL,
  description        TEXT,
  category_id        TEXT REFERENCES categories(id) ON DELETE SET NULL,
  counterparty_id    TEXT REFERENCES counterparties(id) ON DELETE SET NULL,
  transfer_group_id  TEXT REFERENCES transfer_groups(id) ON DELETE SET NULL,
  refunded_transaction_id TEXT REFERENCES transactions(id) ON DELETE SET NULL,
  kind               TEXT NOT NULL DEFAULT 'expense' CHECK(kind IN ('income','expense','transfer','adjustment','refund')),
  status             TEXT NOT NULL DEFAULT 'confirmed' CHECK(status IN ('pending','confirmed')),
  confirmed_at       TEXT,
  source_template_id TEXT,
  currency           TEXT NOT NULL DEFAULT 'SGD',
  notes              TEXT,
  cleared_at         TEXT,
  applied_rule_ids   TEXT,
  reviewed_at        TEXT,
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS transaction_splits (
  id             TEXT PRIMARY KEY,
  transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
  category_id    TEXT REFERENCES categories(id) ON DELETE SET NULL,
  amount         REAL NOT NULL,
  amount_base    REAL NOT NULL,
  description    TEXT,
  sort_order     INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_txn_splits_tx ON transaction_splits(transaction_id);

CREATE TABLE IF NOT EXISTS transaction_attachments (
  id                TEXT PRIMARY KEY,
  ledger_id         TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  transaction_id    TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
  kind              TEXT NOT NULL CHECK(kind IN ('image','pdf')),
  rel_path          TEXT NOT NULL,
  mime_type         TEXT NOT NULL,
  byte_size         INTEGER NOT NULL,
  sha256            TEXT NOT NULL,
  original_filename TEXT,
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS exchange_rates (
  date     TEXT NOT NULL,
  currency TEXT NOT NULL,
  rate     REAL NOT NULL,
  source   TEXT,
  PRIMARY KEY (date, currency)
);

-- Unchanged-across-cutover tables that projectState (and auditLedger) query.
-- Copied exactly from the canonical lib/db/schema.ts. Empty is fine; no seed
-- rows needed — projectState lists them and returns empty slices.

CREATE TABLE IF NOT EXISTS budget_groups (
  id         TEXT PRIMARY KEY,
  ledger_id  TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS budgets (
  id                 TEXT PRIMARY KEY,
  ledger_id          TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  group_id           TEXT REFERENCES budget_groups(id) ON DELETE SET NULL,
  name               TEXT,
  kind               TEXT NOT NULL CHECK(kind IN ('income','expense')),
  amount             REAL NOT NULL,
  saved              REAL NOT NULL DEFAULT 0,
  carry_forward      REAL NOT NULL DEFAULT 0,
  frequency          TEXT NOT NULL CHECK(frequency IN ('daily','weekly','biweekly','monthly','quarterly','yearly')),
  start_date         TEXT NOT NULL,
  end_date           TEXT,
  is_recurring       INTEGER NOT NULL DEFAULT 1,
  rollover           INTEGER NOT NULL DEFAULT 0,
  rollover_limit     REAL,
  last_rolled_period TEXT,
  pending_amount     REAL,
  account_ids        TEXT,
  category_ids       TEXT,
  warning_pct        REAL NOT NULL DEFAULT 80,
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS scheduled_templates (
  id                   TEXT PRIMARY KEY,
  ledger_id            TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name                 TEXT,
  description          TEXT,
  kind                 TEXT NOT NULL CHECK(kind IN ('income','expense','transfer')),
  amount               REAL,
  amount_varies        INTEGER NOT NULL DEFAULT 0,
  splits_enabled       INTEGER NOT NULL DEFAULT 0,
  account_id           TEXT NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  from_account_id      TEXT REFERENCES accounts(id) ON DELETE RESTRICT,
  category_id          TEXT REFERENCES categories(id) ON DELETE SET NULL,
  frequency            TEXT NOT NULL CHECK(frequency IN ('once','daily','weekly','biweekly','monthly','quarterly','yearly')),
  day_of_month         INTEGER,
  day_of_week          INTEGER,
  start_date           TEXT NOT NULL,
  end_date             TEXT,
  next_run             TEXT,
  last_run             TEXT,
  auto_post            INTEGER NOT NULL DEFAULT 1,
  is_active            INTEGER NOT NULL DEFAULT 1,
  max_executions       INTEGER,
  installment_total    INTEGER,
  color                TEXT,
  created_at           TEXT NOT NULL,
  updated_at           TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS scheduled_splits (
  id           TEXT PRIMARY KEY,
  template_id  TEXT NOT NULL REFERENCES scheduled_templates(id) ON DELETE CASCADE,
  account_id   TEXT NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  amount_pct   REAL,
  amount_abs   REAL,
  category_id  TEXT REFERENCES categories(id) ON DELETE RESTRICT,
  description  TEXT,
  sort_order   INTEGER NOT NULL DEFAULT 0,
  CHECK (amount_pct IS NOT NULL OR amount_abs IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS holdings (
  id              TEXT PRIMARY KEY,
  ledger_id       TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  account_id      TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  symbol          TEXT NOT NULL,
  name            TEXT,
  shares          REAL NOT NULL DEFAULT 0,
  cost_basis      REAL NOT NULL DEFAULT 0,
  currency        TEXT NOT NULL,
  last_price      REAL,
  last_price_date TEXT,
  notes           TEXT,
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS rules (
  id              TEXT PRIMARY KEY,
  ledger_id       TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name            TEXT,
  priority        INTEGER NOT NULL DEFAULT 100,
  condition       TEXT NOT NULL,
  actions         TEXT NOT NULL,
  is_active       INTEGER NOT NULL DEFAULT 1,
  run_on_edit     INTEGER NOT NULL DEFAULT 0,
  last_applied_at TEXT,
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS app_state (
  key        TEXT PRIMARY KEY,
  value      TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS db_metadata (
  id              INTEGER PRIMARY KEY CHECK (id = 1),
  app_name        TEXT NOT NULL,
  schema_version  TEXT NOT NULL,
  app_version     TEXT NOT NULL,
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL,
  exported_at     TEXT,
  exported_from   TEXT,
  row_counts      TEXT,
  checksum        TEXT
);

CREATE INDEX IF NOT EXISTS idx_txn_ledger_date ON transactions(ledger_id, date);
CREATE INDEX IF NOT EXISTS idx_txn_account_date ON transactions(account_id, date);
CREATE INDEX IF NOT EXISTS idx_txn_account_status ON transactions(account_id, status);
CREATE INDEX IF NOT EXISTS idx_txn_transfer_group ON transactions(transfer_group_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_txn_dedup ON transactions(account_id, date, time, amount, description);

CREATE TRIGGER IF NOT EXISTS tr_update_account_balance
AFTER INSERT ON transactions
FOR EACH ROW
WHEN NEW.status = 'confirmed'
BEGIN
  UPDATE accounts
  SET current_balance = ROUND(current_balance +
        (CASE WHEN NEW.currency = (SELECT currency FROM accounts WHERE id = NEW.account_id)
              THEN NEW.amount ELSE NEW.amount_base END), 2),
      updated_at = datetime('now')
  WHERE id = NEW.account_id;
END;
`;

// ---------------------------------------------------------------------------
// Helper: build a legacy-shaped in-memory DB, seed fixture data into the
// legacy tables, then apply the DE schema on top so moveLegacyData can run.
//
// Options:
//   pure: true — skip applyEntriesSchema/new-table DDL and write a
//     db_metadata row at schema_version='2026-06-12T00:00:00Z' — a faithful
//     pre-cutover file, exactly as the golden-projection test (Task B5) needs.
//     Existing callers that pass no options (or pure=false) are unchanged and
//     get the full DE schema applied on top as before.
// ---------------------------------------------------------------------------
export async function legacyFixtureDb({ pure = false }: { pure?: boolean } = {}): Promise<{ exec: Exec; close: () => void }> {
  const db = await bareDb();
  const { exec } = db;

  // 1. Apply legacy DDL.
  await exec(LEGACY_SCHEMA);

  if (pure) {
    // Pure mode: write a db_metadata row at a pre-cutover schema version so
    // migrate() can identify the file as needing the 2026-06-14 migration.
    // Do NOT apply the DE schema tables — the migration itself does that as
    // part of the 2026-06-13 entry.
    const metaNow = new Date().toISOString();
    await exec(
      `INSERT INTO db_metadata (id, app_name, schema_version, app_version, created_at, updated_at)
       VALUES (1, 'finch', '2026-06-12T00:00:00Z', '0.0.0', ?, ?)`,
      [metaNow, metaNow],
    );
  } else {
    // 2. Apply the DE schema (entries/postings/entry_tags + categories upgrade +
    //    entry_attachments + entries_fts). applyEntriesSchema runs CATEGORIES_UPGRADE
    //    which re-creates categories with kind='equity' support — the fixture wants this.
    await applyEntriesSchema(exec);
    await exec(ENTRY_ATTACHMENTS_DDL);
    await exec(ENTRIES_FTS_DDL);
  }

  const now = "datetime('now')";

  // 3. Seed fixture data into legacy tables.
  // Ledgers. Use USD as base (matches the original test setup so cross-ccy
  // transfers have non-base account legs that don't violate I9).
  await exec(
    `INSERT INTO ledgers (id,name,base_currency,is_default,color,tagline,created_at,updated_at)
     VALUES ('personal','Personal','USD',1,NULL,NULL,${now},${now})`,
  );

  // Exchange rates for SGD/USD used in fixture txns.
  await exec(`INSERT OR IGNORE INTO exchange_rates (date,currency,rate) VALUES ('2026-05-01','SGD',0.74)`);
  await exec(`INSERT OR IGNORE INTO exchange_rates (date,currency,rate) VALUES ('2026-05-02','SGD',0.74)`);
  await exec(`INSERT OR IGNORE INTO exchange_rates (date,currency,rate) VALUES ('2026-05-03','SGD',0.74)`);
  await exec(`INSERT OR IGNORE INTO exchange_rates (date,currency,rate) VALUES ('2026-05-04','SGD',0.74)`);
  await exec(`INSERT OR IGNORE INTO exchange_rates (date,currency,rate) VALUES ('2026-05-05','SGD',0.74)`);

  // Categories (old CHECK — 'transfer' kind is valid in legacy).
  await exec(`INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at)
    VALUES ('food','personal',NULL,'Food','expense',0,${now},${now}),
           ('income-cat','personal',NULL,'Salary','income',1,${now},${now})`);

  if (!pure) {
    // Ensure system categories (for auditLedger + moveLegacyData).
    // In pure mode the categories table is legacy-schema (no 'equity' kind, no
    // system column) — ensureSystemCategories would fail. The migration path
    // applies CATEGORIES_UPGRADE (via the 2026-06-13 entry) before calling
    // moveLegacyData, which calls ensureSystemCategories internally.
    await ensureSystemCategories(exec, 'personal');
  }

  // Tags.
  await exec(`INSERT INTO tags (id,ledger_id,name,created_at,updated_at)
    VALUES ('tag1','personal','travel',${now},${now}),
           ('tag2','personal','work',${now},${now})`);

  // Accounts: ledger base=USD. a-main/a-cc/a-plain are SGD (non-base);
  // a-usd is USD (matches ledger base). Two accounts have opening balances.
  // current_balance starts at opening_balance (the legacy pattern: the trigger
  // `tr_update_account_balance` will increment it for each confirmed txn insert,
  // landing at the same value recomputeAccountFromPostings produces post-move).
  // Expected final balances (trigger accumulation + opening):
  //   a-main:  500(open) + 3000(inc) - 80(tg-x) - 135(tg-xc) = 3285 SGD
  //   a-cc:    0(no open) - 120(exp) + 80(tg-x) + 30(refund) - 100(sx) = -110 SGD
  //   a-usd:   200(open) + 100.5(tg-xc) - 37(f3 → amount_base) = 263.5 USD
  //   a-plain: 0(no open) - 7(stray/adj) = -7 SGD  [t-pend pending, excluded]
  await exec(
    `INSERT INTO accounts (id,ledger_id,group_id,name,type,currency,current_balance,opening_balance,opening_balance_base,sort_order,include_in_net_worth,is_active,created_at,updated_at)
     VALUES
       ('a-main','personal',NULL,'Main','savings','SGD',500,500,370,0,1,1,${now},${now}),
       ('a-cc','personal',NULL,'Credit Card','credit_card','SGD',0,0,0,1,0,1,${now},${now}),
       ('a-usd','personal',NULL,'USD Account','savings','USD',200,200,200,2,1,1,${now},${now}),
       ('a-plain','personal',NULL,'Plain','savings','SGD',0,0,0,3,1,1,${now},${now})`,
  );

  // Transactions (amounts in account-native currency, amount_base in USD).
  const txCols = `(id,ledger_id,account_id,date,time,amount,amount_base,exchange_rate,description,category_id,counterparty_id,transfer_group_id,refunded_transaction_id,kind,status,confirmed_at,source_template_id,currency,notes,cleared_at,applied_rule_ids,reviewed_at,created_at,updated_at)`;

  // 1. Income tx (SGD account, USD ledger: amount=3000 SGD, amount_base=2220 USD).
  await exec(`INSERT INTO transactions ${txCols} VALUES
    ('t-inc','personal','a-main','2026-05-01','10:00',3000,2220,0.74,'Salary','income-cat',NULL,NULL,NULL,'income','confirmed',${now},NULL,'SGD',NULL,NULL,NULL,NULL,${now},${now})`);

  // 2. Expense tx (SGD account: amount=-120 SGD, amount_base=-88.8 USD).
  await exec(`INSERT INTO transactions ${txCols} VALUES
    ('t-exp','personal','a-cc','2026-05-02',NULL,-120,-88.8,0.74,'Groceries','food',NULL,NULL,NULL,'expense','confirmed',${now},NULL,'SGD',NULL,NULL,NULL,NULL,${now},${now})`);

  // 3. Pending tx.
  await exec(`INSERT INTO transactions ${txCols} VALUES
    ('t-pend','personal','a-plain','2026-05-03',NULL,-50,-37,0.74,'Pending item','food',NULL,NULL,NULL,'expense','pending',NULL,NULL,'SGD',NULL,NULL,NULL,NULL,${now},${now})`);

  // 4. Refund tx (references t-exp, reverses it).
  await exec(`INSERT INTO transactions ${txCols} VALUES
    ('t-refund','personal','a-cc','2026-05-04',NULL,30,22.2,0.74,'Refund','food',NULL,NULL,'t-exp','refund','confirmed',${now},NULL,'SGD',NULL,NULL,NULL,NULL,${now},${now})`);

  // 5. Same-currency transfer: tg-x (SGD→SGD, but ledger base=USD so amount_base≠amount).
  await exec(`INSERT INTO transfer_groups (id,ledger_id,from_currency,to_currency,exchange_rate,notes,created_at,updated_at)
    VALUES ('tg-x','personal','SGD','SGD',1,'note-x',${now},${now})`);
  await exec(`INSERT INTO transactions ${txCols} VALUES
    ('t-xa','personal','a-main','2026-05-01',NULL,-80,-59.2,0.74,'Transfer to a-cc',NULL,NULL,'tg-x',NULL,'transfer','confirmed',${now},NULL,'SGD',NULL,NULL,NULL,NULL,${now},${now}),
    ('t-xb','personal','a-cc','2026-05-01',NULL,80,59.2,0.74,'Transfer from a-main',NULL,NULL,'tg-x',NULL,'transfer','confirmed',${now},NULL,'SGD',NULL,NULL,NULL,NULL,${now},${now})`);

  // 6. Pinned cross-currency transfer with residue: tg-xc.
  //    t-xca: SGD account sends 135 SGD (amount_base=-100 USD).
  //    t-xcb: USD account receives 100.5 USD (= base, I9 holds: amount==amount_base).
  await exec(`INSERT INTO transfer_groups (id,ledger_id,from_currency,to_currency,exchange_rate,notes,created_at,updated_at)
    VALUES ('tg-xc','personal','SGD','USD',0.7444,NULL,${now},${now})`);
  await exec(`INSERT INTO transactions ${txCols} VALUES
    ('t-xca','personal','a-main','2026-05-02',NULL,-135,-100,0.7407,'Transfer to a-usd',NULL,NULL,'tg-xc',NULL,'transfer','confirmed',${now},NULL,'SGD',NULL,NULL,NULL,NULL,${now},${now}),
    ('t-xcb','personal','a-usd','2026-05-02',NULL,100.5,100.5,1,'Transfer from a-main',NULL,NULL,'tg-xc',NULL,'transfer','confirmed',${now},NULL,'USD',NULL,NULL,NULL,NULL,${now},${now})`);

  // 7. Orphan transfer (stray).
  await exec(`INSERT INTO transfer_groups (id,ledger_id,from_currency,to_currency,exchange_rate,notes,created_at,updated_at)
    VALUES ('tg-dead','personal','SGD','SGD',1,NULL,${now},${now})`);
  await exec(`INSERT INTO transactions ${txCols} VALUES
    ('t-stray','personal','a-plain','2026-05-03',NULL,-7,-5.18,0.74,'half a transfer',NULL,NULL,'tg-dead',NULL,'transfer','confirmed',${now},NULL,'SGD',NULL,NULL,NULL,NULL,${now},${now})`);

  // 8. Split expense (SGD account, amount_base in USD).
  await exec(`INSERT INTO transactions ${txCols} VALUES
    ('t-sx','personal','a-cc','2026-05-04','09:00',-100,-74,0.74,'split shop','food',NULL,NULL,NULL,'expense','confirmed',${now},NULL,'SGD',NULL,${now},NULL,NULL,${now},${now})`);
  await exec(`INSERT INTO transaction_splits (id,transaction_id,category_id,amount,amount_base,description,sort_order) VALUES
    ('t-sx-s0','t-sx','food',-60,-44.4,'groceries',0),
    ('t-sx-s1','t-sx',NULL,-40,-29.6,NULL,1)`);

  // 9. F3 row: SGD-denominated row on a USD account (currency != account currency).
  await exec(`INSERT INTO transactions ${txCols} VALUES
    ('t-f3','personal','a-usd','2026-05-05',NULL,-50,-37,0.74,'foreign row','food',NULL,NULL,NULL,'expense','confirmed',${now},NULL,'SGD',NULL,NULL,NULL,NULL,${now},${now})`);

  // Tags on two transactions.
  await exec(`INSERT INTO transaction_tags (transaction_id, tag_id) VALUES
    ('t-inc','tag1'),
    ('t-exp','tag2')`);

  // Attachment row.
  await exec(`INSERT INTO transaction_attachments (id,ledger_id,transaction_id,kind,rel_path,mime_type,byte_size,sha256,created_at,updated_at)
    VALUES ('att1','personal','t-exp','image','receipts/att1.jpg','image/jpeg',1024,'deadbeef',${now},${now})`);

  return db;
}

// ---------------------------------------------------------------------------

const balances = async (exec: Exec) =>
  new Map((await exec('SELECT id, current_balance AS b FROM accounts')).map((r) => [String(r.id), Number(r.b)]));

test('moveLegacyData: audit-clean, id-faithful, balance-preserving, idempotent', async () => {
  const { exec, close } = await legacyFixtureDb();
  try {
    const before = await balances(exec);
    const [single] = await exec("SELECT id, account_id FROM transactions WHERE transfer_group_id IS NULL AND kind IN ('income','expense') LIMIT 1");
    // Pick a transfer group that has exactly 2 legs (orphan stray groups have 1
    // and are re-kinded to adjustment, not a transfer entry with 2 account legs).
    const [grp] = await exec(
      `SELECT transfer_group_id AS g
         FROM transactions
        WHERE transfer_group_id IS NOT NULL
        GROUP BY transfer_group_id HAVING COUNT(*) = 2
        LIMIT 1`,
    );
    const [tagCount] = await exec('SELECT COUNT(*) AS n FROM transaction_tags');

    const res = await moveLegacyData(exec);
    expect(res.entries).toBeGreaterThan(0);

    // Audit clean (the function itself throws on problems; assert again explicitly).
    expect(await auditLedger(exec, undefined, { checkBalances: true })).toEqual([]);

    // Id fidelity: a single's txn id is BOTH its entry id and its account-posting id.
    const sid = String(single.id);
    expect((await exec('SELECT id FROM entries WHERE id = ?', [sid])).length).toBe(1);
    const [sp] = await exec('SELECT account_id FROM postings WHERE id = ?', [sid]);
    expect(String(sp.account_id)).toBe(String(single.account_id));

    // Refund: refunded_entry_id equals the original's entry id.
    const [refundEntry] = await exec("SELECT refunded_entry_id FROM entries WHERE id = 't-refund'");
    expect(String(refundEntry.refunded_entry_id)).toBe('t-exp');

    // A transfer group id is an entry with exactly two account legs keeping old txn ids.
    if (grp) {
      const gid = String(grp.g);
      const legs = await exec('SELECT id FROM postings WHERE entry_id = ? AND account_id IS NOT NULL', [gid]);
      expect(legs.length).toBe(2);
      const oldLegIds = (await exec('SELECT id FROM transactions WHERE transfer_group_id = ?', [gid])).map((r) => String(r.id)).sort();
      expect(legs.map((l) => String(l.id)).sort()).toEqual(oldLegIds);
    }

    // Tags carried over (count preserved — transfer legs collapse onto one entry,
    // so the entry_tags count can only be <= the legacy count; seed has no
    // transfer-leg tags, so equality holds).
    const [etags] = await exec('SELECT COUNT(*) AS n FROM entry_tags');
    expect(Number(etags.n)).toBe(Number(tagCount.n));

    // Balances preserved exactly (recomputed from postings inside the move).
    const after = await balances(exec);
    for (const [id, b] of before) expect(after.get(id)).toBe(b);

    // Idempotent: a re-run changes nothing.
    const [e1] = await exec('SELECT COUNT(*) AS n FROM entries');
    const [p1] = await exec('SELECT COUNT(*) AS n FROM postings');
    await moveLegacyData(exec);
    const [e2] = await exec('SELECT COUNT(*) AS n FROM entries');
    const [p2] = await exec('SELECT COUNT(*) AS n FROM postings');
    expect(Number(e2.n)).toBe(Number(e1.n));
    expect(Number(p2.n)).toBe(Number(p1.n));
  } finally {
    close();
  }
});

test('moveLegacyData maps transfers, strays, splits, F3 rows, and residue ids', async () => {
  const { exec, close } = await legacyFixtureDb();
  try {
    await moveLegacyData(exec);
    expect(await auditLedger(exec, undefined, { checkBalances: true })).toEqual([]);

    // (a) transfer: entry id = group id, two account legs keep txn ids + memos.
    const [te] = await exec("SELECT kind, description FROM entries WHERE id = 'tg-x'");
    expect(String(te.kind)).toBe('transfer');
    const tlegs = await exec("SELECT id, memo FROM postings WHERE entry_id = 'tg-x' AND account_id IS NOT NULL ORDER BY id");
    expect(tlegs.map((l) => String(l.id))).toEqual(['t-xa', 't-xb']);
    expect(String(tlegs[0].memo)).toBe('Transfer to a-cc');

    // (b) pinned cross-ccy: residue leg with the canonical `${entryId}-fx` id.
    const [fx] = await exec("SELECT id, amount_base FROM postings WHERE entry_id = 'tg-xc' AND account_id IS NULL AND id LIKE '%-fx'");
    expect(String(fx.id)).toBe('tg-xc-fx');
    expect(Number(fx.amount_base)).toBe(-0.5);

    // (c) stray leg re-kinded to adjustment with an equity leg.
    const [se] = await exec("SELECT kind FROM entries WHERE id = 't-stray'");
    expect(String(se.kind)).toBe('adjustment');
    const eq = await exec(
      "SELECT c.system AS s FROM postings p JOIN categories c ON c.id = p.category_id WHERE p.entry_id = 't-stray' AND p.account_id IS NULL",
    );
    expect(String(eq[0].s)).toBe('adjustment');

    // (d) splits: ids preserved, signs negated, cleared flag carried.
    const slegs = await exec("SELECT id, amount_base, memo FROM postings WHERE entry_id = 't-sx' AND account_id IS NULL ORDER BY sort_order");
    expect(slegs.map((l) => String(l.id))).toEqual(['t-sx-s0', 't-sx-s1']);
    // Split amount_bases are negated from the fixture values (-44.4, -29.6 → 44.4, 29.6)
    // because category legs balance the negative account leg (USD-base ledger, 0.74 SGD rate).
    expect(slegs.map((l) => Number(l.amount_base))).toEqual([44.4, 29.6]);
    expect(String(slegs[0].memo)).toBe('groceries');
    const [sleg] = await exec("SELECT cleared_at FROM postings WHERE id = 't-sx'");
    expect(sleg.cleared_at).not.toBeNull();

    // (e) F3: re-denominated account leg keeps the original for display.
    const [f3] = await exec("SELECT amount, currency, orig_amount, orig_currency FROM postings WHERE id = 't-f3'");
    expect(String(f3.currency)).toBe('USD');
    expect(Number(f3.orig_amount)).toBe(-50);
    expect(String(f3.orig_currency)).toBe('SGD');
  } finally {
    close();
  }
});

test('dropLegacyTables removes the legacy surface', async () => {
  const { exec, close } = await legacyFixtureDb();
  try {
    await moveLegacyData(exec);
    await dropLegacyTables(exec);
    const left = await exec(
      "SELECT name FROM sqlite_master WHERE name IN ('transactions','transfer_groups','transaction_splits','transaction_tags','transaction_attachments','transactions_fts')",
    );
    expect(left.length).toBe(0);
    // Entries survive and the books still audit clean.
    expect(await auditLedger(exec, undefined, { checkBalances: true })).toEqual([]);
  } finally {
    close();
  }
});
