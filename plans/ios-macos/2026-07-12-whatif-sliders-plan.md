# What-If Sliders (web #411 port) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the web's what-if sliders to iOS — a `FinchCore` `whatIfBaseline` selector (exact port, web tests as contract) + a `WhatIfCard` on Insights with per-category 5%-step sliders and savings math.

**Architecture:** Task 1 ports the pure selector into `FinchCore.Selectors` TDD-first (the web's 4 tests translated verbatim). Task 2 adds the SwiftUI card after `SavingsRateCard`, all money through `store.displayMoneyBase` (privacy-masked for free), cuts in `@State` only.

**Tech Stack:** Swift / SwiftUI; FinchCore is SwiftPM (`swift test`); XcodeGen for the app. Spec: `plans/ios-macos/2026-07-12-whatif-sliders-spec.md`.

## Global Constraints

- Selector semantics must match web `whatIfBaseline` exactly: window = up to `windowMonths` (default 3) trailing complete months **that have spend** (empty months dropped); fallback to the anchor month; `nil` when no spend anywhere or categories end empty; categories = top-`topN` (default 5) by `avgMonthly` desc, `r2`-rounded, positive only; `avgIncome`/`avgSpend` = window sums ÷ window length (pending/transfers/other ledgers excluded via existing helpers).
- Card: 5%-step sliders (0…100); cuts are `@State` — **nothing persists**; all amounts via `store.displayMoneyBase`; card placed after `SavingsRateCard()` in the stack.
- No changes to other selectors/cards; no new dependencies; no zh-Hans catalog work.
- Build BOTH `FinchApp` (iOS) and `FinchMac` (macOS). Known trap: a large `InsightsTab` body can hit the macOS "unable to type-check in reasonable time" error — the card code below is already decomposed into `content`/`row` subview funcs; if macOS still balks, extract further rather than trimming behavior.
- Run from `ios/` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `xcodegen generate` in a fresh worktree; sim fallback `id=<udid>` of a booted device (`finch-fresh-6` exists).

---

### Task 1: `Selectors.whatIfBaseline` (exact port, TDD)

**Files:**
- Create: `ios/FinchCore/Sources/FinchCore/Selectors/WhatIf.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests/WhatIfTests.swift` (create)

**Interfaces:**
- Consumes (existing, all verified): `Selectors.categorySpend(_:_:_:)`, `monthsBack(_:_:)` (oldest-first), `prevMonth(_:)`, `ledgerOf/kindOf/isSpend`, `r2(_:)`; `Tx` memberwise init.
- Produces (consumed by Task 2): `Selectors.WhatIfBaseline` (`months: [String]`, `categories: [Category{categoryId, avgMonthly}]`, `avgIncome`, `avgSpend`; all `Equatable`) and `Selectors.whatIfBaseline(_ txns: [Tx], _ ledgerId: String, _ anchorMonth: String, windowMonths: Int = 3, topN: Int = 5) -> WhatIfBaseline?`.

- [ ] **Step 1: Write the failing tests (the web's 4 cases, translated)**

Create `ios/FinchCore/Tests/FinchCoreTests/WhatIfTests.swift`:

```swift
import XCTest
@testable import FinchCore

final class WhatIfTests: XCTestCase {
    private func tx(_ id: String, _ amount: Double, _ date: String,
                    cat: String? = "food", kind: String = "expense",
                    pending: Bool = false, ledger: String = "personal") -> Tx {
        Tx(id: id, merchant: "m", category: cat, amount: amount, account: "cc", date: date,
           pending: pending, ledgerId: ledger, kind: kind)
    }

    func test_averagesOverTrailingCompleteMonths() {
        let txns = [
            tx("1", -999, "2026-05-03"),                          // partial anchor month — excluded
            tx("2", -90, "2026-04-10"),
            tx("3", -30, "2026-04-12", cat: "transport"),
            tx("4", -110, "2026-03-15"),
            tx("5", 500, "2026-03-20", cat: "salary", kind: "income"),
        ]
        let b = Selectors.whatIfBaseline(txns, "personal", "2026-05")!
        XCTAssertEqual(b.months, ["2026-03", "2026-04"])
        XCTAssertEqual(b.categories[0], .init(categoryId: "food", avgMonthly: 100))      // (110+90)/2
        XCTAssertEqual(b.categories[1], .init(categoryId: "transport", avgMonthly: 15))  // 30/2
        XCTAssertEqual(b.avgSpend, 115)      // (110+90+30)/2
        XCTAssertEqual(b.avgIncome, 250)     // 500/2
    }

    func test_fallsBackToAnchorMonthWhenNoCompleteMonthHasSpend() {
        let b = Selectors.whatIfBaseline([tx("1", -80, "2026-05-03")], "personal", "2026-05")!
        XCTAssertEqual(b.months, ["2026-05"])
        XCTAssertEqual(b.categories, [.init(categoryId: "food", avgMonthly: 80)])
    }

    func test_nilWithoutSpend_pendingAndOtherLedgersIgnored() {
        XCTAssertNil(Selectors.whatIfBaseline([], "personal", "2026-05"))
        XCTAssertNil(Selectors.whatIfBaseline([tx("1", -10, "2026-04-10", pending: true)], "personal", "2026-05"))
        XCTAssertNil(Selectors.whatIfBaseline([tx("1", -10, "2026-04-10", ledger: "family")], "personal", "2026-05"))
        XCTAssertNil(Selectors.whatIfBaseline(
            [tx("1", 100, "2026-04-02", cat: "salary", kind: "income")], "personal", "2026-05"))
    }

    func test_topNCapSortedDesc_refundsNetAgainstSpend() {
        var txns: [Tx] = []
        for (i, cat) in ["a", "b", "c", "d", "e", "f"].enumerated() {
            txns.append(tx("c\(i)", Double(-(600 - i * 100)), "2026-04-05", cat: cat))   // a:600 … f:100
        }
        txns.append(tx("r", 50, "2026-04-20", cat: "a", kind: "refund"))                  // nets a → 550
        let b = Selectors.whatIfBaseline(txns, "personal", "2026-05", topN: 5)!
        XCTAssertEqual(b.categories.count, 5)
        XCTAssertEqual(b.categories.first, .init(categoryId: "a", avgMonthly: 550))
        XCTAssertEqual(b.categories.map(\.categoryId), ["a", "b", "c", "d", "e"])         // f (100) dropped
    }
}
```

- [ ] **Step 2: Run them to confirm they fail**

```bash
cd ios && swift test --filter WhatIfTests 2>&1 | tail -5
```
Expected: FAIL to compile — `whatIfBaseline`/`WhatIfBaseline` don't exist. (If a stale-toolchain artifact appears, `swift package clean` first.)

- [ ] **Step 3: Create the selector**

Create `ios/FinchCore/Sources/FinchCore/Selectors/WhatIf.swift`:

```swift
import Foundation

// What-if baseline — average monthly spend per category over the trailing
// complete months, plus average income/spend totals (port of the web's
// whatIfBaseline, #411 / FEATURE_IDEAS §3.3). The Insights what-if card runs
// interactive hypotheticals ("cut dining 30%") against this baseline; the
// slider math itself is trivial and lives in the card.
extension Selectors {
    public struct WhatIfBaseline: Equatable, Sendable {
        public struct Category: Equatable, Sendable {
            public let categoryId: String
            public let avgMonthly: Double
            public init(categoryId: String, avgMonthly: Double) {
                self.categoryId = categoryId; self.avgMonthly = avgMonthly
            }
        }
        /// Months (YYYY-MM) the averages cover, oldest first.
        public let months: [String]
        /// Top categories by average monthly spend, descending (positive amounts).
        public let categories: [Category]
        /// Average monthly confirmed income over the window.
        public let avgIncome: Double
        /// Average total monthly spend over the window (all categories, not just top-N).
        public let avgSpend: Double
    }

    /// Baseline for the what-if sliders: category spend averaged over up to
    /// `windowMonths` complete months before `anchorMonth` (the current, likely
    /// partial, month). Months with no confirmed spend are dropped so a fresh
    /// ledger isn't diluted toward zero; when no complete month has data the
    /// anchor month itself is the (1-month) window. Returns nil when there's no
    /// spend anywhere to build a baseline from.
    public static func whatIfBaseline(_ txns: [Tx], _ ledgerId: String, _ anchorMonth: String,
                                      windowMonths: Int = 3, topN: Int = 5) -> WhatIfBaseline? {
        if anchorMonth.isEmpty { return nil }
        func hasSpend(_ by: [String: Double]) -> Bool { by.values.contains { $0 > 0 } }

        // Trailing complete months with data; fall back to the anchor month.
        let candidates = monthsBack(prevMonth(anchorMonth), windowMonths)
        var window: [(m: String, by: [String: Double])] = candidates
            .map { ($0, categorySpend(txns, ledgerId, $0)) }
            .filter { hasSpend($0.by) }
        if window.isEmpty {
            let by = categorySpend(txns, ledgerId, anchorMonth)
            if !hasSpend(by) { return nil }
            window = [(anchorMonth, by)]
        }

        let n = Double(window.count)
        var totals: [String: Double] = [:]
        for (_, by) in window {
            for (cat, v) in by { totals[cat, default: 0] += v }
        }
        // Web sorts by value desc; ties get a stable id tiebreak here so the
        // result is deterministic (Swift's sort is not guaranteed stable).
        let categories = totals
            .map { WhatIfBaseline.Category(categoryId: $0.key, avgMonthly: r2($0.value / n)) }
            .filter { $0.avgMonthly > 0 }
            .sorted { $0.avgMonthly == $1.avgMonthly ? $0.categoryId < $1.categoryId
                                                     : $0.avgMonthly > $1.avgMonthly }
            .prefix(topN)
        if categories.isEmpty { return nil }

        let monthSet = Set(window.map(\.m))
        var incomeSum = 0.0
        var spendSum = 0.0
        for t in txns {
            if ledgerOf(t) != ledgerId || (t.pending ?? false) { continue }
            if !monthSet.contains(String(t.date.prefix(7))) { continue }
            let k = kindOf(t)
            if k == "income" { incomeSum += t.amount }
            else if isSpend(t) { spendSum += -t.amount }
        }

        return WhatIfBaseline(months: window.map(\.m), categories: Array(categories),
                              avgIncome: r2(incomeSum / n), avgSpend: r2(spendSum / n))
    }
}
```

- [ ] **Step 4: Run the tests to confirm they pass (+ full FinchCore suite for regressions)**

```bash
cd ios && swift test --filter WhatIfTests 2>&1 | tail -3
swift test 2>&1 | tail -3
```
Expected: `Executed 4 tests, with 0 failures` for the filter; full suite green.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Selectors/WhatIf.swift \
        ios/FinchCore/Tests/FinchCoreTests/WhatIfTests.swift
git commit -m "feat(core): whatIfBaseline selector — what-if sliders baseline (web #411 port)"
```

---

### Task 2: `WhatIfCard` on Insights

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift` (insert `WhatIfCard()` in the stack after `SavingsRateCard()` at ~line 39; add the struct after `SavingsRateCard`'s definition ~line 445)

**Interfaces:**
- Consumes (Task 1): `Selectors.whatIfBaseline(_:_:_:)`, `Selectors.WhatIfBaseline(.Category)`; existing `Card`, `store.displayMoneyBase`, `store.categoryName(_:)`.

- [ ] **Step 1: Insert the card into the stack**

Change (~line 39):
```swift
                                SavingsRateCard()
                                CategoryDeltasCard()
```
to:
```swift
                                SavingsRateCard()
                                WhatIfCard()
                                CategoryDeltasCard()
```

- [ ] **Step 2: Add the `WhatIfCard` struct (after `SavingsRateCard`'s definition)**

```swift
/// What-if sliders — interactive category-cut hypotheticals over a real-history
/// baseline (web parity: #411). Drag a category's slider to a % cut and see the
/// monthly/annual savings plus the effect on average monthly net. Pure client
/// math — cuts are @State only; nothing persists.
private struct WhatIfCard: View {
    @EnvironmentObject private var store: FinchStore
    @State private var cuts: [String: Double] = [:]

    var body: some View {
        let baseline = Selectors.whatIfBaseline(store.txns, store.activeLedgerId, String(store.today.prefix(7)))
        Card(title: "What if…") {
            if let b = baseline {
                content(b)
            } else {
                Text("Not enough spending history yet").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func content(_ b: Selectors.WhatIfBaseline) -> some View {
        let monthlySave = b.categories.reduce(0.0) { $0 + $1.avgMonthly * (cuts[$1.categoryId] ?? 0) / 100 }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Based on your last \(b.months.count) month\(b.months.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if monthlySave > 0 {
                    Button("Reset") { cuts = [:] }.font(.caption)
                }
            }
            ForEach(b.categories, id: \.categoryId) { c in row(c) }
            if monthlySave > 0 {
                Divider()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(store.displayMoneyBase(monthlySave * 12)).font(.title3).fontWeight(.semibold)
                    Text("per year").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(store.displayMoneyBase(monthlySave))/mo").font(.caption).foregroundStyle(.secondary)
                }
                let netBefore = b.avgIncome - b.avgSpend
                Text("Net: \(store.displayMoneyBase(netBefore)) → \(store.displayMoneyBase(netBefore + monthlySave))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Drag a slider to try a cut.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func row(_ c: Selectors.WhatIfBaseline.Category) -> some View {
        let pct = cuts[c.categoryId] ?? 0
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(store.categoryName(c.categoryId) ?? c.categoryId)
                Spacer()
                Text("avg \(store.displayMoneyBase(c.avgMonthly))/mo").font(.caption).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { cuts[c.categoryId] ?? 0 },
                                  set: { cuts[c.categoryId] = $0 }),
                   in: 0...100, step: 5)
                .accessibilityLabel("Cut \(store.categoryName(c.categoryId) ?? c.categoryId)")
                .accessibilityValue("\(Int(pct)) percent")
            if pct > 0 {
                Text("cut \(Int(pct))% → saves ~\(store.displayMoneyBase(c.avgMonthly * pct / 100))/mo")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 3: Build iOS + macOS + run FinchAppTests (regression)**

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
Expected: both builds SUCCEED (if macOS hits the type-check-time error, extract `content`/`row` further into named subviews); tests green.

- [ ] **Step 4: Simulator visual check**

Install + launch into Insights (per the `ios-build-launch` skill; the sim has demo data — if not, `simctl uninstall` first so the seed runs). Verify: the card appears after the savings-rate ring with top-category rows + sliders; dragging updates the row save-line and the annual/monthly/net summary live; Reset clears; with privacy mode on (Settings eye or `defaults write com.juchengquan.finch finch.privacy -bool YES` + relaunch) the amounts read `••••` while sliders still work.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/InsightsTab.swift
git commit -m "feat(ios): What-if sliders card on Insights (web #411 port)"
```

---

## Self-Review

**1. Spec coverage:** selector exact-port semantics + 4 verbatim tests → Task 1; card placement/5%-steps/summary/Reset/@State-only/privacy-via-displayMoneyBase/empty state → Task 2; builds + sim check → Task 2 Steps 3-4; non-goals untouched. ✅
**2. Placeholder scan:** none — full code + commands with expected output in every step.
**3. Type consistency:** `Selectors.WhatIfBaseline(.Category)` field names/init match between Task 1 code, Task 1 tests (`.init(categoryId:avgMonthly:)`), and Task 2 usage (`c.categoryId`, `c.avgMonthly`, `b.months/categories/avgIncome/avgSpend`). One deliberate deviation is documented in-code: a stable id tiebreak on equal `avgMonthly` (web's sort is unstable; determinism helps tests).
