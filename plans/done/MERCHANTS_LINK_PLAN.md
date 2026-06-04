# Link merchants (counterparties) to transactions

Status: **implemented & merged** on `feat/frontend`. `transactions.counterparty_id`
points to `counterparties.id` (SET NULL on delete). Insert/update mutations call
`resolveCounterpartyIdByName` (case-insensitive exact match within the ledger);
`projectState` swaps in the canonical catalog name for any row with a non-NULL
FK, so renames follow history without touching `transactions.description`. Auto-
creation of catalog rows from typed names is intentionally NOT done — the
catalog stays curated. See `plans/database_design_en.md` §6.10 + decision #18.
The original spec is kept below as the design rationale.

---

## 1. Goal & current state

### Today
- There is a `counterparties` table (`id, ledger_id, name, is_verified, …`) and a
  **Merchants** admin screen (`app/(main)/merchants/page.tsx`) that lists / adds /
  renames / verifies / deletes rows.
- A transaction stores its merchant as **free text** in `transactions.description`
  (`Tx.merchant` ⇄ `description`). There is **no `counterparty_id`** — the catalog
  is never referenced. `queries/counterparties.ts:1-3` and `:81-86` say so outright
  ("the link is informational only").

### Consequences (why this is worth doing)
- Renaming a merchant doesn't touch past transactions.
- "Verified" is cosmetic.
- No reliable "all spend at merchant X" — only fuzzy text matching.

### Goal
Give each merchant-bearing transaction a real pointer to a `counterparties` row,
so merchant becomes structured data: pick-or-create on entry, rename propagates,
and grouping/filtering by merchant works.

### Important scoping nuance
`description` is **overloaded** today: it's the merchant for expense/income/refund,
but for **transfers** it's `"Transfer to <account>"` and for scheduled posts it's
the template label. So:
- **Counterparty applies only to `kind IN ('expense','income','refund')`.**
- `transfer` / `adjustment` rows keep `counterparty_id = NULL` and continue to use
  `description` as their label.

---

## 2. Key decisions

### D1. Is merchant mandatory? — and the default value *(the question that prompted this)*
**Recommendation: keep `counterparty_id` NULLABLE; treat NULL as "Unknown".**
- The merchant field is *encouraged* but never blocks a save. A blank merchant on
  an expense/income/refund saves with `counterparty_id = NULL`.
- The UI renders `NULL` via a single fallback label — **`"Unknown"`** (one constant,
  e.g. `UNKNOWN_MERCHANT` in `lib/data.ts`). This is the "default value" — it costs
  no row and no migration, and a later tightening is cheap.
- **If a stricter, truly-mandatory model is wanted later:** seed one reserved
  **per-ledger** `counterparties` row (stable id `cp-unknown-<ledgerId>`, `is_verified
  = 0`, undeletable, rename-allowed) and point blank entries at it. Only then would we
  consider `NOT NULL DEFAULT`. Not needed for v1; NULL + label is strictly simpler and
  forward-compatible.

> Net: "mandatory merchant" is satisfied by a **default fallback**, not a validation
> wall. Start with NULL→"Unknown"; promote to a reserved row only if reporting needs
> every row to resolve to a real merchant id.

### D2. Where does the displayed name live? FK + resolve, vs. denormalized cache
**Recommendation: FK is the single source of truth; resolve the name on read.**
- `transactions.counterparty_id` is canonical. The display name is **derived** by
  joining `counterparties` (server) / a `Map<id,name>` lookup (client), not stored a
  second time. Matches the repo's "derive, don't store redundant" stance (cf.
  `lib/derive.ts`).
- `description` is freed up to be an **optional memo / the transfer-&-scheduled label**
  only. For unlinked legacy/edge rows, display falls back to `description`, then
  `"Unknown"`.
- Rejected alternative — cache the name in `description` and fan-out on rename: faster
  reads but reintroduces drift; not worth it given the store already holds all
  counterparties in memory.

