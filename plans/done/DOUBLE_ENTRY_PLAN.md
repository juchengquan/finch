# Double-entry core — plan

Status: **shipped** — **PR #114** (PR A — additive core: the chokepoint
module `lib/db/entries.ts` + the entries/postings DDL constants in
`lib/db/entries-schema.ts` + the contract test suite, no production reads or
writes yet) + **PR #116** (PR B — the cutover: migration via
`lib/db/cutover.ts`, projection rewrite in `lib/db/state.ts`, mutation rewires
in `lib/db/mutations.ts`, read-path rewires across `lib/db/queries/*`, seed
rewrite, FK re-points, transactionSplits.ts deletion). `SCHEMA_VERSION =
'2026-06-14T00:00:00Z'`.

Canonical implementation:
- `frontend/lib/db/entries-schema.ts` — DDL constants (`ENTRIES_SCHEMA`,
  `CATEGORIES_UPGRADE`), consumed by both `schema.ts` (canonical) and
  `cutover.ts` (migration replay).
- `frontend/lib/db/entries.ts` — the write chokepoint: `postEntry` /
  `rebuildEntry` / `deleteEntry` / `resolveEntryRef` / `auditLedger` /
  `ensureSystemCategories` / `dedupHash` / `recomputeAccountFromPostings`.
- `frontend/lib/db/cutover.ts` — the §8.2 data-move builder (manual sealed
  inserts for id-fidelity; see the top-of-file comment for the id-fidelity
  table + torn-write repair pattern).
- `frontend/lib/db/state.ts` — the `Tx` / `AccountRow` projection
  (`projectState`).
- `frontend/lib/db/mutations.ts` — delegates to the chokepoint.

PR C (audit-on-import wiring + the §10.7 net-worth-explained Insights panel +
the docs follow-up in §12 of this plan) is the remaining open work. The body
below is the as-shipped design; the cross-references in `cutover.ts` /
`entries.ts` / `state.ts` top-comments point here.

Scope (as shipped): `frontend/` — storage + server layers; the client is
deliberately ~untouched.

> **Thesis: double-entry core, single-entry skin.** The `transactions` /
> `transfer_groups` / `transaction_splits` trio is replaced by **`entries`**
> (journal headers) + **`postings`** (balanced legs). Every entry's postings sum
> to zero in the ledger base — enforced at one write chokepoint and backstopped
> by schema triggers. The client keeps consuming the exact same projected `Tx`
> shape (`lib/store.ts`), so pages, selectors (`lib/select.ts`), and the UI
> vocabulary (expense / income / transfer — never "debit/credit") do not change.
> The schema change stays on the shared `SCHEMA_VERSION` lineage so `.finch`
> packs keep round-tripping (`plans/IOS_MACOS_PLAN.md`).

---

## 1. Why (current-model findings)

The single-entry model enforces its bookkeeping by convention in TypeScript;
each gap below is a class of bug the balanced-entry invariant removes:

| # | Finding | Where |
|---|---|---|
| F1 | A transfer's two legs are independent rows; `deleteTransaction` deletes one leg and orphans the other (no chokepoint guard); `updateTransaction` can re-amount / re-account / re-kind a single leg | `lib/db/mutations.ts:645`, `lib/db/queries/transactions.ts:477` |
| F2 | Transfers are reconstructed by sign-archaeology (`MAX(CASE WHEN amount < 0 …)`); an orphan leg renders as a half-transfer with `amount: 0` | `lib/db/queries/transfers.ts:26` |
| F3 | Balance math mixes currencies: a row whose `currency` ≠ account currency contributes its **ledger-base** figure to the account's **native** balance | `lib/db/queries/accounts.ts:28`, trigger in `lib/db/schema.ts:478` |
| F4 | Net worth is a computation, not an identity: `kind='adjustment'` rows and the cross-currency transfer base-residue (realized FX) move balances but are explained by no report; the series selectors also skip the `include_in_net_worth` filter the headline number applies | `lib/select.ts:164,1081` vs `lib/db/queries/accounts.ts:104` |
| F5 | Opening balance is a column, so "balance at a date" is re-derived in three places (recompute, reconcile sum, `runningSeries` end-minus-Σ) | `lib/db/queries/accounts.ts:18`, `lib/db/mutations.ts:562`, `lib/select.ts:1054` |
| F6 | Two split systems that can't express account+category fan-out together; loan principal/interest punted (decision #24 "cash math only") | `transaction_splits` vs `scheduled_splits` |
| F7 | Refund netting re-implemented per selector (`isSpend` widening, rollover SQL, server `categorySpend`) | `lib/select.ts:22`, `lib/budgets/rollover.ts:68` |
| F8 | Integrity checking is byte-level only (SHA-256); no semantic "books balance" check for import / pack validation | `lib/db/checksum.ts` |

---

## 2. Target model

### 2.1 Tables

