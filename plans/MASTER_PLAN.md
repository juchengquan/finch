# Finch — Master Plan

Status snapshot and roadmap, derived from the design prototypes in
`plans/frontend_design/`, the data model in `plans/database_design_en.md`,
and the current implementation in `frontend/`.

> **SQLite integration shipped** (PRs #15–#17): the design-doc schema is now the
> app's live data layer, served by a **server-side** SQLite database. See
> `plans/SQLITE_INTEGRATION_PLAN.md` for the architecture and what remains.

_Last updated: 2026-05-27._

---

## 1. Where we are

**Stack (implemented):** Next.js 16 (App Router, Turbopack) · React 19 · TypeScript ·
Tailwind v4 · shadcn/ui (Radix) · lucide-react · next-themes (light/dark) · Bun.

**Data layer:** a **server-side SQLite database** (the full
`database_design_en.md` schema via `@sqlite.org/sqlite-wasm` in Node) is the
source of truth, persisted to a file at `FINCH_DB_DIR`/`FINCH_DB_FILE`. The
browser talks to it via API routes (`GET /api/state`, `POST /api/mutate`,
`GET /api/db-info`); the Zustand store is a mirror that hydrates on load and
syncs every mutation. Static reference seed still lives in `frontend/data/*.json`.

**Shell & system:**
- ✅ Single-render responsive shell (`PageShell`): desktop sidebar + header,
  mobile bottom tab bar.
- ✅ Light/dark theming (warm = light, noir = dark) via `next-themes`.
- ✅ Display-currency switch (`CurrencyProvider`, shadcn `Select`).
- ✅ shadcn component library in `components/ui/*`; lucide `Icon` shim.
- ✅ SVG chart primitives: `Sparkline`, `BarChart`, `Donut`, `StackedBar`, `Ring`.
- ✅ Money formatting (`fmtMoney`, `fmtMoneyShort`, `fmtNative`).

### Screen status vs. design

Legend: ✅ done · 🟡 partial · ⬜ not started · ⊘ intentionally dropped

| Area | Screen / feature | Status | Notes |
| --- | --- | --- | --- |
| Main | Accounts (net-worth hero, grouped accounts) | ✅ | Mobile parity; desktop is the mobile layout reflowed |
| Main | Account detail (balance hero, sparkline, tx list, details panel) | ✅ | Quick actions are display-only |
| Main | Add expense | ✅ | Amount + category/account `Select` (DB-sourced, ledger-scoped) + date; inserts via the server, appears in Activity |
| Main | Budgets (ring + category list) | ✅ | Per-category **Budget detail** drill-in done |
| Main | Budget detail (ring, left/over, tx list) | ✅ | `budgets/[id]` |
| Main | Insights (trend, insight cards, Apr-vs-May) | ✅ | Metric tabs (Spending/Income/Cashflow) + 3M/6M/1Y ranges |
| Main | Scheduled (month calendar grid + upcoming list) | ✅ | Month nav + per-day dots |
| Main | Transaction detail | ✅ | Dots `DropdownMenu` (recurring/delete), inline recategorize `Select`, recurring toggle |
| Main | Settings | 🟡 | Theme + currency + Data + **Database** (shows server file path, Export, Import disabled); missing grouped sections + **tab-layout editor** |
| Main | Goals | ✅ | Aggregate progress + per-goal Ring cards |
| Main | Subscriptions | ✅ | Monthly + annualized totals + list |
| Main | Activity (cross-account feed, filters, search) | ✅ | Grouped by day, All/Out/In, **SQL search/filter** via the live DB |
| Main | Reports | ✅ | Spending donut + breakdown, **DB-derived** category spend, ledger-scoped |
| Ledger | Pending review (confirm/edit/cancel, bulk) | ✅ | Confirm / Cancel / Confirm-all sync to the server (`app_state` queue) |
| Ledger | Transfers (two-sided) | ✅ | **DB-derived list + "New transfer"** → paired rows sharing `transfer_group_id`; real transactions |
| Ledger | Merchants / counterparties (aliases, verified) | ✅ | List reads the projected table; **create / rename / recategorise / delete**, verify/unverify, add/remove alias, SQL search |
| Ledger | Recurring templates (list + splits) | ✅ | **Create** template + edit fields/splits + delete; **"Post now"** → confirmed tx(s) on the server |
| Ledger | Categories admin | ✅ | **Create / edit / delete** (name/type/icon/hue); delete leaves txns uncategorised |
| Ledger | Tags admin | ✅ | **Create / edit / delete** (name + hue); assignments cascade on delete |
| Ledger | Ledger switcher (bottom sheet) | ✅ | Per-ledger base currency; sidebar + Settings; scopes Activity/derived figures |
| Ledger | Ledger admin table (desktop) | 🟡 | Header only |
| Ledger | Category tree (2-level) | ⬜ | `categories` table seeded; admin screen not DB-wired |
| Ledger | System admin (exchange-rate book, sync log) | ⬜ | `exchange_rates` seeded; `/system` + `/fx` screens still static |
| Ledger | FX transaction detail | 🟡 | dual-currency stored (`amount`/`amount_base`); conversion/rate-locking simplified |
| System | Multi-palette / font / density tweaks panel | ⊘ | Deliberately replaced by light/dark (prior decision) |

**Charts not yet built (design defines them):** `CalendarHeatmap`, multi-series `AreaChart`.

**Cross-cutting status:**
- ✅ **Mutations are real** — add/edit/delete/confirm/verify/alias/transfer/recurring-post
  run SQL on the server DB (triggers maintain balances/snapshots/summaries) and the
  store mirrors the result. (The DB's `status` model is `confirmed`/`pending`/`cancelled`;
  delete = soft-cancel.)
- ✅ **Server-side persistence** — a SQLite file at `FINCH_DB_DIR`/`FINCH_DB_FILE`,
  written after every change and reloaded across restarts. No CSV import / auth / multi-device sync.
- **Desktop is still the mobile layout in a sidebar shell** — the design specifies distinct
  desktop dashboards (account-card grid, activity/admin tables, budget stat tiles,
  large calendar, metric tabs).
- **`MOCK` vs `LEDGER` reference data** still coexist for display metadata (account
  colors/last4, hues) the schema doesn't model; the live figures now come from the DB.
- **Remaining DB wiring**: Categories admin, FX, System screens; tags UI; balance-curve
  & net-worth charts; full FX conversion. Plus cleanup (retire `derive.ts` fallbacks +
  baked JSON totals + dead `repo.ts`/`storage.ts`; resolve the redundant browser
  `DbProvider`). See `SQLITE_INTEGRATION_PLAN.md` §6.

---

## 2. Guiding principles

- **Mobile-first, then bespoke desktop.** Match the editorial design; desktop is
  not just reflowed mobile.
- **Mock-first, backend-last.** Make everything work against an in-memory store
  shaped like the DB design, so a real backend can drop in later behind the same
  data layer.
- **Preserve the aesthetic.** Warm/noir light-dark, editorial type, token-driven.
- **Each phase ships a working, verifiable build** (tsc + lint + `next build` +
  light/dark screenshot check), committed in increments.

---

## 3. Roadmap

### Phase A — Complete the read-only mobile surface ✅ _(done)_
Built on existing mock data; no new state machinery.
- [x] **Goals** — aggregate saved/of-target bar + per-goal `Ring` cards.
- [x] **Subscriptions** — monthly + annualized totals + list with cadence/next.
- [x] **Activity** — cross-account feed grouped by day; All/Out/In filter; search box.
- [x] **Reports** — spending `Donut` + category breakdown + CSV-export toast.
- [x] **Budget detail** route (`budgets/[id]`) — category ring, left/over, tx list.
- [x] **Scheduled** → month **calendar grid** (per-day dots, month nav) + upcoming list.
- [x] **Insights** → metric tabs (Spending/Income/Cashflow) + 3M/6M/1Y ranges.
- [x] **`AreaChart`** primitive (used by Insights cashflow).
- [ ] **`CalendarHeatmap`** primitive — deferred; not required by current screens.

### Phase B — Make it interactive (client state over mock) ✅ _(core done)_
- [x] Typed in-memory **store** — Zustand (`lib/store.ts`), seeded from JSON.
- [x] **Add expense**: amount input + category/account `Select` + date; optimistic
      insert → appears in Activity / account / budget lists.
- [x] **Transaction detail**: `DropdownMenu` ("dots") with mark-recurring + delete,
      inline recategorize `Select`, recurring toggle, and **Split** (move part of the
      amount into another category → creates the split) — all with `sonner` toasts.
- [x] **Pending review**: Confirm / Cancel / Confirm-all mutate the store + toasts.
- [x] Reading surfaces (Activity, account detail, budget detail, tx) read from the store.
- [x] Edit flows — editable **budgets** (override dialog), **recurring splits**
      (live recompute + 100% validation), and **merchant verify / add-alias**.
      All persisted via the store; budgets/counterparties/recurring now editable.

> Derived figures (net worth, per-category `spent`, budget totals) recompute from the
> store as of **Phase C**.

### Phase C — Unify the data model around the ledger schema ✅ _(done)_
- [x] **Per-ledger base currency** model (`LedgerProvider`, `LEDGERS` with `base`);
      `personal` = USD, `family` = SGD, `business` = CNY, `travel` = JPY.
- [x] **Ledger switcher** (`Sheet`) in the desktop sidebar + Settings; sets active ledger.
- [x] **Per-ledger data** — Family ledger fully populated (accounts, categories,
      transactions in SGD); accounts/categories/transactions tagged by ledger.
- [x] **Scope by ledger** — Accounts, Budgets, Activity filter by the active ledger
      (empty states for ledgers without data); Add tags the active ledger.
- [x] **Derive figures from the store** (`lib/derive.ts`) — category spent, account
      balances, net worth recompute (verified: Food budget $612 → $662 after a $50 add).
- [x] **Currency conversion** — amounts stored in each ledger's base; `useMoney` converts
      to the chosen display currency (verified: Family net worth SGD 7,159 → $5,303).

> Full schema fidelity (dual `amount`/`amount_base`, `status` machine,
> counterparties, parent categories, snapshots) landed in **Phase G** — the
> server-side SQLite database, which persists to a file across restarts.

### Phase D — Bespoke desktop dashboards ✅ _(done)_
- [x] Desktop content container (centered, `max-w-6xl`) in the shell so pages stop
      stretching edge-to-edge.
- [x] **Desktop Accounts** — gradient account-card grid + recent-activity table.
- [x] **Desktop Activity** — full transactions table (date/merchant/category/account/status/amount).
- [x] **Desktop Budgets** — Spent/Remaining/Over stat tiles + 2-column category grid.
- [x] **Desktop Insights** — full-width fluid charts + metric/range controls + 3-up
      insight cards + Apr-vs-May comparison.
- [x] **Desktop Scheduled** — large calendar + upcoming list, side by side.
- Account/budget detail drill-ins already read well on desktop (breadcrumbs present).

### Phase E — Ledger-admin completeness ✅ _(done)_
- [x] **Transfers** list-driven — `/transfers` lists all groups → `/transfers/[id]`
      detail (two-sided legs, locked rate, schema rows).
- [x] **Recurring** list-driven — `/recurring` lists all templates → `/recurring/[id]`
      detail with editable splits.
- [x] **Category tree** — read-only 2-level taxonomy at `/categories` (+ ledger tab).
- [x] **FX transaction detail** (`/fx`) — original vs. locked base amount, locked
      rate + date, schema rows, and a JPY→SGD rate sparkline.
- [x] **System admin** (`/system`) — exchange-rate book (rates, source badges,
      sparklines, Refresh) + `sync_log` device list (last sync/txn, This-device badge).
      Added a desktop-only **System** ledger tab.

### Phase F — Persistence & real SQLite ✅ _(done)_
Reframed from the original "build a backend" plan: the app is client-only and runs
in an ephemeral container, where a server/DB would not be durable and would be a
large rewrite. So Phase F leads with **client persistence**, keeping the store as
the seam a real backend can slot behind later.
- [x] **Client persistence** — Zustand `persist` → `localStorage` (`finch-store`,
      versioned, partialized to transactions + pending). SSR-safe via
      `skipHydration` + a `StoreHydration` rehydrate-on-mount. Mutations now
      survive a full reload (verified). localStorage remains the **primary** store.
- [x] **Reset to sample data** control in Settings (restores the seed).
- [x] **Real SQLite file** (`@sqlite.org/sqlite-wasm`) — the store is serialised into
      an actual `.db`:
      - `lib/db/repo.ts` — DB-agnostic schema + save/load (`transactions`, `pending`,
        `meta` JSON), tested in bun against an in-memory `oo1.DB` (`repo.test.ts`).
      - `lib/db/sqlite.ts` — in-memory export (`sqlite3_js_db_export`) / import
        (`sqlite3_deserialize`) to/from `.db` bytes (`sqlite.test.ts` round-trip).
        Loads the worker-free wasm build from `/public` at runtime (`webpackIgnore`)
        so Turbopack never bundles the package's dynamic Worker URL; bun tests resolve
        the package directly.
      - `lib/db/storage.ts` — sinks: **OPFS** (`navigator.storage.getDirectory` →
        `finch.db`, auto-written) and an optional **File System Access** handle the
        user picks once (`showSaveFilePicker`), plus plain Download / Import.
      - `components/sqlite-backup-provider.tsx` — subscribes to the store and
        **auto-mirrors** to OPFS + the connected file on every change (debounced 800ms).
      - Settings → **Database**: sync status, Connect/Disconnect backup file,
        Download .db, Import .db.
      > Verified here: SQL/repo layer + export/import (bun), typecheck/lint/build, and
      > that `/sqlite3.mjs` + `/sqlite3.wasm` and the Settings UI are served. The
      > in-browser OPFS / File System Access / wasm-execution paths need manual
      > verification in a real browser.
> ⚠️ **Superseded by Phase G.** The OPFS / File-System-Access / localStorage
> client persistence above was replaced by a real server-side database. The
> relational schema, queries, and seed built here were reused on the server.

### Phase G — Relational schema + server-side SQLite ✅ _(done; PRs #15–#17)_
The design-doc schema is now the app's live data layer. See
`plans/SQLITE_INTEGRATION_PLAN.md` for detail.
- [x] **Full relational schema** (`lib/db/schema.ts`) + seed (`seed.ts`) + typed
      queries/mutations (`lib/db/queries/*`, `mutations.ts`), all unit-tested.
- [x] **Server-side DB** (`lib/db/server.ts`) — `@sqlite.org/sqlite-wasm` in Node,
      loaded from a file on startup, written back on every change. File path from
      `FINCH_DB_DIR`/`FINCH_DB_FILE`. API: `GET /api/state`, `POST /api/mutate`,
      `GET /api/db-info`.
- [x] **Source-of-truth flip** — the store mirrors the server (hydrate on load,
      POST every mutation). OPFS/localStorage persistence removed. Settings →
      Database shows the file path, Export enabled, Import disabled.
- [x] **DB-backed UI** — Activity (search/filter), Accounts (balances/net worth),
      Merchants (search/verify/alias), Budgets + Reports (DB-derived spend),
      Add-expense, Transaction detail, Transfers (create paired rows), Recurring
      ("Post now").
- [x] **DB-backed admin screens** — Categories admin + Tags admin landed with full
      CRUD in Phase H (below).
- [ ] **Remaining** — FX / System screens; balance-curve & net-worth charts; full
      FX conversion; cleanup (retire `derive.ts` + baked JSON + dead
      `repo.ts`/`storage.ts`; resolve the redundant browser `DbProvider`).

### Phase H — Full CRUD parity ✅ _(done; see `plans/CRUD_PARITY_PLAN.md`)_
Brought every user-facing entity to full Create / Update / Delete (or archive) and
retired the last `app_state` override shims. Delivered in phases on one branch:
- [x] **Schema versioning** — `SCHEMA_VERSION` + `migrate()` in `lib/db/schema.ts`
      (stamps fresh DBs, runs ordered `ALTER`s on existing files; reached **v4**).
- [x] **Balance recompute** — `recomputeAccount` keeps `current_balance` /
      `balance_after` correct after any edit/cancel/delete (the trigger is INSERT-only).
- [x] **Accounts** — display columns + create / table-backed update / archive /
      delete; **`accountOverrides` retired**.
- [x] **Delete/edit everywhere** — shared `<RowActions>` (⋯ menu + confirm) +
      edit dialogs for categories, goals, tags, subscriptions, recurring, transfers,
      merchants.
- [x] **Budgets on the table** — per-category upsert + `budgetByCategory`
      projection; **`budgetOverrides` retired**.
- [x] **Scheduled** create/update/delete; **Transfers** edit (rewrite both legs +
      recompute); **createRecurring**; **createCounterparty**.
- [x] **Last shim retired** — verify/alias write the `counterparties` table;
      **`verifiedExtra`/`aliasExtra` removed**, `app_state` no longer read or written.

### Cross-cutting ✅ _(done)_
- [x] **Accessibility pass** — decorative chart SVGs `aria-hidden`; aria-labels on
      every icon-only button and search/form input; Radix covers dialogs/menus/selects/focus.
- [x] **Unit tests** — `bun test` over `lib/` (formatters, currency conversion,
      derive deltas, **the full DB schema/seed/queries/mutations** incl. CRUD +
      migrations + balance recompute); ~84 tests.
- [x] **CI** runs typecheck · lint · **unit tests** · build. (Playwright e2e was
      removed; browser-only flows are verified manually.)

---

## 4. Open decisions — resolved

1. ~~**State library**~~ → **Zustand** (store is now a mirror over the server DB).
2. **Base/display currency** — each ledger keeps its own base; `useMoney` converts
   to the chosen display currency. (Full cross-currency conversion/locking still simplified.)
3. ~~**Backend shape**~~ → **Next.js API routes + server-side `@sqlite.org/sqlite-wasm`**
   reading/writing an env-configured file (not Flask / not `better-sqlite3`).
4. **Desktop scope** — still the responsive single-render shell; bespoke desktop
   dashboards remain optional.

## 5. Suggested next step

Phases A–H are done — the design-doc SQLite schema is the live, server-backed data
layer; the core money flows run through it; and every entity has full CRUD with no
remaining `app_state` shims. What's left:
1. **Finish the last screens** on the DB — FX, System.
2. ✅ **Cleanup pass** — `derive.ts`, the flat-schema `repo.ts`/`storage.ts`, and
   the redundant browser `DbProvider` were already gone. This pass removed the
   remaining dead `MOCK` re-exports (15 fields incl. `user`/`balance`/`monthSpent`/
   `transactions`/`subscriptions`/`goals`/`bills`/`daily`/`insights`/`aprVsMay`)
   and deleted three orphan JSON files (`dashboard-summary.json`,
   `daily-spending.json`, `bills.json`). The Insights page still consumes baked
   `monthly` / `cashflow` series + `INSIGHTS` / `APR_VS_MAY` — replace with
   derived series from live transactions in a later pass.
3. Optional polish: balance-curve / net-worth charts; real FX conversion; the
   deferred `CalendarHeatmap` / `AreaChart` primitives + Receipt-attach stub.
4. **Income + Adjustment transaction types** — Income is data-supported (Tx
   `kind`, recurring/category `'income'` enums, positive amounts) but has no UI
   entry point. Adjustment isn't represented anywhere (no enum, no UI). The
   smallest income fix is generalising `/add` into "Add transaction" with an
   expense/income toggle; adjustment needs a data model decision (likely a
   transactions enum column) plus an account-detail "Reconcile balance" entry.

Done since (Phase H follow-ups): recurring **split add/remove** UI on the template
detail screen, and the **download backup** now streams the live server DB via
`GET /api/export` (table edits included). **Readable export** — `GET
/api/export/transactions` returns a transactions CSV (account/category names + tags
resolved via joins); Settings has a "Download .csv" button. Multi-entity / XLSX is
a possible later extension (CSV builder lives in `lib/csv.ts`).
