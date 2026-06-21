# Finch — Master Plan

Status snapshot and roadmap, derived from the design prototypes in
`plans/frontend_design/`, the data model in `plans/database_design_en.md`,
and the current implementation in `frontend/`.

> **SQLite integration shipped** (PRs #15–#17): the design-doc schema is now the
> app's live data layer, served by a **server-side** SQLite database. See
> `plans/done/SQLITE_INTEGRATION_PLAN.md` for the architecture and what remains.

_Last updated: 2026-06-08._

### Plans index

What lives in `plans/` (active) vs `plans/done/` (shipped design records):

**Active planning + reference (`plans/`):**

- `MASTER_PLAN.md` — this file.
- `database_design_en.md` — the canonical relational schema design (reference, not a feature plan).
- `FEATURE_IDEAS.md` — categorized backlog of ~50 feature ideas.
- `INSPIRATION_IDEAS.md` — broader product-direction brainstorm.
- `IOS_MACOS_PLAN.md` — (refreshed 2026-06-07) product + architecture direction brief for a future native iOS / macOS port. §2 rewritten storage-first under the now-shipped **double-entry storage model** (`SCHEMA_VERSION = 2026-06-14T00:00:00Z`; see `plans/done/DOUBLE_ENTRY_PLAN.md` for the design record). §2.6 records the `Tx` projection contract native MUST emit; §4.6 the migration discipline; §4.9 the `auditLedger` audit-parity requirement. All three §8 cross-app implications shipped (attachments PR #106, pack format PR #107, ledger CRUD PR #109). §11 cross-references the web's now-shipped i18n approach in `plans/done/I18N_PLAN.md`.
- `PWA_PLAN.md` — **explicitly superseded** by `IOS_MACOS_PLAN.md`. Kept as a fork-in-the-road record; do not implement.

**Shipped design records (`plans/done/`):**

- `BUDGET_CYCLES_PLAN.md`, `CRUD_PARITY_PLAN.md`, `FX_CONVERSION_PLAN.md`, `IMPORT_EXPORT_PLAN.md`, `INSIGHTS_PLAN.md`, `MERCHANTS_LINK_PLAN.md`, `MULTI_CURRENCY_ACCOUNTS_PLAN.md`, `SETTINGS_AND_TRANSFERS_PLAN.md`, `SQLITE_INTEGRATION_PLAN.md`, `budgets_redesign.md` — earlier plans, all shipped.
- `RECONCILE_PLAN.md` — shipped via PRs #90 + #101 (v2).
- `RULES_ENGINE_PLAN.md` — shipped via PRs #91, #94 + the UI series in PR #102.
- `FILE_BACKED_DB_PLAN.md` — shipped via PRs #96, #97, #99, #100 (the persistence runtime moved from in-memory `sqlite-wasm` to file-backed `better-sqlite3` with WAL).
- `RECEIPT_PHOTOS_PLAN.md` — moved here 2026-06-06; shipped via PR #106 (web-app receipt attachments end-to-end — schema + upload route + serve route + transaction-detail UI + lightbox).
- `PACK_FORMAT_PLAN.md` — moved here 2026-06-06; shipped via PR #107 (the cross-platform `.finch` zip pack format end-to-end — build, parse, atomic swap of DB + attachments, magic-byte-routed import, Settings UI).
- `LEDGER_CRUD_PLAN.md` — moved here 2026-06-06; shipped via PR #109 — web-app ledger CRUD (create / rename / restyle / set-default / delete), DB-backed cosmetics + live counts, persisted active ledger, ordered cascade delete with on-disk attachment sweep. Closes the last cross-app implication from `IOS_MACOS_PLAN.md §8`.
- `CATEGORIES_LEVEL3_PLAN.md` — moved here 2026-06-06; shipped via PR #112 — relax the 2-level category taxonomy to a 3-level hard cap (e.g. `Food › Restaurants › Japanese`). **No schema change** — the cap is mutation-layer only. Backend gains a depth check + recursive `rollupCategorySpend` + recursive budget category-id matching. UI: every category `<Select>` renders labels as `Parent › Child › Leaf`; `/categories` admin page renders a 3-level forest with inline "+ subcategory" / "+ sub-subcategory" affordances; color inheritance walks up the chain to the nearest non-null ancestor.
- `I18N_PLAN.md` — **moved here 2026-06-07**; shipped via PRs #113 (foundation: `next-intl` + structured server-error shape `{ code, params }` + format helpers) + #115 (mass extraction of every surface + `zh-CN` coverage). Translations live in app chrome only; **never in the database or `.finch` packs** (the data layer stays locale-neutral, so packs round-trip across locales). Per-device persisted via `localStorage`. The Apple-native i18n path stays orthogonal (`Localizable.strings`).
- `DOUBLE_ENTRY_PLAN.md` — **moved here 2026-06-07**; shipped via PRs #114 (PR A, additive core: chokepoint `lib/db/entries.ts` + entries/postings DDL constants in `lib/db/entries-schema.ts` + contract test suite, no production reads/writes yet) + #116 (PR B, the cutover: migration via `lib/db/cutover.ts`, projection rewrite in `lib/db/state.ts`, mutation rewires in `lib/db/mutations.ts`, read-path rewires across `lib/db/queries/*`, seed rewrite, FK re-points, `transactionSplits.ts` deletion) + PR C (audit-on-import wiring + the §10.7 net-worth-explained Insights panel + the §12 docs follow-up — design-doc v3, MASTER_PLAN sweep). `SCHEMA_VERSION` bumped to `2026-06-14T00:00:00Z`. **Double-entry core, single-entry skin**: `transactions` / `transfer_groups` / `transaction_splits` replaced by `entries` + `postings` with a balanced-leg invariant + schema triggers + `auditLedger`; the client `Tx` projection is preserved so pages and selectors are untouched.

---

## 1. Where we are

**Stack (implemented):** Next.js 16 (App Router, Turbopack) · React 19 · TypeScript ·
Tailwind v4 · shadcn/ui (Radix) · lucide-react · next-themes (light/dark) · Bun.

**Data layer:** a **server-side, file-backed SQLite database** (the full
`database_design_en.md` schema via **`better-sqlite3` with WAL** — see
`plans/done/FILE_BACKED_DB_PLAN.md` for the persistence-runtime move from
`sqlite-wasm`) is the source of truth, persisted to a file at
`FINCH_DB_DIR`/`FINCH_DB_FILE`. The browser talks to it via API routes
(`GET /api/state`, `POST /api/mutate`, `GET /api/db-info`); the Zustand store
is a mirror that hydrates on load and syncs every mutation. Static reference
seed still lives in `frontend/data/*.json`.

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
| Main | Settings | ✅ | Two tabs: **Account** (Theme · Bottom-bar editor · Sample data · Database card · Export `.db` / `.csv` · Import · Snapshot · Restore) + **Ledger** (Active ledger · Display currency · Categories count link · Exchange rates). Sections grouped with the uppercase-header pattern. |
| Main | Goals | ✅ | Now **folded into Budgets** as the *income* budget type (named-budgets redesign); standalone Goals page removed |
| Main | Subscriptions | ➖ | Page + table removed; recurring bills live in `scheduled_templates` (visible on Scheduled). |
| Main | Activity (cross-account feed, filters, search) | ✅ | Grouped by day, All/Out/In, **SQL search/filter** via the live DB |
| Main | Reports | ✅ | Spending donut + breakdown, **DB-derived** category spend, ledger-scoped |
| Ledger | Pending review (confirm/edit/cancel, bulk) | ✅ | Confirm / Cancel / Confirm-all sync to the server (`app_state` queue) |
| Ledger | Transfers (two-sided) | ✅ | **DB-derived list + "New transfer"** → paired rows sharing `transfer_group_id`; real transactions. Also creatable from the **Add** sheet (incl. cross-currency — a Received amount locks the rate). |
| Ledger | Merchants / counterparties (verified) | ✅ | List reads the projected table; **create / rename / delete**, verify/unverify, name search. `aliases` + `category` removed: aliases were search-aid only with no FK, and category is wrong per-merchant (same payee → many categories). |
| Ledger | Recurring templates (list + splits) | ✅ | **Create** template + edit fields/splits + delete; **"Post now"** → confirmed tx(s) on the server |
| Ledger | Categories admin | ✅ | **Create / edit / delete** (name/type/icon/color); delete leaves txns uncategorised. Colour is hex; a curated swatch picker maps OKLCH hues to hex at the standard palette. |
| Ledger | Tags admin | ✅ | **Create / edit / delete** (name + color); assignments cascade on delete. Colour storage matches categories (hex). |
| Ledger | Ledger switcher (bottom sheet) | ✅ | Per-ledger base currency; sidebar + Settings; scopes Activity/derived figures |
| Ledger | Ledger admin table (desktop) | ⊘ | Dropped from the roadmap. The Ledger switcher (sidebar + bottom sheet) now does create + edit + set-default + delete (LEDGER_CRUD_PLAN, shipped 2026-06-06) — no separate admin table needed. |
| Ledger | Category tree (≤ 3-level) | ✅ | `categories.parent_id` (SET NULL on delete = promote children, recursively safe). `/categories` renders a 3-level forest with inline "+ subcategory" / "+ sub-subcategory" affordances. Every level is bookable; `rollupCategorySpend` walks the tree (grandchild → child → parent); a budget on a parent matches descendants recursively. Mutations enforce a depth-3 cap (`CATEGORIES_LEVEL3_PLAN`). |
| Settings | Exchange-rate book | ✅ | Under **Settings › Ledger** (add/delete, sparkline, source badges); DB-backed. The "device/sync" piece was retired with the `sync_log` table — DB file is the source of truth, no multi-device sync to expose. |
| Ledger | FX transaction detail | ⊘ | Dedicated `/fx` page retired — FX info embedded directly into transaction detail: a dual-amount card (Original · {currency} / Base · {ledger base} LOCKED) + a rate-locked badge appear in `<TransactionDetail>` whenever `currency ≠ ledger base`. Silent in lists; full audit on tap. |
| System | Multi-palette / font / density tweaks panel | ⊘ | Deliberately replaced by light/dark (prior decision) |

**Charts not yet built (design defines them):** multi-series `AreaChart`.
(`CalendarHeatmap` shipped in PR #38; `Sankey` shipped with the Insights flow card.)

**Cross-cutting status:**
- ✅ **Mutations are real** — add/edit/delete/confirm/verify/alias/transfer/recurring-post
  run SQL on the server DB (triggers maintain balances/snapshots/summaries) and the
  store mirrors the result. (The DB's `status` model is `confirmed`/`pending`/`cancelled`;
  delete = soft-cancel.)
- ✅ **Server-side persistence** — a SQLite file at `FINCH_DB_DIR`/`FINCH_DB_FILE`,
  written after every change and reloaded across restarts. No CSV import / auth / multi-device sync.
- **Bespoke desktop dashboards landed in Phase D.** Accounts, Activity,
  Budgets, Insights, and Scheduled all have distinct desktop layouts
  (gradient card grid, full transaction table, stat tiles, fluid charts,
  large calendar). The shell is single-render; the layout choice is CSS at
  the `md` breakpoint.
- **`MOCK` reference data** is now seed-only — pre-hydration fallback for
  static lookups (`acctById`, `catById`); every figure that matters comes
  from the live server DB once the store hydrates. The flat-schema
  fallbacks (`derive.ts`, `repo.ts`, `storage.ts`, the `DbProvider`) were
  removed across PRs #30 / #33.

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
      Added a desktop-only **System** ledger tab. _(Later retired — rates moved
      into Settings › Ledger; `sync_log` + the Devices tab were dropped entirely
      since the DB file is the source of truth and no multi-device sync exists.)_

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
`plans/done/SQLITE_INTEGRATION_PLAN.md` for detail.
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
- [x] **FX / System screens** — `/fx` is fully DB-backed (PR #29 onwards);
      `/system` got exchange-rate add/delete CRUD in PR #32.
- [x] **Real FX conversion** — `useMoney` now converts via the projected
      `exchange_rates` table (PR #32). Write-side rate locking was already real.
- [x] **Balance-curve / net-worth charts** — sparklines on the account-detail
      and accounts-list pages, driven by `balanceSeries` / `netWorthSeries`.
- [x] **Cleanup** — `derive.ts`, the flat-schema `repo.ts`/`storage.ts`, and the
      redundant browser `DbProvider` are gone; dead `MOCK` re-exports + orphan
      JSON files removed across PRs #30 and #33 (the Insights derived-series
      rewrite). See `MASTER_PLAN.md §5` for the up-to-date open list.

### Phase H — Full CRUD parity ✅ _(done; see `plans/done/CRUD_PARITY_PLAN.md`)_
Brought every user-facing entity to full Create / Update / Delete (or archive) and
retired the last `app_state` override shims. Delivered in phases on one branch:
- [x] **Schema versioning** — `SCHEMA_VERSION` + `migrate()` in `lib/db/schema.ts`
      (stamps fresh DBs, runs ordered `ALTER`s on existing files; reached **v4**).
- [x] **Balance recompute** — `recomputeAccount` keeps `current_balance` /
      `balance_after` correct after any edit/cancel/delete (the trigger is INSERT-only).
- [x] **Accounts** — display columns + create / table-backed update / archive /
      unarchive (Filter ▾ on the list page surfaces archived accounts with an
      inline Unarchive affordance); **no delete UI** — `deleteAccount` lives in
      the DB layer for future cleanup scripts but is unreachable from the
      store/UI. **`accountOverrides` retired**. See
      `docs/superpowers/specs/2026-06-08-account-archive-unarchive-design.md`.
- [x] **Delete/edit everywhere** — shared `<RowActions>` (⋯ menu + confirm) +
      edit dialogs for categories, goals (as income budgets), tags, recurring,
      transfers, merchants.
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
remaining `app_state` shims. The original §5 list is now mostly complete:

1. ✅ **Last screens on the DB** — `/fx` is DB-backed (reads `store.transactions`
   + `store.exchangeRates`); `/system` got rate add/delete CRUD in PR #32.
2. ✅ **Cleanup pass** — `derive.ts`, the flat-schema `repo.ts`/`storage.ts`, and
   the redundant browser `DbProvider` were already gone. The cleanup pass removed
   15 dead `MOCK` re-exports and four orphan JSON files (`dashboard-summary.json`,
   `daily-spending.json`, `bills.json`, plus `monthly-spending.json` / `cashflow.json`
   / `insights.json` / `apr-vs-may.json` retired with the Insights derived-series
   rewrite).
3. ✅ — **real FX conversion** shipped (PR #32: `useMoney` converts via the live
   `exchange_rates` table). **Insights derived series** shipped (PR #33:
   `monthlySpending` / `monthlyCashflow` / `topCategoryDeltas` selectors).
   **`CalendarHeatmap` primitive** + daily-spending use site on Insights shipped
   (PR #38). **Richer net-worth trend** — fourth metric tab on Insights driven by
   the new `netWorthByMonth` selector (PR #39). The accounts-list / detail
   sparklines stay put as glanceable context. Receipt attachment was de-scoped
   at the time — the old "Receipt — coming soon" quick-action stub on the
   transaction detail was replaced with a **Delete** action. _(Re-opened as
   a candidate in `plans/FEATURE_IDEAS.md` §4.1; listed under "Current open
   items" above.)_
4. ✅ **Income + Adjustment transaction types**. `/add` is now "Add transaction"
   with an income/expense toggle that signs the amount on save. Adjustments are
   modelled as a `transactions.is_adjustment` flag (schema v5, `MIGRATIONS[5]`)
   and created via a new **"Reconcile balance"** dialog on the account-detail
   screen — `adjustAccountBalance` posts a marked delta that moves the balance to
   the target. Adjustments are excluded from category spend, cash flow, budget
   progress and the insights spend heatmap (same places transfers are excluded).

### Future features (curated)

The original plan list is closed. The detailed brainstorm of where to take the
app next lives in `plans/FEATURE_IDEAS.md` — categorized, impact-tagged, S/M/L
effort. The picks already landed are crossed off in the "Done since" coda
below; what's still open is summarized here.

**Current open items (high payoff):**
1. **iOS &amp; macOS native apps** — `plans/ios-macos/IOS_MACOS_PLAN.md` (refreshed 2026-06-07).
   Direction brief, not a build plan: inherited domain model under the now-
   shipped double-entry storage, parity matrix, architecture decisions
   (GRDB on the verbatim schema, Swift port of the chokepoint + selectors
   w/ the web `bun test` suite as the parity oracle, `auditLedger` as the
   audit-parity contract, iCloud Drive file-pack sync), Apple-platform
   upside (App Intents, Spotlight, biometric lock, Share-Extension
   receipts). **All three §8 cross-app implications shipped on the web**
   (attachments PR #106, pack format PR #107, ledger CRUD PR #109);
   `SCHEMA_VERSION = '2026-06-14T00:00:00Z'` after the DE cutover
   (PRs #114 + #116). Native can now adopt the schema verbatim and build
   against a complete reference. **L (the build); the brief itself is done.**

   **STATUS (2026-06-20): the native iOS/macOS app is built** — Phases 1–8 plus
   the full UI remediation (Tiers 1–4, macOS/iPad 3-column), localization
   (en/zh-Hans), the engine parity-oracle expansion, and a cleanup pass all
   shipped (see `plans/ios-macos/`). **Everything that can be built and verified
   without Apple hardware/account is done.** The only remaining work is
   **hardware/account-gated** and cannot be progressed in CI:
   - **CloudKit runtime (Phase 8).** The live mutation-log sync loop + the
     down-sync seed (`FinchCore.DownSync`) are built + unit-tested but **never
     run** — they're inert without a provisioned container. (Inert is now genuinely
     crash-safe: the service gates `CKContainer` construction on the iCloud
     entitlement, since `CKContainer` *traps* rather than throwing when it's absent —
     this previously crashed the unsigned simulator app at launch.) Remaining: join the
     Apple Developer Program, create `iCloud.com.juchengquan.finch` (runbook:
     `plans/ios-macos/IOS_MACOS_PHASE_8_CLOUDKIT_SETUP.md`), wire the CloudKit
     fetch → `DownSync.ingest` → reproject, then verify two-device convergence +
     conflicts on real devices. Until then the Phase 5 iCloud-Drive **file sync
     stays the live path** (CloudKit switch is off by default).
   - **Lock-screen widget redaction (remediation #16).** App Intents + entity
     queries already refuse while locked; redacting the home/lock-screen widget
     when the app is locked needs a **physical device** to verify.
2. **What-if sliders on Insights** (FEATURE_IDEAS §3.3) — "If I cut dining
   30%, I'd save $1,440/yr." Pure math on top of existing data; no schema
   change. **M.**
3. **Annual tax report** (FEATURE_IDEAS §8.1) — `is_tax_relevant` bool on
   categories + a filtered report page + CSV export. **M, schema change.**

⊕ **Recently shipped (since this section was last refreshed):**
- ✅ **Double-entry PR C — audit wiring + net-worth-explained + F4 fix** (this PR; closes `plans/done/DOUBLE_ENTRY_PLAN.md §12 PR-C`) — `auditLedger` is now wired into `GET /api/db-info` (problem count + first 50 problems surfaced in Settings ▸ Account ▸ Database; clean-DB shows "no problems found") and into `POST /api/import` for both bare-`.sqlite3` and `.finch` paths (audit runs on the swap candidate before any destructive operation; live DB stays untouched on failure). `mutations.test.ts` gained an `afterEach` hook that asserts `auditLedger` clean at the end of every scenario — cheap regression net across ~30 tests. F4 fix: `netWorthByMonth` and `netWorthSeries` now honour `include_in_net_worth`, aligning the Insights trend chart with the Accounts header. New `netWorthExplained` selector + `NetWorthExplainedCard` decompose monthly net-worth movement into income / expense / adjustment / FX via the postings-sum-to-zero residual, surfacing previously-invisible adjustments and FX drift on the Insights page. Settings page renders audit status next to the database path (PR #117 in MASTER_PLAN's PR-# space).
- ✅ **Double-entry storage core** (PRs #114 + #116, 2026-06-07; design
  record `plans/done/DOUBLE_ENTRY_PLAN.md`) — `transactions` /
  `transfer_groups` / `transaction_splits` replaced by `entries` +
  `postings` with a balanced-leg invariant + schema triggers (seal /
  posting-currency / cached-balance) + a typed `auditLedger` semantic
  sweep. The client `Tx` projection is preserved as a single-entry skin
  (`lib/db/state.ts`), so pages, selectors, and the UI vocabulary
  (expense / income / transfer — never "debit/credit") are untouched.
  PR A added the chokepoint module (`lib/db/entries.ts`) + entries DDL
  constants (`lib/db/entries-schema.ts`) + the contract test suite, with
  no production writes; PR B did the cutover — migration via
  `lib/db/cutover.ts` (per-entry sealed-write, id-preserving), mutation
  delegation, read-path rewires across `lib/db/queries/*`, seed rewrite,
  FK re-points (`entry_tags`, `entry_attachments`, `entries_fts`).
  `SCHEMA_VERSION` bumped to `2026-06-14T00:00:00Z`; legacy tables
  dropped. PR C (audit wiring + net-worth-explained panel + docs
  follow-up) shipped as the entry above.
- ✅ **Multi-language / i18n** (PR #113 foundation + PR #115 mass
  extraction; design record `plans/done/I18N_PLAN.md`) — `next-intl` +
  per-device `localStorage['finch.locale']` + auto-detect from
  `navigator.languages`. English base catalog (100% coverage),
  Simplified Chinese (`zh-CN`) shipping in lockstep. Server mutations
  throw structured `I18nError(code, params, fallbackEnglish)`; the route
  serialises `{ error: { code, params, message } }` and the client
  decodes via `fromWireError` so toasts can localise without breaking
  unmigrated callers. `useFormat()` + locale-aware `periodLabel` +
  structured `Insight` (`{ key, params }`) round out the formatting
  layer; rule `describeCondition` / `describeActions` take an optional
  `DescribeDict` so the /rules page and rule-builder summary read in the
  active language. App chrome is fully translated; `.finch` packs and
  user-typed data (category names, merchant names, transaction notes)
  are intentionally untouched.
- ✅ **Receipt photos** (PR #106, 2026-06-06; FEATURE_IDEAS §4.1; design
  record `plans/done/RECEIPT_PHOTOS_PLAN.md`) — schema + upload + serve
  + transaction-detail UI + lightbox.
- ✅ **`.finch` pack format** (PR #107, 2026-06-06; design record
  `plans/done/PACK_FORMAT_PLAN.md`) — extended `/api/export?withAttachments=1`
  to build a `.finch` zip carrying the DB + every receipt + an integrity
  manifest; `/api/import` detects pack vs raw `.db` via magic bytes and
  atomically swaps both. **Closes the cross-app file-portability loop the
  iOS plan needed.** Code audit (this PR) confirms every section of
  RECEIPT_PHOTOS_PLAN.md and PACK_FORMAT_PLAN.md matches the live frontend.

⊘ **Superseded — do not implement: PWA** (`plans/PWA_PLAN.md`). The plan was
written when the database lived in the browser (OPFS-backed `sqlite-wasm`);
the data layer is now server-side and file-backed, so the §-by-§ caching
strategy no longer applies. The native iOS/macOS direction
(`plans/ios-macos/IOS_MACOS_PLAN.md §1.1`) explicitly supersedes the "PWA is good
enough" judgement — reach the home screen via real native apps, not a wrapped
web view.

**Layout / a11y polish** ✅ shipped (PR #84) — dark `--muted-foreground`
contrast bump to ~6:1 (WCAG AA), shared `<EmptyState />` across Accounts /
Activity / Budgets / Categories / Transfers, and desktop breadcrumb truncation
in `PageShell`.

**Saved searches** ✅ shipped (PR #89; FEATURE_IDEAS §7.2) — pin the current
Activity filter set (search · direction · tag · date/amount range) as a named,
per-ledger chip and re-apply it in one tap. **Client-only by decision** (a
per-browser convenience, not ledger data): persisted to `localStorage` via a
`useSyncExternalStore` hook, never written to the DB, the Zustand store, or
exports — _not_ the `app_state` route the original §7.2 note assumed.
- ⊘ **No-go: a ⌘K command-palette entry for saved searches.** The palette only
  does `router.push(href)` jumps + self-contained action handlers; applying a
  saved filter means "go to Activity *and* push filter state into its local
  `useState`", which it can't do without either URL-param routing (a new
  pattern nowhere else in the app) or lifting Activity's filter state to a
  shared store. M-effort for an S-feature whose one-tap shortcut (the chip) is
  already on the page the palette would navigate to. Revisit only if URL-param
  routing lands for another reason, or saved searches need to be invoked from
  outside Activity.

**Recurring transfers** ✅ shipped — `generateDueScheduled` now materializes
transfer templates too, calling `createTransfer` once per due date with the
template's id stamped on both legs via `source_template_id`. Transfers post
as **confirmed** (vs pending for income/expense) because they're entirely
within the user's books and a half-confirmed transfer would be visually
confusing on both ledgers. The de-dupe + installment-total caps work
unchanged — the Set collapses the two legs that share a date. Templates
without a `from_account_id` are left to manual entry. See
`plans/database_design_en.md` decision #25.

**Installment tracking** ✅ shipped — new `scheduled_templates.installment_total` column (e.g. 24 for a 24-month phone contract) caps both auto-generation (`generateDueScheduled` mirrors the `max_executions` slice) and manual posting (`postScheduled` rejects once the plan is full). The matching "paid so far" figure is **derived**, not stored — `installmentPaid = COUNT(transactions WHERE source_template_id = id AND status = 'confirmed')` — so pending rows don't inflate progress and cancelling a pending occurrence leaves the counter untouched. The scheduled list shows a "paid/total" badge that turns green when the plan completes. Cash math only — for the interest/principal split of a real loan payment, the user adds transaction splits to the posted row. See `plans/database_design_en.md` §6.12 / decision #24.

**Investment tracking** ✅ shipped — new `holdings` table (one row per position inside an investment-type account) carries `symbol + shares + cost_basis + currency + (last_price, last_price_date)`. Cash stays in `accounts.current_balance` (driven by ordinary buy/sell/dividend transactions); positions are managed separately, valued live as `shares × last_price`, with unrealized gain/loss = value − cost_basis. The investment-account detail page surfaces a "Holdings" panel with add / edit / price-update / delete dialogs and a "Holdings value + ≈ display + unrealized" summary row; the balance card prints "+ X in holdings · total Y" alongside the cash figure. No external feeds — prices are typed manually, and we keep no price-history table (`last_price` overwrites). See `plans/database_design_en.md` §6.18 / decision #23.

**Unrealized FX gain/loss** ✅ shipped — `accounts.opening_balance_base` locks the ledger-base cost of each account's opening balance at creation. With it the account's cost basis is `opening_balance_base + Σ amount_base of confirmed transactions`, and the live valuation `current_balance × today's rate` reveals the drift as unrealized FX. The account-detail balance card shows an "FX gain/loss" line for accounts denominated in a non-base currency; same-currency-as-base accounts read 0 and hide it. `recomputeAmountBases` re-stamps the column when the ledger's base itself changes. See `plans/database_design_en.md` §6.4 / decision #22.

**Counterparty FK link** ✅ shipped — `transactions.counterparty_id` is set at insert/update via `resolveCounterpartyIdByName` (case-insensitive exact match within the ledger); `projectState` overrides `merchant` with the canonical catalog name when the FK is set, so renames on the Merchants page follow transaction history. `ON DELETE SET NULL` preserves the original description text. See `plans/database_design_en.md` §6.9 / decision #18 for the schema and rationale.

**Base-currency-change recompute tool** ✅ shipped — Settings › Ledger has a "Base currency" select; flipping it confirms then atomically rewrites every locked `amount_base` (transactions + splits) under the new base using each row's own date, and re-runs `recomputeAccount` for every account in the ledger. `transfer_groups.amount_base` isn't touched (it's the from-leg native magnitude, not a ledger-base figure). See `plans/database_design_en.md` §6.1 / decision #19 + `lib/db/queries/ledgers.ts::recomputeAmountBases`.

Everything else in the curated list below — Transaction splits, Spending forecast, ⌘K palette, Account-group CRUD, Budget rollover (UI + auto period), Activity filters, Sankey, Refund support, Multi-currency phases 1–4 — is ✅ shipped.

**Picked next:**
1. **Transaction splits** ✅ *(done — see PR)* — ad-hoc category splits on any
   confirmed transaction. New `transaction_splits` table (schema v6) holds the
   per-row category + amount + locked `amount_base`; `categorySpend`,
   `monthlyByCategory`, and `budgetProgress` LEFT JOIN with COALESCE so split
   rows override the parent category. Transaction detail surfaces a multi-row
   editor (Split button) with sum validation; the client `categorySpend`
   selector mirrors the same override.

**Other strong candidates (deferred, queued):**
2. **Spending forecast / cash-flow projection** ✅ *(done — see PR)* —
   `monthForecast` selector projects month-end spend from MTD + a daily
   run-rate × days-remaining + upcoming recurring templates + scheduled
   items. Surfaces as a card on Insights with a stacked bar of the four
   components and a vs-prev-month chip. Past months collapse to actuals.
3. **Cmd-K command palette / global search** ✅ *(done — see PR)* — global
   ⌘K / Ctrl+K opens a single jump-to-anything palette: pages, transactions
   (by merchant or note), merchants, categories, accounts, tags — all
   scoped to the active ledger. Hand-rolled (no `cmdk` dep) on top of the
   existing Dialog + a SearchButton that replaces the placeholder header
   affordance app-wide.

**Smaller wins:**
4. **Account-group CRUD** ✅ *(done — see PR)* — listAccountGroups / create /
   update / delete wired through projection + store + mutations; /accounts page
   surfaces a "New group" affordance + per-group rename/delete; orphan
   accounts land in an "Ungrouped" bucket when their group is deleted.
5. **Budget rollover UI** ✅ *(done — see PR)* — rollover toggle + optional cap
   on the budget detail page, carry-forward shown in the header and folded
   into the ring + remaining figure (matches budgetProgress). Automatic
   period rollover **also shipped** against the named-budgets model
   (`rollBudgetsIfDue` in `lib/budgets/rollover.ts`, driven from
   `lib/db/server.ts`; tracked via the `last_rolled_period` / `pending_amount`
   columns); the PR #48 engine was superseded by the redesign and replayed.
   See `plans/done/BUDGET_CYCLES_PLAN.md`.
6. **Date / amount filters on Activity** ✅ *(done — see PR)* — `minAmount` /
   `maxAmount` on ListOptions + selectTransactions (date range already wired
   on the server, just unused). UI: collapsible "Filters" panel below the
   direction control with date + amount-range inputs and an active-count
   indicator.

**Bigger / scope-expanding:**
7. **Sankey diagram** ✅ *(done — see PR)* — new `Sankey` SVG primitive +
   `incomeCategoryFlow` selector; "Where {Month} income went" card on
   Insights flows income → top-N expense categories + a "Saved" stub.
8. **Investment tracking** ✅ *(done)* — `holdings` table per investment-type
   account carries shares + cost basis + last logged price (no price history;
   updates overwrite). Buy / sell / dividend transactions still move the account's
   cash balance through the normal path; positions are managed separately and
   summed for a live total = cash + Σ shares × last_price. Investment-account
   detail page has a Holdings panel with add / edit / price-update / delete
   dialogs; the balance card surfaces "+ X in holdings · total Y" alongside
   cash. See `plans/database_design_en.md` §6.18 / decision #23.
9. **Refund support** ✅ *(done)* — `kind='refund'` on `transactions` linked back
   to the original expense via `refunded_transaction_id` (SET NULL on delete).
   Schema, decision, and cascade policy live in
   `plans/database_design_en.md` §6.9 / §8 / §13. Shipped: schema + `idx_txn_refunded`,
   query layer (`addTransaction` accepts `kind`/`refundedTransactionId`, `getRefundsFor`),
   `categorySpend`/`monthlyByCategory` + `lib/select.ts` + budget rollover widened to
   `kind IN ('expense','refund')` so the positive refund nets against its category,
   cash-flow income gated to `kind='income'`, and a "Refund" action on transaction
   detail that pre-fills amount + category from the original.
10. **Multi-currency accounts** ✅ *(fully done — see
    `plans/done/MULTI_CURRENCY_ACCOUNTS_PLAN.md`)* — per-account currency is a
    stored/editable property. **Phase 1 (storage):** writes true ledger-base
    `amount_base` and accumulates the account-currency delta into balances.
    **Phase 2 (read/display):** `useMoney.toBase`/`fmtFrom`; `balanceSeries`
    walks the native amount; net-worth selectors sum mixed currencies in the
    ledger base via a `ToBase`; account detail shows native + "≈ display".
    **Phase 3 (entry UX):** add-expense currency follows the selected account;
    `updateTransaction` reconverts `amount_base` on an amount edit. **Phase 4
    (polish):** cross-currency transfer UX — `selectTransfers`/`listTransfers`
    return both legs' native amounts + currencies; the transfers list shows
    "sent → received @ rate". The FX-transaction detail also embeds the
    locked-rate block directly into `<TransactionDetail>` (PR #60) so foreign
    rows surface rate + dual-amount audit info without a separate `/fx` page.
    Unrealized FX gain/loss shipped in PR #66 (`accounts.opening_balance_base`
    locks the cost basis at account creation; the account-detail balance card
    surfaces the drift). Base-currency-change recompute tool shipped in PR #64
    (Settings › Ledger lets the user flip a ledger's base; `recomputeAmountBases`
    atomically rewrites every locked `amount_base` and re-stamps
    `opening_balance_base`).

### Done since (Phase H follow-ups)
- Recurring **split add/remove** UI on the template detail screen.
- **Download backup** now streams the live server DB via `GET /api/export` (table
  edits included).
- **Readable export** — `GET /api/export/transactions` returns a transactions CSV
  (account/category names + tags resolved via joins); Settings has a "Download
  .csv" button. Multi-entity / XLSX is a possible later extension (CSV builder
  lives in `lib/csv.ts`).
- **Real FX** — `useMoney` converts via the live `exchange_rates` table; System
  screen got rate add/delete CRUD (PR #32).
- **Insights derived series** — `monthlySpending` / `monthlyCashflow` /
  `topCategoryDeltas` selectors replace the last baked totals; the MoM header
  reads `{prev} vs {cur}` from the live data (PR #33).
- **12-month seed history** — `data/transactions.json` extended back to Jun 2025
  (~10 plausible txns/month, 92 new rows) so the 3M / 6M / 1Y ranges have real
  data; balances unchanged via the opening-balance recompute (PR #36).
- **`/fx` in the ledger sidebar** (PR #38).
- **`CalendarHeatmap` primitive + daily-spending heatmap on Insights** (PR #38).
- **Net worth metric tab on Insights** — `netWorthByMonth` selector + a fourth
  tab next to Spending / Income / Cashflow (PR #39).

### Done since (post-PR-#66)

Feature work, polish, and infra after the unrealized-FX / holdings PR. Cross-
references to `plans/FEATURE_IDEAS.md` are in parentheses.

- **Eight correctness fixes from the code-quality audit** (PR #69) — silent
  category drop on `postScheduled`, mixed-currency holdings sums, FTS5
  punctuation tokenization, installment badge missing from default Upcoming
  list, `unrealizedFx` ledger filter, archived account holdings, `SAVEPOINT`
  vs `BEGIN` in nested mutations, unknown patch keys.
- **Transaction-insert consolidation refactor** (PR #70) — three transaction
  write paths collapsed into a single `insertTxRow` helper in
  `queries/transactions.ts`; `mutations.ts` shrunk by 93 LOC.
- **🟡/🔵 polish pass** (PR #71) — six small cleanups + three coverage tests.
- **Four small items** (PR #72) — SQL trigger for investment-only holdings
  account, sort holdings by value, 404 state, recurring transfers (`generateDueScheduled` materializes transfer templates too).
- **Local-heuristic category suggestion on Add** (PR #73, ≈ FEATURE_IDEAS §1.3)
  — when the typed merchant resolves to a counterparty or matches past
  transactions, suggest the most-common category from history. No model, no
  API; quiet "Suggested: X · 4×" chip the user can tap to apply.
- **PWA scoping plan** (PR #68) — `plans/PWA_PLAN.md` checked in;
  implementation deferred (see "Current open items" above).
- **FEATURE_IDEAS catalog** (PR #74) — ≈ 50 features grouped by 11 themes
  with effort/impact tags; the source of truth for "what could we do next".
- **Recent-expense chips on Add** (PR #75, FEATURE_IDEAS §1.1) — horizontal
  row of "Starbucks · $4.50" chips above the amount input when type=expense;
  tap pre-fills merchant + amount + account + category. Dedup by
  (merchant + amount + account + category). New `recentExpenses` selector.
- **30/60/90-day cashflow forecast on account detail** (PR #76, FEATURE_IDEAS §2.1)
  — `accountForecast` selector projects daily balance from current_balance +
  every scheduled template that touches this account, capped by
  `installment_total - paid` and `max_executions`. Renders as a forecast card
  on the account detail page with a sparkline of projected balance, an
  upcoming-events list, and a "low point" stat that turns red if it dips
  negative or warning-yellow if it dips below today.
- **Per-merchant anomaly detector** (PR #78, FEATURE_IDEAS §3.1) — new
  `merchantStats` + `anomalyScore` selectors in `lib/select.ts`; z-score over
  each merchant's confirmed-expense history (counterparty FK first, lowercased
  description fallback). `minCount = 3`, `threshold = 2.5`. A small
  warning-tinted "Unusual" badge appears inline next to the merchant name on
  Activity (mobile + desktop) and account-detail transaction lists.
- **Weekly digest card on Insights** (PR #79, FEATURE_IDEAS §3.2) — Sunday-
  night recap of the most-recently-completed Mon-Sun: spent, income, net,
  vs-prev-week %, vs-12-week-avg, top 5 categories, biggest hit. New
  `weeklyDigest` selector + `WeeklyDigestCard` component at the top of the
  Insights page.
- **Bulk recategorize from Activity** (PR #79, FEATURE_IDEAS §7.1) — new
  "Select" mode on `/activity` turns rows into multi-select; floating action
  bar with category picker applies one category to every selected row in a
  single server roundtrip via a new `bulkRecategorize` mutation.
- **Schema audit follow-ups** (PR #80) — `scheduled_templates.category_id`
  FK swapped from `ON DELETE RESTRICT` to `SET NULL` (categories with linked
  schedules can now be deleted, matching transactions); dead `budgets.tag_ids`
  column dropped (was stored but never read); new composite index
  `idx_rate_currency_date` for `convertToBase`'s hot path; new
  `idx_txn_account_status` for `recomputeAccount`. `SCHEMA_VERSION` bumped
  with an idempotent migration. `isAlreadyAppliedError` regex extended to
  swallow "no such column / table / index" for `DROP COLUMN` and
  table-recreation re-runs.
- **Layout / a11y fixes** (PR #81) — budget detail breadcrumb resolves the
  budget's actual name from the live store (was reading via `catById`, so
  the breadcrumb always read "Uncategorized"); mobile header touch targets
  bumped to 44×44 (`SearchButton` baked in `size-11 md:size-9`, back/profile
  buttons explicit at the call site); new `focus-ring` Tailwind v4 utility
  applied to the 14 custom inputs/buttons that suppressed the browser focus
  outline without a fallback; `interactiveWidget: 'resizes-content'` on
  the Next.js viewport export so the on-screen keyboard shrinks `dvh` (fixes
  the add-expense submit hiding behind the iOS keyboard).
- **Spending pattern surfacer** (PR #82, FEATURE_IDEAS §3.4) — four new
  descriptive rules in the insights engine: `weekendVsWeekday` (weekend per-
  calendar-day spend vs weekday), `topCategoryByWeekday` (when one category
  dominates a weekday's spend), `endOfMonthBump` (days 23-31 vs days 1-22),
  `quietestDay` (counterpart to the existing `weekdaySkew` — the day-of-week
  that's reliably half the daily average). All gated on a minimum-data floor
  so they don't fire on stub ledgers.

### Done since (post-PR-#82)

The persistence-runtime upgrade + the reconcile-engine-rules feature triad +
plan-folder hygiene. Cross-references to `plans/FEATURE_IDEAS.md` are in
parentheses.

- **File-backed SQLite + WAL** (PRs #96, #97, #99, #100) — the persistence
  runtime moved from in-memory `@sqlite.org/sqlite-wasm` (whole-file snapshot
  per mutation) to file-backed **`better-sqlite3`** with WAL
  (`synchronous=NORMAL`). Every COMMIT fsyncs frames into `${file}-wal` and
  auto-checkpoint drains them into the main file; no in-memory snapshot
  dance. Export = `VACUUM INTO`; import = close conn → swap file → reopen.
  Tests use `bun:sqlite` via a cross-runtime driver (`lib/db/driver.ts`)
  behind the same `Exec` shape. Cuts per-mutation write cost from O(N bytes)
  to row-level. Design record: `plans/done/FILE_BACKED_DB_PLAN.md`.
- **Reconcile-to-statement v2** (PR #101) — "add missing transactions
  during reconcile." The original flow forced a gap into an adjustment; v2
  treats the gap as a real transaction the user forgot, making "add the
  missing row" a first-class in-flow action (quick-add + auto-clear,
  confirm-and-clear shortcut for pending rows, gap-framing copy). No schema
  change — composes existing mutations. Design record:
  `plans/done/RECONCILE_PLAN.md §10–11`.
- **Rules-engine UI series** (PR #102) — finishes the conditional rules
  feature with a read-only `/rules` page, the condition + action builder
  sheet, a backfill ("Apply to existing") flow with a preview-N-matches
  step, and an inline "create rule from this transaction" prompt after a
  manual recategorize. Design record: `plans/done/RULES_ENGINE_PLAN.md`.
- **Plan status reconciliation** (PR #103) — reconciled the Reconcile and
  Rules Engine plans against shipped state with sharper status preambles
  pointing at the implementing PRs. (Precursor to the plan-folder cleanup
  in PR #105.)
- **Reviewed / unreviewed status** (PR #104, INSPIRATION_IDEAS §5.1) — new
  `transactions.reviewed_at` triage column, distinct from `status`
  (confirmed/pending) and `cleared_at` (statement reconcile). Closes the
  rules engine's `mark_reviewed` action (previously a no-op — there was no
  column to set). UI: "Needs review · N" filter on Activity with bulk
  mark-all-reviewed; primary dot on unreviewed rows; per-row toggle on the
  transaction detail. Backfill action applies it too.
- **iOS &amp; macOS direction brief + receipt-photos scoping plan** (PR #105) —
  two new planning docs. `plans/ios-macos/IOS_MACOS_PLAN.md` is a direction brief for
  a future native Apple port (inherited domain model, parity matrix,
  architecture decisions, the `.finch` pack format for iCloud Drive
  file-pack sync, 8 resolved decisions including OS baseline + the
  receipt-attachments shared schema). `plans/RECEIPT_PHOTOS_PLAN.md`
  scopes the web-app implementation of attachments on top of that shared
  schema. Same PR also moved `RECONCILE_PLAN.md`, `RULES_ENGINE_PLAN.md`,
  and `FILE_BACKED_DB_PLAN.md` from `plans/` to `plans/done/` (the three
  recent shipped plans) and updated this file's Plans index.
- **Receipt photos — full implementation** (PR #106, FEATURE_IDEAS §4.1) —
  new `transaction_attachments` table (pointer rows only; files NEVER stored
  as DB blobs — they live under `${FINCH_DB_DIR}/attachments/`). New
  `POST /api/attachments` (multipart, sharp-based EXIF-strip + HEIC→JPEG
  transcode + magic-byte mime sniff) and `GET /api/attachments/[id]` (streamed
  serve with traversal guard). UI: `<AttachmentsRow>` on the transaction
  detail (file picker w/ `capture="environment"` for mobile camera,
  thumbnail strip), plus an `<AttachmentViewer>` lightbox (pinch-zoom images,
  embed PDFs, keyboard nav, delete-via-toast). Schema bumped
  `2026-06-10` → `2026-06-11`.
- **`.finch` pack format — full implementation** (PR #107,
  PACK_FORMAT_PLAN.md) — closes the cross-app file-portability loop the iOS
  plan needed. New `lib/db/pack.ts` (pure build/parse/extract with manifest
  schema, per-file sha256 integrity, path-traversal guards in BOTH the
  manifest and the extract step). `GET /api/export?withAttachments=true`
  now emits a `.finch` zip carrying the DB + every receipt + the manifest;
  `POST /api/import` routes via magic bytes (`PK\\x03\\x04` = pack,
  `SQLite format 3\\0` = bare DB) and atomically swaps both the DB and the
  attachments folder with an `.old-<ts>` rotation. Settings UI gains an
  "Include receipts (.finch)" checkbox; import file picker accepts
  `.finch,.zip`. Back-compat: bare-`.db` round-trip still works.
- **Plan-folder hygiene** (PR #108) — `RECEIPT_PHOTOS_PLAN.md` and
  `PACK_FORMAT_PLAN.md` moved from `plans/` to `plans/done/`; both
  preambles updated to "shipped." `IOS_MACOS_PLAN.md` §2.5, §8, §13, §14
  refreshed to reflect that the shared schema + pack format are now live
  on the web (canonical reference for native to match); §8 cross-app
  implications now show "2 of 3 shipped" with ledger CRUD as the only
  remaining item. Code audit confirmed every section of the two shipped
  plans matches the live frontend.
- **Settings standardised on `.finch`; auto-backups configurable** (PR
  #108) — six items, all in service of one user-visible promise: "your
  data lives in `.finch` files." (1) Export row collapses to a single
  **"Download .finch"** button (the prior checkbox+button combo was
  hard to discover next to a more prominent download affordance). (2)
  Import file picker `accept=".finch"` only; the server's magic-byte
  router still accepts legacy `.sqlite3`/`.zip` drops for back-compat
  but the UI is one format. (3) Auto-backups become **`.finch.bak`**
  packs (DB + receipts + manifest) so a restore brings receipts back
  too — not just the DB. `restoreBackup` reads both `.finch.bak` and
  legacy `.sqlite3.bak` (magic-byte routing) so nothing on disk is
  stranded. (4) **New "Backup frequency"** row in Settings (Select:
  *After every change · At most hourly · daily · weekly · Off*) —
  persisted in `app_state['backupConfig']` so the choice travels with
  the database. (5) **New "Backups kept"** row (Select: 5/10/14/30/50/
  100) — same persistence. (6) Plan docs refreshed (PACK_FORMAT_PLAN
  postscript, IOS_MACOS_PLAN §8 + §9 + parity matrix row 33). Env vars
  `FINCH_BACKUP_MIN_INTERVAL_MS`/`FINCH_BACKUP_KEEP` become fallback
  defaults — only used when the user hasn't picked anything. New
  `autoBackup({ force: true })` opt overrides both throttle and "off"
  for import-safety + user-pressed "Backup now."
- **Ledger CRUD on the web** (this PR; `plans/done/LEDGER_CRUD_PLAN.md`)
  — **closes the last cross-app implication from `IOS_MACOS_PLAN.md §8`**.
  Three commits matching the plan's §10 split:
  (1) **Backend round-trip** — schema gains `ledgers.color` + `tagline`
  (additive migration, `SCHEMA_VERSION` → `2026-06-12`); `LedgerRow`
  carries projected cosmetics + live `accounts`/`txns` counts via
  subselects; four new query helpers (`createLedger`,
  `updateLedger`, `setDefaultLedger`, `deleteLedger`); four matching
  mutations + optimistic store actions. `deleteLedger` is the careful
  one: SAVEPOINT-wrapped ordered DELETEs from leaves up (attachments →
  transactions → scheduled → rules → holdings → budgets → ... → ledger),
  attachment `rel_path`s collected before delete and unlinked from disk
  after; default reassignment when removing the default; the deleted
  ledger's key swept from `app_state['displayCurrencyByLedger']`;
  refuses the last ledger. +9 tests covering the cascade, counts,
  default flip, last-ledger guard.
  (2) **Provider + persistence** — `LedgerProvider` reads cosmetics +
  counts from the projection (drops the static-JSON merge), with a
  hashed-hue fallback for null colors; **active ledger persisted
  per-device in `localStorage`** via `useSyncExternalStore` (SSR-safe);
  derived effective active id during render handles the "persisted id
  no longer in projection" cleanup case (no setState-in-effect cascade).
  (3) **UI** — switcher: "New ledger" dialog (name + base currency +
  color + tagline); live `N accounts · M txns` counts under each
  dropdown row. Settings › Ledger gains "Name & appearance" Edit dialog,
  "Make default" row (hidden when already default), and a Danger zone
  with a typed-name confirm delete dialog showing the live blast radius.
  Same PR also fixes a long-standing bug: `postScheduled` hardcoded
  `ledgerId = 'personal'` — now reads the template's own `ledger_id`,
  so templates in non-personal ledgers post into their right ledger.
- **3-level categories** (this PR; `plans/done/CATEGORIES_LEVEL3_PLAN.md`)
  — relax the 2-level taxonomy cap to a 3-level hard cap (e.g.
  `Food › Restaurants › Japanese`). **No schema change** — the cap is
  mutation-layer-only; the `categories.parent_id` doc comment is the
  only schema-file touch.
  (1) **Backend** — `assertCanBeParent` rewritten as a depth check;
  new `assertSubtreeFitsUnder` for the move case (a level-2 node with
  grandchildren can only land under a top-level parent); new
  `isInSubtreeOf` cycle defence; removed the old "can't move a node
  with children" hard block (`assertSubtreeFitsUnder` covers it
  correctly). `rollupCategorySpend` rewritten as a memoised tree walk;
  new `expandDescendants` helper; `budgetProgress` signature gains
  an optional `categories[]` parameter so a budget on a parent
  catches every descendant at match time (the behaviour change for
  existing 2-level budgets is benign — they catch what users usually
  already wanted). New `categoryPath`, `resolveCategoryColor`
  helpers. **+6 tests** (depth-3 OK / depth-4 rejected, subtree move
  guard, cycle, 3-level rollup, expandDescendants, recursive budget
  match).
  (2) **UI Select sweep** — mechanical: every category `<Select>`
  renders labels as `Parent › Child › Leaf`, sorted by path so
  siblings cluster (transaction detail recategorize, split editor,
  Add transaction, Edit transaction, rule builder condition + action
  pickers, budget filter ChipMultiSelect, scheduled template form).
  (3) **/categories admin page** — `buildCategoryTree` replaced
  inline with a 3-level forest; rendering adds sub-subcategory rows
  + inline "+" affordances on top-level and subcategory rows (the
  affordance hides when the chain is already at depth 3); search
  walks all three levels with force-expand on intermediate matches;
  edit-dialog parent picker accepts every category whose depth +
  the editing subtree's depth ≤ 3 (and isn't inside the editing
  subtree), labels via `categoryPath`. The previous "hide the
  parent picker when the node has children" gate is gone — the
  depth math handles it correctly. Color inheritance walks up the
  ancestor chain via `resolveCategoryColor` (was a one-level
  fallback).

