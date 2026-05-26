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
| Main | Add expense | 🟡 | Static layout only; pickers/receipt/split not wired |
| Main | Budgets (ring + category list) | ✅ | Per-category **Budget detail** drill-in done |
| Main | Budget detail (ring, left/over, tx list) | ✅ | `budgets/[id]` |
| Main | Insights (trend, insight cards, Apr-vs-May) | ✅ | Metric tabs (Spending/Income/Cashflow) + 3M/6M/1Y ranges |
| Main | Scheduled (month calendar grid + upcoming list) | ✅ | Month nav + per-day dots |
| Main | Transaction detail | 🟡 | Action bar + "dots" menu are no-ops; no mini history chart |
| Main | Settings | 🟡 | Theme + currency + 2 rows; missing grouped sections + **tab-layout editor** |
| Main | Goals | ✅ | Aggregate progress + per-goal Ring cards |
| Main | Subscriptions | ✅ | Monthly + annualized totals + list |
| Main | Activity (cross-account feed, filters, search) | ✅ | Grouped by day, All/Out/In, search |
| Main | Reports | ✅ | Spending donut + category breakdown + export toast |
| Ledger | Pending review (confirm/edit/cancel, bulk) | 🟡 | Renders queue; actions are no-ops |
| Ledger | Transfers (FX rate-lock, two-sided) | 🟡 | Single hardcoded sample; not list-driven |
| Ledger | Merchants / counterparties (aliases, verified) | ✅ | Read-only |
| Ledger | Recurring template (splits, StackedBar) | 🟡 | Single hardcoded sample; not editable |
| Ledger | Ledger switcher (bottom sheet) | ⬜ | `ledgers.json` exists |
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
- No persistence, no backend/API, no CSV import, no auth/sync.

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

### Phase B — Make it interactive (client state over mock)
- [ ] Introduce a typed in-memory **store** (Zustand or context+reducer) seeded from JSON.
- [ ] **Add expense**: real `Select` pickers (category/account), date `Popover`+calendar,
      amount keypad, optimistic insert → appears in lists.
- [ ] **Transaction detail**: wire the `DropdownMenu` ("dots") + action bar
      (split / recategorize / mark recurring / delete) with `sonner` toasts.
- [ ] **Pending review**: Confirm / Edit / Cancel + bulk Confirm-all actually mutate status.
- [ ] Edit flows for budgets, recurring templates/splits, merchants (verify/alias).

### Phase C — Unify the data model around the ledger schema
- [ ] Merge `MOCK` + `LEDGER` into one **ledger-scoped** model matching
      `database_design_en.md` (dual `amount`/`amount_base`, `status`, `transfer_group_id`,
      counterparties, categories w/ parent, recurring + splits, snapshots).
- [ ] **Ledger switcher** (bottom sheet) + ledger context; scope all views to active ledger.
- [ ] Derive net-worth / budget / summary figures from transactions instead of static fields.

### Phase D — Bespoke desktop dashboards
- [ ] Desktop Accounts (gradient account-card grid + merged activity table).
- [ ] Desktop Budgets (on-track/over stat tiles + pace), Insights (metric tabs),
      Scheduled (large calendar + view toggle), Activity (summary tiles + table).
- [ ] Desktop drill-ins with breadcrumbs.

### Phase E — Ledger-admin completeness
- [ ] Transfers + Recurring as **list-driven** detail (not single samples).
- [ ] **Category tree** (2-level), **FX transaction detail**, **System admin**
      (exchange-rate book + `sync_log` device list).

### Phase F — Backend & persistence _(largest; separate track)_
- [ ] Implement the SQLite schema (`schema.sql` + migrations) and a data API.
- [ ] Replace the mock store with API calls behind the same data layer.
- [ ] CSV import (delimiter detect, transfer-keyword detect, dedup constraint),
      exchange-rate fetch/cache, multi-device sync, auth.
- [ ] Trigger-maintained aggregates (`ledger_summaries`, balances, snapshots).

### Cross-cutting (ongoing)
- [ ] Accessibility pass (focus, labels, keyboard for menus/dialogs).
- [ ] Tests: unit (formatters/store) + a few Playwright smoke flows.
- [ ] CI already runs typecheck/lint/build; add tests when they exist.

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

Phase A is complete — the four stubs and the partial mobile screens are now a
demoable read-only app. **Phase B** is next: introduce a client store and make
the actions real (Add expense pickers, the tx "dots" menu, Pending confirm/cancel).
