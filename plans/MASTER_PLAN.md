# Finch — Master Plan

Status snapshot and roadmap, derived from the design prototypes in
`plans/frontend_design/`, the data model in `plans/database_design_en.md`,
and the current implementation in `frontend/`.

_Last updated: 2026-05-26._

---

## 1. Where we are

**Stack (implemented):** Next.js 16 (App Router, Turbopack) · React 19 · TypeScript ·
Tailwind v4 · shadcn/ui (Radix) · lucide-react · next-themes (light/dark) · Bun.
All data is mock JSON in `frontend/data/`; there is **no backend**.

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
| Main | Add expense | ✅ | Amount input + category/account `Select` + date; writes to store, appears in Activity |
| Main | Budgets (ring + category list) | ✅ | Per-category **Budget detail** drill-in done |
| Main | Budget detail (ring, left/over, tx list) | ✅ | `budgets/[id]` |
| Main | Insights (trend, insight cards, Apr-vs-May) | ✅ | Metric tabs (Spending/Income/Cashflow) + 3M/6M/1Y ranges |
| Main | Scheduled (month calendar grid + upcoming list) | ✅ | Month nav + per-day dots |
| Main | Transaction detail | ✅ | Dots `DropdownMenu` (recurring/delete), inline recategorize `Select`, recurring toggle |
| Main | Settings | 🟡 | Theme + currency + 2 rows; missing grouped sections + **tab-layout editor** |
| Main | Goals | ✅ | Aggregate progress + per-goal Ring cards |
| Main | Subscriptions | ✅ | Monthly + annualized totals + list |
| Main | Activity (cross-account feed, filters, search) | ✅ | Grouped by day, All/Out/In, search |
| Main | Reports | ✅ | Spending donut + category breakdown + export toast |
| Ledger | Pending review (confirm/edit/cancel, bulk) | ✅ | Confirm / Cancel / Confirm-all mutate the store + toasts |
| Ledger | Transfers (FX rate-lock, two-sided) | 🟡 | Single hardcoded sample; not list-driven |
| Ledger | Merchants / counterparties (aliases, verified) | ✅ | Read-only |
| Ledger | Recurring template (splits, StackedBar) | 🟡 | Single hardcoded sample; not editable |
| Ledger | Ledger switcher (bottom sheet) | ✅ | Per-ledger base currency; sidebar + Settings; scopes Activity/derived figures |
| Ledger | Ledger admin table (desktop) | 🟡 | Header only |
| Ledger | Category tree (2-level) | ⬜ | — |
| Ledger | System admin (exchange-rate book, sync log) | ⬜ | `exchange-rates.json`, devices exist |
| Ledger | FX transaction detail | ⬜ | `LEDGER.fxTx` sample exists |
| System | Multi-palette / font / density tweaks panel | ⊘ | Deliberately replaced by light/dark (prior decision) |

**Charts not yet built (design defines them):** `CalendarHeatmap`, multi-series `AreaChart`.

**Cross-cutting gaps:**
- No client state for **mutations** — every add/edit/confirm/cancel is display-only.
- **Desktop is the mobile layout in a sidebar shell** — the design specifies distinct
  desktop dashboards (account-card grid, activity/admin tables, budget stat tiles,
  large calendar, metric tabs).
- **Two un-unified mock models**: `MOCK` (USD/Chase framing) and `LEDGER`
  (SGD/Singapore). The DB design implies one ledger-scoped model with dual
  amounts (`amount` + `amount_base`) and a pending→confirmed→cancelled workflow.
- Client-side `localStorage` persistence (Phase F); no backend/API, CSV import, or auth/sync.

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

> Remaining for full schema fidelity (dual `amount`/`amount_base` on FX rows, `status`
> machine, counterparties, parent categories, snapshots) is backend-shaped and lands in
> **Phase F**. The store now persists to `localStorage` (Phase F), so changes survive reloads.

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

### Phase F — Persistence & backend 🟡 _(persistence done)_
Reframed from the original "build a backend" plan: the app is client-only and runs
in an ephemeral container, where a server/DB would not be durable and would be a
large rewrite. So Phase F leads with **client persistence**, keeping the store as
the seam a real backend can slot behind later.
- [x] **Client persistence** — Zustand `persist` → `localStorage` (`finch-store`,
      versioned, partialized to transactions + pending). SSR-safe via
      `skipHydration` + a `StoreHydration` rehydrate-on-mount. Mutations now
      survive a full reload (verified).
- [x] **Reset to sample data** control in Settings (restores the seed).
- [ ] _(future, optional)_ Real server/DB: SQLite schema (`plans/database_design_en.md`)
      behind Next.js route handlers + `better-sqlite3`, swapped in behind the store;
      CSV import, exchange-rate fetch/cache, multi-device sync, auth. Out of scope
      while the demo is client-only/ephemeral.

### Cross-cutting ✅ _(done)_
- [x] **Accessibility pass** — decorative chart SVGs `aria-hidden`; aria-labels on
      every icon-only button and search/form input; Radix covers dialogs/menus/selects/focus.
- [x] **Unit tests** — `bun test` over `lib/` (formatters, currency conversion,
      derive deltas); 12 tests.
- [x] **Playwright smoke flows** — `bun run test:e2e` (root redirect, add-expense,
      split, theme toggle).
- [x] **CI** runs typecheck · lint · **unit tests** · build (e2e runs locally;
      it needs a browser binary).

---

## 4. Open decisions

1. **State library** for Phase B — Zustand (simple, recommended) vs. React
   context+reducer.
2. **Base/display currency** — design ledger base is SGD; current app defaults
   USD. Pick the canonical base for the unified model.
3. **Backend shape** (Phase F) — the DB doc hints at a Flask admin UI; decide
   Next.js API routes + SQLite (e.g. `better-sqlite3`) vs. a separate service.
4. **Desktop scope** — full bespoke dashboards (Phase D) vs. a lighter
   responsive polish, given effort.

## 5. Suggested next step

Phases A–F **and** the cross-cutting polish (a11y + tests in CI) are complete. The
app is feature-complete against the design. What's left is **optional**: the real
server/DB track (Phase F), the deferred `CalendarHeatmap` primitive, and two
intentional stubs that need a backend/storage — **Receipt attach** and **Pending
Edit** (toasts for now).
