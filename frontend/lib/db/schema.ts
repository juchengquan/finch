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

import { ENTRIES_SCHEMA, CATEGORIES_UPGRADE } from './entries-schema';

// Receipt attachments for the double-entry entries layer (PR B). Same
// pointer-only design as transaction_attachments (RECEIPT_PHOTOS_PLAN §2),
// which it replaces at cutover; rel_path stays server-internal.
// Also consumed by legacyFixtureDb() in cutover.test.ts.
export const ENTRY_ATTACHMENTS_DDL = `
CREATE TABLE IF NOT EXISTS entry_attachments (
  id                TEXT PRIMARY KEY,
  ledger_id         TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  entry_id          TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
  kind              TEXT NOT NULL CHECK(kind IN ('image','pdf')),
  rel_path          TEXT NOT NULL,
  mime_type         TEXT NOT NULL,
  byte_size         INTEGER NOT NULL,
  sha256            TEXT NOT NULL,
  original_filename TEXT,
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_eattach_entry  ON entry_attachments(entry_id);
CREATE INDEX IF NOT EXISTS idx_eattach_ledger ON entry_attachments(ledger_id);`;

// FTS over entries.description + notes (replaces transactions_fts at cutover).
// Also consumed by legacyFixtureDb() in cutover.test.ts.
export const ENTRIES_FTS_DDL = `
CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
  id UNINDEXED,
  description,
  notes,
  tokenize='unicode61 remove_diacritics 2'
);
CREATE TRIGGER IF NOT EXISTS tr_entry_fts_insert AFTER INSERT ON entries BEGIN
  INSERT INTO entries_fts (id, description, notes)
  VALUES (NEW.id, COALESCE(NEW.description, ''), COALESCE(NEW.notes, ''));
END;
CREATE TRIGGER IF NOT EXISTS tr_entry_fts_delete AFTER DELETE ON entries BEGIN
  DELETE FROM entries_fts WHERE id = OLD.id;
END;
CREATE TRIGGER IF NOT EXISTS tr_entry_fts_update AFTER UPDATE OF description, notes ON entries BEGIN
  UPDATE entries_fts SET description = COALESCE(NEW.description, ''), notes = COALESCE(NEW.notes, '')
   WHERE id = NEW.id;
END;`;