```sql
-- Journal entry header: everything `transactions` carries today MINUS the money.
CREATE TABLE entries (
  id                 TEXT PRIMARY KEY,                 -- 'e-…' (migration reuses old txn ids)
  ledger_id          TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  date               TEXT NOT NULL,                    -- YYYY-MM-DD; rate-effective date for every leg
  time               TEXT,
  description        TEXT,                             -- merchant / memo line (FTS-indexed)
  -- Cached classification label for the UI/projection. The postings SHAPE is
  -- the truth (see §2.4 I7); postEntry stamps the label and the audit checks it.
  kind               TEXT NOT NULL CHECK(kind IN ('opening','income','expense','transfer','adjustment','refund')),
  status             TEXT NOT NULL DEFAULT 'confirmed' CHECK(status IN ('pending','confirmed')),
  confirmed_at       TEXT,
  counterparty_id    TEXT REFERENCES counterparties(id) ON DELETE SET NULL,
  refunded_entry_id  TEXT REFERENCES entries(id) ON DELETE SET NULL,
  source_template_id TEXT,
  notes              TEXT,
  applied_rule_ids   TEXT,
  reviewed_at        TEXT,
  -- Double-submit backstop (replaces idx_txn_dedup). Chokepoint-computed
  -- sha256 over date|time|description|sorted(account:amount) — NULL when time
  -- is NULL, reproducing today's "NULL time never collides" carve-out for
  -- scheduled auto-posts.
  dedup_hash         TEXT,
  -- Two-phase write flag: postings are inserted while sealed = 0, then the
  -- seal UPDATE fires the balance-check trigger (§3.2). A sealed entry's
  -- postings are immutable; edits unseal → rewrite → reseal.
  sealed             INTEGER NOT NULL DEFAULT 0,
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL
);

-- The money. Per entry: >= 2 postings, >= 1 account posting, Σ amount_base = 0.
CREATE TABLE postings (
  id            TEXT PRIMARY KEY,                      -- 'p-…' (migration reuses old txn ids)
  entry_id      TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
  -- Exactly one side: account leg (account_id set) or category leg (account_id
  -- NULL). A category leg's category_id may itself be NULL = "uncategorized",
  -- preserving today's SET-NULL-on-category-delete semantics.
  account_id    TEXT REFERENCES accounts(id) ON DELETE RESTRICT,
  category_id   TEXT REFERENCES categories(id) ON DELETE SET NULL,
  CHECK (account_id IS NULL OR category_id IS NULL),
  amount        REAL NOT NULL,                         -- signed, in `currency`
  currency      TEXT NOT NULL,                         -- account leg: MUST equal the account's currency (trigger §3.2);
                                                       -- category leg: the ledger base
  amount_base   REAL NOT NULL,                         -- signed, locked at the entry's date (unchanged philosophy)
  exchange_rate REAL NOT NULL,
  -- Display-only original figure when the user entered the row in a currency
  -- other than the account's (the "JPY hotel on the SGD card" case, §5.2).
  orig_amount   REAL,
  orig_currency TEXT,
  memo          TEXT,                                  -- per-split description (was transaction_splits.description)
  -- Reconcile clearing stays PER LEG (account postings only) — clearing a
  -- transfer from account A's statement must not clear account B's leg.
  cleared_at    TEXT,
  sort_order    INTEGER NOT NULL DEFAULT 0
);

-- Renames (same shape, FK re-pointed):
--   transaction_tags(transaction_id, tag_id)   → entry_tags(entry_id, tag_id)
--   transaction_attachments.transaction_id     → entry_attachments.entry_id
--   transactions_fts (+ its 3 sync triggers)   → entries_fts over entries.description/notes
```

Indexes:

```sql
CREATE INDEX idx_entry_ledger_date   ON entries(ledger_id, date);
CREATE INDEX idx_entry_pending       ON entries(ledger_id, status) WHERE status = 'pending';
CREATE INDEX idx_entry_source        ON entries(source_template_id) WHERE source_template_id IS NOT NULL;
CREATE INDEX idx_entry_refunded      ON entries(refunded_entry_id)  WHERE refunded_entry_id IS NOT NULL;
CREATE INDEX idx_entry_counterparty  ON entries(counterparty_id)    WHERE counterparty_id IS NOT NULL;
CREATE INDEX idx_entry_unsealed      ON entries(sealed)             WHERE sealed = 0;  -- audit: torn writes
CREATE UNIQUE INDEX idx_entry_dedup  ON entries(ledger_id, dedup_hash) WHERE dedup_hash IS NOT NULL;
CREATE INDEX idx_post_entry          ON postings(entry_id);
CREATE INDEX idx_post_account        ON postings(account_id)  WHERE account_id IS NOT NULL;
CREATE INDEX idx_post_category       ON postings(category_id) WHERE category_id IS NOT NULL;
```

No denormalized `date`/`status` on postings: every hot path joins `entries` on
its PK, which is cheap at personal scale. Revisit only if profiling says so.

### 2.2 Sign conventions

Account legs keep today's `transactions.amount` convention (+ = money in).
Category legs are the balancing side (ledger-cli convention: expenses positive,
income negative):

| Entry (kind) | Account leg(s) | Category leg(s) |
|---|---|---|
| expense $100 groceries | account −100 | `Food` **+100** |
| income $3,000 salary | account +3000 | `Salary` **−3000** |
| refund $50 of groceries | account +50 | `Food` **−50** (nets automatically) |
| transfer A→B | A −X, B +Y | `sys:fx-gain` equity leg = −(Σ base residue), only when ≠ 0 |
| opening balance B | account +B | `sys:opening-balance` −B |
| balance adjustment δ | account +δ | `sys:balance-adjustment` −δ |

