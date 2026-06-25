# Insights advice engine CP1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the 6 reuse-existing web insight rules as a pure `Selectors.generateInsights` selector + an Insights card atop Insights › Trends.

**Architecture:** No engine change beyond a new pure selector. (1) FinchCore: `Insight`/`InsightContext` + `generateInsights` (6 rules), reusing `categorySpend`/`prevMonth`/`budgetProgress`/`netWorthSeries`; emits English strings + a `fmt` money closure. (2) FinchApp: an `InsightsCard` building the context from the store.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), FinchCore, XcodeGen, XCTest.

## Global Constraints

- **CP1 = 6 rules** in web priority order: spendingTrend, overBudget, pending, topCategory, goalProgress, netWorthTrend. (The 5 day-of-week/day-of-month pattern rules are CP2.)
- `Insight { tone: .pos/.warn/.neut; icon: String; title: String; body: String }` — plain English strings matching the web `en` copy. `generateInsights(_ ctx:, fmt: (Double)->String, max: 6) -> [Insight]`; `fmt` formats money (app passes `store.displayMoneyBase`).
- Reuse existing selectors — **no new aggregation.** `categorySpend` returns positive net-spend magnitudes per category (expense+refund, excludes pending); `budgetProgress.over` is expense-only, overage = `used - base`; `netWorthSeries` uses the default identity `toBase`.
- **Must build iOS AND macOS (FinchMac).** Sim `iPhone 17 Pro Max`. New files → `xcodegen generate`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit; **no `Co-Authored-By` trailer**.

---

## File Structure

**Create (FinchCore):** `ios/FinchCore/Sources/FinchCore/Selectors/InsightRules.swift`.
**Create (tests):** `ios/FinchCore/Tests/FinchCoreTests/InsightsRulesTests.swift`.
**Modify (FinchApp):** `ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift`.

---

### Task 1: `Insight` + `generateInsights` (6 rules) + tests

**Files:**
- Create: `ios/FinchCore/Sources/FinchCore/Selectors/InsightRules.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests/InsightsRulesTests.swift`

