# Finch — SQLite Schema Integration Plan

> Companion to `plans/database_design_en.md` (the schema source of truth) and
> `plans/MASTER_PLAN.md` (overall roadmap). This document is the **incremental
> plan for making the design-doc SQLite schema the live backing model** of the
> frontend, replacing the current mix of baked JSON, the Zustand store, and the
> `baseline + delta` derivations — and for routing **all app interactions
> (search, add, filter, …) through the database**.
>
> _Branch:_ `feat/frontend` · _Last updated: 2026-05-26._

---

## 1. Decisions (locked)

| Question | Decision |
|----------|----------|
| **Persistence method** | **A SQLite `.db` file** is the persistence method — stored in **OPFS** (`finch.db`), with localStorage as a no-OPFS fallback and an optional File System Access backup file. ✅ *Implemented (Phase F + `b8aed11`) — see §2.* |
| **DB seam (target)** | A **live in-memory SQLite** (`oo1.DB`) becomes the working source of truth, held open for the session and **queried directly** for reads/writes. The `.db` file remains the persistence method (the live DB is exported to it on change). |
| **Schema scope** | **Full design schema** — all 17 tables + indexes + triggers from `database_design_en.md`, even where the UI doesn't use them yet. |
| **Currency model** | **Adopt dual-currency now**: per-transaction `currency` + native `amount` + locked `amount_base` (per-ledger base currency) + `exchange_rate`. |
| **One file, all ledgers** | **One `.db` for all ledgers** — the schema's native design; no structural changes (see §5). |

---

## 2. Current state — what's already implemented

Persistence-by-file is **done**. Today's data flow (`b8aed11` on `feat/frontend`,
building on Phase F):

- **The `.db` file is the persistence method.** `lib/persistence.ts` → `loadPersisted()`
  on startup: read `finch.db` from **OPFS** (`importBytesToState`); else **localStorage**;
  else keep the seed. `components/store-hydration.tsx` calls it after mount and
  `setState`s the result.
- **Auto-save on every change.** `components/sqlite-backup-provider.tsx` debounces
  (800ms) and writes the current state to OPFS (primary) or localStorage (fallback),
  plus an optional connected backup file; it also **flushes immediately on
  `visibilitychange`/`pagehide`**, and offers Download / Import `.db`.
- **`persist` middleware removed** (`lib/store.ts`); the store starts from seed each
  render (SSR-safe) and is hydrated post-mount. The one-time `localStorage → OPFS`
  migration is effectively handled (localStorage is the fallback/migration source).
- **New editable slice:** `accountOverrides` + `setAccountDetails` (account
  name/type/last4/institution/routing), threaded into `lib/db/repo.ts` `PersistState`.
- **New interaction surfaces** (the components the migration will wire to the DB):
  `add-expense-form` + `add-expense-sheet` (+ provider), `transaction-sheet` +
  `transaction-detail` (+ provider), `use-is-desktop`. Providers are mounted in
  `app/layout.tsx`.
- **e2e/Playwright removed** — verification is now **typecheck · lint · `bun test` ·
  build**, plus manual in-browser checks.

**The gap to the target.** The `.db` today is a **serialized snapshot of the Zustand
store** through a *flat 3-table* schema (`transactions`, `pending`, `meta`-JSON in
`lib/db/repo.ts`). SQLite is opened only momentarily at import/export and is **never
queried**. To get the full relational schema, dual-currency, and **DB-backed
interactions** (§4), we add a **live, queryable connection** and the relational schema —
while keeping the file as the persistence method.

---

## 3. Target architecture

### 3.1 Live DB + file persistence
- One persistent `sqlite-wasm` `oo1.DB` per session (`lib/db/client.ts`).
- On startup: if OPFS holds `finch.db`, `sqlite3_deserialize` it; otherwise create a
  fresh DB, apply the schema, and seed it.
- On every write, the existing `SqliteBackupProvider` debounce exports the **live DB**
  (`client.export()` → `sqlite3_js_db_export`) to OPFS + the connected file handle.
  (Today it serializes the store; we repoint it at the live client. The provider's
  debounce, visibilitychange flush, fallback, and download/import stay as-is.)

### 3.2 The "store-as-cache" bridge (what makes this gradual)
SQLite is the truth, but the **Zustand store stays as a read-cache** so screens don't
all change at once:
- On load, hydrate store slices from SQL `SELECT`s.
- A mutation runs the SQL write (triggers maintain derived tables), then re-`SELECT`s
  the affected slice back into the store.
- Components keep using their existing `useFinanceStore(...)` selectors.

We migrate **one domain at a time** (reads *and* writes together, so the cache never
drifts). As each domain moves to SQL, its baked totals in `data/*.json` and its
`baseline + delta` logic in `lib/derive.ts` are deleted.

### 3.3 SQL location
The design doc suggests `queries/*.sql` files. In the Next/Turbopack bundler we will
instead colocate SQL as typed functions in **`lib/db/queries/*.ts`** (template strings +
typed row mappers). Deliberate deviation, recorded here.

