# Budgets Page UI Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich the iOS/macOS Budgets tab — a summary card that shows remaining-to-spend, an overall banded bar, and an "N over" badge (with savings goals split out), plus a per-row "remaining" figure.

**Architecture:** A pure, unit-tested `BudgetSummary.compute` aggregates per-budget figures (goals excluded from spend totals); a `FinchStore.budgetSummary` wraps it against live state; a `BudgetSummaryCard` renders it; `BudgetRowView`'s caption gains the remaining figure. No engine change — `Selectors.budgetProgress` already returns `remaining`/`over`.

**Tech Stack:** SwiftUI (iOS 17 / macOS 14 floor); FinchCore (`BudgetRow`, `Selectors.budgetProgress`); XCTest; XcodeGen; `xcodebuild`.

## Global Constraints

- **Worktree / branch:** `/tmp/finch-budui` on `feat/ios-budgets-ui` (off `origin/feat/frontend`). PR targets `feat/frontend`.
- **Environment:** `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before any `xcodebuild`/`xcodegen`; run `xcodegen generate` (from `/tmp/finch-budui/ios`) after adding any new file. Sim `ios-finch2`; iOS `-derivedDataPath /tmp/dd-bud`, mac `/tmp/dd-budmac`.
- **Commits:** no `Co-Authored-By` trailer. `feat(ios): …` subjects.
- **No engine/schema/parity/web change** — FinchApp only. Do not touch `FinchCore`.
- **Money is privacy-aware:** every amount shown routes `store.displayMoneyBase(_ baseAmount: Double) -> String`. Never call `Money.format` in a view. Progress bars (ratios) stay visible under privacy.
- **Goal definition (verbatim):** a budget is a **goal** when `type == "income" && isRecurring == 0`; everything else is a **spend** budget. `Selectors.budgetProgress` sets `over` only for `type == "expense"`, and `remaining = base − used` (so a goal's remaining is `target − saved`).
- **SwiftUI-first** (no UIKit).

## File Map

| File | Task | Responsibility |
|------|------|----------------|
| `ios/FinchApp/Sources/FinchApp/Common/BudgetSummary.swift` | 1 (create) | Pure `BudgetSummary` value + `compute` + shared `BudgetThreshold.color` |
| `ios/FinchApp/Tests/FinchAppTests/BudgetSummaryTests.swift` | 1 (create) | Unit tests for `compute` + `BudgetThreshold.color` |
| `ios/FinchApp/Sources/FinchApp/FinchStore+ViewHelpers.swift` | 2 (modify) | `budgetSummary` wrapper; remove `budgetTotalsDisplay` |
| `ios/FinchApp/Sources/FinchApp/Tabs/BudgetSummaryCard.swift` | 2 (create) | The summary-card view |
| `ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift` | 2, 3 (modify) | `summarySection` → card (T2); `BudgetRowView` caption + threshold (T3) |

---

### Task 1: `BudgetSummary` pure helper + `BudgetThreshold.color` + tests

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Common/BudgetSummary.swift`
- Create: `ios/FinchApp/Tests/FinchAppTests/BudgetSummaryTests.swift`

**Interfaces:**
- Consumes: `FinchCore.BudgetRow` (fields `type: String`, `isRecurring: Int`).
- Produces: `struct BudgetSummary` (fields below); `static func BudgetSummary.compute(_ budgets: [BudgetRow], progress: (BudgetRow) -> (used: Double, base: Double, over: Bool)) -> BudgetSummary`; `enum BudgetThreshold { static func color(pct: Int) -> Color }`. Task 2 calls both; Task 3 calls `BudgetThreshold.color`.

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchApp/Tests/FinchAppTests/BudgetSummaryTests.swift`:

```swift
import XCTest
import FinchCore
@testable import FinchApp