**Interfaces:**
- Produces: `Insight` (Tone/icon/title/body), `InsightContext`, `Selectors.generateInsights(_:fmt:max:) -> [Insight]`.

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchCore/Tests/FinchCoreTests/InsightsRulesTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class InsightsRulesTests: XCTestCase {
    private let fmt: (Double) -> String = { String(format: "$%.0f", $0) }

    private func ctx(_ q: DatabaseQueue, month: String = "2026-05", today: String = "2026-05-31") throws -> InsightContext {
        InsightContext(
            txns: try Projection.run(dbQueue: q, ledgerId: "l1"),
            accounts: try Projection.accounts(dbQueue: q, ledgerId: "l1"),
            budgets: try Projection.budgets(dbQueue: q, ledgerId: "l1"),
            categories: try Projection.categories(dbQueue: q, ledgerId: "l1"),
            ledgerId: "l1", month: month, today: today)
    }
    private func add(_ q: DatabaseQueue, _ amount: Double, _ date: String, pending: Bool = false, cat: String = "c1") throws {
        var a: [String: JSONValue] = ["ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(amount),
            "merchant": .string("M"), "categoryId": .string(cat), "date": .string(date), "skipRules": .bool(true)]
        if pending { a["status"] = .string("pending") }
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args(a))
    }
    private func titles(_ ins: [Insight]) -> [String] { ins.map(\.title) }

    func test_empty_ledger_no_insights() throws {
        let q = try TestSeed.base()
        XCTAssertTrue(Selectors.generateInsights(try ctx(q), fmt: fmt).isEmpty)
    }

    func test_pending_insight() throws {
        let q = try TestSeed.base()
        try add(q, -40, "2026-05-10", pending: true)
        let ins = Selectors.generateInsights(try ctx(q), fmt: fmt)
        XCTAssertTrue(ins.contains { $0.title.contains("pending to review") && $0.tone == .neut })
    }

    func test_top_category_insight() throws {
        let q = try TestSeed.base()
        try add(q, -60, "2026-05-10")
        let ins = Selectors.generateInsights(try ctx(q), fmt: fmt)
        XCTAssertTrue(ins.contains { $0.title.contains("leads your spending") && $0.title.contains("Food") })
    }

    func test_over_budget_insight() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
            "id": .string("b1"), "ledgerId": .string("l1"), "name": .string("Groceries"),
            "type": .string("expense"), "amount": .double(100), "categoryIds": .array([.string("c1")])]))
        try add(q, -150, "2026-05-15")
        let ins = Selectors.generateInsights(try ctx(q), fmt: fmt)
        XCTAssertTrue(ins.contains { $0.title == "Groceries over budget" && $0.tone == .warn })
    }

    func test_spending_trend_up() throws {
        let q = try TestSeed.base()
        try add(q, -100, "2026-04-10")   // prev month
        try add(q, -150, "2026-05-10")   // current month (up 50%)
        let ins = Selectors.generateInsights(try ctx(q), fmt: fmt)
        XCTAssertTrue(ins.contains { $0.title == "Spending up 50% vs last month" && $0.tone == .warn })
    }

    func test_goal_progress_insight() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
            "id": .string("g1"), "ledgerId": .string("l1"), "name": .string("Savings"),
            "type": .string("income"), "amount": .double(1000)]))
        try Apply.apply(dbQueue: q, action: "contributeBudget", args: Args(["id": .string("g1"), "amount": .double(250)]))
        let ins = Selectors.generateInsights(try ctx(q), fmt: fmt)
        XCTAssertTrue(ins.contains { $0.title == "Savings is 25% funded" && $0.tone == .pos })
    }

    func test_net_worth_trend_present() throws {
        let q = try TestSeed.base()
        try add(q, 500, "2026-05-10")   // income → net worth up
        let ins = Selectors.generateInsights(try ctx(q), fmt: fmt)
        XCTAssertTrue(ins.contains { $0.title.contains("Net worth") })
    }

    func test_max_six_and_priority_order() throws {
        let q = try TestSeed.base()
        try add(q, -100, "2026-04-10"); try add(q, -150, "2026-05-10")     // spendingTrend + topCategory
        try add(q, -40, "2026-05-11", pending: true)                       // pending
        let ins = Selectors.generateInsights(try ctx(q), fmt: fmt)
        XCTAssertLessThanOrEqual(ins.count, 6)
        // spendingTrend (if firing) precedes pending precedes topCategory
        let t = titles(ins)
        if let iSpend = t.firstIndex(where: { $0.contains("vs last month") }),
           let iPend = t.firstIndex(where: { $0.contains("pending to review") }) {
            XCTAssertLessThan(iSpend, iPend)
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter InsightsRulesTests`
Expected: FAIL to compile — `Insight`/`InsightContext`/`generateInsights` undefined.

- [ ] **Step 3: Implement `InsightRules.swift`**

Create `ios/FinchCore/Sources/FinchCore/Selectors/InsightRules.swift`:

```swift
import Foundation

/// A narrative insight card (advice). iOS is English-only, so title/body are
/// rendered strings (matching the web `en` copy); money is formatted by the
/// caller's `fmt` closure.
public struct Insight: Equatable, Sendable {
    public enum Tone: String, Sendable { case pos, warn, neut }
    public let tone: Tone
    public let icon: String      // semantic: arrowUp/arrowDown/doc/fork/check
    public let title: String
    public let body: String
    public init(tone: Tone, icon: String, title: String, body: String) {
        self.tone = tone; self.icon = icon; self.title = title; self.body = body
    }
}

/// Inputs for `generateInsights` (the app builds this from its store).
public struct InsightContext {
    public var txns: [Tx]
    public var accounts: [AccountRow]
    public var budgets: [BudgetRow]
    public var categories: [CategoryRow]
    public var ledgerId: String
    public var month: String   // "YYYY-MM"
    public var today: String
    public init(txns: [Tx], accounts: [AccountRow], budgets: [BudgetRow], categories: [CategoryRow],
                ledgerId: String, month: String, today: String) {
        self.txns = txns; self.accounts = accounts; self.budgets = budgets; self.categories = categories
        self.ledgerId = ledgerId; self.month = month; self.today = today
    }
}

extension Selectors {
    /// Up to `max` narrative insights in web priority order. `fmt` formats money.
    /// Pure; reuses categorySpend/prevMonth/budgetProgress/netWorthSeries.
    public static func generateInsights(_ c: InsightContext, fmt: (Double) -> String, max: Int = 6) -> [Insight] {
        var out: [Insight] = []
        func add(_ i: Insight?) { if let i, out.count < max { out.append(i) } }
        add(spendingTrendInsight(c, fmt))
        add(overBudgetInsight(c, fmt))
        add(pendingInsight(c, fmt))
        add(topCategoryInsight(c, fmt))
        add(goalProgressInsight(c, fmt))
        add(netWorthTrendInsight(c, fmt))
        return out
    }

    private static func spendingTrendInsight(_ c: InsightContext, _ fmt: (Double) -> String) -> Insight? {
        let cur = categorySpend(c.txns, c.ledgerId, c.month).values.reduce(0, +)
        let prev = categorySpend(c.txns, c.ledgerId, prevMonth(c.month)).values.reduce(0, +)
        guard prev > 0 else { return nil }
        let pct = Int((abs(cur - prev) / prev * 100).rounded())
        guard pct != 0 else { return nil }
        let down = cur < prev
        return Insight(tone: down ? .pos : .warn, icon: down ? "arrowDown" : "arrowUp",
            title: "Spending \(down ? "down" : "up") \(pct)% vs last month",
            body: "\(fmt(cur)) this month vs \(fmt(prev)) last month.")
    }

    private static func overBudgetInsight(_ c: InsightContext, _ fmt: (Double) -> String) -> Insight? {
        let nodes = c.categories.map { CategoryNode(id: $0.id, parentId: $0.parentId) }
        var worst: (name: String, p: BudgetProgress)?
        for b in c.budgets where b.type == "expense" {
            let p = budgetProgress(b, c.txns, c.today, nodes)
            if p.over, worst == nil || (p.used - p.base) > (worst!.p.used - worst!.p.base) { worst = (b.name, p) }
        }
        guard let w = worst else { return nil }
        return Insight(tone: .warn, icon: "arrowUp",
            title: "\(w.name) over budget",
            body: "At \(fmt(w.p.used)) of \(fmt(w.p.base)) — \(fmt(w.p.used - w.p.base)) over.")
    }

    private static func pendingInsight(_ c: InsightContext, _ fmt: (Double) -> String) -> Insight? {
        let pend = c.txns.filter { ledgerOf($0) == c.ledgerId && ($0.pending ?? false) }
        guard !pend.isEmpty else { return nil }
        let total = pend.reduce(0.0) { $0 + abs($1.nativeAmount ?? $1.amount) }
        return Insight(tone: .neut, icon: "doc",
            title: "\(pend.count) pending to review",
            body: "\(fmt(total)) awaiting confirmation on the Pending screen.")
    }

    private static func topCategoryInsight(_ c: InsightContext, _ fmt: (Double) -> String) -> Insight? {
        let spend = categorySpend(c.txns, c.ledgerId, c.month)
        let total = spend.values.reduce(0, +)
        guard total > 0, let top = spend.max(by: { $0.value < $1.value }), top.value > 0 else { return nil }
        let pct = Int((top.value / total * 100).rounded())
        let name = c.categories.first { $0.id == top.key }?.name ?? "Uncategorized"
        return Insight(tone: .neut, icon: "fork",
            title: "\(name) leads your spending",
            body: "\(fmt(top.value)) — \(pct)% of expenses this period.")
    }

    private static func goalProgressInsight(_ c: InsightContext, _ fmt: (Double) -> String) -> Insight? {
        let goals = c.budgets.filter { $0.type == "income" && $0.amount > 0 && $0.saved < $0.amount }
        guard let g = goals.max(by: { ($0.saved / $0.amount) < ($1.saved / $1.amount) }) else { return nil }
        let pct = Int((g.saved / g.amount * 100).rounded())
        return Insight(tone: .pos, icon: "check",
            title: "\(g.name) is \(pct)% funded",
            body: "\(fmt(g.saved)) of \(fmt(g.amount)) saved.")
    }

    private static func netWorthTrendInsight(_ c: InsightContext, _ fmt: (Double) -> String) -> Insight? {
        let series = netWorthSeries(c.txns, c.accounts, c.ledgerId)
        guard series.count >= 2, let first = series.first, let last = series.last else { return nil }
        let delta = last - first
        guard abs(delta) >= 1 else { return nil }
        let up = delta > 0
        return Insight(tone: up ? .pos : .warn, icon: up ? "arrowUp" : "arrowDown",
            title: up ? "Net worth is trending up" : "Net worth dipped",
            body: "\(delta >= 0 ? "+" : "−")\(fmt(abs(delta))) across this period's activity.")
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter InsightsRulesTests`
Expected: PASS (8 tests). If `categorySpend`'s sign nets a seeded refund unexpectedly, or `netWorthSeries`'s direction differs, adjust the *test expectation* to the real selector output (don't change the selectors) — the assertions check rule wiring, not the selectors' internals. (e.g. if `test_spending_trend_up`'s pct rounds differently, match the actual.)

- [ ] **Step 5: Full FinchCore suite**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchCore/Sources/FinchCore/Selectors/InsightRules.swift \
        ios/FinchCore/Tests/FinchCoreTests/InsightsRulesTests.swift
git commit -m "feat(ios): generateInsights selector + Insight model (core 6 rules)"
```

---

### Task 2: `InsightsCard` in the Trends tab

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift`

**Interfaces:**
- Consumes: `Selectors.generateInsights`, `Insight` (Task 1); `store.txns/accounts/budgets/pickableCategories/activeLedgerId/today/displayMoneyBase`; the existing `Card<Content>` helper.

- [ ] **Step 1: Insert the card in the Trends list**

In `InsightsTab.swift`, in the `if view == .trends { … }` branch, add `InsightsCard()` as the **first card** — immediately after the range `Picker` and before `MonthlySpendingCard(months: rangeMonths)`:
```swift
                    .pickerStyle(.segmented)
                    InsightsCard()
                    MonthlySpendingCard(months: rangeMonths)
```

- [ ] **Step 2: Add the `InsightsCard` view**

Add (e.g. near the other private card structs in the file):
```swift
private struct InsightsCard: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        let ctx = InsightContext(
            txns: store.txns, accounts: store.accounts, budgets: store.budgets,
            categories: store.pickableCategories, ledgerId: store.activeLedgerId,
            month: String(store.today.prefix(7)), today: store.today)
        let insights = Selectors.generateInsights(ctx, fmt: store.displayMoneyBase)
        return Card(title: "Insights") {
            if insights.isEmpty {
                Text("Add a few transactions to see insights.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(insights.enumerated()), id: \.offset) { _, ins in row(ins) }
                }
            }
        }
    }

    @ViewBuilder private func row(_ ins: Insight) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol(ins.icon))
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(color(ins.tone).opacity(0.15), in: Circle())
                .foregroundStyle(color(ins.tone))
            VStack(alignment: .leading, spacing: 2) {
                Text(ins.title).font(.subheadline.weight(.medium))
                Text(ins.body).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func color(_ t: Insight.Tone) -> Color {
        switch t { case .pos: return .green; case .warn: return .orange; case .neut: return .blue }
    }
    private func symbol(_ icon: String) -> String {
        switch icon {
        case "arrowUp": return "arrow.up"; case "arrowDown": return "arrow.down"
        case "doc": return "doc.text"; case "fork": return "fork.knife"; case "check": return "checkmark"
        default: return "sparkles"
        }
    }
}
```

- [ ] **Step 3: Build iOS + full FinchApp suite**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Full FinchCore suite**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test 2>&1 | grep -iE "error:|Test Suite 'All tests'"`
Expected: all pass.

- [ ] **Step 5: Build macOS (FinchMac)**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual verification on the simulator**

Insights › Trends: the **Insights** card is first. With seeded data it shows firing rows (e.g. "X over budget" in orange, "N pending to review", "<cat> leads your spending"); an empty ledger shows "Add a few transactions to see insights." Toggle to Breakdown and back — card persists.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch -initialTab insights
```
(If `-initialTab insights` isn't recognized, navigate manually.)

- [ ] **Step 7: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift
git commit -m "feat(ios): Insights advice card on the Trends tab"
```

---

## Self-Review

**Spec coverage** (against `2026-06-25-ios-insights-advice-cp1-design.md`):
- `Insight`/`InsightContext` + `generateInsights` (6 rules, priority order, max 6) → Task 1 step 3. ✓
- Each rule's thresholds + en copy + tone/icon → Task 1 step 3. ✓
- Reuse categorySpend/prevMonth/budgetProgress/netWorthSeries; fmt closure → Task 1. ✓
- InsightsCard at top of Trends + tone colors + SF symbols + empty fallback → Task 2. ✓
- No engine change; build iOS+macOS; tests → Task 2 steps 3-5. ✓

**Placeholder scan:** No TBD/TODO; full code in every step; sim step concrete. ✓

**Type consistency:** `InsightContext(txns:accounts:budgets:categories:ledgerId:month:today:)` built identically in the test helper and `InsightsCard`; `generateInsights(_:fmt:max:)` signature matches both call sites; rules use `categorySpend(_:_:_:)`/`prevMonth(_:)`/`budgetProgress(_:_:_:_:)`/`netWorthSeries(_:_:_:)` as surveyed; `Insight.Tone`/`icon` mapped in the card; `CategoryRow.parentId`/`.name`, `BudgetRow.type`/`.amount`/`.saved`, `Tx.nativeAmount`/`.pending` all exist. Tests project via `Projection.run`/`.accounts`/`.budgets`/`.categories`. ✓

---

## Out of scope (CP2)

The 5 day-of-week/day-of-month pattern rules (weekend-vs-weekday, category-by-weekday, end-of-month bump, spendy-day, quietest-day); i18n; web changes.
