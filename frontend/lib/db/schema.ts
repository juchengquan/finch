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
  is_adjustment      INTEGER NOT NULL DEFAULT 0,
  created_at         TEXT NOT NULL
);

-- Ad-hoc category splits for one transaction. When a row has splits, the
-- splits override the parent transaction's category in aggregations: the
-- parent's category_id stays as a default but isn't used while splits exist.
-- Splits' amounts (native + base) must sum to the parent's amount/amount_base.
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

CREATE TABLE IF NOT EXISTS account_balance_snapshots (
  id         TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  date       TEXT NOT NULL,
  balance    REAL NOT NULL,
  UNIQUE(account_id, date)
);

CREATE TABLE IF NOT EXISTS budgets (
  id                 TEXT PRIMARY KEY,
  ledger_id          TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name               TEXT,
  type               TEXT NOT NULL CHECK(type IN ('income','expense')),
  amount             REAL NOT NULL,
  carry_forward      REAL NOT NULL DEFAULT 0,
  frequency          TEXT NOT NULL CHECK(frequency IN ('daily','weekly','biweekly','monthly','quarterly','yearly')),
  start_date         TEXT NOT NULL,
  end_date           TEXT,
  is_recurring       INTEGER NOT NULL DEFAULT 1,
  rollover           INTEGER NOT NULL DEFAULT 0,
  rollover_limit     REAL,
  -- Last period the auto-rollover has processed for this budget (e.g.
  -- '2026-04', '2026-W17', '2026-Q2'). NULL = never rolled.
  last_rolled_period TEXT,
  -- Staged amount change activated at the next period boundary; NULL = no
  -- pending change. Lets a mid-period amount edit affect "the next cycle"
  -- without retroactively shifting the current period's spent-of-budget.
  pending_amount     REAL,
  account_ids        TEXT,
  category_ids       TEXT,
  tag_ids            TEXT,
  warning_pct        REAL NOT NULL DEFAULT 80,
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS scheduled_templates (
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
  frequency            TEXT NOT NULL CHECK(frequency IN ('once','daily','weekly','biweekly','monthly','quarterly','yearly')),
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
  color                TEXT,
  created_at           TEXT NOT NULL,
  updated_at           TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS scheduled_splits (
  id           TEXT PRIMARY KEY,
  template_id  TEXT NOT NULL REFERENCES scheduled_templates(id) ON DELETE CASCADE,
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

-- Transitional store slices not yet migrated to real tables (pending, scheduled,
-- and the override maps). Each later phase moves a key out of here into its
-- proper table. Holds one JSON value per key.
CREATE TABLE IF NOT EXISTS app_state (
  key   TEXT PRIMARY KEY,
  value TEXT
);

-- Single-row table describing the database itself: what produced it, what
-- schema version it carries, when it was last written, and (after an export)
-- the row counts + checksum a reimport uses to detect corruption / tampering.
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
CREATE INDEX IF NOT EXISTS idx_budget_last_rolled ON budgets(last_rolled_period);
CREATE INDEX IF NOT EXISTS idx_scheduled_ledger_active ON scheduled_templates(ledger_id, is_active) WHERE is_active = 1;
CREATE INDEX IF NOT EXISTS idx_summary_ledger_month ON ledger_summaries(ledger_id, year_month);
CREATE INDEX IF NOT EXISTS idx_networth_ledger_date ON net_worth_snapshots(ledger_id, date);
CREATE INDEX IF NOT EXISTS idx_goals_ledger ON goals(ledger_id);
CREATE INDEX IF NOT EXISTS idx_subs_ledger ON subscriptions(ledger_id);
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

// Versioning model
// -----------------
// Schema versions are ISO 8601 UTC datetime strings (second precision). They
// sort chronologically by simple lex order, so MIGRATIONS can stay a plain
// object iterated via Object.keys().sort().
//
// History note: versions 1..7 were integers and remain so in `LEGACY_MIGRATIONS`
// for backwards-compat opening older files. The first datetime version is
// BOOTSTRAP_VERSION — it introduces the db_metadata table and is the line that
// older integer-versioned files cross into the new scheme.
//
// SCHEMA_VERSION is whatever we've shipped most recently; bump it (with a new
// MIGRATIONS entry) whenever the canonical CREATE statements change shape.
const LEGACY_LATEST = 7;
export const BOOTSTRAP_VERSION = '2026-05-30T08:15:30Z';
export const SCHEMA_VERSION = '2026-05-30T14:00:00Z';
export const APP_NAME = 'finch';

const LEGACY_MIGRATIONS: Record<number, string[]> = {
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
  5: [
    // Balance-reconciliation marker — distinguishes manual adjustments from
    // real income/expense so they're excluded from category spend and cash flow.
    'ALTER TABLE transactions ADD COLUMN is_adjustment INTEGER NOT NULL DEFAULT 0',
  ],
  6: [
    `CREATE TABLE IF NOT EXISTS transaction_splits (
       id             TEXT PRIMARY KEY,
       transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
       category_id    TEXT REFERENCES categories(id) ON DELETE SET NULL,
       amount         REAL NOT NULL,
       amount_base    REAL NOT NULL,
       description    TEXT,
       sort_order     INTEGER NOT NULL DEFAULT 0
     )`,
    'CREATE INDEX IF NOT EXISTS idx_txn_splits_tx ON transaction_splits(transaction_id)',
  ],
  7: [
    'ALTER TABLE scheduled_templates ADD COLUMN color TEXT',
  ],
};

// Datetime-keyed migrations applied above BOOTSTRAP_VERSION. The bootstrap step
// itself (creating db_metadata + seeding its row) is handled inline by migrate()
// because it transitions the file from the integer scheme to the datetime one.
const MIGRATIONS: Record<string, string[]> = {
  // Budget cycles + automatic period rollover groundwork (see
  // plans/BUDGET_CYCLES_PLAN.md). Two new columns + an index on the
  // catch-up marker — no behavioural change until later commits wire the
  // rollover loop and cycle-aware reads.
  '2026-05-30T14:00:00Z': [
    'ALTER TABLE budgets ADD COLUMN last_rolled_period TEXT',
    'ALTER TABLE budgets ADD COLUMN pending_amount REAL',
    'CREATE INDEX IF NOT EXISTS idx_budget_last_rolled ON budgets(last_rolled_period)',
  ],
};

// Read the package version once so the metadata row reports it on import.
function appVersion(): string {
  try {
    // The package.json is at the import root via the @/* alias.
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const pkg = require('@/package.json') as { version?: string };
    return String(pkg.version ?? '0.0.0');
  } catch {
    return '0.0.0';
  }
}

async function ensureMetadataRow(exec: ExecFn, schemaVersion: string): Promise<void> {
  const rows = await exec('SELECT id FROM db_metadata WHERE id = 1');
  const now = new Date().toISOString();
  if (rows.length === 0) {
    await exec(
      `INSERT INTO db_metadata (id, app_name, schema_version, app_version, created_at, updated_at)
       VALUES (1, ?, ?, ?, ?, ?)`,
      [APP_NAME, schemaVersion, appVersion(), now, now],
    );
  } else {
    await exec(
      `UPDATE db_metadata SET schema_version = ?, app_version = ?, updated_at = ? WHERE id = 1`,
      [schemaVersion, appVersion(), now],
    );
  }
}

/**
 * Bring a database up to SCHEMA_VERSION. `fresh` means the file was just created
 * (CREATE statements are already current → only stamp the version + create the
 * metadata row). An existing file is detected by whether it has a db_metadata
 * row: if it doesn't, it predates the datetime scheme and gets the legacy
 * integer migrations replayed before being bootstrapped to BOOTSTRAP_VERSION.
 * Either way, datetime migrations strictly newer than the current
 * schema_version are then applied in lex order.
 */
export async function migrate(exec: ExecFn, opts: { fresh: boolean }): Promise<void> {
  if (opts.fresh) {
    await ensureMetadataRow(exec, SCHEMA_VERSION);
    // Stamp user_version too as a defence-in-depth legacy probe.
    await exec(`PRAGMA user_version = ${LEGACY_LATEST}`);
    return;
  }

  // db_metadata presence is the cleanest signal that a file has crossed the
  // bootstrap line. We probe with a best-effort SELECT so the absence of the
  // table doesn't blow up here — applySchema is expected to have just run.
  const metaRows = await exec('SELECT schema_version FROM db_metadata WHERE id = 1');
  if (metaRows.length === 0) {
    // Pre-bootstrap file. Replay the integer migrations through LEGACY_LATEST.
    const v = await exec('PRAGMA user_version');
    const from = Number(v[0]?.user_version ?? 0) || 1;
    for (let i = from + 1; i <= LEGACY_LATEST; i++) {
      for (const sql of LEGACY_MIGRATIONS[i] ?? []) await exec(sql);
    }
    await exec(`PRAGMA user_version = ${LEGACY_LATEST}`);
    await ensureMetadataRow(exec, BOOTSTRAP_VERSION);
  }

  // Walk datetime migrations strictly greater than the recorded version.
  const cur = String(
    (await exec('SELECT schema_version FROM db_metadata WHERE id = 1'))[0]?.schema_version ?? BOOTSTRAP_VERSION,
  );
  const ordered = Object.keys(MIGRATIONS).sort();
  for (const version of ordered) {
    if (version <= cur) continue;
    for (const sql of MIGRATIONS[version] ?? []) await exec(sql);
  }

  if (ordered.length > 0 || cur !== SCHEMA_VERSION) {
    await ensureMetadataRow(exec, SCHEMA_VERSION);
  }
}
