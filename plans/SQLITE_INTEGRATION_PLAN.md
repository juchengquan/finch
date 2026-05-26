# Finch — SQLite Schema Integration Plan

> Companion to `plans/database_design_en.md` (the schema source of truth) and
> `plans/MASTER_PLAN.md` (overall roadmap). This document is the **incremental
> plan for making the design-doc SQLite schema the live backing model** of the
> frontend, replacing the current mix of baked JSON, the Zustand store, and the
> `baseline + delta` derivations.
>
> _Branch:_ `feat/frontend` · _Last updated: 2026-05-26._

---

## 1. Decisions (locked)

| Question | Decision |
|----------|----------|
| **DB seam** | A **live in-memory SQLite** (`oo1.DB`) is the working source of truth, held open for the session. Every change is **mirrored to the persistent file** (OPFS + optional File System Access handle) — extending the Phase F sync already built. |
| **Schema scope** | **Full design schema** — all 17 tables + indexes + triggers from `database_design_en.md`, even where the UI doesn't use them yet. |
| **Currency model** | **Adopt dual-currency now**: per-transaction `currency` + native `amount` + locked `amount_base` (per-ledger base currency) + `exchange_rate`. |
| **One file, all ledgers** | **One `.db` for all ledgers** — this is the schema's native design; no structural changes (see §3). |

---

## 2. Architecture

### 2.1 Live DB + file mirror
- One persistent `sqlite-wasm` `oo1.DB` per session (`lib/db/client.ts`).
- On startup: if OPFS holds `finch.db`, `sqlite3_deserialize` it; otherwise create a
  fresh DB, apply the schema, and seed it.
- On every write, the existing `SqliteBackupProvider` debounce (800ms) exports the
  **live DB** (`client.export()` → `sqlite3_js_db_export`) and writes the bytes to
  OPFS + the connected file handle. (Today it re-serializes the store; we point it
  at the live client instead.)

### 2.2 The "store-as-cache" bridge (what makes this gradual)
SQLite is the truth, but the **Zustand store stays as a read-cache** so screens don't
all change at once:
- On load, hydrate store slices from SQL `SELECT`s.
- A mutation runs the SQL write (triggers maintain derived tables), then re-`SELECT`s
  the affected slice back into the store.
- Components keep using their existing `useFinanceStore(...)` selectors.

We migrate **one domain at a time** (reads *and* writes together, so the cache never
drifts). As each domain moves to SQL, its baked totals in `data/*.json` and its
`baseline + delta` logic in `lib/derive.ts` are deleted.

### 2.3 SQL location
The design doc suggests `queries/*.sql` files. In the Next/Turbopack bundler we will
instead colocate SQL as typed functions in **`lib/db/queries/*.ts`** (template
strings + typed row mappers). This is a deliberate deviation, recorded here.

### 2.4 Reactivity
Writes refresh the cached store slice, which already drives re-renders — no new global
subscription machinery is required.

---

## 3. One file for all ledgers — schema impact

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

## 4. Seed conversion (the trickiest correctness work)

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
- **Counterparties / budgets / recurring**: map `verified`/`aliases`, `budget`
  overrides, and `recurring-templates.json` (+ splits) into their tables.

A one-time **`localStorage → DB` import** runs on first launch so existing local data
isn't lost when truth moves from localStorage to the OPFS `.db`. After that, the
Zustand `persist` middleware is dropped.

---

## 5. Phases

Each phase is its own PR against `feat/frontend`, ends with **typecheck · lint ·
`bun test` · build** green, and notes what needs in-browser verification.

### Phase 0 — Foundation (no UI change)
- `lib/db/schema.ts` — full schema (17 tables + indexes + triggers), verbatim intent
  from the design doc.
- `lib/db/client.ts` — one persistent `oo1.DB`; deserialize from OPFS or
  create + schema + seed; `exec` / `query` / `export()`.
- Rewire `SqliteBackupProvider` to mirror the **live client** (keep OPFS + FS handle +
  debounce).
- `lib/db/seed.ts` — relational + dual-currency seed (per §4).
- bun tests: schema applies; triggers fire (balance, snapshot, summary); headline
  queries (monthly-by-category, cash flow, budget progress, net worth) return expected
  numbers.
- *App still runs off the store; DB runs alongside, test-verified.*

### Phase 1 — Transactions spine + dual-currency
Migrate the transactions slice (list / detail / add / edit / delete→`status='cancelled'`)
to DB writes with `amount_base` / `exchange_rate` / `balance_after` + triggers; hydrate
the store's `transactions` from SQL. Month spent/income come from `ledger_summaries`.
Establishes the `DbProvider` + query-hook infra. (May split 1a read / 1b write.)

### Phase 2 — Accounts, groups, balances, net worth
Account screens + balance curve (`account_balance_snapshots`) + net worth (two-level
`include_in_net_worth`, `net_worth_snapshots`). Retire `accountBalance` / `netWorth`
deltas.

### Phase 3 — Categories (hierarchical) + counterparties + tags
Category tree from `categories.parent_name`; per-category spend from the monthly query
(kills baked `category.spent`). Counterparty verify/alias persist to `counterparties`
(replaces `verifiedExtra` / `aliasExtra`). Add `tags` / `transaction_tags` plumbing.

### Phase 4 — Budgets
Real `budgets` table with JSON filters + rollover; budget-progress query replaces
`budgetOverrides` + baked `category.budget`.

### Phase 5 — Recurring templates + splits
`recurring_templates` + `recurring_splits`; split editing and "post" (auto_post →
pending/confirmed tx) write to DB.

### Phase 6 — Transfers + transfer_groups
Transfer creation makes a paired tx sharing `transfer_group_id`; reports exclude
transfers correctly (the double-count guard); cross-ledger transfers supported.

### Phase 7 — Reports, summaries, exchange rates, FX
`ledger_summaries`-driven monthly reports / cash flow / apr-vs-may; `exchange_rates`
table + FX screen + import-time rate locking; net-worth trend.

### Phase 8 — System / sync_log + teardown
`sync_log` device list; delete `lib/derive.ts` deltas, baked totals, and replaced store
slices; drop `persist` (DB is truth); final a11y / test / docs pass.

---

## 6. Risks & open items
- **Seed correctness** (currency, balance ordering, category hierarchy) — verified by
  bun tests in Phase 0 before any UI depends on it.
- **Truth migration** — the one-time `localStorage → DB` import must be idempotent and
  not clobber an existing OPFS `.db`.
- **Browser-only paths** (OPFS, File System Access, wasm execution) remain
  **manually verified in a real browser** each phase — they can't run headlessly in CI.
- **Trigger parity in `sqlite-wasm`** — confirm triggers behave identically to the doc
  (Phase 0 tests cover balance/summary triggers).