final class BudgetSummaryTests: XCTestCase {
    /// Minimal BudgetRow factory — only `type`/`isRecurring` matter to `compute`.
    private func budget(_ id: String, type: String = "expense", isRecurring: Int = 1) -> BudgetRow {
        BudgetRow(id: id, ledgerId: "L", groupId: nil, name: id, type: type, amount: 0, saved: 0,
                  carryForward: 0, frequency: "monthly", startDate: "2026-01-01", endDate: nil,
                  isRecurring: isRecurring, rollover: 0, rolloverLimit: nil, pendingAmount: nil,
                  lastRolledPeriod: nil, accountIds: [], categoryIds: [], warningPct: 80)
    }

    func test_mixed_spend_and_goal_excludes_goal_from_spend() {
        let budgets = [budget("under"), budget("over"), budget("goal", type: "income", isRecurring: 0)]
        let prog: [String: (used: Double, base: Double, over: Bool)] = [
            "under": (71.20, 600, false),
            "over":  (1850, 1500, true),
            "goal":  (650, 2000, false),
        ]
        let s = BudgetSummary.compute(budgets) { prog[$0.id]! }
        XCTAssertEqual(s.spentBase, 1921.20, accuracy: 0.001)
        XCTAssertEqual(s.budgetBase, 2100, accuracy: 0.001)
        XCTAssertEqual(s.remainingBase, 178.80, accuracy: 0.001)
        XCTAssertEqual(s.overCount, 1)
        XCTAssertEqual(s.goalSavedBase, 650, accuracy: 0.001)
        XCTAssertEqual(s.goalTargetBase, 2000, accuracy: 0.001)
        XCTAssertTrue(s.hasSpend)
        XCTAssertTrue(s.hasGoals)
    }

    func test_recurring_income_is_spend_not_goal() {
        // income + recurring is NOT a goal — counts as spend.
        let s = BudgetSummary.compute([budget("inc", type: "income", isRecurring: 1)]) { _ in (500, 1000, false) }
        XCTAssertEqual(s.spentBase, 500, accuracy: 0.001)
        XCTAssertTrue(s.hasSpend)
        XCTAssertFalse(s.hasGoals)
    }

    func test_goals_only() {
        let s = BudgetSummary.compute([budget("g", type: "income", isRecurring: 0)]) { _ in (650, 2000, false) }
        XCTAssertFalse(s.hasSpend)
        XCTAssertTrue(s.hasGoals)
        XCTAssertEqual(s.budgetBase, 0, accuracy: 0.001)
        XCTAssertEqual(s.overCount, 0)
    }

    func test_empty() {
        let s = BudgetSummary.compute([]) { _ in (0, 0, false) }
        XCTAssertFalse(s.hasSpend)
        XCTAssertFalse(s.hasGoals)
        XCTAssertEqual(s.remainingBase, 0, accuracy: 0.001)
    }