### 3.4 Reactivity
Writes refresh the cached store slice, which already drives re-renders — no new global
subscription machinery is required.

---

## 4. DB-backed interactions (the headline goal)

**Every meaningful interaction is a typed function in `lib/db/queries/*.ts` that runs
SQL against the live DB.** Reads return rows the store-cache slices consume; writes
mutate + let triggers update derived tables, then re-`SELECT`. The catalog below is the
working checklist (grouped by surface; the phase that delivers each is in brackets).

**Global [P0/P1]**
- Ledger scoping on every query (`WHERE ledger_id = :active`); active-ledger switch is a
  filter change, not a reload.

**Transactions · Activity · `transaction-sheet`/`-detail` [P1]**
- **List** (paginated, date-desc), **search** (substring over merchant / note /
  counterparty), **filter** (account, category, status, date range, amount range, tag,
  pending-only), **sort**.
- **Add** (insert with `amount`/`amount_base`/`exchange_rate`/`balance_after`), **edit**,
  **delete** (`status='cancelled'`), **confirm pending**, **confirm-all**.

**Add-expense (`add-expense-form`/`-sheet`) [P1]**
- Insert via the same write path; account/category pickers sourced from DB.

**Accounts [P2]**
- List + group, current balance, **balance curve** (`account_balance_snapshots`),
  **edit details** (`accountOverrides` → `UPDATE accounts`), **net worth**
  (two-level `include_in_net_worth`).

**Categories [P3]**
- Tree (`parent_name`), **per-category spend** (monthly query), create/rename.

**Counterparties / Merchants [P3]**
- List, **search**, **verify** (`is_verified`), **add alias**, merge.

**Budgets [P4]**
- List, **progress** query (filters + rollover), set/create/edit.

**Recurring [P5]**
- List, **edit splits**, **post** (`auto_post` → pending/confirmed tx), archive.

**Transfers [P6]**
- **Create** paired tx sharing `transfer_group_id`; list groups; cross-ledger.

**Reports · Insights · FX [P7]**
- Monthly-by-category, cash flow, apr-vs-may, net-worth trend (from `ledger_summaries` /
  `net_worth_snapshots`); `exchange_rates` lookups + import-time rate locking.

**System [P8]**
- `sync_log` device list, DB stats, reset, export/import (already present).

---

## 5. One file for all ledgers — schema impact

**No schema changes.** The design is already single-file / multi-ledger:

- Every per-ledger table carries `ledger_id TEXT REFERENCES ledgers(id) ON DELETE
  CASCADE`. One file = the `ledgers` table (N rows) + everything else discriminated
  by `ledger_id`.
- **Active ledger is a UI filter** (`WHERE ledger_id = :active`), not a file swap.
  `LedgerProvider` just changes the filter value.
- **`exchange_rates`** is intentionally ledger-agnostic (PK `date, currency`) — shared
  across all ledgers in the file.
- **Cross-ledger features require one file**: `transfer_groups` + the
  `ledger_summaries` `transfer_in`/`transfer_out` split move money between ledgers
  without double-counting in global views. Impossible with one-file-per-ledger.
- **`sync_log`** (per device+ledger) becomes informational under whole-file OPFS
  mirroring — it backs the System screen device list.

**Application-layer discipline this imposes:**
1. Every `INSERT` sets the correct `ledger_id`.
2. Every read scopes by `ledger_id` (except the global tables: `exchange_rates`).
3. `categories.parent_name` lookups are resolved **within a ledger** (names are unique
   per ledger, not globally).
4. Export/import moves **all ledgers together** (matches today's single `finch.db`
   mirror). Per-ledger export, if ever wanted, is an app-layer filtered query — still
   no schema change.

> The rejected alternative (one file per ledger) would mean *removing* `ledger_id`
> everywhere, losing cross-ledger transfers + global net worth, and mirroring N files.

---

## 6. Seed conversion (the trickiest correctness work)

`lib/db/seed.ts` builds the relational + dual-currency seed from the current
`data/*.json`. Non-trivial mappings:

- **Enums**: account `checking→savings`, `credit→credit_card`, `invest→investment`;
  keep `cash`/`fx`/`virtual` where they appear.
- **Categories**: flatten today's `categories.json` + the hardcoded `categoryTree`
  (in `lib/data.ts`) into hierarchical rows (`parent_name`, `type`).
- **Currency**: assign each transaction a `currency` from its account; compute
  `amount_base` via `exchange_rates` (locked); set `exchange_rate`/`exchange_rate_date`.
- **`balance_after`**: insert transactions **per account in date order** so the
  balance trigger computes a correct running balance; seed `accounts.current_balance`
  follows from the last row.
- **Counterparties / budgets / recurring / account edits**: map `verified`/`aliases`,
  `budgetOverrides`, `recurring-templates.json` (+ splits), and `accountOverrides` into
  their tables (account edits become `UPDATE accounts`, not a separate table).

> The `localStorage → DB` migration is already handled by `lib/persistence.ts` (§2).
> Phase 0 must make the live-DB load path **read an existing OPFS `finch.db` if present**
> and only seed when it's absent — i.e. not clobber a user's data.

