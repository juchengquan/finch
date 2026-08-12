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
  color      TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS budget_groups (
  id         TEXT PRIMARY KEY,
  ledger_id  TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  color      TEXT,
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
  -- Per-account icon, mirroring categories.icon: a name resolved through the
  -- curated set, NOT a raw platform symbol. NULL = derive from the type column,
  -- which is what every account did before this column existed.
  icon                 TEXT,
  -- Free-text note. NULL and '' both mean "none"; nothing parses this.
  notes                TEXT,
  -- Credit-card cycle, day-of-month 1-31. statement_day is when the cycle
  -- closes, due_day when payment is owed — the one you act on. Stored as a day
  -- rather than a date because issuers state it that way and it repeats; a day
  -- past the end of a short month clamps to that month's last day, the same
  -- rule scheduled_templates.day_of_month already uses. Meaningless on other
  -- account types and left NULL there; nothing enforces that, since a type can
  -- change and dropping the values on the way through would lose them.
  statement_day        INTEGER,
  due_day              INTEGER,
  -- Credit limit in the account's own currency. Enables utilisation and
  -- available-credit figures; NULL = unknown, which is not the same as 0.
  credit_limit         REAL,
  -- Who holds the account -- "DBS", "Amex". Free text, purely descriptive:
  -- nothing matches on it, and it is what tells two cards apart at a glance.
  institution          TEXT,
  -- Last four digits, for telling cards apart and matching a statement. TEXT,
  -- not INTEGER: "0042" must stay "0042", and it is an identifier rather than a
  -- number -- nothing ever does arithmetic on it. Deliberately only the last
  -- four; this file is exported and synced, and a full number does not belong
  -- in a backup.
  account_last4        TEXT,
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
  -- Merchants are GLOBAL — one shared catalog across every ledger, so there is
  -- no ledger_id. COLLATE NOCASE makes "=" and the name index case-insensitive
  -- without needing LOWER() in the WHERE clause. resolveCounterpartyIdByName
  -- runs on every transaction write, so the index actually getting used here
  -- matters. Names are intentionally NOT unique — two merchants may share one.
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
  -- Time-of-day the cycle turns over, 'HH:mm'. NULL = midnight.
  start_time         TEXT,
  end_date           TEXT,
  end_time           TEXT,
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
  counterparty_ids   TEXT,
  -- Free-text note, same shape and meaning as entries.notes and accounts.notes.
  -- NULL and '' both mean "none"; nothing parses this.
  notes              TEXT,
  -- Visual identity, mirroring categories.icon/color. Budget GROUPS already
  -- carry a colour; the budgets themselves did not, which is why the list reads
  -- flatter than Categories. NULL on both = no icon / inherit nothing.
  icon               TEXT,
  color              TEXT,
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
-- Resolver index: name under the column's NOCASE collation lets "WHERE name = ?"
-- short-circuit to an index seek for the per-write counterparty lookup. Without
-- it the resolver scans every row.
CREATE INDEX IF NOT EXISTS idx_counterparty_name ON counterparties(name);
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
export const SCHEMA_VERSION = '2026-08-12T01:00:00Z';
export const APP_NAME = 'finch';

// Schema changes made after the baseline, keyed by the version they upgrade TO.
// Applied in lex (== chronological) order for versions strictly greater than a
// database's recorded schema_version.
const MIGRATIONS: Record<string, string[] | ((exec: ExecFn) => Promise<void>)> = {
  // entries.pending_kind — which kind of pending a row is. Additive and nullable;
  // the refresh backfills it from the date, so no data migration is needed. An
  // hour past the account-fields bump because both land the same day and versions
  // are compared as strings.
  '2026-08-12T01:00:00Z': [
    'ALTER TABLE entries ADD COLUMN pending_kind TEXT',
    // Backfilled immediately: without it every existing pending row sits at
    // "pending + NULL" until the first refresh, which is indistinguishable from a bug
    // and forces readers back onto the date. date('now') is UTC and may be a day off
    // for a distant user; the first refresh runs on the device's wall day and fixes it.
    "UPDATE entries SET pending_kind = CASE WHEN date > date('now') THEN 'upcoming' ELSE 'due' END WHERE status = 'pending'",
    // The triggers that keep it correct from here on. Additive — which is the whole
    // reason the rule is a trigger and not a CHECK: CREATE TRIGGER applies to an
    // existing table, ALTER ... CHECK does not.
    "CREATE TRIGGER IF NOT EXISTS tr_entry_pending_kind_insert AFTER INSERT ON entries\nFOR EACH ROW WHEN NEW.pending_kind IS NOT (\n  CASE WHEN NEW.status <> 'pending' THEN NULL\n       WHEN NEW.date > date('now')  THEN 'upcoming'\n       ELSE 'due' END)\nBEGIN\n  UPDATE entries SET pending_kind =\n    CASE WHEN NEW.status <> 'pending' THEN NULL\n         WHEN NEW.date > date('now')  THEN 'upcoming'\n         ELSE 'due' END\n   WHERE id = NEW.id;\nEND",
    "CREATE TRIGGER IF NOT EXISTS tr_entry_pending_kind_update AFTER UPDATE OF status, date ON entries\nFOR EACH ROW WHEN NEW.pending_kind IS NOT (\n  CASE WHEN NEW.status <> 'pending' THEN NULL\n       WHEN NEW.date > date('now')  THEN 'upcoming'\n       ELSE 'due' END)\nBEGIN\n  UPDATE entries SET pending_kind =\n    CASE WHEN NEW.status <> 'pending' THEN NULL\n         WHEN NEW.date > date('now')  THEN 'upcoming'\n         ELSE 'due' END\n   WHERE id = NEW.id;\nEND",
  ],
  // Account detail fields (icon / notes / credit-card cycle / credit limit), plus
  // budgets.notes — one version bump covering both tables rather than two.
  // Purely additive and all nullable, so existing rows read as "unset" and no
  // backfill is needed. Ordered after the baseline columns here because ALTER
  // appends; the CREATE TABLE above groups them logically instead, which is the
  // same split every earlier additive migration has (column order is never
  // relied on — every query names its columns).
  '2026-08-12T00:00:00Z': [
    'ALTER TABLE accounts ADD COLUMN icon TEXT',
    'ALTER TABLE accounts ADD COLUMN notes TEXT',
    'ALTER TABLE accounts ADD COLUMN statement_day INTEGER',
    'ALTER TABLE accounts ADD COLUMN due_day INTEGER',
    'ALTER TABLE accounts ADD COLUMN credit_limit REAL',
    'ALTER TABLE accounts ADD COLUMN institution TEXT',
    'ALTER TABLE accounts ADD COLUMN account_last4 TEXT',
    'ALTER TABLE budgets ADD COLUMN notes TEXT',
    'ALTER TABLE budgets ADD COLUMN icon TEXT',
    'ALTER TABLE budgets ADD COLUMN color TEXT',
  ],
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
  // entries_fts land on existing files. Every statement is idempotent under
  // the isAlreadyAppliedError rule.
  // NOTE: ENTRIES_SCHEMA is listed first — it creates the entries/postings/
  // entry_tags tables that CATEGORIES_UPGRADE and subsequent steps reference.
  // The CATEGORIES_UPGRADE dance is replay-safe by construction (see its comment in entries-schema.ts).
  //
  // PR-C-FOLLOWUPS NOTE: the '2026-06-14' cutover (data-move + accounts-dance
  // + legacy-table drops) is intentionally absent. The project is pre-release
  // with no legacy databases to preserve, so the upgrade path is dead code;
  // the canonical SCHEMA above already carries the post-cutover shape. If a
  // pre-DE database ever needs to be carried forward, the cutover code lives
  // in git history at the DE PR C merge commit and can be reinstated behind a
  // versioned MIGRATIONS entry.
  '2026-06-13T00:00:00Z': [
    ENTRIES_SCHEMA,
    ...CATEGORIES_UPGRADE,
    ENTRY_ATTACHMENTS_DDL,
    ENTRIES_FTS_DDL,
  ],
  // Group colors (iOS-first UI; engine parity): nullable, additive.
  '2026-07-17T00:00:00Z': [
    'ALTER TABLE budget_groups ADD COLUMN color TEXT',
    'ALTER TABLE account_groups ADD COLUMN color TEXT',
  ],
  // Income budgets (goals) now track progress from real transactions matched by
  // account/category/tag/merchant. Re-add tag_ids (dropped 2026-06-06) + add
  // counterparty_ids. Additive + nullable (NULL = unconstrained).
  '2026-07-21T00:00:00Z': [
    'ALTER TABLE budgets ADD COLUMN tag_ids TEXT',
    'ALTER TABLE budgets ADD COLUMN counterparty_ids TEXT',
  ],
  // Link a posted transaction to the scheduled occurrence it fulfils, so the
  // occurrence resolves even when the transaction carries a different date.
  '2026-07-22T00:00:00Z': [
    'ALTER TABLE entries ADD COLUMN occurrence_date TEXT',
  ],
  // #533 ("global merchants", schema 2026-07-20) dropped counterparties.ledger_id
  // from the baseline DDL but shipped NO migration — databases created before it
  // still carry the per-ledger table, and every NEW-merchant insert fails its
  // NOT NULL constraint ("SQLite error 19"). Existing merchants resolve by name
  // without inserting, which is how this hid. Guarded rebuild via the standard
  // recreation dance; a no-op on databases that are already global. Keyed AFTER
  // 07-22 because affected files were already re-stamped to 2026-07-22 by the
  // later entries, and this runner only replays versions strictly greater than
  // the recorded one.
  '2026-07-23T00:00:00Z': async (exec) => {
    const cols = await exec(`PRAGMA table_info(counterparties)`);
    if (!cols.some((r) => String(r.name) === 'ledger_id')) return;
    for (const sql of [
      'PRAGMA foreign_keys = OFF',
      'DROP TABLE IF EXISTS counterparties_new',
      `CREATE TABLE counterparties_new (
         id                TEXT PRIMARY KEY,
         name              TEXT NOT NULL COLLATE NOCASE,
         is_verified       INTEGER NOT NULL DEFAULT 0,
         created_at        TEXT NOT NULL,
         updated_at        TEXT NOT NULL
       )`,
      `INSERT INTO counterparties_new (id,name,is_verified,created_at,updated_at)
         SELECT id,name,is_verified,created_at,updated_at FROM counterparties`,
      'DROP TABLE counterparties',
      'ALTER TABLE counterparties_new RENAME TO counterparties',
      'CREATE INDEX IF NOT EXISTS idx_counterparty_name ON counterparties(name)',
      'PRAGMA foreign_keys = ON',
    ])
      await exec(sql);
  },
  // A budget cycle's turnover time. Additive + nullable: NULL means midnight,
  // which is exactly what every existing budget already does.
  '2026-08-01T00:00:00Z': [
    'ALTER TABLE budgets ADD COLUMN start_time TEXT',
    'ALTER TABLE budgets ADD COLUMN end_time TEXT',
  ],
  // A purchase paid from several accounts takes a single category. The rules
  // engine used to break that (its `split` action ignored the account leg count),
  // and the projection copies an entry's whole `splits` array onto every
  // account-leg row — so such an entry had its categories summed once per payment
  // leg, and a budget alerted at twice the real spend.
  //
  // The shape is now refused at write time, which strands any row already in it:
  // rebuildEntry rebuilds legs when legs are provided OR the date changes, and
  // validates the result, so changing the date carries the forbidden shape forward
  // and throws. Merge each such entry's plain category legs into the dominant one
  // (largest |amount_base|) — already the single category the projection displays
  // for it — preserving the total so the entry re-seals. Equity legs (the sys:fx
  // residue) are not part of the split and are left alone.
  '2026-08-03T00:00:00Z': async (exec) => {
    // Tolerate a partial database, the way the counterparties rebuild above does:
    // migrate() is exercised against minimal fixtures that carry only the tables a
    // given migration touches, so this must be a no-op when there is nothing to
    // scan rather than throwing "no such table".
    const present = await exec(
      `SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('entries','postings','categories')`,
      [],
    );
    if (present.length < 3) return;
    const bad = await exec(
      `SELECT e.id AS id FROM entries e
        WHERE (SELECT COUNT(*) FROM postings p
                WHERE p.entry_id = e.id AND p.account_id IS NOT NULL) > 1
          AND (SELECT COUNT(*) FROM postings p JOIN categories c ON c.id = p.category_id
                WHERE p.entry_id = e.id AND c.kind != 'equity') > 1`,
      [],
    );
    for (const row of bad) {
      const entryId = String(row.id);
      const legs = await exec(
        `SELECT p.id AS pid, p.amount_base AS ab FROM postings p JOIN categories c ON c.id = p.category_id
          WHERE p.entry_id = ? AND c.kind != 'equity'
          ORDER BY ABS(p.amount_base) DESC, p.sort_order`,
        [entryId],
      );
      if (legs.length === 0) continue;
      const total = legs.reduce((sum, l) => sum + Number(l.ab), 0);
      // Postings on a sealed entry are immutable, so unseal, merge, reseal. The
      // total is unchanged, so the seal's balance check still passes.
      await exec('UPDATE entries SET sealed = 0 WHERE id = ?', [entryId]);
      for (const l of legs.slice(1)) await exec('DELETE FROM postings WHERE id = ?', [String(l.pid)]);
      // A category leg is always in ledger base, so `amount` mirrors it.
      await exec('UPDATE postings SET amount = ?, amount_base = ? WHERE id = ?',
        [total, total, String(legs[0].pid)]);
      await exec('UPDATE entries SET sealed = 1 WHERE id = ?', [entryId]);
    }
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
  // NEVER swallow a trigger/view re-parse failure. Under modern ALTER
  // semantics a RENAME re-parses every trigger; a failure surfaces as
  // "error in trigger X: no such table/column …" — which the patterns below
  // would otherwise match, silently skipping the RENAME and leaving the
  // table MISSING (this is exactly how the cutover broke on Linux CI while
  // passing on macOS, whose bun:sqlite build defaulted to legacy ALTER
  // semantics). A re-parse failure is a real migration failure: abort.
  if (/error in (trigger|view)/i.test(msg)) return false;
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
