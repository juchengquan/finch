# Budget Cycle-History Chart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spent-vs-budget bars across the last ~6 cycles on the budget detail page ("do I chronically bust this budget?").

**Architecture:** Task 1 adds `Selectors.budgetCycleHistory` to FinchCore (TDD) — reusing `budgetProgress`'s accumulation via a newly factored `usedInWindow` helper and the existing cycle math (`advance` becomes internal). Task 2 adds a dashed reference line to the shared `BarChart` (defaulted param) and a "History" section to `BudgetDetailView`.

**Tech Stack:** Swift / SwiftUI / Swift Charts; FinchCore is SwiftPM (`swift test`). Spec: `plans/ios-macos/2026-07-15-budget-cycle-history-spec.md`.

## Global Constraints

- Past cycles' `base` = plain `budget.amount` (historical carry-forward isn't stored — say so in the doc comment); the **current** cycle's `base` = `amount + (type == "expense" ? carryForward : 0)` to match `budgetProgress`.
- Reuse `budgetProgress`'s predicate by **factoring** its accumulation loop into a shared internal helper — no duplication; `budgetProgress`'s observable behavior must not change (full FinchCore suite proves it).
- `[]` for `isRecurring == 0` (one-shots) and for `today < startDate`. Windows oldest-first, at most `cycles` (default 6), last one flagged `isCurrent`.
- `BarChart` gains `referenceLine: Double? = nil` — the existing Insights `MonthlySpendingCard` call site must compile and render unchanged.
- History section hidden when `< 2` points. Bar colors: `.red` when `over`, else `.green`; current cycle at `.opacity(0.45)`. Caption money via `store.displayMoneyBase` (privacy-maskable); bar geometry/labels stay raw (chart convention).
- Build both `FinchApp` (iOS) and `FinchMac` (macOS). Commands from `ios/` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `xcodegen generate` in a fresh worktree; sim fallback `id=<udid>` of a booted device.

---

### Task 1: `Selectors.budgetCycleHistory` (+ factor `usedInWindow`, TDD)

**Files:**
- Create: `ios/FinchCore/Sources/FinchCore/Selectors/BudgetHistory.swift`
- Modify: `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift:256` (make `advance` internal) and `:308-335` (factor the loop)
- Test: `ios/FinchCore/Tests/FinchCoreTests/BudgetHistoryTests.swift` (create)

**Interfaces:**
- Consumes (existing): `cycleWindow`, `advance` (after visibility change), `date`/`ymd`/`addDays`, `expandDescendants`, `matchedAmount`, `ledgerOf/kindOf`, `r2`; `BudgetRow` (memberwise init, no defaults); `Tx`.
- Produces (consumed by Task 2): `Selectors.BudgetCyclePoint { from, to, used, base, over, isCurrent }` (all `public let`, `Equatable, Sendable`) and `Selectors.budgetCycleHistory(_ budget: BudgetRow, _ txns: [Tx], _ today: String, _ categories: [CategoryNode] = [], cycles: Int = 6) -> [BudgetCyclePoint]`. Also (internal): `usedInWindow(_ budget:_ txns:_ matchSet:_ accountSet:from:to:) -> Double`.

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchCore/Tests/FinchCoreTests/BudgetHistoryTests.swift`:

```swift
import XCTest
@testable import FinchCore

final class BudgetHistoryTests: XCTestCase {
    private func budget(amount: Double = 100, frequency: String = "monthly",
                        startDate: String = "2026-03-01", isRecurring: Int = 1,
                        carryForward: Double = 0, accountIds: [String] = [],
                        type: String = "expense") -> BudgetRow {
        BudgetRow(id: "b1", ledgerId: "l1", groupId: nil, name: "Food", type: type,
                  amount: amount, saved: 0, carryForward: carryForward, frequency: frequency,
                  startDate: startDate, endDate: nil, isRecurring: isRecurring, rollover: 0,
                  rolloverLimit: nil, pendingAmount: nil, lastRolledPeriod: nil,
                  accountIds: accountIds, categoryIds: ["food"], warningPct: 80)
    }
    private func tx(_ id: String, _ amount: Double, _ date: String,
                    cat: String = "food", acct: String = "a1") -> Tx {
        Tx(id: id, merchant: "m", category: cat, amount: amount, account: acct, date: date,
           pending: false, ledgerId: "l1", kind: "expense")
    }