### D3. Deleting a merchant that's in use
**Recommendation: `ON DELETE SET NULL`** (the row becomes "Unknown"), plus a UI
confirm that says how many transactions will be unlinked. (A "merge into another
merchant" flow is a nice-to-have — see §8.)

### D4. Matching on entry (find-or-create)
Resolve typed text to an id: case-insensitive exact-name match within the active
ledger → reuse; otherwise create a new (unverified) counterparty. Blank → NULL.

---

## 3. Schema changes (`lib/db/schema.ts`)

```sql
-- in CREATE TABLE transactions:
counterparty_id  TEXT REFERENCES counterparties(id) ON DELETE SET NULL,
-- new index:
CREATE INDEX IF NOT EXISTS idx_txn_counterparty
  ON transactions(counterparty_id) WHERE counterparty_id IS NOT NULL;
```
- Bump `SCHEMA_VERSION`.
- No `NOT NULL` (per D1). No reserved row in v1.

---

## 4. Data layer

### 4.1 `Tx` shape (`lib/store.ts`)
- Add `counterpartyId?: string` to `Tx`.
- `Tx.merchant` stays the **display name** (resolved), so existing UI reading
  `t.merchant` is unchanged.

### 4.2 Reads (`lib/db/queries/transactions.ts` + `lib/select.ts`)
- `listTransactions`: `LEFT JOIN counterparties cp ON cp.id = t.counterparty_id`;
  `rowToTx` sets `counterpartyId` and `merchant = cp.name ?? description ?? 'Unknown'`.
- Search: extend the `description LIKE ?` filter to also match the joined `cp.name`.
- `lib/select.ts` (`selectTransactions`, and anywhere merchant is shown): resolve via a
  `Map<counterpartyId,name>` built from the store's `counterparties`, with the same
  fallback chain. Keep the client mirror in lockstep with the SQL.

### 4.3 Writes (`lib/db/mutations.ts`, `lib/db/queries/transactions.ts`)
- `AddInput` + `addTransaction`: accept `counterpartyId?: string | null`; write the column.
  Keep `description` for an optional memo.
- A shared **resolveCounterparty(exec, ledgerId, name) → id | null** helper:
  trim → blank ⇒ `null`; exact (case-insensitive) name match ⇒ that id; else
  `createCounterparty` and return the new id. Used by add + edit.
- `updateTransaction`: already supports arbitrary column patches — add
  `counterpartyId` to its patch `Pick` (mirrors how `kind`/`refundedTransactionId`
  were just added) and write `counterparty_id`.
- Transfers (`createTransfer`) + scheduled posts: leave `counterparty_id = NULL`
  (their `description` label is intentional). Revisit scheduled in §8.

### 4.4 Seed + rebuild (`lib/db/seed.ts`, `lib/db/state.ts`) — the "backfill"
Because we reset rather than migrate, linking happens **at seed time**:
- `insertTransactions`: for each `expense|income|refund` row, `resolveCounterparty`
  by its merchant text within the row's ledger (creating catalog rows as needed),
  and set `counterparty_id`. The existing `counterpartiesData` seed stays as the
  curated/verified set; name matches reuse those ids.
- `state.ts` rebuild (store → DB) must carry `counterpartyId` through so live-created
  links survive an export/rebuild round-trip.

### 4.5 Merchant rename / delete (`lib/db/queries/counterparties.ts`)
- Rename: unchanged mechanically (FK means it auto-propagates to display) — drop the
  `:71` comment that says category/links don't apply.
- Delete: `ON DELETE SET NULL` handles the unlink; update the `:81-86` comment.

## 5. UI

- **Add/Edit form** (`components/add-expense-form.tsx`): the "Merchant" text input
  becomes a **combobox** — search existing merchants (scoped to active ledger via the
  store's `counterparties`), pick one, or "Create '<typed>'". Stores the resolved
  `counterpartyId` (or null) on save. Transfer mode is unaffected (no merchant field).
- **Transaction detail** (`components/transaction-detail.tsx`): same merchant picker
  for editing; calls `updateTransaction({ counterpartyId })`.
- **Merchants page** (`app/(main)/merchants/page.tsx`): show a per-merchant **usage
  count** ("12 transactions"); delete confirm states the unlink count; optionally a
  "verified" filter now that it's meaningful.
- **Search** (`components/command-palette.tsx`, `activity`): matches merchant names via
  the read changes in §4.2 — no per-call-site change beyond using the updated selector.
- Display fallback constant `UNKNOWN_MERCHANT = 'Unknown'` (`lib/data.ts`), used wherever
  a row resolves to no counterparty.

## 6. Reset & rollout
- Schema change ⇒ **reset the live DB**: rename `frontend/.data/finch.sqlite3` aside
  (the established `.stale-*` convention) and restart the dev server so it reseeds with
  links. No `MIGRATIONS` entry (pre-release, no DBs to preserve).
- Old exported backups (pre-column) become incompatible — acceptable pre-release; note
  it in the import path if we surface a message.

## 7. Risks & edge cases
- **Duplicate-by-spelling at seed**: normalize on trim + case before matching so
  "Amazon"/"amazon" collapse to one row. Decide whether to also strip punctuation
  (recommend: trim + case only for v1, to stay predictable).
- **Cross-ledger**: counterparties are per-ledger; never match/reuse across ledgers.
- **Store/SQL drift**: `lib/select.ts` must mirror the new join/fallback exactly, or
  client and server disagree on merchant text. Add a unit test asserting parity.
- **Optimistic add**: store sets `merchant` to the typed name immediately; server
  reconciles `counterpartyId` + canonical name on the next projection.

## 8. Out of scope (follow-ups)
- **Merge merchants** (dedupe two catalog rows, repoint transactions).
- **Counterparty on scheduled templates** (so auto-posts link too).
- **Auto-categorize by merchant** (a merchant's usual category as a default).
- Reserved per-ledger "Unknown" row + `NOT NULL` (the strict variant of D1).

## 9. Phased checklist
1. **Schema**: add `counterparty_id` + index; bump `SCHEMA_VERSION`. *(D1, §3)*
2. **Read path**: join + `rowToTx`/`selectTransactions` resolution + fallback; search. *(§4.2)*
3. **Write path**: `resolveCounterparty` helper; `addTransaction` + `updateTransaction`
   write the column. *(§4.3)*
4. **Seed/rebuild**: link at seed; carry `counterpartyId` through `state.ts`. *(§4.4)*
5. **UI**: merchant combobox in Add + detail; merchants-page usage counts / delete
   confirm. *(§5)*
6. **Reset** the live DB; **parity test** for store-vs-SQL merchant resolution. *(§6, §7)*
