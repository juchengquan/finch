import Foundation
import GRDB

/// The iOS port's mirror of the web's `lib/db/core/schema.ts`.
/// `ddl` is the web's fully-interpolated `SCHEMA` string (one
/// `export const SCHEMA` template literal that already expands
/// `${ENTRIES_SCHEMA}` / `${ENTRY_ATTACHMENTS_DDL}` / `${ENTRIES_FTS_DDL}`),
/// copied BYTE-FOR-BYTE and executed as one statement. Emitted with:
///   cd frontend && bun -e 'import {SCHEMA} from "@/lib/db/core/schema"; process.stdout.write(SCHEMA)'
public enum Schema {
    /// Matches the web's `SCHEMA_VERSION` (`schema.ts:435`).
    public static let version = "2026-07-23T00:00:00Z"
    /// Matches the web's `APP_NAME` (`schema.ts:436`).
    public static let appName = "finch"

    /// The verbatim web `SCHEMA` (raw literal — do not edit by hand;
    /// re-emit from the web to refresh).
    public static let ddl = #"""

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
  counterparty_ids   TEXT,
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

CREATE TABLE IF NOT EXISTS entries (
  id                 TEXT PRIMARY KEY,
  ledger_id          TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  date               TEXT NOT NULL,
  time               TEXT,
  description        TEXT,
  -- Cached classification label; the postings SHAPE is the truth (design doc
  -- I7). postEntry stamps it, auditLedger checks it.
  kind               TEXT NOT NULL CHECK(kind IN ('opening','income','expense','transfer','adjustment','refund')),
  status             TEXT NOT NULL DEFAULT 'confirmed' CHECK(status IN ('pending','confirmed')),
  confirmed_at       TEXT,
  counterparty_id    TEXT REFERENCES counterparties(id) ON DELETE SET NULL,
  refunded_entry_id  TEXT REFERENCES entries(id) ON DELETE SET NULL,
  source_template_id TEXT,
  -- The scheduled occurrence this entry fulfils (yyyy-MM-dd), when it was posted
  -- from a template. NULL for everything else. Lets a transaction dated "when I
  -- actually paid" still resolve the occurrence it was due on.
  occurrence_date    TEXT,
  notes              TEXT,
  applied_rule_ids   TEXT,
  reviewed_at        TEXT,
  -- Double-submit backstop (the entries-layer mirror of transactions's
  -- idx_txn_dedup, which still exists). NULL when time is NULL,
  -- reproducing the old index's "NULL time never collides" carve-out.
  dedup_hash         TEXT,
  -- Two-phase write flag: postings insert while sealed = 0, then the seal
  -- UPDATE fires the balance-check trigger. Sealed postings are immutable.
  sealed             INTEGER NOT NULL DEFAULT 0,
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS postings (
  id            TEXT PRIMARY KEY,
  entry_id      TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
  -- Exactly one side: account leg (account_id set) or category leg
  -- (account_id NULL; category_id may itself be NULL = uncategorized, which
  -- preserves the SET-NULL-on-category-delete semantics).
  account_id    TEXT REFERENCES accounts(id) ON DELETE RESTRICT,
  category_id   TEXT REFERENCES categories(id) ON DELETE SET NULL,
  amount        REAL NOT NULL,
  currency      TEXT NOT NULL,
  amount_base   REAL NOT NULL,
  exchange_rate REAL NOT NULL,
  -- Display-only original figure when the user typed a currency other than
  -- the account's (DOUBLE_ENTRY_PLAN §5.2).
  orig_amount   REAL,
  orig_currency TEXT,
  memo          TEXT,
  -- Reconcile clearing is per account leg (clearing a transfer from account
  -- A's statement must not clear account B's leg).
  cleared_at    TEXT,
  sort_order    INTEGER NOT NULL DEFAULT 0,
  CHECK (account_id IS NULL OR category_id IS NULL)
);

CREATE TABLE IF NOT EXISTS entry_tags (
  entry_id TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
  tag_id   TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (entry_id, tag_id)
);

CREATE INDEX IF NOT EXISTS idx_entry_ledger_date  ON entries(ledger_id, date);
CREATE INDEX IF NOT EXISTS idx_entry_pending      ON entries(ledger_id, status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_entry_source       ON entries(source_template_id) WHERE source_template_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_entry_refunded     ON entries(refunded_entry_id)  WHERE refunded_entry_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_entry_counterparty ON entries(counterparty_id)    WHERE counterparty_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_entry_unsealed     ON entries(sealed)             WHERE sealed = 0;
CREATE UNIQUE INDEX IF NOT EXISTS idx_entry_dedup ON entries(ledger_id, dedup_hash) WHERE dedup_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_post_entry         ON postings(entry_id);
CREATE INDEX IF NOT EXISTS idx_post_account       ON postings(account_id)  WHERE account_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_post_category      ON postings(category_id) WHERE category_id IS NOT NULL;

-- Balance + shape check, fired by the seal UPDATE (two-phase write).
CREATE TRIGGER IF NOT EXISTS tr_entry_seal BEFORE UPDATE OF sealed ON entries
FOR EACH ROW WHEN NEW.sealed = 1 AND (
     ROUND((SELECT COALESCE(SUM(amount_base), 0) FROM postings WHERE entry_id = NEW.id), 2) != 0
  OR (SELECT COUNT(*) FROM postings WHERE entry_id = NEW.id) < 2
  OR (SELECT COUNT(*) FROM postings WHERE entry_id = NEW.id AND account_id IS NOT NULL) < 1)
BEGIN
  SELECT RAISE(ABORT, 'Entry postings must balance');
END;

-- Sealed entries are immutable: INSERT and money/shape UPDATE and DELETE on
-- their postings abort. cleared_at + memo are deliberately NOT in the UPDATE
-- column list — per-leg clearing edits sealed entries. The WHEN subquery
-- returns NULL once the parent entry row is gone, so the FK CASCADE from an
-- entry delete passes the DELETE guard untouched.
-- The UPDATE guard checks OLD and NEW entry_id, so a posting can be neither
-- moved into nor smuggled out of a sealed entry.
CREATE TRIGGER IF NOT EXISTS tr_post_sealed_insert BEFORE INSERT ON postings
FOR EACH ROW WHEN (SELECT sealed FROM entries WHERE id = NEW.entry_id) = 1
BEGIN
  SELECT RAISE(ABORT, 'Unseal the entry before editing postings');
END;

CREATE TRIGGER IF NOT EXISTS tr_post_sealed_update
BEFORE UPDATE OF entry_id, account_id, amount, currency, amount_base, exchange_rate, orig_amount, orig_currency, sort_order ON postings
FOR EACH ROW WHEN (SELECT sealed FROM entries WHERE id = NEW.entry_id) = 1
  OR (SELECT sealed FROM entries WHERE id = OLD.entry_id) = 1
BEGIN
  SELECT RAISE(ABORT, 'Unseal the entry before editing postings');
END;

CREATE TRIGGER IF NOT EXISTS tr_post_sealed_delete BEFORE DELETE ON postings
FOR EACH ROW WHEN (SELECT sealed FROM entries WHERE id = OLD.entry_id) = 1
BEGIN
  SELECT RAISE(ABORT, 'Unseal the entry before editing postings');
END;

-- Account-leg currency guard (kills the old amount/amount_base mixing bug by
-- construction — design doc F3/I3).
-- (The missing-account COALESCE branch is unreachable in practice — the FK
-- with ON DELETE RESTRICT guarantees the account row exists — kept as pure
-- defense-in-depth.)
CREATE TRIGGER IF NOT EXISTS tr_post_currency_insert BEFORE INSERT ON postings
FOR EACH ROW WHEN NEW.account_id IS NOT NULL
  AND NEW.currency != COALESCE((SELECT currency FROM accounts WHERE id = NEW.account_id), NEW.currency)
BEGIN
  SELECT RAISE(ABORT, 'Account posting must be in the account currency');
END;

CREATE TRIGGER IF NOT EXISTS tr_post_currency_update BEFORE UPDATE OF account_id, currency ON postings
FOR EACH ROW WHEN NEW.account_id IS NOT NULL
  AND NEW.currency != COALESCE((SELECT currency FROM accounts WHERE id = NEW.account_id), NEW.currency)
BEGIN
  SELECT RAISE(ABORT, 'Account posting must be in the account currency');
END;

-- Cached balance: confirmed-entry account legs move it on INSERT, in the
-- account's own currency — no currency CASE (cf. the old
-- tr_update_account_balance). Edits/deletes recompute explicitly.
CREATE TRIGGER IF NOT EXISTS tr_post_balance AFTER INSERT ON postings
FOR EACH ROW WHEN NEW.account_id IS NOT NULL
  AND (SELECT status FROM entries WHERE id = NEW.entry_id) = 'confirmed'
BEGIN
  UPDATE accounts
     SET current_balance = ROUND(current_balance + NEW.amount, 2),
         updated_at = datetime('now')
   WHERE id = NEW.account_id;
END;


-- Receipt attachments, re-pointed at entries (PR B). Same pointer-only design
-- as transaction_attachments (RECEIPT_PHOTOS_PLAN §2), which it replaces at
-- cutover; rel_path stays server-internal.

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
CREATE INDEX IF NOT EXISTS idx_eattach_ledger ON entry_attachments(ledger_id);

-- FTS over entries.description + notes (replaces transactions_fts at cutover).

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
END;

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
"""#

    /// Apply the full canonical schema as ONE statement.
    public static func apply(to db: Database) throws {
        try db.execute(sql: ddl)
    }
}