    func test_monthlyWalk_orderUsedOverAndCurrent() {
        let txns = [
            tx("1", -50, "2026-03-10"),    // cycle 1: 50 (under)
            tx("2", -120, "2026-04-05"),   // cycle 2: 120 (over)
            tx("3", -10, "2026-05-02"),    // cycle 3 (current): 10
        ]
        let pts = Selectors.budgetCycleHistory(budget(), txns, "2026-05-15")
        XCTAssertEqual(pts.count, 3)
        XCTAssertEqual(pts.map(\.from), ["2026-03-01", "2026-04-01", "2026-05-01"])
        XCTAssertEqual(pts.map(\.used), [50, 120, 10])
        XCTAssertEqual(pts.map(\.over), [false, true, false])
        XCTAssertEqual(pts.map(\.isCurrent), [false, false, true])
        XCTAssertEqual(pts[0].to, "2026-03-31")
    }

    func test_weeklyWindowsStepBySevenDays() {
        let pts = Selectors.budgetCycleHistory(
            budget(frequency: "weekly", startDate: "2026-06-01"), [tx("1", -5, "2026-06-02")], "2026-06-16")
        XCTAssertEqual(pts.map(\.from), ["2026-06-01", "2026-06-08", "2026-06-15"])
        XCTAssertEqual(pts[0].to, "2026-06-07")
        XCTAssertEqual(pts.map(\.used), [5, 0, 0])
    }

    func test_capsAtCyclesKeepingLatest() {
        let pts = Selectors.budgetCycleHistory(budget(startDate: "2025-01-01"), [], "2026-05-15", cycles: 6)
        XCTAssertEqual(pts.count, 6)
        XCTAssertEqual(pts.last!.from, "2026-05-01")   // newest kept, oldest dropped
        XCTAssertEqual(pts.first!.from, "2025-12-01")
    }

    func test_accountFilterRespected() {
        let b = budget(accountIds: ["a1"])
        let txns = [tx("1", -40, "2026-03-05", acct: "a1"), tx("2", -99, "2026-03-06", acct: "a2")]
        let pts = Selectors.budgetCycleHistory(b, txns, "2026-03-20")
        XCTAssertEqual(pts.map(\.used), [40])   // a2 txn excluded
    }

    func test_oneShotAndFutureStartReturnEmpty() {
        XCTAssertTrue(Selectors.budgetCycleHistory(budget(isRecurring: 0), [], "2026-05-15").isEmpty)
        XCTAssertTrue(Selectors.budgetCycleHistory(budget(startDate: "2026-09-01"), [], "2026-05-15").isEmpty)
    }

    func test_currentBaseIncludesCarryForward_pastIsPlainAmount() {
        let pts = Selectors.budgetCycleHistory(budget(carryForward: 25), [], "2026-04-10")
        XCTAssertEqual(pts.count, 2)
        XCTAssertEqual(pts[0].base, 100)    // past: plain amount
        XCTAssertEqual(pts[1].base, 125)    // current: amount + carryForward (expense)
    }
}
```

- [ ] **Step 2: Run to confirm they fail**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && swift test --filter BudgetHistoryTests 2>&1 | tail -4
```
Expected: FAIL to compile — `budgetCycleHistory`/`BudgetCyclePoint` don't exist.

- [ ] **Step 3: Make `advance` internal + factor `usedInWindow` out of `budgetProgress`**

In `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift`:

Change line 256 from:
```swift
    private static func advance(_ d: Date, _ frequency: String) -> Date {
```
to:
```swift
    static func advance(_ d: Date, _ frequency: String) -> Date {
```

Add the shared accumulation helper next to `matchedAmount` (after it), and rewrite `budgetProgress`'s loop to use it. The helper:
```swift
    /// Sum of budget-matched activity in [from, to] — the accumulation shared by
    /// budgetProgress (current cycle) and budgetCycleHistory (each past cycle).
    static func usedInWindow(_ budget: BudgetRow, _ txns: [Tx], _ matchSet: Set<String>,
                             _ accountSet: Set<String>?, from: String, to: String) -> Double {
        var used = 0.0
        for t in txns {
            if ledgerOf(t) != budget.ledgerId { continue }
            if (t.pending ?? false) || kindOf(t) == "transfer" || kindOf(t) == "adjustment" { continue }
            if t.date < from || t.date > to { continue }
            if let accountSet, !accountSet.contains(t.account) { continue }
            let amt = matchedAmount(t, matchSet)
            if budget.type == "expense" { if amt < 0 { used += -amt } }
            else if amt > 0 { used += amt }
        }
        return used
    }
```
and in `budgetProgress`, replace the `for t in txns { … }` block inside the `else` branch with:
```swift
            used = usedInWindow(budget, txns, matchSet, accountSet, from: win.from, to: win.to)
```
(the surrounding `oneShotIncome` special case, `r2` rounding, `base`/`remaining`/`pct`/`over` lines stay exactly as they are).

