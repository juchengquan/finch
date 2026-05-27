// The full relational schema from plans/database_design_en.md, adapted for the
// browser sqlite-wasm runtime. Deliberate, documented deviations from the doc:
//   - Primary keys reuse the app's existing string ids (e.g. 'food', 'cc') as
//     TEXT PKs rather than UUIDs, so the migration can keep the current UI
//     lookups (catById/acctById) working slice by slice. New rows get generated
//     ids. (Doc §3.1 prefers UUIDs; not required for a single-device file.)
//   - `date` columns are ISO `YYYY-MM-DD` (the app's existing format), not the
//     doc's `YYYY/MM/DD`. strftime('%Y-%m', date) still works for summaries.
//
// One file holds ALL ledgers; every per-ledger table carries `ledger_id`.

export const SCHEMA = `
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS ledgers (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  base_currency TEXT NOT NULL DEFAULT 'SGD',
  is_default    INTEGER NOT NULL DEFAULT 0,
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS account_groups (
  id                   TEXT PRIMARY KEY,
  ledger_id            TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name                 TEXT NOT NULL,
  include_in_net_worth INTEGER NOT NULL DEFAULT 1,
  sort_order           INTEGER NOT NULL DEFAULT 0,
  created_at           TEXT NOT NULL,
  updated_at           TEXT NOT NULL
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
  credit_limit         REAL,
  notes                TEXT,
  color                TEXT,
  last4                TEXT,
  institution          TEXT,
  routing              TEXT,
  primary_budget_id    TEXT,
  include_in_net_worth INTEGER,
  is_active            INTEGER NOT NULL DEFAULT 1,
  created_at           TEXT NOT NULL,
  updated_at           TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS categories (
  id          TEXT PRIMARY KEY,
  ledger_id   TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  parent_name TEXT,
  type        TEXT NOT NULL CHECK(type IN ('expense','income','transfer','refund')),
  icon        TEXT,
  hue         INTEGER,
  sort_order  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS tags (
  id        TEXT PRIMARY KEY,
  ledger_id TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name      TEXT NOT NULL,
  color     TEXT
);

CREATE TABLE IF NOT EXISTS transaction_tags (
  transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
  tag_id         TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (transaction_id, tag_id)
);

CREATE TABLE IF NOT EXISTS counterparties (
  id                TEXT PRIMARY KEY,
  ledger_id         TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  standardized_name TEXT NOT NULL,
  aliases           TEXT,
  category          TEXT,
  logo_url          TEXT,
  is_verified       INTEGER NOT NULL DEFAULT 0,
  created_at        TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS transfer_groups (
  id            TEXT PRIMARY KEY,
  ledger_id     TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  created_at    TEXT NOT NULL,
  amount_base   REAL NOT NULL,
  from_currency TEXT NOT NULL,
  to_currency   TEXT NOT NULL,
  exchange_rate REAL,
  notes         TEXT
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
  exchange_rate_date TEXT,
  description        TEXT,
  category_id        TEXT REFERENCES categories(id) ON DELETE SET NULL,
  counterparty_id    TEXT REFERENCES counterparties(id) ON DELETE SET NULL,
  transfer_group_id  TEXT REFERENCES transfer_groups(id) ON DELETE SET NULL,
  status             TEXT NOT NULL DEFAULT 'confirmed' CHECK(status IN ('pending','confirmed','cancelled')),
  confirmed_at       TEXT,
  source_template_id TEXT,
  source_split_id    TEXT,
  balance_after      REAL NOT NULL,
  currency           TEXT NOT NULL DEFAULT 'SGD',
  notes              TEXT,
  recurring          INTEGER NOT NULL DEFAULT 0,
  created_at         TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS account_balance_snapshots (
  id         TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  date       TEXT NOT NULL,
  balance    REAL NOT NULL,
  UNIQUE(account_id, date)
);

CREATE TABLE IF NOT EXISTS budgets (
  id             TEXT PRIMARY KEY,
  ledger_id      TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name           TEXT,
  type           TEXT NOT NULL CHECK(type IN ('income','expense')),
  amount         REAL NOT NULL,
  carry_forward  REAL NOT NULL DEFAULT 0,
  frequency      TEXT NOT NULL CHECK(frequency IN ('daily','weekly','biweekly','monthly','quarterly','yearly')),
  start_date     TEXT NOT NULL,
  end_date       TEXT,
  is_recurring   INTEGER NOT NULL DEFAULT 1,
  rollover       INTEGER NOT NULL DEFAULT 0,
  rollover_limit REAL,
  account_ids    TEXT,
  category_ids   TEXT,
  tag_ids        TEXT,
  warning_pct    REAL NOT NULL DEFAULT 80,
  created_at     TEXT NOT NULL,
  updated_at     TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS recurring_templates (
  id                   TEXT PRIMARY KEY,
  ledger_id            TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name                 TEXT,
  type                 TEXT NOT NULL CHECK(type IN ('income','expense','transfer')),
  amount               REAL,
  amount_varies        INTEGER NOT NULL DEFAULT 0,
  splits_enabled       INTEGER NOT NULL DEFAULT 0,
  account_id           TEXT REFERENCES accounts(id) ON DELETE RESTRICT,
  account_name         TEXT,
  from_account_id      TEXT REFERENCES accounts(id) ON DELETE RESTRICT,
  from_account_name    TEXT,
  category_id          TEXT REFERENCES categories(id) ON DELETE RESTRICT,
  frequency            TEXT NOT NULL CHECK(frequency IN ('daily','weekly','biweekly','monthly','quarterly','yearly')),
  day_of_month         INTEGER,
  day_of_week          INTEGER,
  nth_weekday          INTEGER,
  start_date           TEXT NOT NULL,
  end_date             TEXT,
  next_run             TEXT,
  last_run             TEXT,
  auto_post            INTEGER NOT NULL DEFAULT 1,
  reminder_days_before INTEGER NOT NULL DEFAULT 3,
  is_active            INTEGER NOT NULL DEFAULT 1,
  is_archived          INTEGER NOT NULL DEFAULT 0,
  max_executions       INTEGER,
  last_executed_at     TEXT,
  notes                TEXT,
  created_at           TEXT NOT NULL,
  updated_at           TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS recurring_splits (
  id           TEXT PRIMARY KEY,
  template_id  TEXT NOT NULL REFERENCES recurring_templates(id) ON DELETE CASCADE,
  account_id   TEXT REFERENCES accounts(id) ON DELETE RESTRICT,
  account_name TEXT,
  amount_pct   REAL,
  amount_abs   REAL,
  category_id  TEXT REFERENCES categories(id) ON DELETE RESTRICT,
  description  TEXT,
  sort_order   INTEGER NOT NULL DEFAULT 0,
  CHECK (amount_pct IS NOT NULL OR amount_abs IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS net_worth_snapshots (
  id               TEXT PRIMARY KEY,
  ledger_id        TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  date             TEXT NOT NULL,
  total_base       REAL,
  total_investment REAL,
  total_debt       REAL,
  notes            TEXT,
  UNIQUE(ledger_id, date)
);

CREATE TABLE IF NOT EXISTS goals (
  id         TEXT PRIMARY KEY,
  ledger_id  TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  target     REAL NOT NULL,
  saved      REAL NOT NULL DEFAULT 0,
  eta        TEXT,
  hue        INTEGER NOT NULL DEFAULT 200,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS subscriptions (
  id         TEXT PRIMARY KEY,
  ledger_id  TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  amount     REAL NOT NULL,
  cadence    TEXT NOT NULL DEFAULT 'monthly',
  next_date  TEXT,
  hue        INTEGER NOT NULL DEFAULT 200,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS scheduled_items (
  id         TEXT PRIMARY KEY,
  ledger_id  TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  day        INTEGER NOT NULL,
  month      TEXT NOT NULL,
  label      TEXT NOT NULL,
  amount     REAL NOT NULL,
  type       TEXT NOT NULL,
  color      TEXT
);

CREATE TABLE IF NOT EXISTS ledger_summaries (
  id                TEXT PRIMARY KEY,
  ledger_id         TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  year_month        TEXT NOT NULL,
  type              TEXT NOT NULL CHECK(type IN ('income','expense','transfer_in','transfer_out')),
  total_base        REAL NOT NULL,
  transaction_count INTEGER NOT NULL DEFAULT 0,
  UNIQUE(ledger_id, year_month, type)
);

CREATE TABLE IF NOT EXISTS exchange_rates (
  date        TEXT NOT NULL,
  currency    TEXT NOT NULL,
  rate_to_sgd REAL NOT NULL,
  source      TEXT,
  PRIMARY KEY (date, currency)
);

CREATE TABLE IF NOT EXISTS sync_log (
  device_id    TEXT PRIMARY KEY,
  ledger_id    TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  device_name  TEXT NOT NULL,
  last_sync_at TEXT NOT NULL,
  last_txn_id  TEXT,
  is_current   INTEGER NOT NULL DEFAULT 0
);

-- Transitional store slices not yet migrated to real tables (pending, recurring,
-- and the override maps). Each later phase moves a key out of here into its
-- proper table. Holds one JSON value per key.
CREATE TABLE IF NOT EXISTS app_state (
  key   TEXT PRIMARY KEY,
  value TEXT
);

CREATE INDEX IF NOT EXISTS idx_ag_ledger ON account_groups(ledger_id);
CREATE INDEX IF NOT EXISTS idx_acc_ledger ON accounts(ledger_id);
CREATE INDEX IF NOT EXISTS idx_acc_group ON accounts(group_id);
CREATE INDEX IF NOT EXISTS idx_cat_ledger ON categories(ledger_id);
CREATE INDEX IF NOT EXISTS idx_tags_ledger ON tags(ledger_id);
CREATE INDEX IF NOT EXISTS idx_counterparty_ledger ON counterparties(ledger_id);
CREATE INDEX IF NOT EXISTS idx_counterparty_verified ON counterparties(is_verified);
CREATE INDEX IF NOT EXISTS idx_txn_ledger_date ON transactions(ledger_id, date);
CREATE INDEX IF NOT EXISTS idx_txn_account_date ON transactions(account_id, date);
CREATE INDEX IF NOT EXISTS idx_txn_category ON transactions(category_id);
CREATE INDEX IF NOT EXISTS idx_txn_transfer_group ON transactions(transfer_group_id);
CREATE INDEX IF NOT EXISTS idx_txn_pending ON transactions(ledger_id, status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_txntag_txn ON transaction_tags(transaction_id);
CREATE INDEX IF NOT EXISTS idx_txntag_tag ON transaction_tags(tag_id);
CREATE INDEX IF NOT EXISTS idx_snap_account_date ON account_balance_snapshots(account_id, date);
CREATE INDEX IF NOT EXISTS idx_budget_ledger_freq ON budgets(ledger_id, frequency, start_date);
CREATE INDEX IF NOT EXISTS idx_recurring_ledger_active ON recurring_templates(ledger_id, is_active) WHERE is_active = 1;
CREATE INDEX IF NOT EXISTS idx_summary_ledger_month ON ledger_summaries(ledger_id, year_month);
CREATE INDEX IF NOT EXISTS idx_networth_ledger_date ON net_worth_snapshots(ledger_id, date);
CREATE INDEX IF NOT EXISTS idx_goals_ledger ON goals(ledger_id);
CREATE INDEX IF NOT EXISTS idx_subs_ledger ON subscriptions(ledger_id);
CREATE INDEX IF NOT EXISTS idx_sched_ledger ON scheduled_items(ledger_id);
CREATE INDEX IF NOT EXISTS idx_rate_date ON exchange_rates(date);
CREATE INDEX IF NOT EXISTS idx_rate_currency ON exchange_rates(currency);

CREATE TRIGGER IF NOT EXISTS tr_update_account_balance
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
  UPDATE accounts
  SET current_balance = NEW.balance_after, updated_at = datetime('now')
  WHERE id = NEW.account_id;
END;

CREATE TRIGGER IF NOT EXISTS tr_snapshot_balance
AFTER INSERT ON transactions
FOR EACH ROW
WHEN NEW.balance_after IS NOT NULL
BEGIN
  INSERT OR IGNORE INTO account_balance_snapshots (id, account_id, date, balance)
  VALUES (lower(hex(randomblob(16))), NEW.account_id, NEW.date, NEW.balance_after);
END;

CREATE TRIGGER IF NOT EXISTS tr_update_ledger_summary
AFTER INSERT ON transactions
FOR EACH ROW
WHEN NEW.status = 'confirmed'
BEGIN
  INSERT INTO ledger_summaries (id, ledger_id, year_month, type, total_base, transaction_count)
  VALUES (
    lower(hex(randomblob(16))),
    NEW.ledger_id,
    strftime('%Y-%m', NEW.date),
    CASE
      WHEN NEW.transfer_group_id IS NOT NULL AND NEW.amount > 0 THEN 'transfer_in'
      WHEN NEW.transfer_group_id IS NOT NULL AND NEW.amount < 0 THEN 'transfer_out'
      WHEN NEW.amount > 0 THEN 'income'
      ELSE 'expense'
    END,
    NEW.amount_base,
    1
  )
  ON CONFLICT(ledger_id, year_month, type) DO UPDATE SET
    total_base = total_base + NEW.amount_base,
    transaction_count = transaction_count + 1;
END;

CREATE TRIGGER IF NOT EXISTS tr_update_ledger_summary_status
AFTER UPDATE OF status ON transactions
FOR EACH ROW
WHEN OLD.status = 'confirmed' AND NEW.status != 'confirmed'
BEGIN
  INSERT INTO ledger_summaries (id, ledger_id, year_month, type, total_base, transaction_count)
  VALUES (
    lower(hex(randomblob(16))),
    NEW.ledger_id,
    strftime('%Y-%m', NEW.date),
    CASE
      WHEN NEW.transfer_group_id IS NOT NULL AND NEW.amount > 0 THEN 'transfer_in'
      WHEN NEW.transfer_group_id IS NOT NULL AND NEW.amount < 0 THEN 'transfer_out'
      WHEN NEW.amount > 0 THEN 'income'
      ELSE 'expense'
    END,
    -OLD.amount_base,
    -1
  )
  ON CONFLICT(ledger_id, year_month, type) DO UPDATE SET
    total_base = total_base - OLD.amount_base,
    transaction_count = transaction_count - 1;
END;
`;