    func test_threshold_bands() {
        XCTAssertEqual(BudgetThreshold.color(pct: 50), .green)
        XCTAssertEqual(BudgetThreshold.color(pct: 69), .green)
        XCTAssertEqual(BudgetThreshold.color(pct: 70), .yellow)
        XCTAssertEqual(BudgetThreshold.color(pct: 90), .yellow)
        XCTAssertEqual(BudgetThreshold.color(pct: 91), .red)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /tmp/finch-budui/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/BudgetSummaryTests 2>&1 | grep -E "error:|cannot find|TEST SUCCEEDED|TEST FAILED"
```

Expected: FAIL — `cannot find 'BudgetSummary' in scope`.

- [ ] **Step 3: Implement `BudgetSummary` + `BudgetThreshold`**

Create `ios/FinchApp/Sources/FinchApp/Common/BudgetSummary.swift`:

```swift
import SwiftUI
import FinchCore

/// Ledger-wide budget health, split into spend vs. savings-goal totals. Pure and
/// unit-tested — `progress` is injected (the store passes `Selectors.budgetProgress`)
/// so this has no store/engine dependency. A budget is a GOAL when
/// `type == "income" && isRecurring == 0`; everything else is a SPEND budget.
struct BudgetSummary: Equatable {
    var spentBase: Double        // Σ used over spend budgets
    var budgetBase: Double       // Σ base over spend budgets
    var remainingBase: Double    // budgetBase − spentBase (negative when overspent)
    var overCount: Int           // # spend budgets currently over budget
    var goalSavedBase: Double    // Σ used (= saved) over goal budgets
    var goalTargetBase: Double   // Σ base (= target) over goal budgets
    var hasGoals: Bool
    var hasSpend: Bool

    static func compute(_ budgets: [BudgetRow],
                        progress: (BudgetRow) -> (used: Double, base: Double, over: Bool)) -> BudgetSummary {
        var spent = 0.0, budget = 0.0, overCount = 0
        var goalSaved = 0.0, goalTarget = 0.0
        var hasSpend = false, hasGoals = false
        for b in budgets {
            let p = progress(b)
            if b.type == "income" && b.isRecurring == 0 {      // goal
                hasGoals = true
                goalSaved += p.used
                goalTarget += p.base
            } else {                                           // spend
                hasSpend = true
                spent += p.used
                budget += p.base
                if p.over { overCount += 1 }
            }
        }
        return BudgetSummary(spentBase: spent, budgetBase: budget, remainingBase: budget - spent,
                             overCount: overCount, goalSavedBase: goalSaved, goalTargetBase: goalTarget,
                             hasGoals: hasGoals, hasSpend: hasSpend)
    }
}

/// The 3-color budget banding, shared by the summary bar and the rows so they agree.
/// pct is an INTEGER 0–100 (as `BudgetProgress.pct`): green < 70, yellow 70–90, red > 90.
enum BudgetThreshold {
    static func color(pct: Int) -> Color {
        pct > 90 ? .red : (pct >= 70 ? .yellow : .green)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /tmp/finch-budui/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/BudgetSummaryTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **` (5 tests).

- [ ] **Step 5: Commit**

```bash
cd /tmp/finch-budui && git add ios/FinchApp/Sources/FinchApp/Common/BudgetSummary.swift ios/FinchApp/Tests/FinchAppTests/BudgetSummaryTests.swift && git commit -m "feat(ios): pure BudgetSummary.compute + shared BudgetThreshold banding"
```

---

### Task 2: `budgetSummary` store helper + `BudgetSummaryCard` + wire the summary section

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/FinchStore+ViewHelpers.swift` (replace `budgetTotalsDisplay`, lines 225–232)
- Create: `ios/FinchApp/Sources/FinchApp/Tabs/BudgetSummaryCard.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift` (`summarySection`, lines 202–208)

**Interfaces:**
- Consumes: `BudgetSummary.compute`, `BudgetThreshold.color` (Task 1); `Selectors.budgetProgress`; `store.displayMoneyBase`.
- Produces: `FinchStore.budgetSummary: BudgetSummary`; `struct BudgetSummaryCard`. Both are terminal (used only by `BudgetsTab`).

- [ ] **Step 1: Add the `budgetSummary` store helper; remove `budgetTotalsDisplay`**

In `FinchStore+ViewHelpers.swift`, replace the `budgetTotalsDisplay` computed property (lines 225–232):

```swift
    public var budgetTotalsDisplay: (used: String, base: String) {
        var used = 0.0, base = 0.0
        for b in budgets {
            let p = Selectors.budgetProgress(b, txns, today, categoryNodes)
            used += p.used; base += p.base
        }
        return (displayMoneyBase(used), displayMoneyBase(base))
    }
```

with:

```swift
    /// Ledger-wide budget health for the Budgets summary card — spend totals with
    /// savings goals split out (see BudgetSummary). Raw base-currency doubles; the
    /// card formats via the privacy-aware displayMoneyBase.
    var budgetSummary: BudgetSummary {
        BudgetSummary.compute(budgets) { b in
            let p = Selectors.budgetProgress(b, txns, today, categoryNodes)
            return (p.used, p.base, p.over)
        }
    }
```

- [ ] **Step 2: Create the `BudgetSummaryCard` view**

Create `ios/FinchApp/Sources/FinchApp/Tabs/BudgetSummaryCard.swift`:

```swift
import SwiftUI
import FinchCore

/// The Budgets-tab health header: expense-budget remaining (hero) + overall
/// color-banded bar + spent/budget caption + an "N over" badge, with a separate
/// goals line. All amounts route store.displayMoneyBase (privacy-aware); the bar
/// is a ratio (no maskable amount). Replaces the old two-number StatusSummaryRow.
struct BudgetSummaryCard: View {
    @EnvironmentObject private var store: FinchStore
    let summary: BudgetSummary

    private var overallPct: Int {
        summary.budgetBase > 0 ? Int((summary.spentBase / summary.budgetBase * 100).rounded()) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if summary.hasSpend {
                HStack(alignment: .firstTextBaseline) {
                    if summary.remainingBase < 0 {
                        HStack(spacing: 4) {
                            Text(store.displayMoneyBase(-summary.remainingBase))
                                .font(.title2.weight(.semibold)).foregroundStyle(.red)
                            Text("over").font(.subheadline).foregroundStyle(.red)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Text(store.displayMoneyBase(summary.remainingBase))
                                .font(.title2.weight(.semibold))
                            Text("left to spend").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if summary.overCount > 0 {
                        Label("\(summary.overCount) over", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(.red)
                    }
                }
                ProgressView(value: min(summary.spentBase / max(summary.budgetBase, 0.01), 1.0))
                    .tint(BudgetThreshold.color(pct: overallPct))
                Text("\(store.displayMoneyBase(summary.spentBase)) spent · of \(store.displayMoneyBase(summary.budgetBase))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if summary.hasGoals {
                if summary.hasSpend { Divider() }
                Text("Goals · \(store.displayMoneyBase(summary.goalSavedBase)) of \(store.displayMoneyBase(summary.goalTargetBase)) saved")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 3: Wire the card into `BudgetsTab.summarySection`**

In `BudgetsTab.swift`, replace `summarySection` (lines 202–208):

```swift
    @ViewBuilder private var summarySection: some View {
        Section {
            let t = store.budgetTotalsDisplay
            StatusSummaryRow(leadingLabel: "Spent", leadingValue: t.used,
                             trailingLabel: "Budget", trailingValue: t.base)
        }
    }
```

with:

```swift
    @ViewBuilder private var summarySection: some View {
        Section { BudgetSummaryCard(summary: store.budgetSummary) }
    }
```

- [ ] **Step 4: Build FinchApp**

```bash
cd /tmp/finch-budui/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild build -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -derivedDataPath /tmp/dd-bud 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```

Expected: `** BUILD SUCCEEDED **`. (If `StatusSummaryRow` is now reported unused — it isn't; it's still used by the Accounts tab. Leave the type.)

- [ ] **Step 5: Build FinchMac**

```bash
cd /tmp/finch-budui/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodebuild build -scheme FinchMac -destination 'platform=macOS' -derivedDataPath /tmp/dd-budmac CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd /tmp/finch-budui && git add ios/FinchApp/Sources/FinchApp/FinchStore+ViewHelpers.swift ios/FinchApp/Sources/FinchApp/Tabs/BudgetSummaryCard.swift ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift && git commit -m "feat(ios): Budgets summary card — remaining, overall bar, over-count, goals split out"
```

---

### Task 3: `BudgetRowView` caption — add the remaining figure

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift` (`BudgetRowView`, lines 439–479)

**Interfaces:**
- Consumes: `BudgetThreshold.color` (Task 1); `store.displayMoneyBase`; `store.daysLeft(until:)`; `BudgetProgress` fields `remaining`, `over`, `pct`, `to`.
- Produces: nothing new (view-internal change).

- [ ] **Step 1: Replace the caption `HStack` and the private threshold helper**

In `BudgetRowView`, replace the caption `HStack` (lines 460–472):

```swift
            HStack {
                if isGoal {
                    Text("\(progress.pct)% saved")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("\(store.daysLeft(until: progress.to)) days left")
                        .font(.caption2).foregroundStyle(.secondary)
                    if progress.over {
                        Spacer()
                        Text("Over").font(.caption2).foregroundStyle(.red)
                    }
                }
            }
```

with:

```swift
            HStack(spacing: 0) {
                if isGoal {
                    if progress.remaining <= 0 {
                        Text("Goal reached").foregroundStyle(.green)
                    } else {
                        Text("\(store.displayMoneyBase(progress.remaining)) to go").foregroundStyle(.secondary)
                    }
                    Text(" · \(progress.pct)% saved").foregroundStyle(.secondary)
                } else {
                    if progress.over {
                        Text("\(store.displayMoneyBase(-progress.remaining)) over").foregroundStyle(.red)
                    } else {
                        Text("\(store.displayMoneyBase(progress.remaining)) left").foregroundStyle(.secondary)
                    }
                    Text(" · \(store.daysLeft(until: progress.to)) days left").foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
```

Then update the bar tint (line 459) to use the shared banding and delete the now-unused private helper (lines 475–478). Change:

```swift
                .tint(isGoal ? .green : thresholdColor(progress.pct))   // native enhancement
```
to:
```swift
                .tint(isGoal ? .green : BudgetThreshold.color(pct: progress.pct))   // native enhancement
```
and delete:
```swift
    /// Native 3-color banding (NOT web parity). pct is an INTEGER 0–100.
    private func thresholdColor(_ pct: Int) -> Color {
        pct > 90 ? .red : (pct >= 70 ? .yellow : .green)
    }
```

- [ ] **Step 2: Build FinchApp + FinchMac**

```bash
cd /tmp/finch-budui/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null
xcodebuild build -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -derivedDataPath /tmp/dd-bud 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
xcodebuild build -scheme FinchMac -destination 'platform=macOS' -derivedDataPath /tmp/dd-budmac CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```

Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the BudgetSummary tests (regression)**

```bash
cd /tmp/finch-budui/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/BudgetSummaryTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /tmp/finch-budui && git add ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift && git commit -m "feat(ios): budget rows show remaining / over / to-go in the caption"
```

---

## Manual sim verification (controller/human, after Task 3)

Install & launch to the Budgets tab (`xcrun simctl launch ios-finch2 com.juchengquan.finch -initialTab budgets`) and confirm on the demo data: the summary card shows "$1,071.27 left to spend", an overall bar, "1 over", and a "Goals · $650.00 of $2,000.00 saved" line; the **Rent** row reads "$350.00 over · 12 days left" (red), **Groceries** reads "$528.80 left · 12 days left", and **Vacation Fund** reads "…to go · 33% saved". Toggle privacy (eye) — amounts mask, bars stay.

## Out of scope

The "N over" badge is a static flag (no tap-to-filter); no row-density or typography refresh; no engine/schema/web change; zh-Hans strings for new copy follow the standard localization pass.

## Self-Review

**Spec coverage:** richer summary (T2 card: remaining hero, banded bar, over-count, goals line); goals split out (T1 `compute` goal filter, used by the card); better row info (T3 caption remaining/over/to-go + Goal-reached); shared banding (T1 `BudgetThreshold`, used by card T2 + row T3); no engine change (T1 injects a tuple closure over the existing `budgetProgress`); privacy (all amounts via `displayMoneyBase`); tests (T1); FinchApp + FinchMac builds (T2, T3). All covered.

**Placeholder scan:** none — complete code and exact anchors throughout.

**Type consistency:** `BudgetSummary` fields (`spentBase`, `budgetBase`, `remainingBase`, `overCount`, `goalSavedBase`, `goalTargetBase`, `hasGoals`, `hasSpend`) and `compute(_:progress:)`'s `(used, base, over)` tuple defined in T1 are used verbatim by `budgetSummary` (T2) and `BudgetSummaryCard` (T2). `BudgetThreshold.color(pct:)` (T1) is called by the card (T2) and the row (T3). `BudgetProgress.remaining/over/pct/to` match the struct at `Models.swift:218`.
