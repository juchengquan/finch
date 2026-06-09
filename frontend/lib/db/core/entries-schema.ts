// PR A of plans/DOUBLE_ENTRY_PLAN.md: the entries/postings DDL + the categories
// upgrade, as standalone constants. Deliberately NOT part of the canonical
// SCHEMA yet — in this PR only tests apply it; PR B folds ENTRIES_SCHEMA into
// schema.ts's SCHEMA and replays CATEGORIES_UPGRADE inside the cutover
// MIGRATIONS entry. Triggers are added in later tasks of this PR.

export const ENTRIES_SCHEMA = `
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
`;

// categories gains kind 'equity', loses kind 'transfer', gains the `system`
// marker column. SQLite can't ALTER a CHECK — standard recreation dance
// (mirrors the scheduled_templates rebuild in schema.ts's 2026-06-06 entry).
// Replay-safe by construction (audited in PR B): there is deliberately NO
// staging-table drop — on a replay after a mid-dance crash the surviving
// categories_new still holds the data; CREATE fails "already exists"
// (swallowed by the migration runner), INSERT OR IGNORE tops up any missing
// rows (or is swallowed when the source table is already gone), and the
// RENAME promotes the populated staging table. A crash in ANY window
// therefore replays to the correct end state — unlike a dance that drops
// staging first, which silently promotes an EMPTY table after a crash
// between DROP categories and RENAME. (FK enforcement is OFF around the
// dance so the staging table's self-referential parent_id FK parses while
// both tables exist.)
//
// legacy_alter_table is toggled ON around the dance: under modern ALTER
// semantics (SQLite ≥3.25, pinned OFF by applyPragmaBootstrap) RENAME
// re-parses EVERY trigger in the schema, and any trigger referencing a
// table/column that is transiently missing mid-dance aborts the RENAME with
// "error in trigger …" — which the migration runner must not (and now does
// not) swallow. Legacy semantics skip the re-parse; our staging rename needs
// no reference rewriting, so legacy mode is exactly right here.
export const CATEGORIES_UPGRADE: string[] = [
  'PRAGMA foreign_keys = OFF',
  'PRAGMA legacy_alter_table = ON',
  `CREATE TABLE categories_new (
     id         TEXT PRIMARY KEY,
     ledger_id  TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
     parent_id  TEXT REFERENCES categories(id) ON DELETE SET NULL,
     name       TEXT NOT NULL,
     kind       TEXT NOT NULL CHECK(kind IN ('expense','income','equity')),
     icon       TEXT,
     color      TEXT,
     sort_order INTEGER NOT NULL DEFAULT 0,
     system     TEXT CHECK(system IN ('opening','adjustment','fx')),
     created_at TEXT NOT NULL,
     updated_at TEXT NOT NULL
   )`,
  `INSERT OR IGNORE INTO categories_new (id, ledger_id, parent_id, name, kind, icon, color, sort_order, system, created_at, updated_at)
   SELECT id, ledger_id, parent_id, name,
          CASE WHEN kind = 'transfer' THEN 'expense' ELSE kind END,
          icon, color, sort_order, NULL, created_at, updated_at
   FROM categories`,
  'DROP TABLE categories',
  'ALTER TABLE categories_new RENAME TO categories',
  'CREATE INDEX IF NOT EXISTS idx_cat_parent ON categories(parent_id) WHERE parent_id IS NOT NULL',
  'CREATE INDEX IF NOT EXISTS idx_cat_ledger ON categories(ledger_id)',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_cat_system ON categories(ledger_id, system) WHERE system IS NOT NULL',
  'PRAGMA legacy_alter_table = OFF',
  'PRAGMA foreign_keys = ON',
];

type ExecLike = (sql: string, bind?: (string | number | null)[]) => Promise<unknown>;

export async function applyEntriesSchema(exec: ExecLike): Promise<void> {
  await exec(ENTRIES_SCHEMA);
  for (const sql of CATEGORIES_UPGRADE) await exec(sql);
}