- [ ] **Step 4: Create `BudgetHistory.swift`**

Create `ios/FinchCore/Sources/FinchCore/Selectors/BudgetHistory.swift`:

```swift
import Foundation

// Budget cycle history — spent vs budget across the trailing cycles, for the
// budget detail page's History chart ("do I chronically bust this budget?").
// iOS-original (no web counterpart yet).
extension Selectors {
    public struct BudgetCyclePoint: Equatable, Sendable {
        /// Cycle bounds (YYYY-MM-DD, inclusive).
        public let from: String
        public let to: String
        /// Budget-matched activity in the cycle (same predicate as budgetProgress).
        public let used: Double
        /// The cap the cycle is judged against. Past cycles use the plain budget
        /// amount — historical carry-forward isn't stored and can't be
        /// reconstructed; the current cycle includes carryForward so it agrees
        /// with budgetProgress and the page header.
        public let base: Double
        public let over: Bool
        public let isCurrent: Bool
    }

    /// The budget's last `cycles` cycle windows (oldest first, ending with the
    /// cycle containing `today`). Empty for one-shot budgets (no cycles) and
    /// when `today` precedes the start date.
    public static func budgetCycleHistory(_ budget: BudgetRow, _ txns: [Tx], _ today: String,
                                          _ categories: [CategoryNode] = [],
                                          cycles: Int = 6) -> [BudgetCyclePoint] {
        guard budget.isRecurring != 0 else { return [] }
        let start = date(budget.startDate), now = date(today)
        guard now >= start else { return [] }

        // Enumerate windows from startDate through the one containing today,
        // keeping only the trailing `cycles` (same guard bound as cycleWindow).
        var windows: [(from: String, to: String)] = []
        var s = start, guardI = 0
        while s <= now && guardI < 5000 {
            let e = advance(s, budget.frequency)
            windows.append((ymd(s), ymd(addDays(e, -1))))
            if windows.count > cycles { windows.removeFirst() }
            s = e
            guardI += 1
        }

        let accountSet = budget.accountIds.isEmpty ? nil : Set(budget.accountIds)
        let matchSet = categories.isEmpty ? Set(budget.categoryIds) : expandDescendants(budget.categoryIds, categories)
        let isExpense = budget.type == "expense"

        return windows.enumerated().map { i, w in
            let isCurrent = i == windows.count - 1
            let base = r2(budget.amount + (isCurrent && isExpense ? budget.carryForward : 0))
            let used = r2(usedInWindow(budget, txns, matchSet, accountSet, from: w.from, to: w.to))
            return BudgetCyclePoint(from: w.from, to: w.to, used: used, base: base,
                                    over: isExpense && used > base, isCurrent: isCurrent)
        }
    }
}
```

- [ ] **Step 5: Run the filter + the FULL FinchCore suite (proves `budgetProgress` unchanged)**

```bash
cd ios && swift test --filter BudgetHistoryTests 2>&1 | tail -3
swift test 2>&1 | tail -3
```
Expected: 6/6 for the filter; full suite green (any `budgetProgress`-covering test still passing).

- [ ] **Step 6: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Selectors/BudgetHistory.swift \
        ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift \
        ios/FinchCore/Tests/FinchCoreTests/BudgetHistoryTests.swift
