# Insights advice engine — CP1 (iOS)

**Date:** 2026-06-25
**Status:** Design approved, pending implementation
**Scope:** FinchCore `generateInsights` selector (core 6 rules) + an Insights card on the iOS Insights › Trends tab. The last open **Tier-1** parity gap. CP2 (the 5 day-of-week / day-of-month pattern rules) is a separate later effort.

## Problem

iOS Insights is **charts only**; the web also runs a heuristic engine producing short narrative "insights" cards (`frontend/lib/insights.ts`, 11 rules, max 6 shown). iOS has no advice rules. CP1 ports the **6 rules that reuse existing iOS selectors / direct filters**, with the card UI + engine scaffolding; CP2 adds the 5 pattern rules to the same selector.

## Goal

A pure `Selectors.generateInsights` (FinchCore) producing up to 6 `Insight` values in the web's priority order, rendered as a card at the top of Insights › Trends. iOS is English-only, so the selector emits plain English strings matching the web's `en` copy; money is formatted by an injected `fmt` closure (the `netWorthSeries`-style idiom), keeping display/locale policy in the app.

## Non-goals (CP2 / later)

- The 5 pattern rules: weekend-vs-weekday, category-by-weekday, end-of-month bump, spendy-day (weekdaySkew), quietest-day — they need new day-of-week/day-of-month aggregation + min-data gates.
- No i18n framework (matches the rest of iOS — hardcoded English). No web change.

## Key decisions (locked)

1. **CP1 = the 6 reuse-existing rules:** spending trend, over budget, pending to review, top category, goal progress, net-worth trend.
2. **`Insight` carries rendered English strings** (`title`/`body`) + `tone`/`icon`; the selector takes a `fmt: (Double) -> String` money closure (app passes `store.displayMoneyBase`).
3. **Reuse** `categorySpend`, `prevMonth`, `budgetProgress`, `netWorthSeries` — no new aggregation.
4. Card at the **top of the Trends list**; empty fallback when none fire.

## Detailed design

### FinchCore — `Insight` + `generateInsights`

New file `ios/FinchCore/Sources/FinchCore/Selectors/InsightRules.swift`:

```swift
public struct Insight: Equatable, Sendable {
    public enum Tone: String, Sendable { case pos, warn, neut }
    public let tone: Tone
    public let icon: String      // semantic: "arrowUp"/"arrowDown"/"doc"/"fork"/"check"
    public let title: String
    public let body: String
}

public struct InsightContext {
    public var txns: [Tx]
    public var accounts: [AccountRow]
    public var budgets: [BudgetRow]
    public var categoryNodes: [CategoryNode]   // for budgetProgress descendant expansion + names
    public var ledgerId: String
    public var month: String                   // current month "YYYY-MM"
    public var today: String
    public var netWorthSeries: [Double]        // precomputed by the app (same series the NetWorth card uses)
    public init(...) { ... }
}

extension Selectors {
    /// Up to `max` narrative insights in web priority order; `fmt` formats money
    /// (display base). Pure; reuses categorySpend/prevMonth/budgetProgress/netWorthSeries.
    public static func generateInsights(_ c: InsightContext, fmt: (Double) -> String, max: Int = 6) -> [Insight]
}
```

`generateInsights` evaluates the 6 rules in order, appends each non-nil result, stops at `max`.

**Rules (thresholds + copy verbatim from the web `en`):**