So server-side: `categorySpend = SUM(amount_base) over category legs of entries
WHERE kind IN ('expense','refund')` (positive, refunds net in — F7 dies);
income totals gate on `kind = 'income'`. **Aggregations bucket by the entry's
kind — exact parity with today's selectors — never by `categories.kind`.** The
seed stamps every category `'expense'` (`lib/db/seed.ts:131`, the JSON
fixtures carry no kind) while income rows reference them, so category-row kind
is a *display hint* (picker grouping, equity hiding), not money math. A strict
"income entries may only post to income categories" validation can be added to
I7 later without schema change; not in this plan.

### 2.3 System (equity) categories

`categories.kind` CHECK becomes `('expense','income','equity')` — it gains
`'equity'` for the system rows and **drops `'transfer'`**: under double-entry a
transfer has two account legs and no category leg, so a transfer-kind category
is unreferenceable by construction. The categories admin page stops offering
the type (`TYPES` in `app/(main)/categories/page.tsx:34`); the migration
re-kinds any existing `'transfer'` rows to `'expense'` (none in seed — only
user-created rows can exist). A new nullable column marks the three system
rows:

```sql
system TEXT CHECK(system IN ('opening','adjustment','fx'))   -- NULL = ordinary category
CREATE UNIQUE INDEX idx_cat_system ON categories(ledger_id, system) WHERE system IS NOT NULL;
```

`ensureSystemCategories(exec, ledgerId)` (idempotent) seeds **Opening balance**
/ **Balance adjustment** / **FX gain/loss** per ledger; called from seed, the
migration, and ledger creation (coordinate with `plans/LEDGER_CRUD_PLAN.md` §3
`createLedger`). They are resolved by `system`, never by id or name (rename-
safe). UI: category pickers already filter by kind (`expense`/`income`), so
equity rows stay out of forms; the categories admin page hides them.

### 2.4 Invariants (the contract)

| # | Invariant | Enforced by |
|---|---|---|
| I1 | Per entry: `ROUND(Σ amount_base, 2) = 0`, **exact** (residue is an explicit `sys:fx-gain` leg, §5.1) | chokepoint + seal trigger |
| I2 | Per entry: ≥ 2 postings, ≥ 1 account leg | chokepoint + seal trigger |
| I3 | Account leg `currency` = the account's `currency`; category leg `currency` = ledger base | chokepoint + posting trigger |
| I4 | Postings of a sealed entry are immutable; postings never exist without their entry (FK CASCADE); legs are never written/edited/deleted individually | seal + posting triggers |
| I5 | Every posting's account/category belongs to the entry's ledger | chokepoint + audit |
| I6 | Only `status='confirmed'` entries move cached balances; `current_balance = Σ confirmed account-leg amounts` (opening entry included — F5 dies) | trigger + `recomputeAccount` |
| I7 | `entries.kind` matches the postings shape: `transfer` ⟺ 2 account legs; `opening`/`adjustment` ⟺ equity leg with matching `system`; `refund` ⟹ positive account leg (+ optional `refunded_entry_id`) | chokepoint + audit |
| I8 | Global trial balance: `Σ all postings.amount_base = 0` per ledger | audit (§3.3) |
| I9 | Display-currency identity: `amount = amount_base` exactly when `currency` = ledger base | chokepoint + audit |

### 2.5 What dies / what survives

**Dies:** `transfer_groups` (a transfer is just an entry with two account legs;
its locked from→to rate is derivable as `|toAmount / fromAmount|`),
`transaction_splits` (splits are just N category legs), the sign-archaeology in
`listTransfers`, the currency CASE in balance math, `accounts.opening_balance`
+ `accounts.opening_balance_base` (become opening entries), the dedup index's
column-tuple form.

