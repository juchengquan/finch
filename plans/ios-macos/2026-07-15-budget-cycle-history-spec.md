# Spec: budget cycle-history chart ("do I chronically bust this budget?")

**Date:** 2026-07-15
**Status:** design approved, ready for implementation plan
**Scope:** native app (`ios/`) — a `FinchCore` selector + a "History" section on `BudgetDetailView` + one optional param on the shared `BarChart`. **iOS-original** (no web counterpart; iOS leapfrogs the web here — a web port can follow later).

## Goal

On a budget's detail page, show spent-vs-budget **bars across the last ~6 cycles** so the user can see at a glance whether they chronically bust (or never touch) this budget — the missing time dimension next to the current-cycle progress bar.

## Current state (baseline)

- `Selectors.cycleWindow(_ frequency:_ startDate:_ today:_ endDate:_ isRecurring:)` (Selectors.swift:267) anchors cycles at `startDate` and steps by `advance(_:frequency:)` (daily/weekly/biweekly/quarterly/yearly/default-monthly; month-adds clamp like JS). `isRecurring == 0` → a single open-ended window (no cycles).
- `Selectors.budgetProgress` (Selectors.swift:308) computes the **current** cycle only: predicate = same ledger, not pending/transfer/adjustment, in-window, optional `accountIds` filter, `expandDescendants(categoryIds)` match via `matchedAmount` (splits-aware), direction by `budget.type` ("expense": negative amounts count; "income": positive). `base = amount + (expense ? carryForward : 0)`.
- `BudgetDetailView` (WriteScreens/) shows: progress section → optional Goal/Pending sections → "This cycle" transactions. No chart anywhere on budget screens.
- `BarChart` (Common/ChartViews/BarChart.swift): categorical bars, `DataPoint{label, value, color}`, no reference-line support. Consumers: `MonthlySpendingCard` (Insights).

## Design

### 1. `FinchCore` selector — `budgetCycleHistory`

- New file `ios/FinchCore/Sources/FinchCore/Selectors/BudgetHistory.swift`:
  - `public struct BudgetCyclePoint: Equatable, Sendable { from: String; to: String; used: Double; base: Double; over: Bool; isCurrent: Bool }`
  - `public static func budgetCycleHistory(_ budget: BudgetRow, _ txns: [Tx], _ today: String, _ categories: [CategoryNode] = [], cycles: Int = 6) -> [BudgetCyclePoint]`
- Semantics:
  - Returns `[]` when `budget.isRecurring == 0` (one-shot budgets/goals have no cycles) — this also covers one-shot income goals.
  - Enumerate cycle windows from `budget.startDate` stepping by `advance(_, budget.frequency)` (the same walk `cycleWindow` does), up to and **including the cycle containing `today`**; keep the **last `cycles`** of them, oldest first. A budget younger than `cycles` cycles returns only what exists (possibly a single, current, cycle). If `today < startDate`, return `[]`.
  - Per cycle: `used` = the exact `budgetProgress` accumulation (same predicate, same `matchedAmount`/direction rules) over `[from, to]`; `r2`-rounded.
  - `base`: **past cycles use `budget.amount`** — historical carry-forward is not stored and cannot be reconstructed (documented in the doc comment); the **current** cycle uses `amount + (expense ? carryForward : 0)` so it agrees with `budgetProgress`/the page header.
  - `over = budget.type == "expense" && used > base`. `isCurrent` = the last enumerated cycle (the one containing `today`).
  - Implementation note: factor the per-window accumulation into a small shared helper used by both `budgetProgress` and `budgetCycleHistory` (or have the new selector reuse the internals directly) — do NOT duplicate the predicate logic.
- **Tests** (`FinchCoreTests/BudgetHistoryTests.swift`):
  1. Monthly budget, 3 months of history with one over-cycle: window count, oldest-first order, per-cycle `used`, `over` flags, `isCurrent` only on the last.
  2. Weekly frequency: windows step by 7 days from `startDate`.
  3. Young budget (started last month): returns 2 points, not 6.
  4. Account filter respected (txn on an excluded account doesn't count).
  5. One-shot (`isRecurring == 0`) → `[]`; `today` before `startDate` → `[]`.
  6. Current cycle's `base` includes `carryForward` (expense type); past cycles' `base` = plain `amount`.

### 2. `BarChart` — optional reference line

- Add `var referenceLine: Double? = nil` to `BarChart`; when non-nil, render a dashed `RuleMark(y: .value(yLabel, referenceLine!))` in `.secondary` style behind/over the bars. Defaulted param — the existing `MonthlySpendingCard` call site is untouched.

### 3. `BudgetDetailView` — "History" section

- New `Section("History")` inserted **between the progress section and the Goal/Pending sections**, rendered only when `budgetCycleHistory` returns **≥ 2 points** (one bar answers nothing; also hides for one-shots automatically).
- `BarChart(data: points…, referenceLine: budget.amount)` with:
  - `value` = `used`; color = `.red` when `over`, `.green` otherwise; the **current cycle at reduced opacity** (e.g. `.opacity(0.45)`) to signal in-progress.
  - `label` = cycle-start short label: monthly/quarterly/yearly → "MMM" (e.g. "Mar"); daily/weekly/biweekly → "M/d" (e.g. "3/1"). Derive from `from` (YYYY-MM-DD) without new dependencies.
  - Fixed height ~140; a caption row: "Last N cycles · budget ⟨`displayMoneyBase(budget.amount)`⟩" (privacy-masked via the store formatter).
  - The a11y values BarChart already emits carry raw numbers; leave as-is (consistent with the other charts — chart geometry/labels are outside the privacy mask by convention).

## Non-goals

- No historical carry-forward reconstruction (impossible from stored state; documented).
- No tap-to-drill into a past cycle (future enhancement).
- No web-side port in this feature (recorded as a deliberate iOS-ahead divergence — the reverse of the usual parity flow; note it in the handoff when refreshing).
- No changes to `budgetProgress` behavior (only, at most, factoring its accumulation into a shared internal helper).

## Testing / verification

- Selector unit tests above via `swift test` (also runs in CI's FinchCore job).
- Builds: `FinchApp` (iOS) + `FinchMac` (macOS); `FinchAppTests` regression.
- Simulator: a monthly demo budget shows History bars + dashed cap line, current bar dimmed; a one-shot/young budget hides the section; privacy mode leaves bars/labels (shapes) while the caption's money masks.

## Risks

- Cycle walk cost: up to `guard`-bounded iterations per budget (same guard pattern as `cycleWindow`, cap 5000) once per detail-page render — negligible (single budget, not the list).
- `BarChart` change touches a shared primitive — defaulted param + verify the Insights consumer renders unchanged (build + eyeball).
- Demo-seed data may have short history (seeded ~1-2 months) — verify with what exists; the young-budget path makes that fine.