export const SCHEMA = `
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS ledgers (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  base_currency TEXT NOT NULL DEFAULT 'SGD',
  is_default    INTEGER NOT NULL DEFAULT 0,
  -- Cosmetic fields surfaced in the ledger switcher (LEDGER_CRUD_PLAN section 2).
  -- Previously lived in static data/ledgers.json only; now persisted so a
  -- user-created ledger can carry its own colour/tagline and so packs
  -- round-trip the full visual state across devices. Both nullable -- the
  -- switcher falls back to a hue derived from the id when color is null.
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
  -- Cached running balance. Kept in sync by recomputeAccountFromPostings() —
  -- see queries/accounts.ts and lib/db/entries.ts. Treat as derived state;
  -- the opening entry (open-<id>) is the source of truth for the starting
  -- point and is included in the postings sum.
  current_balance      REAL NOT NULL DEFAULT 0,
  color                TEXT,
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
  -- Reconcile-to-statement checkpoint (RECONCILE_PLAN §2.2). Stamped by
  -- reconcileAccount when the user finishes a guided session: the statement's
  -- ending date + the matching balance in this account's native currency.
  -- Both null when the account has never been reconciled. Editing a row that
  -- was cleared during this session flips the badge to "edited since" via a
  -- transaction-level updated_at comparison; we don't store a separate "still
  -- valid" flag.
  last_reconciled_at      TEXT,
  last_reconciled_balance REAL,
  created_at           TEXT NOT NULL,
  updated_at           TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS categories (
  id         TEXT PRIMARY KEY,
  ledger_id  TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  -- Optional parent within a ≤3-level taxonomy (CATEGORIES_LEVEL3_PLAN).
  -- NULL = top-level. Depth cap is enforced in the mutation layer
  -- (assertCanBeParent / assertSubtreeFitsUnder in mutations.ts) — a
  -- self-referential CHECK is hard to express cleanly in SQLite, so the
  -- rule lives where the writes happen. Promote-on-delete: SET NULL pushes
  -- children up to top-level when their parent is removed (recursively
  -- safe at any depth — a level-3 grandchild becomes level-2 when its
  -- level-2 parent is deleted, no rows are destroyed).
  parent_id  TEXT REFERENCES categories(id) ON DELETE SET NULL,
  name       TEXT NOT NULL,
  kind       TEXT NOT NULL CHECK(kind IN ('expense','income','equity')),
  icon       TEXT,
  color      TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  -- Equity system rows (DOUBLE_ENTRY_PLAN §2.3): 'opening'/'adjustment'/'fx'
  -- markers for the three per-ledger system categories. NULL = ordinary
  -- user category. kind='equity' rows are hidden from pickers and excluded
  -- from spend aggregations.
  system     TEXT CHECK(system IN ('opening','adjustment','fx')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_cat_parent ON categories(parent_id) WHERE parent_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_cat_system ON categories(ledger_id, system) WHERE system IS NOT NULL;

CREATE TABLE IF NOT EXISTS tags (
  id         TEXT PRIMARY KEY,
  ledger_id  TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  color      TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS counterparties (
  id                TEXT PRIMARY KEY,
  ledger_id         TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  -- COLLATE NOCASE makes "=" and the (ledger_id, name) index case-insensitive
  -- without needing LOWER() in the WHERE clause. resolveCounterpartyIdByName
  -- runs on every transaction write, so the index actually getting used here
  -- matters.
  name              TEXT NOT NULL COLLATE NOCASE,
  is_verified       INTEGER NOT NULL DEFAULT 0,
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
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
  -- Last period the auto-rollover has processed for this budget (e.g.
  -- '2026-04', '2026-W17', '2026-Q2', 'BW-2026-04-13'). NULL = never rolled.
  last_rolled_period TEXT,
  -- Staged amount change activated at the next period boundary; NULL = no
  -- pending change. Lets a mid-period amount edit affect only the next
  -- cycle (BUDGET_CYCLES_PLAN §2).
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
  -- Description stamped onto each posted transaction (falls back to name when
  -- null). Distinct from name, which is the template's own label in the UI.
  description          TEXT,
  kind                 TEXT NOT NULL CHECK(kind IN ('income','expense','transfer')),
  amount               REAL,
  amount_varies        INTEGER NOT NULL DEFAULT 0,
  splits_enabled       INTEGER NOT NULL DEFAULT 0,
  -- Account references are real FKs (like transactions); display names are
  -- derived by joining accounts at read time, not stored. The native currency
  -- of a posted row is the linked account's currency.
  account_id           TEXT NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  from_account_id      TEXT REFERENCES accounts(id) ON DELETE RESTRICT,
  -- SET NULL on delete (matches transactions.category_id): the schedule keeps
  -- running, posting uncategorized rows the user can re-classify later. RESTRICT
  -- would block category cleanup whenever any schedule referenced it.
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
  -- Installment plan tracking. installment_total = how many payments the plan
  -- has in total (e.g. 24 for a 24-month phone contract); NULL = "this is a
  -- normal recurring expense, not a finite plan". The matching "paid so far"
  -- count is NOT stored — it's derived from the confirmed transactions linked
  -- back through source_template_id, so pending rows don't inflate progress
  -- and a cancelled pending row leaves the counter untouched. Cash math only:
  -- the interest/principal split of a payment lives in transaction splits on
  -- the posted row, not here.
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

-- Per-position investment holdings inside an investment-type account.
-- Cash sits in accounts.current_balance (driven by transactions); positions
-- (e.g. 100 shares of VTI) live here with a locked cost basis + the last price
-- the user logged. Total account value at display = cash + Σ shares × last_price
-- (computed live, not stored). Prices are entered manually; we keep no history
-- table — last_price is the authoritative figure and gets overwritten on update.
-- ON DELETE CASCADE on account_id: archiving an account is the supported
-- "decomission" path; a hard account delete (only possible when txn-less)
-- takes its holdings with it rather than leaving orphans.
CREATE TABLE IF NOT EXISTS holdings (
  id              TEXT PRIMARY KEY,
  ledger_id       TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  account_id      TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  symbol          TEXT NOT NULL,
  name            TEXT,
  shares          REAL NOT NULL DEFAULT 0,
  -- Total amount paid in the holding's own currency, locked at entry. The
  -- per-share average is derived as cost_basis / shares; we don't store it
  -- because partial sells / DRIP reinvestments would have to keep both in sync.
  cost_basis      REAL NOT NULL DEFAULT 0,
  currency        TEXT NOT NULL,
  -- Last price the user logged (per share, in the row's own currency). NULL =
  -- no price yet; the holding shows cost basis but no live valuation.
  last_price      REAL,
  last_price_date TEXT,
  notes           TEXT,
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS exchange_rates (
  date     TEXT NOT NULL,
  currency TEXT NOT NULL,
  rate     REAL NOT NULL,
  source   TEXT,
  PRIMARY KEY (date, currency)
);

-- Conditional rules engine (RULES_ENGINE_PLAN). Each row is one if-then rule.
-- The condition tree and the ordered action list are stored as JSON text (same
-- flat-JSON idiom as budgets.account_ids / app_state.value) and deserialized
-- into the typed Condition / Action shapes by the engine at read time;
-- normalizing the tree into sub-tables would be over-engineering for a
-- single-user app. Rules apply in priority order (lower first); later rules
-- override earlier ones, with the losing rule still recorded in the
-- transaction's applied_rule_ids for traceability.
CREATE TABLE IF NOT EXISTS rules (
  id           TEXT PRIMARY KEY,
  ledger_id    TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name         TEXT,
  priority     INTEGER NOT NULL DEFAULT 100,
  condition    TEXT NOT NULL,
  actions      TEXT NOT NULL,
  is_active    INTEGER NOT NULL DEFAULT 1,
  -- Whether the rule re-fires when a transaction is edited (not just on
  -- insert). Defaults to 0 (insert-only) — the safer footgun-free default;
  -- the user opts a rule into edit-time re-application explicitly.
  run_on_edit  INTEGER NOT NULL DEFAULT 0,
  -- Last time this rule was run across existing rows (the "Apply to existing"
  -- backfill); null = never backfilled.
  last_applied_at TEXT,
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL
);

-- Transitional store slices not yet migrated to real tables (pending, scheduled,
-- and the override maps). Each later phase moves a key out of here into its
-- proper table. Holds one JSON value per key.
CREATE TABLE IF NOT EXISTS app_state (
  key        TEXT PRIMARY KEY,
  value      TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
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

-- ===== Double-entry core (DOUBLE_ENTRY_PLAN; PR A #114, canonicalized in PR B) =====
${ENTRIES_SCHEMA}

-- Receipt attachments, re-pointed at entries (PR B). Same pointer-only design
-- as transaction_attachments (RECEIPT_PHOTOS_PLAN §2), which it replaces at
-- cutover; rel_path stays server-internal.
${ENTRY_ATTACHMENTS_DDL}

-- FTS over entries.description + notes (replaces transactions_fts at cutover).
${ENTRIES_FTS_DDL}

CREATE INDEX IF NOT EXISTS idx_ag_ledger ON account_groups(ledger_id);
CREATE INDEX IF NOT EXISTS idx_budget_groups_ledger ON budget_groups(ledger_id);
CREATE INDEX IF NOT EXISTS idx_acc_ledger ON accounts(ledger_id);
CREATE INDEX IF NOT EXISTS idx_acc_group ON accounts(group_id);
CREATE INDEX IF NOT EXISTS idx_cat_ledger ON categories(ledger_id);
CREATE INDEX IF NOT EXISTS idx_tags_ledger ON tags(ledger_id);
CREATE INDEX IF NOT EXISTS idx_counterparty_ledger ON counterparties(ledger_id);
-- Resolver index: (ledger_id, name) under the column's NOCASE collation lets
-- "WHERE ledger_id = ? AND name = ?" short-circuit to an index seek for the
-- per-write counterparty lookup. Without it the resolver scans every row.
CREATE INDEX IF NOT EXISTS idx_counterparty_ledger_name ON counterparties(ledger_id, name);
CREATE INDEX IF NOT EXISTS idx_budget_ledger_freq ON budgets(ledger_id, frequency, start_date);
CREATE INDEX IF NOT EXISTS idx_budget_last_rolled ON budgets(last_rolled_period);
CREATE INDEX IF NOT EXISTS idx_scheduled_ledger_active ON scheduled_templates(ledger_id, is_active) WHERE is_active = 1;
CREATE INDEX IF NOT EXISTS idx_scheduled_splits_template ON scheduled_splits(template_id);
CREATE INDEX IF NOT EXISTS idx_rate_date ON exchange_rates(date);
-- Composite for rateToHub's WHERE currency = ? AND date <= ? ORDER BY date DESC;
-- a single-column (currency) index would force a scan over the date filter.
CREATE INDEX IF NOT EXISTS idx_rate_currency_date ON exchange_rates(currency, date DESC);
CREATE INDEX IF NOT EXISTS idx_holdings_ledger ON holdings(ledger_id);
CREATE INDEX IF NOT EXISTS idx_holdings_account ON holdings(account_id);
CREATE INDEX IF NOT EXISTS idx_rules_ledger_active ON rules(ledger_id, is_active);

-- One named budget per (ledger, name, cycle). Stops a double-submit or a
-- copy-paste from silently creating two identical budgets that both match the
-- same transactions. Legacy NULL-named rows are no longer created, but NULLs
-- would be distinct here anyway.
CREATE UNIQUE INDEX IF NOT EXISTS idx_budget_unique ON budgets(ledger_id, name, frequency, start_date);

-- Defense-in-depth guard for holdings.account_id: the row's account MUST be
-- an investment-type account. The mutation handler already enforces this, but
-- a direct SQL insert (an import path, a future bulk loader, anything that
-- bypasses the handler) could slip a stock position into a credit card. The
-- BEFORE-trigger RAISES on the insert so the schema is its own contract.
CREATE TRIGGER IF NOT EXISTS tr_holdings_investment_only_insert
BEFORE INSERT ON holdings
FOR EACH ROW
WHEN COALESCE((SELECT type FROM accounts WHERE id = NEW.account_id), '') != 'investment'
BEGIN
  SELECT RAISE(ABORT, 'Holdings can only be added to an investment account');
END;

-- Same guard on account_id updates. Today no mutation moves a holding between
-- accounts, but the column isn't immutable in SQL — a manual UPDATE would
-- otherwise be free to move a position to a non-investment account.
CREATE TRIGGER IF NOT EXISTS tr_holdings_investment_only_update
BEFORE UPDATE OF account_id ON holdings
FOR EACH ROW
WHEN COALESCE((SELECT type FROM accounts WHERE id = NEW.account_id), '') != 'investment'
BEGIN
  SELECT RAISE(ABORT, 'Holdings can only be added to an investment account');
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
export const SCHEMA_VERSION = '2026-06-14T00:00:00Z';
export const APP_NAME = 'finch';

// Replay-safe recreation dance for accounts: removes the opening_balance and
// opening_balance_base columns (they became opening entries in the cutover).
// Pattern mirrors CATEGORIES_UPGRADE in entries-schema.ts:
//   NO staging drop — on a replay after a mid-dance crash the surviving
//   accounts_new still holds the data; the CREATE fails "already exists"
//   (swallowed by the migration runner), INSERT OR IGNORE tops up any missing
//   rows (or is a no-op when the source table is already gone), and the RENAME
//   promotes the populated staging table. FK OFF/ON wrap is required because
//   account_groups / ledgers are referenced by the staging table's FKs and
//   SQLite won't parse a self-referential FK during the rename in FK=ON mode.
const ACCOUNTS_DROP_OPENING_COLUMNS: string[] = [
  'PRAGMA foreign_keys = OFF',
  `CREATE TABLE IF NOT EXISTS accounts_new (
     id                   TEXT PRIMARY KEY,
     ledger_id            TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
     group_id             TEXT REFERENCES account_groups(id) ON DELETE SET NULL,
     name                 TEXT NOT NULL,
     type                 TEXT NOT NULL CHECK(type IN ('savings','credit_card','investment','cash','fx','virtual')),
     currency             TEXT NOT NULL DEFAULT 'SGD',
     current_balance      REAL NOT NULL DEFAULT 0,
     color                TEXT,
     sort_order           INTEGER NOT NULL DEFAULT 0,
     include_in_net_worth INTEGER NOT NULL DEFAULT 1,
     is_active            INTEGER NOT NULL DEFAULT 1,
     archived_at          TEXT,
     last_reconciled_at      TEXT,
     last_reconciled_balance REAL,
     created_at           TEXT NOT NULL,
     updated_at           TEXT NOT NULL
   )`,
  // INSERT OR IGNORE: replay-safe — if accounts_new already has the rows (a
  // previous partial run), OR IGNORE skips them; if the source accounts table
  // is already gone (post-RENAME), the SELECT returns 0 rows harmlessly.
  `INSERT OR IGNORE INTO accounts_new
     (id, ledger_id, group_id, name, type, currency, current_balance,
      color, sort_order, include_in_net_worth, is_active, archived_at,
      last_reconciled_at, last_reconciled_balance, created_at, updated_at)
   SELECT id, ledger_id, group_id, name, type, currency, current_balance,
          color, sort_order, include_in_net_worth, is_active, archived_at,
          last_reconciled_at, last_reconciled_balance, created_at, updated_at
   FROM accounts`,
  'DROP TABLE accounts',
  'ALTER TABLE accounts_new RENAME TO accounts',
  'CREATE INDEX IF NOT EXISTS idx_acc_ledger ON accounts(ledger_id)',
  'CREATE INDEX IF NOT EXISTS idx_acc_group ON accounts(group_id)',
  'PRAGMA foreign_keys = ON',
];

// Schema changes made after the baseline, keyed by the version they upgrade TO.
// Applied in lex (== chronological) order for versions strictly greater than a
// database's recorded schema_version.
const MIGRATIONS: Record<string, string[] | ((exec: ExecFn) => Promise<void>)> = {
  // accounts.opening_balance_base shipped in the unrealized-FX work (#66) but the
  // SCHEMA_VERSION wasn't bumped, so databases created in the window between the
  // baseline and #66 report the baseline version yet lack the column — and
  // nothing healed them (CREATE TABLE IF NOT EXISTS can't add a column, and this
  // runner only replays versions strictly greater than the recorded one). This
  // ALTER closes that gap; it's idempotent (see runMigrationStmt) so it's a
  // no-op on files that already carry the column.
  '2026-06-05T00:00:00Z': ['ALTER TABLE accounts ADD COLUMN opening_balance_base REAL NOT NULL DEFAULT 0'],
  // Schema audit follow-ups:
  //   - new composite index serves rateToHub's (currency, date) lookups on
  //     every transaction write; the single-column idx_rate_currency it
  //     supersedes is dropped.
  //   - new (account_id, status) index for recomputeAccount.
  //   - budgets.tag_ids was declared but never read by any selector — drop it.
  //   - scheduled_templates.category_id FK swaps from RESTRICT to SET NULL so a
  //     category can be deleted even when a schedule references it (mirrors
  //     transactions.category_id). SQLite has no ALTER for FK clauses, so the
  //     table is rebuilt via the standard recreation dance.
  '2026-06-06T00:00:00Z': [
    'DROP INDEX IF EXISTS idx_rate_currency',
    'CREATE INDEX IF NOT EXISTS idx_rate_currency_date ON exchange_rates(currency, date DESC)',
    'CREATE INDEX IF NOT EXISTS idx_txn_account_status ON transactions(account_id, status)',
    'ALTER TABLE budgets DROP COLUMN tag_ids',
    // Rebuild scheduled_templates with the new FK. Each step is re-runnable:
    // the staging table is dropped first, the canonical re-create uses the
    // same column order as the CREATE TABLE above, and RENAME is the last
    // step so a partial failure leaves the original table intact.
    'PRAGMA foreign_keys = OFF',
    'DROP TABLE IF EXISTS scheduled_templates_new',
    `CREATE TABLE scheduled_templates_new (
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
     )`,
    `INSERT INTO scheduled_templates_new (
       id, ledger_id, name, description, kind, amount, amount_varies, splits_enabled,
       account_id, from_account_id, category_id, frequency, day_of_month, day_of_week,
       start_date, end_date, next_run, last_run, auto_post, is_active, max_executions,
       installment_total, color, created_at, updated_at
     ) SELECT
       id, ledger_id, name, description, kind, amount, amount_varies, splits_enabled,
       account_id, from_account_id, category_id, frequency, day_of_month, day_of_week,
       start_date, end_date, next_run, last_run, auto_post, is_active, max_executions,
       installment_total, color, created_at, updated_at
     FROM scheduled_templates`,
    'DROP TABLE scheduled_templates',
    'ALTER TABLE scheduled_templates_new RENAME TO scheduled_templates',
    'CREATE INDEX IF NOT EXISTS idx_scheduled_ledger_active ON scheduled_templates(ledger_id, is_active) WHERE is_active = 1',
    'PRAGMA foreign_keys = ON',
  ],
  // Reconcile-to-statement (RECONCILE_PLAN). Three additive columns:
  //   - transactions.cleared_at: ticked-off-against-a-statement flag.
  //   - accounts.last_reconciled_at/_balance: the verified-correct checkpoint.
  // All nullable, defaulted via the migration runner's "duplicate column"
  // swallow rule (see isAlreadyAppliedError); safe to re-run on a file that
  // already carries them.
  '2026-06-07T00:00:00Z': [
    'ALTER TABLE transactions ADD COLUMN cleared_at TEXT',
    'ALTER TABLE accounts ADD COLUMN last_reconciled_at TEXT',
    'ALTER TABLE accounts ADD COLUMN last_reconciled_balance REAL',
  ],
  // Conditional rules engine (RULES_ENGINE_PLAN). A new rules table + its
  // index, plus the applied_rule_ids observability column on transactions.
  // CREATE TABLE/INDEX IF NOT EXISTS and ADD COLUMN are all idempotent under
  // the isAlreadyAppliedError swallow rule, so re-runs are safe.
  '2026-06-08T00:00:00Z': [
    `CREATE TABLE IF NOT EXISTS rules (
       id           TEXT PRIMARY KEY,
       ledger_id    TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
       name         TEXT,
       priority     INTEGER NOT NULL DEFAULT 100,
       condition    TEXT NOT NULL,
       actions      TEXT NOT NULL,
       is_active    INTEGER NOT NULL DEFAULT 1,
       run_on_edit  INTEGER NOT NULL DEFAULT 0,
       last_applied_at TEXT,
       created_at   TEXT NOT NULL,
       updated_at   TEXT NOT NULL
     )`,
    'CREATE INDEX IF NOT EXISTS idx_rules_ledger_active ON rules(ledger_id, is_active)',
    'ALTER TABLE transactions ADD COLUMN applied_rule_ids TEXT',
  ],
  // Dedup UNIQUE backstops (#5). De-dupe first so the index build can't fail on
  // a pre-existing file that already holds duplicates: keep the lowest rowid of
  // each colliding group, drop the rest. Both DELETEs are no-ops on a clean DB.
  // Equality here uses IS so NULL keys (e.g. a NULL transaction time) group
  // together for the cleanup — stricter than the index itself, which is the
  // safe direction (it only removes rows the index would also reject).
  '2026-06-09T00:00:00Z': [
    `DELETE FROM transactions WHERE rowid NOT IN (
       SELECT MIN(rowid) FROM transactions
       GROUP BY account_id, date, time, amount, description
     )`,
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_txn_dedup ON transactions(account_id, date, time, amount, description)',
    `DELETE FROM budgets WHERE rowid NOT IN (
       SELECT MIN(rowid) FROM budgets
       GROUP BY ledger_id, name, frequency, start_date
     )`,
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_budget_unique ON budgets(ledger_id, name, frequency, start_date)',
  ],
  // Review triage flag (INSPIRATION_IDEAS section 5.1). One additive column;
  // idempotent ADD COLUMN under the isAlreadyAppliedError swallow rule.
  '2026-06-10T00:00:00Z': [
    'ALTER TABLE transactions ADD COLUMN reviewed_at TEXT',
  ],
  // Receipt attachments (RECEIPT_PHOTOS_PLAN §2). New pointer-only table +
  // two indexes. Bytes live on the server filesystem, not in the DB. All
  // three statements are CREATE ... IF NOT EXISTS — idempotent under the
  // isAlreadyAppliedError swallow rule, so re-runs are safe.
  '2026-06-11T00:00:00Z': [
    `CREATE TABLE IF NOT EXISTS transaction_attachments (
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
     )`,
    'CREATE INDEX IF NOT EXISTS idx_attach_txn ON transaction_attachments(transaction_id)',
    'CREATE INDEX IF NOT EXISTS idx_attach_ledger ON transaction_attachments(ledger_id)',
  ],
  // Ledger CRUD cosmetic fields (LEDGER_CRUD_PLAN §2). Two additive nullable
  // columns; idempotent ADD COLUMN under the isAlreadyAppliedError swallow.
  '2026-06-12T00:00:00Z': [
    'ALTER TABLE ledgers ADD COLUMN color TEXT',
    'ALTER TABLE ledgers ADD COLUMN tagline TEXT',
  ],
  // Double-entry cutover, phase 1 (PR B / DOUBLE_ENTRY_PLAN §12): the DE core
  // tables/triggers + the categories equity upgrade + entry_attachments +
  // entries_fts land on existing files. Structures only — the data move and
  // the legacy-table drops are the '2026-06-14' entry. Every statement is
  // idempotent under the isAlreadyAppliedError rule.
  // NOTE: ENTRIES_SCHEMA is listed first — it creates the entries/postings/
  // entry_tags tables that CATEGORIES_UPGRADE and subsequent steps reference.
  // The CATEGORIES_UPGRADE dance is replay-safe by construction (see its comment in entries-schema.ts).
  '2026-06-13T00:00:00Z': [
    ENTRIES_SCHEMA,
    ...CATEGORIES_UPGRADE,
    ENTRY_ATTACHMENTS_DDL,
    ENTRIES_FTS_DDL,
  ],
  // Double-entry cutover, phase 2 (PR B): move every legacy row into
  // entries/postings (id-faithful — see cutover.ts), rebuild accounts without
  // the opening-balance columns (the figures became opening ENTRIES), then
  // drop the legacy tables. moveLegacyData recomputes balances and runs the
  // full auditLedger, THROWING on any problem — a failed audit aborts the
  // version (it is never stamped) and the pre-migration .pre-de.bak snapshot
  // (server.ts) is the rollback. Replay-safe: the move skips/repairs
  // per-entry, the accounts dance follows the no-staging-drop pattern, and
  // the drops are IF EXISTS.
  '2026-06-14T00:00:00Z': async (exec) => {
    const { moveLegacyData, dropLegacyTables } = await import('./cutover');
    await moveLegacyData(exec);
    for (const sql of ACCOUNTS_DROP_OPENING_COLUMNS) await runMigrationStmt(exec, sql);
    await dropLegacyTables(exec);
  },
};

// Additive migrations (ALTER TABLE ADD COLUMN, CREATE ... IF NOT EXISTS) must be
// safe to replay on a database that already carries the change — the baseline
// shipped several shape changes without a version bump, so a file's recorded
// version no longer reliably distinguishes "needs this" from "already has it".
// Swallow only the SQLite errors that mean "the target already exists"; anything
// else is a real migration failure and propagates.
function isAlreadyAppliedError(err: unknown): boolean {
  const msg = String((err as { message?: unknown })?.message ?? err);
  // - "duplicate column name" — ADD COLUMN re-run
  // - "already exists" — CREATE TABLE / INDEX / TRIGGER re-run
  // - "no such column" — DROP COLUMN re-run after the column is gone
  // - "no such table/index" — DROP / table-recreation step where the target
  //   was already cleaned up. Real DBs (produced by applySchema) always have
  //   every base table, so the only place this fires is migration replays.
  return /duplicate column name|already exists|no such (column|table|index)/i.test(msg);
}

async function runMigrationStmt(exec: ExecFn, sql: string): Promise<void> {
  try {
    await exec(sql);
  } catch (err) {
    if (isAlreadyAppliedError(err)) return;
    throw err;
  }
}

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
    const entry = MIGRATIONS[version];
    if (typeof entry === 'function') await entry(exec);
    else for (const sql of entry ?? []) await runMigrationStmt(exec, sql);
  }
  await ensureMetadataRow(exec, SCHEMA_VERSION);
}