git commit -m "feat(core): budgetCycleHistory — spent vs budget across trailing cycles"
```

---

### Task 2: `BarChart` reference line + History section on `BudgetDetailView`

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Common/ChartViews/BarChart.swift` (whole body shown below)
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetDetailView.swift` (insert section after `Section { progress(budget, p) }` at ~line 26; add two private helpers)

**Interfaces:**
- Consumes (Task 1): `Selectors.budgetCycleHistory(...)`, `Selectors.BudgetCyclePoint`.
- Produces: `BarChart(data:xLabel:yLabel:referenceLine:)` (new defaulted param).

- [ ] **Step 1: Add the reference line to `BarChart`**

Replace `BarChart`'s `body` (the `Chart(data) { … }` initializer can't host an extra mark — switch to the block form with `ForEach`):

```swift
    /// Optional dashed horizontal rule (e.g. a budget cap) drawn across the bars.
    var referenceLine: Double? = nil

    var body: some View {
        Chart {
            ForEach(data) { point in
                BarMark(x: .value(xLabel, point.label), y: .value(yLabel, point.value))
                    .foregroundStyle(point.color)
                    .accessibilityLabel(Text(point.label))
                    .accessibilityValue(Text(String(format: "%.0f", point.value)))
            }
            if let referenceLine {
                RuleMark(y: .value(yLabel, referenceLine))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
    }
```
(`referenceLine` is declared with the other stored properties; keep `data/xLabel/yLabel` as-is. The existing `MonthlySpendingCard` call site compiles unchanged.)

- [ ] **Step 2: Insert the History section in `BudgetDetailView`**

After `Section { progress(budget, p) }` (before the `if budget.type == "income"` Goal section), insert:

```swift
                    historySection(budget)
```

Add the helpers to the struct (near `transactionsSection`):

```swift
    /// Spent-vs-budget bars across the trailing cycles (hidden for one-shots and
    /// when there's under 2 cycles of history — one bar answers nothing).
    @ViewBuilder private func historySection(_ b: BudgetRow) -> some View {
        let pts = Selectors.budgetCycleHistory(b, store.txns, store.today, store.categoryNodes)
        if pts.count >= 2 {
            Section("History") {
                BarChart(data: pts.map { p in
                    BarChart.DataPoint(label: cycleLabel(p.from, b.frequency),
                                       value: p.used,
                                       color: (p.over ? Color.red : Color.green)
                                           .opacity(p.isCurrent ? 0.45 : 1))
                }, xLabel: "Cycle", yLabel: "Spent", referenceLine: b.amount)
                .frame(height: 140)
                Text("Last \(pts.count) cycles · budget \(store.displayMoneyBase(b.amount))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Short x-axis label for a cycle start: month name for month-grained
    /// frequencies, M/d for day-grained ones.
    private func cycleLabel(_ from: String, _ frequency: String) -> String {
        let parts = from.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]), (1...12).contains(m) else { return from }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        switch frequency {
        case "daily", "weekly", "biweekly": return "\(m)/\(d)"
        default: return months[m - 1]   // monthly / quarterly / yearly
        }
    }
```

- [ ] **Step 3: Build iOS + macOS + run FinchAppTests**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|reasonable time|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" -only-testing:FinchAppTests 2>&1 | grep -iE "Executed .* tests|TEST SUCCEEDED|TEST FAILED"
```
Expected: both builds SUCCEED; tests green.

- [ ] **Step 4: Simulator visual check**

Install + launch (per the `ios-build-launch` skill; fresh-install if the demo data is gone so the seed runs). Open Budgets → a monthly budget's detail: History section shows bars (green/red, current dimmed) + the dashed cap line + the caption; verify the Insights → "Monthly spending" card still renders identically (shared-BarChart regression); demo budgets with < 2 cycles correctly hide the section — note which budgets rendered it. Also confirm privacy mode masks the caption amount.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Common/ChartViews/BarChart.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetDetailView.swift
git commit -m "feat(ios): budget cycle-history bars on the detail page (+ BarChart reference line)"
```

---

## Self-Review

**1. Spec coverage:** selector semantics (one-shot/future-start empty, oldest-first, cap at `cycles`, past base = amount, current base includes carry, predicate reuse via factored `usedInWindow`, `advance` visibility) → Task 1; 6 spec'd tests → Task 1 Step 1 (6 test funcs); BarChart defaulted `referenceLine` + untouched Insights consumer → Task 2 Step 1 + Step 4 regression eyeball; History section placement/gating/colors/dimmed-current/labels/caption → Task 2 Step 2; builds + sim → Task 2 Steps 3-4. ✅
**2. Placeholder scan:** none — complete code + commands with expected output everywhere.
**3. Type consistency:** `BudgetCyclePoint{from,to,used,base,over,isCurrent}` matches between Task 1 (definition + tests) and Task 2 (`p.used/p.over/p.isCurrent/p.from`); `usedInWindow` signature used identically in `budgetProgress` and `budgetCycleHistory`; `BarChart.DataPoint(label:value:color:)` and the new `referenceLine:` label match the primitive; `budget(...)`/`tx(...)` fixtures use the real memberwise inits verified against `Budget.swift:33` and `Models.swift:31`.
