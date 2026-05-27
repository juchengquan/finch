# Finch — SQLite Schema Integration Plan

> Companion to `plans/database_design_en.md` (the schema source of truth) and
> `plans/MASTER_PLAN.md` (overall roadmap). This tracked making the design-doc
> SQLite schema the live backing model of the app and routing interactions
> (search / add / filter / verify / post / transfer …) through it.
>
> _Branch:_ `feat/frontend` · _Last updated: 2026-05-27._
>
> **Status: shipped (PRs #15–#17).** The relational schema is the app's data
> layer, served by a **server-side** SQLite database. A few screens and some
> cleanup remain — see §6.

---

## 1. Decisions (final)

| Question | Decision |
|----------|----------|
| **Where the DB lives** | **Server-side.** The Next.js server owns a single SQLite database (`lib/db/server.ts`), loaded from a file on startup and written back after every change. The browser talks to it over API routes. *(This superseded the earlier browser-only OPFS plan — see §2.)* |
| **File / persistence** | A real `.db` file whose location comes from env vars: **`FINCH_DB_DIR`** (default `<cwd>/.data`) + **`FINCH_DB_FILE`** (default `finch.sqlite3`). Survives restarts when the dir is persistent; written atomically (temp + rename). |
| **Source of truth** | The **server database**. The Zustand store is a **mirror**: it hydrates from `GET /api/state` and every action POSTs `/api/mutate`, replacing the store with the server's projected state. |
| **Schema scope** | The **full design schema** — all 17 tables + indexes + triggers from `database_design_en.md`, plus a transitional `app_state` table for slices not yet promoted to real tables. |
| **Currency model** | Dual-currency: per-transaction `currency` + native `amount` + `amount_base` + `exchange_rate`. The add path stores all four; cross-currency conversion/locking is still simplified (rate = 1 when the entry matches the ledger base). |
| **One file, all ledgers** | One `.db` for all ledgers; `ledger_id` scopes every table (see §3). |

---

## 2. Architecture as built

The plan originally targeted a **browser** live DB persisted to OPFS. Midway we
switched to a **server-side** database (env-configured file), which is more
correct for "synced to a file across restarts" and is fully testable via `curl`.
The browser OPFS / localStorage persistence was removed.

**Data flow**
- **`lib/db/server.ts`** — process-singleton SQLite (the `@sqlite.org/sqlite-wasm`
  runtime in Node), `deserialize`d from the env file on first use (or seeded if
  absent), written back after each mutation. `serverExternalPackages` keeps the
  wasm package out of the bundler.
- **API routes** (`app/api/*`, Node runtime):
  - `GET /api/state` → projected full app state.
  - `POST /api/mutate` → `{ action, args }` runs a write (`lib/db/mutations.ts`),
    triggers maintain balances/snapshots/summaries, persists, returns new state.
  - `GET /api/db-info` → the resolved file path (shown in Settings).
- **Client** (`lib/api-client.ts`) — `fetchState` / `mutate` / `fetchDbInfo`.
  `StoreHydration` loads state on mount; store actions update optimistically then
  POST and reconcile from the server response.
- **Relational layer** (driver-agnostic, reused on server + in tests):
  `schema.ts` (DDL + triggers), `seed.ts` (relational + dual-currency seed),
  `state.ts` (`serializeState`/`deserializeState`/`projectState`/`buildState`),
  `queries/*.ts` (typed reads), `mutations.ts` (typed writes).
- **Browser query DB** (`components/db-provider.tsx` + `lib/db/runtime.ts`) — a
  second in-memory DB rebuilt from the store, used by the read-query screens
  (Activity/Accounts/Merchants/Budgets/Reports). Now redundant with the server
  (see §6 cleanup).

**SQL location** — colocated as typed functions in `lib/db/queries/*.ts` (not
`queries/*.sql` as the design doc suggests). Deliberate deviation.

---

## 3. One file for all ledgers — schema impact

**No schema changes** — the design is already single-file / multi-ledger:
- Every per-ledger table carries `ledger_id REFERENCES ledgers(id) ON DELETE CASCADE`.
- Active ledger is a `WHERE ledger_id = :active` filter, not a file swap.
- `exchange_rates` is intentionally ledger-agnostic (shared).
- Cross-ledger transfers + global net worth require the shared file.

Discipline: every `INSERT` sets `ledger_id`; reads scope by it (except global
tables); `categories.parent_name` resolves within a ledger.

---

## 4. Seed conversion (done)

`lib/db/seed.ts` builds the relational + dual-currency seed from `data/*.json`:
enum mapping (`checking→savings`, `credit→credit_card`, `invest→investment`);
each account's **opening balance** is fixed (seed balance − seed deltas) so
`current_balance` tracks the live transaction set; counterparties/budgets/
transfer_groups/exchange_rates seeded; pending/recurring/override slices live in
`app_state`. `reset` reseeds the whole DB.

> Note: the 3 illustrative cross-ledger seeded transfers were dropped — they
> referenced accounts that don't exist as real accounts. Transfers are now real
> transaction pairs.

---

## 5. Phases — status

| Phase | What it delivered | Status |
|-------|-------------------|--------|
| **0 — Foundation** | `schema.ts`, `seed.ts`, `client.ts`, `queries/transactions.ts` + tests | ✅ #15 |
| **1 — Relational persistence** | `state.ts` serialize/deserialize; store-as-cache; round-trip test | ✅ #15 |
| **Query backends** | `queries/{accounts,categories,counterparties,reports}.ts` + tests | ✅ #15 |
| **UI: Activity** | list / search / filter via SQL | ✅ #16 |
| **UI: Add-expense** | category/account pickers from the DB, ledger-scoped | ✅ #16 |
| **UI: Transaction detail** | category pickers ledger-scoped | ✅ #16 |
| **2 — Accounts** | balances / group totals / net worth + detail tx list from DB; opening-balance fix | ✅ #16 |
| **3 — Merchants** | verified/aliases + search from DB; `buildState` applies verify/alias | ✅ #16 |
| **4 — Budgets** | spend DB-derived (`categorySpend`) | ✅ #16 |
| **7 — Reports** | DB-derived category spend, ledger-scoped | ✅ #16 |
| **Server flip** | server-side DB + API + env file persistence; Settings shows path, Import disabled | ✅ #16 |
| **6 — Transfers** | `createTransfer` → paired rows sharing `transfer_group_id`; DB-derived list + "New transfer" | ✅ #16 |
| **5 — Recurring** | split editing; **"Post now"** → confirmed tx(s) with account-name resolution | ✅ #17 |

Categories "spent" and Reports moved to **true DB-derived** figures (lower than
the former curated mock totals) by explicit decision.

---

## 6. Remaining work

**Screens DB-wired — done:**
- ✅ **Categories admin** (`/categories`) — reads projected categories; create + rename.
- ✅ **FX** (`/fx`) — shows a real foreign-currency transaction with its locked
  base/rate; rates from the projected `exchange_rates`. `insertTransactions` locks
  the per-row rate at import.
- ✅ **System** (`/system`) — exchange rates + devices projected (`sync_log`
  extended with name/current).
- ✅ **Pending** (`/pending`) — migrated to `transactions.status='pending'`;
  confirm flips status (flows into reports/balances), cancel voids. Legacy
  `app_state` pending slice retired.
- ✅ **Goals** (`/goals`) — new `goals` table; create + contribute.
- ✅ **Subscriptions** (`/subscriptions`) — new `subscriptions` table; add.
- ✅ **Scheduled** (`/scheduled`) — new `scheduled_items` table; calendar reads it.

**Schema-backed UI — done:**
- ✅ **Tags / `transaction_tags`** — projected; tag chips + create + assign on the
  transaction detail, tag filter on Activity.
- ✅ **Balance curve** — `balanceSeries` (from the projected store) drives a
  sparkline on the account detail.
- ✅ **Net-worth trend** — `netWorthSeries` drives a sparkline on Accounts.

**Known/intentional (still simplified):**
- **Insights** stays curated (seed has no multi-month history).
- **Dual-currency**: rate *locking* is now real (stored per transaction), but
  cross-base conversion (e.g. deriving a USD base from a to-SGD rate table) is
  still simplified.
- **Recurring templates** still live in `app_state` JSON rather than the
  `recurring_templates` table.

**Cleanup / teardown — done:**
- ✅ Deleted the dead flat-schema layer: `lib/db/repo.ts` trimmed to shared types,
  `lib/db/sqlite.ts` flat (de)serialize removed, `lib/db/storage.ts` reduced to
  `downloadBytes`.
- ✅ Resolved the redundant **browser `DbProvider`**: the server projection
  (`/api/state`) now carries accounts/categories/counterparties, the store mirrors
  them, and the read screens compute from the store via `lib/select.ts`.
  `components/db-provider.tsx`, `lib/db/runtime.ts`, `lib/db/client.ts` deleted.
- ✅ Retired `lib/derive.ts` (figures come from the projected store).
- ✅ Removed the baked `spent` totals from `data/categories.json` (recomputed now).
  `accounts.balance` / `categories.budget` stay — they seed the DB.

---

## 7. Notes & deviations
- TEXT primary keys reuse the app's existing string ids (not UUIDs); dates are ISO
  `YYYY-MM-DD`. Both are documented deviations from `database_design_en.md`.
- A transitional `app_state(key,value)` table holds store slices (pending,
  recurring, budget/account overrides, verified/alias) not yet promoted to real
  tables; each is read/written by `mutations.ts` and projected by `state.ts`.
- The server singleton assumes a single server instance (fine for `bun dev` / a
  single container); a multi-instance deploy would need a shared DB.
- Verification is **typecheck · lint · `bun test` · `next build`** plus `curl`
  against the API routes; browser-only UI flows still need a manual check.