export async function applySchema(exec: (sql: string, bind?: (string | number | null)[]) => Promise<unknown>): Promise<void> {
  await exec(SCHEMA);
}

type ExecFn = (sql: string, bind?: (string | number | null)[]) => Promise<Record<string, unknown>[]>;

// Bump when the CREATE statements above change shape. Version 1 = the original
// schema; 2 adds accounts.opening_balance; 3 adds account display columns;
// 4 adds categories.hue.
export const SCHEMA_VERSION = 4;

// MIGRATIONS[v] upgrades an existing database from version v-1 to v. A freshly
// created DB already has the latest CREATE statements, so it skips these and is
// just stamped with SCHEMA_VERSION.
const MIGRATIONS: Record<number, string[]> = {
  2: [
    'ALTER TABLE accounts ADD COLUMN opening_balance REAL NOT NULL DEFAULT 0',
    // Backfill from the (assumed-correct) current balance and the live txn set.
    `UPDATE accounts SET opening_balance = ROUND(current_balance - COALESCE(
       (SELECT SUM(amount_base) FROM transactions
         WHERE transactions.account_id = accounts.id AND status != 'cancelled'), 0), 2)`,
  ],
  3: [
    // Display fields previously held in the accountOverrides app_state shim.
    'ALTER TABLE accounts ADD COLUMN color TEXT',
    'ALTER TABLE accounts ADD COLUMN last4 TEXT',
    'ALTER TABLE accounts ADD COLUMN institution TEXT',
    'ALTER TABLE accounts ADD COLUMN routing TEXT',
  ],
  4: [
    // Category accent colour (hue 0–360), previously only in the static mock.
    'ALTER TABLE categories ADD COLUMN hue INTEGER',
  ],
};

/**
 * Bring a database up to SCHEMA_VERSION. `fresh` means the file was just created
 * (CREATE statements are already current → only stamp the version). An existing
 * file gets the ordered migrations for each version above its current one; a
 * pre-versioning file reports version 0 and is treated as version 1.
 */
export async function migrate(exec: ExecFn, opts: { fresh: boolean }): Promise<void> {
  if (!opts.fresh) {
    const rows = await exec('PRAGMA user_version');
    const from = Number(rows[0]?.user_version ?? 0) || 1;
    for (let v = from + 1; v <= SCHEMA_VERSION; v++) {
      for (const sql of MIGRATIONS[v] ?? []) await exec(sql);
    }
  }
  await exec(`PRAGMA user_version = ${SCHEMA_VERSION}`);
}
