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
  id         TEXT PRIMARY KEY,
  ledger_id  TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS budget_groups (
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
  -- Cached running balance. Kept in sync by recomputeAccount() — see
  -- queries/accounts.ts. Treat as derived state; opening_balance is the
  -- source of truth for the starting point.
  current_balance      REAL NOT NULL DEFAULT 0,
  opening_balance      REAL NOT NULL DEFAULT 0,
  color                TEXT,
  last4                TEXT,
  institution          TEXT,
  routing              TEXT,
  -- Sort order within the account group (and within "ungrouped"). Smaller
  -- values come first.
  sort_order           INTEGER NOT NULL DEFAULT 0,
  -- Whether this account counts toward net worth. Defaulted from the type
  -- column at create time (credit_card → 0, everything else → 1); the user
  -- can flip it per-account afterwards. account_groups are purely
  -- organisational and do not influence this flag.
  include_in_net_worth INTEGER NOT NULL DEFAULT 1,
  is_active            INTEGER NOT NULL DEFAULT 1,
  -- Set when is_active flips to 0; null when active. Lets the UI surface
  -- "archived <date>" without losing the audit trail.
  archived_at          TEXT,
  created_at           TEXT NOT NULL,
  updated_at           TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS categories (
  id         TEXT PRIMARY KEY,
  ledger_id  TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  type       TEXT NOT NULL CHECK(type IN ('expense','income','transfer','refund')),
  icon       TEXT,
  hue        INTEGER,
  sort_order INTEGER NOT NULL DEFAULT 0
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
  -- Rate used to derive amount_base from amount at txn time; locked so a later
  -- rates-table edit doesn't reshape history. The rate's effective date is the
  -- txn's own date column — we don't carry a separate exchange_rate_date.
  exchange_rate      REAL NOT NULL,
  description        TEXT,
  category_id        TEXT REFERENCES categories(id) ON DELETE SET NULL,
  transfer_group_id  TEXT REFERENCES transfer_groups(id) ON DELETE SET NULL,
  kind               TEXT NOT NULL DEFAULT 'expense' CHECK(kind IN ('income','expense','transfer','adjustment')),
  status             TEXT NOT NULL DEFAULT 'confirmed' CHECK(status IN ('pending','confirmed')),
  confirmed_at       TEXT,
  source_template_id TEXT,
  currency           TEXT NOT NULL DEFAULT 'SGD',
  notes              TEXT,
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

CREATE TABLE IF NOT EXISTS budgets (
  id                 TEXT PRIMARY KEY,
  ledger_id          TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  group_id           TEXT REFERENCES budget_groups(id) ON DELETE SET NULL,
  name               TEXT,
  type               TEXT NOT NULL CHECK(type IN ('income','expense')),
  amount             REAL NOT NULL,
  saved              REAL NOT NULL DEFAULT 0,
  carry_forward      REAL NOT NULL DEFAULT 0,
  frequency          TEXT NOT NULL CHECK(frequency IN ('daily','weekly','biweekly','monthly','quarterly','yearly')),
  start_date         TEXT NOT NULL,
  end_date           TEXT,
  is_recurring       INTEGER NOT NULL DEFAULT 1,
  rollover           INTEGER NOT NULL DEFAULT 0,
  rollover_limit     REAL,
  -- Last period the auto-rollover has processed for this budget (e.g.
  -- '2026-04', '2026-W17', '2026-Q2', 'BW-2026-04-13'). NULL = never rolled.
  last_rolled_period TEXT,
  -- Staged amount change activated at the next period boundary; NULL = no
  -- pending change. Lets a mid-period amount edit affect only the next
  -- cycle (BUDGET_CYCLES_PLAN §2).
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
  start_date           TEXT NOT NULL,
  end_date             TEXT,
  next_run             TEXT,
  last_run             TEXT,
  auto_post            INTEGER NOT NULL DEFAULT 1,
  is_active            INTEGER NOT NULL DEFAULT 1,
  max_executions       INTEGER,
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
CREATE INDEX IF NOT EXISTS idx_budget_groups_ledger ON budget_groups(ledger_id);
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
CREATE INDEX IF NOT EXISTS idx_budget_ledger_freq ON budgets(ledger_id, frequency, start_date);
CREATE INDEX IF NOT EXISTS idx_budget_last_rolled ON budgets(last_rolled_period);
CREATE INDEX IF NOT EXISTS idx_scheduled_ledger_active ON scheduled_templates(ledger_id, is_active) WHERE is_active = 1;
CREATE INDEX IF NOT EXISTS idx_scheduled_splits_template ON scheduled_splits(template_id);
CREATE INDEX IF NOT EXISTS idx_rate_date ON exchange_rates(date);
CREATE INDEX IF NOT EXISTS idx_rate_currency ON exchange_rates(currency);
CREATE INDEX IF NOT EXISTS idx_txn_source_template ON transactions(source_template_id) WHERE source_template_id IS NOT NULL;

-- Confirmed inserts move the account balance by their delta (in the account's
-- currency: the native amount when the entry is in that currency, else the
-- ledger-base figure for a foreign entry on a base-currency account). Pending
-- rows don't move it; recomputeAccount() handles confirm/edit/delete.
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

export async function applySchema(exec: (sql: string, bind?: (string | number | null)[]) => Promise<unknown>): Promise<void> {
  await exec(SCHEMA);
}

type ExecFn = (sql: string, bind?: (string | number | null)[]) => Promise<Record<string, unknown>[]>;

// Versioning
// ----------
// A single ISO 8601 UTC datetime stamped into db_metadata. This project is
// pre-release with no databases to preserve, so there is no legacy / backward-
// compat machinery — fresh databases are created directly from the canonical
// SCHEMA above. A future shape change bumps SCHEMA_VERSION and adds a MIGRATIONS
// entry to carry forward databases created after this baseline.
export const SCHEMA_VERSION = '2026-06-01T04:00:00Z';
export const APP_NAME = 'finch';

// Schema changes made after the baseline, keyed by the version they upgrade TO.
// Applied in lex (== chronological) order for versions strictly greater than a
// database's recorded schema_version. Empty at the baseline.
const MIGRATIONS: Record<string, string[]> = {
  // '2026-06-15T12:00:00Z': ['ALTER TABLE accounts ADD COLUMN preferred_rate TEXT'],
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
 * Stamp/upgrade a database to SCHEMA_VERSION. `fresh` files were just created
 * from the canonical SCHEMA, so this only records the metadata row. Existing
 * files replay any MIGRATIONS newer than their recorded schema_version, then
 * re-stamp. (No legacy/bootstrap handling — see the Versioning note above.)
 */
export async function migrate(exec: ExecFn, opts: { fresh: boolean }): Promise<void> {
  if (opts.fresh) {
    await ensureMetadataRow(exec, SCHEMA_VERSION);
    return;
  }
  const cur = String(
    (await exec('SELECT schema_version FROM db_metadata WHERE id = 1'))[0]?.schema_version ?? '',
  );
  for (const version of Object.keys(MIGRATIONS).sort()) {
    if (version <= cur) continue;
    for (const sql of MIGRATIONS[version] ?? []) await exec(sql);
  }
  await ensureMetadataRow(exec, SCHEMA_VERSION);
}
