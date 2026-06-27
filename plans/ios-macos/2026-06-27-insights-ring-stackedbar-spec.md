# Spec: wire Ring + StackedBar into Insights

**Date:** 2026-06-27
**Status:** design approved, ready for implementation plan
**Scope:** native iOS/macOS app (`ios/`), `FinchApp` target only — `Tabs/InsightsTab.swift`. No `FinchCore`/selector changes.

## Goal

Wire the two remaining unused chart primitives — `Ring` and `StackedBar` (ported from web in #342) — into the Insights tab as net-new, non-redundant visuals: a **Savings rate** ring card and an **asset-allocation** stacked bar inside the existing **Net worth by type** card.

## Motivation

Insights already has 13 cards covering most analytics (BarChart, Donut, Sankey, CalendarHeatmap, AreaChart all wired). `Ring` and `StackedBar` (#342) are the only primitives with no consumer. Both are single-proportion visuals, so they're wired only where they add a metric/visual nothing else shows — avoiding duplication of the existing Donut (category spend) and Sankey (income flow).

## Current state (baseline)

- `Tabs/InsightsTab.swift` renders a vertical stack of `Card`-wrapped views (`InsightsCard`, `MonthlySpendingCard`, `NetWorthCard`, `CashflowCard`, `CategoryDeltasCard`, `WeeklyDigestCard`, `IncomeSankeyCard`, `SpendingHeatmapCard`, `NetWorthByTypeCard`, `CategoryBreakdownCard`, `RecentExpensesCard`, `ForecastCard`, `HoldingsCard`).
- `NetWorthByTypeCard` loads `Selectors.netWorthByAccountType(store.accounts, store.activeLedgerId) { store.toBase($0, from: $1) }` → rows of `(type, balance)`, rendered as a plain text list (label + amount).
- `Common/ChartViews/Ring.swift`: `Ring(value:max:size:stroke:color:track:) { label }` (and a label-less convenience init). `value/max` clamped to [0,1]; arc starts at top; round cap. Has its own a11y value.
- `Common/ChartViews/StackedBar.swift`: `StackedBar(slices: [Slice], height:cornerRadius:)`, `Slice(value: Double, color: Color)`. One horizontal bar of proportional segments; fills width; `accessibilityHidden(true)`.
- `Selectors.monthlyCashflow(txns, ledgerId, endMonth, n) -> [CashflowPoint]`, `CashflowPoint(m, inc, exp)` — income and expense per month (excludes pending/transfer/adjustment; `exp` stored positive).
- No account-type → color mapping exists anywhere yet.

## Design

### 1. New `SavingsRateCard` (uses `Ring`)

- **Data (inline):** `let pt = Selectors.monthlyCashflow(store.txns, store.activeLedgerId, String(store.today.prefix(7)), 1).last`. From it, `inc = pt?.inc ?? 0`, `exp = pt?.exp ?? 0`.
- **Rate:** `inc > 0 ? (inc - exp) / inc : nil` (a fraction; ×100 for display). Inline math — no new selector.
- **Render:** `Card(title: "Savings rate")` containing a `Ring` with a centered `Text("\(pct)%")` label, where `pct = Int((rate * 100).rounded())`.
  - `Ring(value: max(0, rate*100), max: 100, color: rate >= 0 ? .green : .orange)` — the ring fills 0…100%; a negative rate clamps the arc to 0 but the center label still shows the real (negative) percent. (iOS has no `Color.success`/`.warning` tokens — use the standard `.green`/`.orange` the other cards use.)
  - A one-line caption under/next to the ring: `"(income − expense) ÷ income, this month"`.
- **Empty states:**
  - `rate == nil` (no income this month, `inc <= 0`): show `Text("No income this month").font(.caption).foregroundStyle(.secondary)` instead of the ring.
  - Overspent (`rate < 0`): ring arc at 0, center label shows the negative percent (e.g. `-18%`) with the `.orange` ring color; caption may add "spent more than earned".
- **Placement:** insert into the card stack in the cashflow cluster — immediately after `CashflowCard` (and before `CategoryDeltasCard`).

### 2. Augment `NetWorthByTypeCard` (uses `StackedBar`)

- Reuse the already-loaded `rows` from `Selectors.netWorthByAccountType(...)`.
- Compute `assets = rows.filter { $0.balance > 0 }`. If `assets` is non-empty, render a `StackedBar` **above** the existing text list:
  - `StackedBar(slices: assets.map { StackedBar.Slice(value: $0.balance, color: typeColor($0.type)) })` with a little vertical padding below it.
  - Liabilities (negative balances, e.g. credit cards) are excluded from the bar but remain in the list unchanged.
  - If `assets` is empty, render the list only (no bar).
- **`typeColor(_ type: String) -> Color`** — a small private helper local to the card (default palette, approved):
  - `cash → .green`, `savings → .blue`, `investment → .purple`, `fx → .teal`, `virtual → .gray`, default → `.secondary`.
  - (These match the account types `createAccount` accepts: savings/credit_card/investment/cash/fx/virtual.)
- The existing text list (label via `AccountSheetTypeLabel.label(r.type)` + `store.displayMoneyBase(r.balance)`) is unchanged.

## Non-goals

- No new selectors / no `FinchCore` changes (savings-rate math is inline, mirroring how the other cards compute inline).
- No spend-by-merchant card (minimal scope chosen).
- No changes to the other 11 cards, the chart primitives themselves, or the Insights range/segmented control.
- No unit tests added (the math is a one-line inline expression and the cards are SwiftUI views — consistent with the existing 13 cards, which have no per-card unit tests). Verification is build + simulator visual check.

## Testing / verification

- iOS (`FinchApp`) **and** macOS (`FinchMac`) build green (the cards are cross-platform SwiftUI; no iOS-only APIs introduced).
- Simulator visual check of all states:
  - Savings rate: a normal month (positive %), a **no-income** month (caption), an **overspent** month (negative label, arc at 0).
  - Net worth by type: a ledger with multiple asset types (bar shows proportional segments), a ledger with only one asset (full bar), and a ledger with no positive assets (list only, no bar).
- The existing `FinchAppTests` suite still passes (no logic changed in tested code).

## Risks

- Insights is a shared/hot file across both sessions — implement on a branch off the latest `feat/frontend`, `git fetch` + check open PRs first. (At spec time: 0 open PRs; the other session has moved off Insights to macOS parity, now wrapped.)
- Keep `InsightsTab.swift` additions small and self-contained (two private structs / a helper) so the file doesn't balloon; if it feels too large, the cards can later move to their own file — out of scope here.