1. **spendingTrend** — `cur = total expense from categorySpend(txns, ledgerId, month)`, `prev = …(prevMonth(month))`. If `prev > 0` and `pct = round(|cur-prev|/prev·100) != 0`: `tone = cur < prev ? .pos : .warn`, `icon = cur < prev ? "arrowDown" : "arrowUp"`, title `"Spending \(cur<prev ? "down" : "up") \(pct)% vs last month"`, body `"\(fmt(cur)) this month vs \(fmt(prev)) last month."`
2. **overBudget** — over all `type == "expense"` budgets, compute `budgetProgress(b, txns, today, categoryNodes)`; pick the one with the largest `used - base` where `over`. If found: `.warn`, `"arrowUp"`, title `"\(b.name) over budget"`, body `"At \(fmt(p.used)) of \(fmt(p.base)) — \(fmt(p.used - p.base)) over."`
3. **pending** — `let pend = txns.filter { ledgerOf == ledgerId && $0.pending == true }`; `count = pend.count`, `total = pend.map { abs(nativeAmount ?? amount) }.reduce(+)`. If `count > 0`: `.neut`, `"doc"`, title `"\(count) pending to review"`, body `"\(fmt(total)) awaiting confirmation on the Pending screen."`
4. **topCategory** — `let spend = categorySpend(txns, ledgerId, month)`; `total = spend.values.sum()`; `top = spend.max(by: value)`. If `total > 0` and a top exists: `pct = round(top.value/total·100)`, `name = categoryNodes name for top.key (?? "Uncategorized")`, `.neut`, `"fork"`, title `"\(name) leads your spending"`, body `"\(fmt(top.value)) — \(pct)% of expenses this period."`
5. **goalProgress** — `income` budgets with `amount > 0 && saved < amount`; pick max `saved/amount`. If found: `pct = round(saved/amount·100)`, `.pos`, `"check"`, title `"\(b.name) is \(pct)% funded"`, body `"\(fmt(b.saved)) of \(fmt(b.amount)) saved."`
6. **netWorthTrend** — `series = c.netWorthSeries`; need `>= 2` points; `delta = last - first`. If `abs(delta) >= 1`: `tone = delta > 0 ? .pos : .warn`, `icon = delta > 0 ? "arrowUp" : "arrowDown"`, title `delta > 0 ? "Net worth is trending up" : "Net worth dipped"`, body `"\(delta >= 0 ? "+" : "−")\(fmt(abs(delta))) across this period's activity."`

(Exact sign/category semantics of `categorySpend` to be matched in the plan — it returns per-category spend for the month; "total expense" = sum of its values. If it returns signed values, take magnitudes.)

### FinchApp — `InsightsCard`

- A new card placed **first** in the Trends branch of `InsightsTab` (above Monthly spending).
- Builds `InsightContext` from the store: `txns`, `accounts`, `budgets`, `categoryNodes`, `activeLedgerId`, `month` = current month of `store.today`, `today`, and `netWorthSeries` (the same series the NetWorth card computes). Calls `Selectors.generateInsights(ctx, fmt: store.displayMoneyBase)`.
- Renders each `Insight` as a row: a tone-colored icon circle (`pos`→green, `warn`→orange, `neut`→blue) with the SF Symbol (`arrowUp`→"arrow.up", `arrowDown`→"arrow.down", `doc`→"doc.text", `fork`→"fork.knife", `check`→"checkmark"), a title (`.headline`-ish), and a muted body. Empty fallback: "Add a few transactions to see insights." Uses the existing `Card` idiom.

### Reuse / helpers

`Selectors.categorySpend`, `Selectors.prevMonth`, `Selectors.budgetProgress`, `Selectors.netWorthSeries`, `Selectors.ledgerOf`; `store.displayMoneyBase`, `store.categoryNodes`, `store.budgets`, `store.today`.

## Facts (verified)

- Web rules + en copy: `frontend/lib/insights.ts` + `frontend/messages/en.json` `insightCards`. `Insight` web type `{ tone, icon, title:{key,params}, body:{key,params} }`; render `frontend/components/ui/insight-card.tsx` (tone colors pos=success/warn=warning/neut=primary).
- iOS selectors present: `categorySpend(_:_:_:)`, `prevMonth(_:)`, `budgetProgress(_:_:_:_:)`, `netWorthSeries(_:_:_:_:)`. No existing advice engine (`Insights.swift` is digest aggregates only).
- iOS strings are hardcoded English; `InsightsTab` uses a `Card<Content>` idiom in a `LazyVStack` under a Trends/Breakdown toggle.

## Testing

- **FinchCore (`generateInsights`):**
  - spendingTrend up + down (pct + tone) and skipped when prev = 0 / equal.
  - overBudget fires for an over budget, picks the worst, none when within budget.
  - pending: count + total when pending txns exist; absent otherwise.
  - topCategory: leader + % share; absent when no expense.
  - goalProgress: an income budget under target; absent when funded.
  - netWorthTrend: up/down by series; absent when |delta| < 1 or < 2 points.
  - **priority order** + **max-6 cap** (all 6 firing → 6 in order); **empty** on empty data. (fmt stub e.g. `{ String(format: "$%.0f", $0) }`.)
- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests green.
- **Manual (sim):** Insights › Trends shows the advice card at top with firing rules; an over-budget category shows the warn row; pending txns show the count; empty ledger shows the fallback.

## Out of scope (CP2)

The 5 day-of-week/day-of-month pattern rules; i18n; web changes.