---

## 7. Phases

Each phase is its own PR against `feat/frontend`, ends with **typecheck · lint ·
`bun test` · build** green, and notes what needs in-browser verification.

> **Already landed** (Phase F + `b8aed11`): file-based persistence, OPFS-authoritative
> load, localStorage fallback/migration, dropping `persist`, and the
> add-expense / transaction sheet components. Phases below build the relational layer
> and route interactions (§4) through it.

### Phase 0 — Foundation (no UI change) ✅ *landed*
- ✅ `lib/db/schema.ts` — full schema (17 tables + indexes + triggers).
- ✅ `lib/db/client.ts` — live `oo1.DB`: `createLiveDb()` (schema + seed) and
  `openLiveDb(bytes)` (deserialize an existing file); `exec` / `export()`.
- ✅ `lib/db/seed.ts` — relational + dual-currency seed (per §6): ledgers,
  account_groups, accounts, categories, counterparties, budgets, transfer_groups,
  exchange_rates, transactions (+ snapshot/summary tables filled by triggers).
  recurring/pending/tags/sync_log/net_worth are seeded in their own phases.
- ✅ `lib/db/queries/transactions.ts` — list / search / filter / add / update /
  cancel / confirm (the §4 transactions interactions).
- ✅ bun tests (`seed.test.ts`, `queries/transactions.test.ts`): schema applies;
  balance/snapshot/summary triggers fire; ledger isolation; headline query.
- *App still runs off the store; the live DB layer runs alongside, test-verified.*
- ⏭ **Deferred to Phase 1** (needs in-browser verification): repointing
  `SqliteBackupProvider`/`persistence.ts` to the live client. **Hazard found:** the
  current OPFS `finch.db` uses the *flat* schema (`lib/db/repo.ts`) with a
  `transactions` table whose columns differ from the relational one — `CREATE TABLE
  IF NOT EXISTS` will **not** reconcile them. Phase 1 must use a new OPFS filename
  (or an explicit migration) so the relational DB never collides with a flat-schema
  file.

### Phase 1 — Transactions spine + dual-currency
Wire the **existing** surfaces — `activity` list, `transaction-sheet`/`-detail`,
`add-expense-form`/`-sheet` — to DB queries from §4 (list / search / filter / sort /
add / edit / delete / confirm), with `amount`/`amount_base`/`exchange_rate`/
`balance_after` + triggers. Hydrate the store's `transactions` slice from SQL; month
spent/income from `ledger_summaries`. Establishes the `DbProvider` + query-hook infra.
(May split 1a read / 1b write.)

### Phase 2 — Accounts, groups, balances, net worth
Account list/detail + balance curve (`account_balance_snapshots`) + net worth (two-level
`include_in_net_worth`, `net_worth_snapshots`). **Edit details** route
`accountOverrides`→`UPDATE accounts`. Retire `accountBalance` / `netWorth` deltas.

### Phase 3 — Categories (hierarchical) + counterparties + tags
Category tree from `categories.parent_name`; per-category spend from the monthly query
(kills baked `category.spent`). Counterparty list/search/**verify**/**alias** persist to
`counterparties` (replaces `verifiedExtra` / `aliasExtra`). Add `tags` /
`transaction_tags` plumbing + tag filter.

### Phase 4 — Budgets
Real `budgets` table with JSON filters + rollover; budget-progress query replaces
`budgetOverrides` + baked `category.budget`.

### Phase 5 — Recurring templates + splits
`recurring_templates` + `recurring_splits`; split editing and **post** (auto_post →
pending/confirmed tx) write to DB.

### Phase 6 — Transfers + transfer_groups
Transfer creation makes a paired tx sharing `transfer_group_id`; reports exclude
transfers correctly (the double-count guard); cross-ledger transfers supported.

### Phase 7 — Reports, summaries, exchange rates, FX
`ledger_summaries`-driven monthly reports / cash flow / apr-vs-may; `exchange_rates`
table + FX screen + import-time rate locking; net-worth trend.

### Phase 8 — System / sync_log + teardown
`sync_log` device list; delete `lib/derive.ts` deltas, baked totals, and replaced store
slices; collapse `lib/db/repo.ts` (flat-schema serializer) once the live schema fully
replaces it; final a11y / test / docs pass.

---

## 8. Risks & open items
- **Architectural shift** — today the `.db` is serialize-only; making it live-queryable
  is the core change. The store-as-cache bridge (§3.2) is what prevents regressions
  during the gradual migration.
- **Seed correctness** (currency, balance ordering, category hierarchy) — verified by
  bun tests in Phase 0 before any UI depends on it.
- **Don't clobber user data** — the live-DB load path must reuse an existing OPFS
  `finch.db` and only seed when absent.
- **Browser-only paths** (OPFS, File System Access, wasm execution) remain **manually
  verified in a real browser** each phase — no e2e harness anymore, so this is the only
  coverage for those paths.
- **Trigger parity in `sqlite-wasm`** — confirm triggers behave identically to the doc
  (Phase 0 tests cover balance/summary triggers).