**Survives unchanged:** the `Tx` projection contract (§4), `lib/select.ts` and
every page/component, budgets + groups, rules engine semantics, counterparties,
tags (junction re-pointed), scheduled templates + splits, holdings (decision
#23 stands — **no** commodity/lot accounting in this plan), exchange-rate
model + locked-rate philosophy, pending/confirmed semantics,
`current_balance` cache + insert-trigger + recompute pattern, FTS search, the
attachment pipeline, autobackup/pack/import machinery (table lists updated).

### 2.6 Why not full chart-of-accounts

Folding categories into a unified account tree (GnuCash/Beancount style) would
rewrite the categories admin, budget `category_ids` filters, the rules engine's
`set_category`, and every picker — for no user-visible gain in a consumer app.
The XOR posting gets the balanced-entry invariant while leaving all of that
untouched. Full CoA remains a possible phase 2; nothing here forecloses it.

**Tags are deliberately not part of the posting model.** A leg needs an amount
and exactly-once placement; tags are amount-less, 0..N, and overlapping by
design (a dinner tagged `#tokyo-trip` + `#reimbursable` shows at full value in
both views — tag sums exceed money moved on purpose). They stay entry-level
labels in `entry_tags`, a filter dimension, never a balancing bucket. The
balancing leg is always an account or a category. (If a tag-like dimension
ever needs to *partition* money — per-project P&L, envelopes — that's a new
postings dimension to design then, not a reuse of tags.)

---

## 3. The write chokepoint — `lib/db/entries.ts` (new)

All writes to `entries`/`postings` go through one module, the way `insertTxRow`
is the single insert path today. Runs inside the route's `BEGIN/COMMIT`
(`lib/db/server.ts:392`); multi-step rewrites use the SAVEPOINT-composition
idiom from `recomputeAmountBases` (`lib/db/queries/ledgers.ts:50`).

### 3.1 API

```ts
type NewLeg =
  | { accountId: string; amount: number;            // signed, in the ACCOUNT's currency
      origAmount?: number; origCurrency?: string;   // foreign-entry display figures (§5.2)
      clearedAt?: string | null; memo?: string | null }
  | { categoryId: string | null; amountBase: number; memo?: string | null };  // ledger base

interface NewEntry {
  id?: string; ledgerId: string; date: string; time?: string | null;
  description: string; kind: EntryKind; status?: 'pending' | 'confirmed';
  categoryLegsAutoBalance?: boolean;   // common case: derive the single category leg from the account leg
  legs: NewLeg[];
  notes?, counterpartyId?, refundedEntryId?, sourceTemplateId?, timestamp?, skipRules?;
}

postEntry(exec, e: NewEntry): Promise<{ entryId: string }>
rebuildEntry(exec, entryId, patch: EntryPatch): Promise<{ touchedAccountIds: string[] }>
deleteEntry(exec, entryId): Promise<{ touchedAccountIds: string[] }>
resolveEntryRef(exec, idFromClient): Promise<{ entryId, postingId, accountId } | null>  // §4.2
auditLedger(exec, ledgerId?): Promise<AuditProblem[]>                                   // §3.3
ensureSystemCategories(exec, ledgerId): Promise<SystemCategoryIds>
```

`postEntry` responsibilities, in order (mirrors `insertTxRow`'s current duties):
resolve account currencies + ledger base → derive each leg's
`amount_base`/`exchange_rate` via `convertToBase` at the entry date (callers
may pre-supply, as seed does today) → run counterparty resolution + the rules
engine for income/expense/refund kinds (`skipRules` parity; a rule's `split`
action becomes N category legs) → **derive the residue leg** (§5.1) → compute
`dedup_hash` → INSERT entry (`sealed=0`) + postings → `UPDATE entries SET
sealed = 1` (fires the balance check) → done. Friendly dedup error mapping
moves to the new constraint signature in `withDedupMessage`
(`lib/db/mutations.ts:186`).

`rebuildEntry` is the single edit path (replaces `updateTransaction` +
`updateTransfer` + `setTransactionSplits`): snapshot → unseal → patch header
and/or rewrite legs (amount/currency/date edits re-derive locked bases and the
residue leg, preserving today's "rate is always the rate on the row's own
date" invariant) → reseal → `recomputeAccount` for every touched account.
Convenience wrappers keep `mutations.ts` cases thin: `postSimple` (one account
leg + auto-balanced category leg/s), `postTransfer`, `postAdjustment`,
`postOpening`.

### 3.2 Schema backstops (triggers)

Same "the schema is its own contract" posture as the holdings guards:

```sql
-- Balance + shape check, fired by the seal UPDATE (two-phase write).
CREATE TRIGGER tr_entry_seal BEFORE UPDATE OF sealed ON entries
FOR EACH ROW WHEN NEW.sealed = 1 AND (
     ROUND((SELECT COALESCE(SUM(amount_base), 0) FROM postings WHERE entry_id = NEW.id), 2) != 0
  OR (SELECT COUNT(*) FROM postings WHERE entry_id = NEW.id) < 2
  OR (SELECT COUNT(*) FROM postings WHERE entry_id = NEW.id AND account_id IS NOT NULL) < 1)
BEGIN SELECT RAISE(ABORT, 'Entry postings must balance'); END;

-- Sealed entries are immutable: INSERT/UPDATE/DELETE on their postings abort.
-- The WHEN subquery returns NULL once the parent entry row is gone, so the
-- FK CASCADE from deleteEntry passes through the DELETE guard untouched.
CREATE TRIGGER tr_post_sealed_insert BEFORE INSERT ON postings
FOR EACH ROW WHEN (SELECT sealed FROM entries WHERE id = NEW.entry_id) = 1
BEGIN SELECT RAISE(ABORT, 'Unseal the entry before editing postings'); END;
-- … tr_post_sealed_update / tr_post_sealed_delete analogous …

-- Account-leg currency guard (kills F3 by construction).
CREATE TRIGGER tr_post_currency BEFORE INSERT ON postings
FOR EACH ROW WHEN NEW.account_id IS NOT NULL
  AND NEW.currency != COALESCE((SELECT currency FROM accounts WHERE id = NEW.account_id), NEW.currency)
BEGIN SELECT RAISE(ABORT, 'Account posting must be in the account currency'); END;
-- … same guard on UPDATE OF account_id, currency …

-- Cached balance: replaces tr_update_account_balance. No currency CASE —
-- posting.amount IS account-native. Insert-only, exactly like today; edits
-- and deletes go through recomputeAccount.
CREATE TRIGGER tr_post_balance AFTER INSERT ON postings
FOR EACH ROW WHEN NEW.account_id IS NOT NULL
  AND (SELECT status FROM entries WHERE id = NEW.entry_id) = 'confirmed'
BEGIN
  UPDATE accounts SET current_balance = ROUND(current_balance + NEW.amount, 2),
                      updated_at = datetime('now')
  WHERE id = NEW.account_id;
END;
```

`recomputeAccount` simplifies to:

```sql
SELECT COALESCE(SUM(p.amount), 0) FROM postings p
JOIN entries e ON e.id = p.entry_id
WHERE p.account_id = ? AND e.status = 'confirmed'
```

(no opening-balance seed term — the opening entry is in the sum).

### 3.3 `auditLedger` — the trial balance (F8)

Read-only sweep returning typed problems: unbalanced/unsealed/under-2-leg
entries, kind↔shape mismatches (I7), account-leg currency mismatches, cross-
ledger postings (I5), `amount ≠ amount_base` on base-currency legs (I9),
non-zero global trial balance (I8), and cached `current_balance` drift vs the
recompute sum. Wired into: **import** (`/api/import` after the checksum
check — semantic validation on top of byte integrity), **`/api/db-info`**
(surfaced count), the **migration** (§8, abort on failure), and a test helper
asserted at the end of every `mutations.test.ts` scenario (cheap, catches
regressions broadly).

---

## 4. Projection — the single-entry skin

### 4.1 The `Tx` contract is preserved

`projectState` (`lib/db/state.ts`) emits **one `Tx` per account leg** — exactly
today's row shape, including two `Tx` rows per transfer. `lib/store.ts` and
`lib/select.ts` need **no changes** (the client-side refund/`isSpend` widening
stays as-is; it's correct against this projection).

| `Tx` field | Source |
|---|---|
| `id` | **account posting id** (§4.2) |
| `amount` | account leg `amount_base` (signed — same as today) |
| `nativeAmount` / `currency` | leg `orig_amount ?? amount` / `orig_currency ?? currency` |
| `account` | leg `account_id` |
| `category` | the entry's single category leg's `category_id`; with ≥ 2 category legs, the largest-\|amount\| leg's (display default; aggregations use `splits`) |
| `splits` | ≥ 2 category legs → `[{ id, categoryId, amount: −leg.amount, amountBase: −leg.amount_base, description: memo }]` — **negated** back to today's parent-signed convention (`lib/store.ts:64`). Equity legs are never projected as splits or category. |
| `kind` | `entries.kind`; **`kind='opening'` entries are filtered out** of the Tx list entirely (opening balances are invisible in Activity today) and projected into `AccountRow.openingBalance` / `openingBalanceBase` instead |
| `transferGroupId` | the entry id, when the entry has ≥ 2 account legs (so `selectTransfers`' grouping works verbatim) |
| `refundedTransactionId` | the refunded entry's (single) account-posting id, via join |
| `clearedAt` | the leg's `cleared_at` (per-account clearing preserved) |
| `tags` | `entry_tags` (both transfer legs now share tags — §10.3) |
| `merchant`, `date`, `time`, `note`, `pending`, `ledgerId`, `sourceTemplateId`, `counterpartyId`, `appliedRuleIds`, `reviewedAt` | `entries` columns (merchant = description with the counterparty-canonical override, unchanged) |

`AccountRow.openingBalance/openingBalanceBase` are projected from the opening
entry's account leg (0/0 when none), keeping `lib/reconcile.ts` and
`unrealizedFx` (`lib/select.ts:843`) working unchanged.

### 4.2 Client-id strategy: `Tx.id` = account-posting id

Every mutation arg that is "a transaction id" today resolves through
`resolveEntryRef(postingId) → { entryId, postingId, accountId }` at the
`applyMutation` boundary. Posting-scoped ops (`setCleared`) use the posting;
everything else (update/delete/confirm/tags/splits/attachments/refund-link)
operates on the entry. Combined with id reuse in the migration (§8.3), client
state is **bit-identical across the cutover**.

---

## 5. Multi-currency mechanics

### 5.1 The FX residue leg (realized FX, made explicit)

Cross-currency transfer legs each lock their own `amount_base` (rates table or
user-pinned amounts), so `Σ base ≠ 0` in general. `postEntry`/`rebuildEntry`
compute the residue and append a `sys:fx-gain` equity leg of `−residue`
(skipped when `|residue| < 0.005`). Entries therefore balance **exactly** (I1
needs no tolerance), and the silent net-worth drift in F4 becomes a real,
queryable posting. Same-currency entries produce no residue by construction
(the auto-balanced category leg is the exact negation; split legs reuse the
existing last-split-absorbs-rounding logic).

### 5.2 Foreign-currency entry on a mismatched account (fixes F3)

When the user enters an amount in a currency other than the account's, the
account leg is **converted into the account's currency** at the entry date
(`convertToBase(amount, entered → account currency, date)` — the USD-hub
cross-rate path that transfers already use), and the typed original is kept as
`orig_amount`/`orig_currency` for display. The account balance moves by an
account-native figure, always.

### 5.3 `changeLedgerBase` (`recomputeAmountBases` rewrite)

Per entry, in one SAVEPOINT: reconvert each **account leg's** `amount_base`
from its native amount at the entry date under the new base; rewrite each
**category leg** (`amount = amount_base` = old base figure reconverted at the
same date); delete + re-derive the **residue leg**; then update
`ledgers.base_currency`, recompute every account, and run `auditLedger`. The
`opening_balance_base` re-stamping clause disappears — opening entries are
reconverted by the same uniform path.

---

## 6. Mutation rewires (`lib/db/mutations.ts`)

| Case | Becomes |
|---|---|
| `addTransaction` | `postSimple` — account leg (sign by kind) + auto-balanced category leg; rules/counterparty/dedup inside `postEntry` |
| `createTransfer` | `postTransfer` — two account legs (+ residue leg); **no `transfer_groups` INSERT**; same validation (distinct accounts, positive magnitudes, same-currency equality, pinned `toAmount` honored verbatim) |
| `updateTransfer` | `rebuildEntry` with the same proportional-scaling semantics (`queries/transfers.ts:78` doc comment carries over) |
| `deleteTransfer` / `deleteTransaction` | `deleteEntry` — one path; deleting any leg's `Tx.id` removes the whole entry (fixes F1; §10.1) |
| `updateTransaction` | `rebuildEntry` — patch contract preserved verbatim (amount is native-in-`currency` as today; amount/currency/date edits re-lock bases; account move swaps the leg's `account_id` + re-derives currency/base; status flip moves `confirmed_at`; income→refund reclassification = kind label + `refunded_entry_id` only, since both shapes are `account +X / category −X`) |
| `setTransactionSplits` | `rebuildEntry` replacing category legs (negate input signs per §2.2); same sum-to-parent penny validation, now subsumed by I1 |
| `adjustAccountBalance` / `reconcileAccount`'s remainder | `postAdjustment` — account leg + `sys:balance-adjustment` leg; reconcile's cleared-sum query drops its `opening_balance` term (opening leg is created pre-cleared) |
| `setCleared` | `UPDATE postings SET cleared_at … WHERE id = ?` (per-leg, as today) |
| `setReviewed` / `markAllReviewed` / `bulkRecategorize` | entry-level UPDATEs (`bulkRecategorize` rewrites the category leg of single-category entries; split entries are skipped — parity, since today it only sets the ignored parent default) |
| `confirmTransaction` / `confirmPendingWithMerchant` / `confirmAllPending` | `entries.status` flip + recompute (unchanged pattern) |
| `postScheduled` / `generateDueScheduled` | post entries; transfer occurrences = one entry (not two rows) — the date-dedupe Set logic simplifies |
| `reset` | RESET_TABLES swaps in `entries`, `postings`, `entry_tags`, `entry_attachments` |
| rules `backfillRule` | header-field UPDATEs on entries; `set_category` rewrites the category leg of single-category entries |
| `createAccount` | inserts the account (no balance columns) + posts the opening entry when `openingBalance ≠ 0` (dated today, leg pre-`cleared_at`, kind `opening`) |
| `deleteAccount` | guard becomes "no postings" (`COUNT postings WHERE account_id` — the opening entry counts; delete it first via UI affordance or auto-delete when it's the only one: **auto-delete the opening entry, then the account** — preserves today's "txn-less accounts are deletable" UX) |
| `changeLedgerBase` | §5.3 |

`lib/store.ts` is untouched — optimistic updates already speak `Tx`, and
`deleteTransfer`'s optimistic filter (`t.transferGroupId !== id`) keeps working
because `transferGroupId` *is* the entry id.

> **PR-B adapter preconditions (from PR-A review):** when an adapter rewrites
> legs through `rebuildEntry`, it must (a) forward each account leg's
> `cleared_at` — omission silently un-clears a reconciled row — and (b) pass
> explicit `amountBase` values when the entry carries user-pinned rates that a
> date edit must preserve: `rebuildEntry`'s date-only path deliberately
> re-locks from the rates table (decide per call site whether pinned bank
> rates survive date edits; `updateTransfer`'s adapter almost certainly wants
> them preserved).

## 7. Read-path rewires

| Reader | Change |
|---|---|
| `state.ts` `projectState` | entries ⋈ postings → §4.1 table; `splitsByTransaction` dies (legs arrive in the same join); opening entries → `AccountRow` fields |
| `queries/transactions.ts` `listTransactions` / `getTransaction` | `FROM postings p JOIN entries e`, one row per account leg; filters map 1:1 (`direction` → sign of `p.amount`, `accountId` → `p.account_id`, amount bounds → `ABS(p.amount_base)`, FTS → `entries_fts`); `categoryId` filter matches via EXISTS over category legs (now also matches split rows — §10.4) |
| `queries/transfers.ts` `listTransfers` | entries with ≥ 2 account legs; from/to by leg sign within a sealed, audited entry; effective rate = `|to/from|` |
| `queries/categories.ts` `categorySpend` | SUM over category legs of `kind IN ('expense','refund')` entries — §2.2 entry-kind bucketing (split COALESCE gymnastics deleted) |
| `lib/budgets/rollover.ts` `spentInRange` | same shape (category legs ⋈ entries; **keeps** the `kind IN ('expense','refund')` gate, drops `transfer_group_id IS NULL` + the split-join) |
| `queries/accounts.ts` | `recomputeAccount` per §3.2; `listAccounts` projects opening fields; `netWorth` unchanged |
| `queries/scheduled.ts` `installmentPaid` | `COUNT entries WHERE source_template_id AND confirmed` — transfer templates stop double-counting (§10.5) |
| `queries/export.ts` `transactionsCsv` | join rewrite; CSV columns/order unchanged (category column follows the §4.1 largest-split rule) |
| `queries/attachments.ts` + `/api/attachments*` | table/FK rename; route still receives `transactionId` (= posting id) and resolves via `resolveEntryRef` |
| `queries/metadata.ts` `CANONICAL_TABLES` | `transactions`/`transaction_tags`/`transaction_splits`/`transfer_groups` → `entries`/`postings`/`entry_tags`/`entry_attachments` (checksum + pack `row_counts` keys follow; old packs still import — migrations run when the swapped file is opened) |
| `lib/db/server.ts` `requiredTables` | `transactions` → `entries`, `postings` |

## 8. Migration

### 8.1 Canonical schema + version

Rewrite `SCHEMA` in `lib/db/schema.ts` to the new shape (fresh DBs are born
double-entry), bump `SCHEMA_VERSION` to `2026-06-12T00:00:00Z`, and add one
`MIGRATIONS` entry that upgrades existing dev DBs in place. Before the data
move, the runner takes a defensive `VACUUM INTO '<file>.pre-de.bak'` snapshot
(one line; this migration is the largest the project has shipped).

### 8.2 Data move (inside the migration's transaction)

1. Create new tables/indexes/triggers; rebuild `categories` with the new CHECK
   + `system` column (SQLite can't ALTER a CHECK — the `scheduled_templates`
   recreation dance; a migrated file keeping the old CHECK would *reject* the
   equity system rows), re-kinding `'transfer'` rows to `'expense'` in the
   copy; `ensureSystemCategories` per ledger.
2. **Transfers**: per `transfer_group_id` — entry id = **the group id**, kind
   `transfer`, header from the legs (`MAX(date)`, shared time/notes); the two
   rows become account legs **keeping their row ids**; Σ-base residue → fx leg.
3. **Singles**: entry id = **the transaction id**; account leg id = **the same
   transaction id** (different table — no collision; this is what keeps every
   client-visible id stable); category leg id `<id>-c0` with the negated
   amount/base; rows with splits get one category leg per split (ids reused,
   signs negated); `kind='adjustment'` rows balance against
   `sys:balance-adjustment`.
4. **Strays** (the F1/F2 damage): transfer-kind rows whose group is missing or
   half-deleted migrate as `adjustment` entries against
   `sys:balance-adjustment`.
5. **Foreign-currency rows on mismatched accounts** (F3): account leg amount =
   `convert(native → account currency, row date)`; original pair preserved as
   `orig_*`. Balances will shift for these rows — that's the bug fix landing
   (§10.2).
6. **Opening balances**: per account with `opening_balance ≠ 0` — entry
   `open-<accountId>` dated the account's `created_at`, account leg
   (`amount = opening_balance`, `amount_base = opening_balance_base`,
   pre-cleared) + equity leg; then rebuild `accounts` without the two columns
   (the `scheduled_templates_new` recreation dance).
7. `transaction_tags` → `entry_tags` (transfer pairs: UNION of both legs'
   tags); `transaction_attachments` → `entry_attachments` (ids equal — pure
   rename, no remap); `refunded_transaction_id` values are already the
   refunded entry ids.
8. Backfill `entries_fts`; drop old tables + FTS + triggers.
9. Recompute every account; run `auditLedger` and **abort the migration on any
   problem** (the `.pre-de.bak` snapshot is the rollback).

### 8.3 Id stability summary

| Old | New | Client impact |
|---|---|---|
| `transactions.id` (single) | entry id AND account-posting id | `Tx.id` unchanged |
| `transactions.id` (transfer leg) | account-posting id | `Tx.id` unchanged |
| `transfer_groups.id` | entry id of the transfer | `Tx.transferGroupId` unchanged |
| `transaction_splits.id` | category-posting id | `Tx.splits[].id` unchanged |

## 9. Seed & fixtures

`data/transactions.json` stays in `Tx` shape (fixtures untouched).
`insertTransactions` (`lib/db/seed.ts`) converts: group rows by
`transferGroupId` → `postTransfer`-shaped entries; singles → `postSimple`
shapes with pre-resolved bases (seed already batch-converts; pass them
through, `skipRules` as today). `seedTransactionTags` targets `entry_tags`.
Seed calls `ensureSystemCategories` per seeded ledger. The seeded accounts'
`openingBalance` fields become opening entries via the same `createAccount`
path.

## 10. Deliberate behavior changes

1. **Deleting a transfer leg deletes the whole transfer** (was: silent orphan
   leg). Transaction-detail delete copy gains a "removes both sides" hint when
   `transferGroupId` is set.
2. **Balances move for foreign-currency rows on mismatched accounts** — the F3
   fix materializing at migration time. Expected to touch few/no real rows
   (the add form defaults to the account currency); the migration logs a count.
3. **Tags and reviewed-state become entry-level** — a transfer's two legs share
   them (was: independently taggable legs).
4. **Category filter in Activity now matches split transactions** whose splits
   contain the category (was: parent-category-only match).
5. **`installmentPaid` on transfer templates counts occurrences, not legs**
   (pre-existing double-count bug fixed by construction).
6. **`Tx.category` for split rows** = largest split's category (was: the stale
   parent default, which aggregations already ignored).
7. **Adjustment/opening entries carry explicit equity legs** — invisible in
   today's UI (projection emits `category: null` for equity legs), but newly
   queryable: a future Insights "net-worth explained" panel
   (income − expenses + adjustments + FX) becomes a SELECT, not a project.
8. **The category type picker drops "Transfer"** (§2.3); existing
   transfer-kind categories silently become expense-kind. They were inert —
   no aggregation ever read them.

## 11. Tests

- **New `lib/db/entries.test.ts`** — the contract suite: I1–I9 (balance, seal
  abort on unbalanced/1-leg/0-account-leg, sealed-immutability, currency guard,
  cascade-delete passthrough, residue derivation incl. pinned-amount transfers,
  dedup hash parity incl. NULL-time carve-out, audit catches each seeded
  corruption, ledger-scope guard).
- **Migration test** (`migrate.test.ts`): build a pre-DE fixture DB (singles,
  transfer, pinned cross-currency transfer, splits, refund link, adjustment,
  orphan transfer leg, foreign-currency row, tags, attachment rows, opening
  balances, a user-created transfer-kind category → asserts re-kinded to
  expense) → migrate → audit clean + **golden projection test**:
  `projectState` output deep-equals the pre-migration projection except the
  documented deltas (§10).
- **Rewritten assertions**: `mutations.test.ts` (table names + audit helper at
  scenario end), `queries/transactions.test.ts`, `seed.test.ts`,
  `state.test.ts`, `import.test.ts` / `pack.test.ts` / `metadata.test.ts`
  (row_counts keys), `budgets/rollover.test.ts`, `domains.test.ts`.
- **Untouched (the skin proof)**: `select.test.ts`, `insights.test.ts`,
  `reconcile.test.ts`, rules engine tests, `recurrence`, `csv`, `rates`,
  `holdings`, `driver`/`probe`.
- **e2e**: existing flows should pass unchanged (add/edit/delete, transfer
  create/edit/delete, splits editor, refund flow, reconcile + clear, pending
  confirm, scheduled post, export/import round-trip). One new e2e: delete a
  transfer from the detail sheet → both legs gone from both accounts.

## 12. File touch list & PR split

| Path | Change |
|---|---|
| `lib/db/schema.ts` | New canonical SCHEMA (entries/postings/entry_tags/entry_attachments/entries_fts + triggers + indexes; categories `system` column + `equity` kind); version bump; the §8 MIGRATIONS entry |
| `lib/db/entries.ts` **(new)** | Chokepoint: postEntry/rebuildEntry/deleteEntry/resolveEntryRef/auditLedger/ensureSystemCategories + wrappers |
| `lib/db/queries/transactions.ts` | Reads via postings⋈entries; `insertTxRow`/`updateTransaction` bodies delegate to the chokepoint |
| `lib/db/queries/transfers.ts` | Shrinks: list = 2-account-leg entries; update/delete delegate |
| `lib/db/queries/transactionSplits.ts` | Deleted (splits are legs) |
| `lib/db/queries/accounts.ts` | recompute/list/netWorth per §7; create/delete per §6 |
| `lib/db/queries/categories.ts`, `lib/budgets/rollover.ts` | Spend SQL over category legs |
| `lib/db/queries/ledgers.ts` | `recomputeAmountBases` per §5.3 |
| `lib/db/queries/scheduled.ts`, `export.ts`, `attachments.ts`, `metadata.ts` | Per §7 |
| `lib/db/mutations.ts` | Case rewires per §6; RESET_TABLES; dedup message signature |
| `lib/db/state.ts` | Projection per §4.1 |
| `lib/db/seed.ts` | Per §9 |
| `lib/db/server.ts` | `requiredTables` |
| `app/api/import/route.ts`, `app/api/db-info/route.ts` | `auditLedger` wiring |
| `components/transaction-detail.tsx` | Delete-copy hint for transfer legs (§10.1) |
| `app/(main)/categories/page.tsx` | Drop `'transfer'` from `TYPES` (§2.3) — with the line above, the only client files touched |
| tests | Per §11 |
| `plans/database_design_en.md` | v3: §6 entries/postings reference, retire transactions/transfer_groups/transaction_splits sections, new decisions #26+ (XOR postings, equity categories, seal pattern, residue legs, id reuse) |
| `plans/MASTER_PLAN.md`, `plans/LEDGER_CRUD_PLAN.md` | Track shipping; ledger-delete ordered list + `createLedger` → `ensureSystemCategories` |

**Suggested PR split**

1. **PR A — additive core**: schema additions behind the chokepoint module +
   `entries.test.ts`. App still runs entirely on the old tables; new code is
   exercised by tests only. Small, reviewable, establishes the contract.
2. **PR B — the cutover**: migration + seed + every §6/§7 rewire + projection +
   table lists + test updates + golden projection test. Inherently atomic
   (the tables swap); commit-split inside the PR: (b1) migration+seed,
   (b2) write paths, (b3) read paths/projection, (b4) test sweep.
3. **PR C — dividends & hardening**: audit wiring (import / db-info / test
   helper), the §10.1 delete-copy hint, align `netWorthSeries`/`netWorthByMonth`
   with `include_in_net_worth` (the F4 inconsistency — a pre-existing bug now
   trivially fixable), docs (design-doc v3, MASTER_PLAN).

---

## Out of scope

- ❌ **Full chart-of-accounts** (categories stay their own table — §2.6).
- ❌ **Commodity/lot accounting for holdings** (decision #23 stands; the
  postings model doesn't block it later).
- ❌ **Integer minor units (cents)**: tempting while the money core is open,
  but it doubles the blast radius; the locked `r2` discipline + exact-balance
  residue legs make float drift *detectable* (audit I1/I8), which is the
  acute need. Revisit as its own migration if audit ever trips in practice.
- ❌ **Credit-card `include_in_net_worth` default flip** (liability framing
  argues for it, but it's a product decision independent of this schema —
  follow-up).
- ❌ **Net-worth-explained Insights panel** (enabled by §10.7; build when
  wanted).
- ❌ Budget/rules/scheduled feature changes of any kind.
