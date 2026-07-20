# Budgets page UI optimization — design

**Date:** 2026-07-20
**Status:** Design agreed in a brainstorming session; plan follows.
**Scope:** FinchApp Budgets tab only (`Tabs/BudgetsTab.swift` + one small view-helper + one
pure summary helper). **No** FinchCore/engine/schema change, **no** web change.

## Purpose

The Budgets page is functional but under-informative in two spots:

1. **The summary is two bare numbers.** `summarySection` shows `Spent $X / Budget $Y` via
   `StatusSummaryRow` — no overall progress, no "remaining", and no signal that a budget is
   over. Worse, `budgetTotalsDisplay` sums **all** budgets, so **savings goals are folded into
   the spend total** (a goal's saved/target counts as "spent"/"budget"), conflating saving with
   spending.
2. **Rows don't show the actionable number.** A row shows `used / base` but not **remaining to
   spend** — the number a user actually acts on.

This design enriches the summary and the rows using figures the engine already computes.

## Decisions (from the brainstorm)

1. **Summary: separate goals from spend.** The top card reflects **expense budgets only**
   (spent / budget / remaining / over-count). Savings goals get their own compact line.
2. **Rows: keep `used / base`, add remaining to the caption.** The top line (`$71 / $600`) and
   the 3-color bar are unchanged; the caption line gains the remaining figure.
3. **Goal definition:** a budget is a **goal** when `type == "income" && isRecurring == 0` — the
   exact test `BudgetRowView` already uses. Everything else is a **spend** budget.
4. **No global cycle countdown.** Budgets carry a per-budget `frequency` (weekly/monthly/yearly),
   so a single summary-level "days left" would be dishonest. Per-row "N days left" stays.
5. **No engine work.** `Selectors.budgetProgress` already returns `remaining` (`base − used`,
   negative when over) and `over`. The UI consumes those directly.
6. **Not chosen (explicitly out):** raw row-density changes and a pure visual/typography refresh
   were considered and declined — this is about summary richness + row info only.

## Visual

**Row — expense (under budget):** top line + bar unchanged; caption adds remaining.
```
Groceries                       $71.20 / $600.00
▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░
$528.80 left · 12 days left
```
**Row — expense (over budget):** the remaining phrase becomes "$X over" in red.
```
Rent                          $1,850.00 / $1,500.00
████████████████████████████████████████
$350.00 over · 12 days left
```
**Row — goal:** no day countdown; caption is "to go · N% saved".
```
Vacation Fund                   $650.00 / $2,000.00
▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░
$1,350.00 to go · 33% saved
```

**Summary card (expense budgets only):**
```
$1,071.27 left to spend                       ⚠ 1 over
████████████████░░░░░░░░
$2,298.73 spent · of $3,370.00
Goals · $650.00 of $2,000.00 saved            ← only when the ledger has ≥1 goal
```
- **Remaining is the hero** ("$X left to spend"); when the ledger's spend total is itself over
  budget (spent > budget), the hero reads "$X over" in red.
- **Overall bar**, color-banded by overall pct with the same thresholds as the rows.
- Secondary caption: "$X spent · of $Y".
- **"N over" badge** (red), top-right, only when `overCount > 0`.
- **Goals line** appears only when goals exist; it never affects the spend numbers.

## Components

### 1. `BudgetSummary` — a pure aggregation helper (new)
A pure, testable value + function with no view/store dependency. Lives in
`FinchApp/Sources/FinchApp/Common/BudgetSummary.swift`.

```swift
struct BudgetSummary: Equatable {
    var spentBase: Double        // Σ used over spend budgets
    var budgetBase: Double       // Σ base over spend budgets
    var remainingBase: Double    // budgetBase − spentBase (may be negative)
    var overCount: Int           // # spend budgets with progress.over
    var goalSavedBase: Double     // Σ used over goal budgets
    var goalTargetBase: Double    // Σ base over goal budgets
    var hasGoals: Bool
    var hasSpend: Bool           // ≥1 spend budget (drives whether the spend card shows)
}

/// `isGoal`/`progress` are injected so the helper stays pure & unit-testable (the
/// caller passes `Selectors.budgetProgress`). A budget is a goal when
/// `type == "income" && isRecurring == 0`.
static func compute(_ budgets: [BudgetRow],
                    progress: (BudgetRow) -> BudgetProgress) -> BudgetSummary
```
Overall pct for the bar is derived in the view (`spentBase / budgetBase`), not stored.

### 2. `FinchStore` view-helper (new, in `FinchStore+ViewHelpers.swift`)
Wraps the pure helper against live store state; returns the raw `BudgetSummary` (the view
formats amounts through the privacy-aware `displayMoneyBase`, and computes the bar ratio, which
is a proportion and carries no maskable amount):
```swift
var budgetSummary: BudgetSummary   // BudgetSummary.compute(budgets) { Selectors.budgetProgress($0, txns, today, categoryNodes) }
```
`budgetTotalsDisplay` is superseded by the card and removed (its only caller is the summary
section).

### 3. `BudgetThreshold.color(pct:)` — shared banding (new tiny helper)
Extract `BudgetRowView.thresholdColor` (green `< 70`, yellow `70–90`, red `> 90`) to
`Common/BudgetSummary.swift` so the summary bar and the rows band identically. `BudgetRowView`
calls the shared version.

### 4. `BudgetSummaryCard` — the card view (new)
Replaces `StatusSummaryRow` inside `BudgetsTab.summarySection`. Renders (all money via
`store.displayMoneyBase`):
- hero remaining / "$X over" (red when `remainingBase < 0`),
- the "N over" badge when `overCount > 0`,
- the overall bar (`min(spentBase / budgetBase, 1)`, `.tint(BudgetThreshold.color(overallPct))`;
  guard `budgetBase == 0`),
- the "$X spent · of $Y" caption,
- the conditional goals line (`hasGoals`).
When `!hasSpend && hasGoals` (goals-only ledger), the spend block is hidden and only the goals
line shows.

### 5. `BudgetRowView` caption (modified)
The `used/base` top line and the bar are untouched. The caption `HStack` changes:
- **Spend, under:** `"\(store.displayMoneyBase(progress.remaining)) left"` + `" · "` +
  `"\(store.daysLeft(until: progress.to)) days left"` (secondary).
- **Spend, over:** `"\(store.displayMoneyBase(-progress.remaining)) over"` in **red** + `" · "` +
  days-left. (Replaces the current right-aligned "Over" tag.)
- **Goal:** `"\(store.displayMoneyBase(progress.remaining)) to go"` + `" · "` +
  `"\(progress.pct)% saved"`. No day countdown. When the goal is fully met
  (`progress.remaining <= 0`), the caption reads `"Goal reached · \(pct)% saved"` (green)
  instead of a negative "to go".

## Data flow

Read-only. `BudgetsTab` reads `store.budgetSummary` for the card and per-row
`Selectors.budgetProgress` for rows (unchanged). Every write already reprojects and republishes,
so the card and rows refresh together. Privacy mode masks all amounts through `displayMoneyBase`;
the bars (proportions) remain visible, matching today's rows.

## Error / edge handling

- **`budgetBase == 0`** (no spend budgets, or all zero-base): bar shows empty, remaining = spent
  → hero handles gracefully; when `!hasSpend`, the spend block is hidden entirely.
- **No goals:** the goals line is omitted.
- **Over budget:** `remaining` is negative → hero/caption use `-remaining` with the "over"
  phrasing and red tint.
- **Goal met/exceeded** (`remaining <= 0`): row caption reads "Goal reached" (green) rather than
  a negative "to go"; the goals-summary line still sums raw saved/target (an over-saved goal
  simply pushes saved past target).
- **Search active:** the summary card reflects the whole ledger (not the filtered subset), same
  as `budgetTotalsDisplay` today — the summary is a ledger health readout, not a search result.

## Testing

- **Unit (`FinchAppTests`):** `BudgetSummary.compute` with a stubbed `progress` closure —
  mixed spend + goal budgets (goals excluded from spend totals), an over-budget budget
  (`overCount`, negative `remainingBase`), goals-only (`!hasSpend`, `hasGoals`), and empty.
- **Builds:** FinchApp + FinchMac.
- No UI snapshot tests (layout is conventional SwiftUI).

## Out of scope

- The "N over" badge is a **static** flag (not tap-to-filter/scroll — a good follow-up).
- No row-density change, no typography/spacing refresh, no reorder/group changes.
- No engine, schema, parity-fixture, or web change.
- zh-Hans strings for the new copy ("left to spend", "over", "to go", "saved", "N over") follow
  the standard generated-localization pass, tracked separately.
