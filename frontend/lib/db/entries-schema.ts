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
  -- Double-submit backstop (replaces idx_txn_dedup). NULL when time is NULL,
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
`;

// categories gains kind 'equity', loses kind 'transfer', gains the `system`
// marker column. SQLite can't ALTER a CHECK — standard recreation dance
// (mirrors the scheduled_templates rebuild in schema.ts's 2026-06-06 entry).
// Re-runnable: each step is idempotent under the isAlreadyAppliedError rule
// PR B's migration runner applies; in this PR tests run it once on a fresh DB.
export const CATEGORIES_UPGRADE: string[] = [
  'PRAGMA foreign_keys = OFF',
  'DROP TABLE IF EXISTS categories_new',
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
  `INSERT INTO categories_new (id, ledger_id, parent_id, name, kind, icon, color, sort_order, system, created_at, updated_at)
   SELECT id, ledger_id, parent_id, name,
          CASE WHEN kind = 'transfer' THEN 'expense' ELSE kind END,
          icon, color, sort_order, NULL, created_at, updated_at
   FROM categories`,
  'DROP TABLE categories',
  'ALTER TABLE categories_new RENAME TO categories',
  'CREATE INDEX IF NOT EXISTS idx_cat_parent ON categories(parent_id) WHERE parent_id IS NOT NULL',
  'CREATE INDEX IF NOT EXISTS idx_cat_ledger ON categories(ledger_id)',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_cat_system ON categories(ledger_id, system) WHERE system IS NOT NULL',
  'PRAGMA foreign_keys = ON',
];

type ExecLike = (sql: string, bind?: (string | number | null)[]) => Promise<unknown>;

export async function applyEntriesSchema(exec: ExecLike): Promise<void> {
  await exec(ENTRIES_SCHEMA);
  for (const sql of CATEGORIES_UPGRADE) await exec(sql);
}
