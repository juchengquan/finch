# Budget manual order — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (or executing-plans). Checkbox steps.

**Goal:** Long-press-drag budgets within a group (Accounts-style), persisted per-ledger via `app_state` (`budgetOrderByLedger`) — no schema change.

**Architecture:** New `setBudgetOrder` action + projection reader (mirrors `displayCurrencyByLedger` at every layer) → FinchStore plumb → ViewHelpers ordering → BudgetsTab `.onMove`. Spec: `plans/ios-macos/2026-07-17-budget-order-design.md` (all code blocks live there — copy verbatim).

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS) `** BUILD SUCCEEDED **`; the new unit test + existing FinchCore tests must pass. No `Co-Authored-By`. **No schema change** — app_state only. PR → `feat/frontend`.

---

### Task 1: Engine — action + projection + unit test

**Files:**
- Modify `ios/FinchCore/Sources/FinchCore/Store/ActionName.swift` — `case setBudgetOrder` next to `setDisplayCurrency` (~line 112).
- Modify `ios/FinchCore/Sources/FinchCore/Store/Domain/App.swift` — handler entry `.setBudgetOrder: setBudgetOrder` in `handlers` + the `setBudgetOrder` func from the spec (place after `setDisplayCurrency`, ~line 82).
- Modify `ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift` — `budgetOrderByLedger(dbQueue:)` mirroring the `displayCurrencyByLedger` reader (~line 76): same shape, key `'budgetOrderByLedger'`, decode `[String: [String]]`.
- Test `ios/FinchCore/Tests/FinchCoreTests/` — add `BudgetOrderTests.swift` (mirror an existing test file's setup, e.g. how others build a `DatabaseQueue`/seed via `TestSeed`):

```swift
import XCTest
@testable import FinchCore

final class BudgetOrderTests: XCTestCase {
    func test_setBudgetOrder_roundTrips_andMergesPerLedger() throws {
        let q = try TestSeed.emptyDB()   // ← use the suite's existing helper; read TestSeed.swift and mirror its idiom
        try Apply.apply(dbQueue: q, action: "setBudgetOrder",
                        args: Args(["ledgerId": .string("personal"), "budgetIds": .array([.string("b2"), .string("b1")])]))
        try Apply.apply(dbQueue: q, action: "setBudgetOrder",
                        args: Args(["ledgerId": .string("travel"), "budgetIds": .array([.string("t1")])]))
        let map = try Projection.budgetOrderByLedger(dbQueue: q)
        XCTAssertEqual(map["personal"], ["b2", "b1"])
        XCTAssertEqual(map["travel"], ["t1"])
    }
}
```
(If `TestSeed.emptyDB()` isn't the actual helper name, read `TestSeed.swift` and use the suite's real bootstrap; if `Apply.apply` takes `ActionName` not `String`, match the suite's call style.)

- [ ] **Step 1:** the three engine edits. **Step 2:** the test; run `xcodebuild test … -only-testing:FinchCoreTests/BudgetOrderTests` (or the suite's standard invocation — check how CI/tests are run, `bun`-free) — must pass. **Step 3:** commit (engine + test): `feat(ios-core): setBudgetOrder action — per-ledger manual budget order in app_state`.

---

### Task 2: Store + UI

**Files:**
- Modify `ios/FinchApp/Sources/FinchApp/FinchStore.swift` — `var budgetOrderByLedger: [String: [String]] = [:]` next to `displayCurrencyByLedger` (~line 69); in the refresh path (~line 218) read `Projection.budgetOrderByLedger(dbQueue: q)` and assign alongside the others (~line 224).
- Modify `ios/FinchApp/Sources/FinchApp/FinchStore+ViewHelpers.swift` — add `applyBudgetOrder` (spec code) and wrap the returns of `budgets(in:)` (~line 205) and `ungroupedBudgets`.
- Modify `ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift` — `.onMove { moveBudgets(in: groupName, from: $0, to: $1) }` on the grouped ForEach (~line 205) and the ungrouped ForEach (group `"Ungrouped"`); add `moveBudgets` (spec code) next to `delete(_:)`.

- [ ] **Step 1:** the three files. **Step 2:** build iOS + macOS (standard commands) — both `** BUILD SUCCEEDED **`. **Step 3:** commit: `feat(ios): drag-reorder budgets within a group (Accounts-style), persisted per ledger`.

---

### Task 3: Verification (controller)

- [ ] Build to a known path, install (keep data), then DB-proof the full loop: `sqlite3` insert an order via the action path is impractical — instead write `app_state.budgetOrderByLedger` directly reversing a group's ids, relaunch, screenshot: the group renders reversed; then confirm a fresh budget appends at the end of its group. Human drag pass post-merge.

---

## Self-review notes
- Layer symmetry with displayCurrencyByLedger verified at every step (action/handler/projection/store/UI). ✓
- `budgets(in:)` maps nil→"Ungrouped" so `moveBudgets(in: "Ungrouped")` works for the bare section. `guard !searchActive` prevents filtered-index misalignment. New budgets (ids not in the saved list) keep created_at order, appended — stable via offset tiebreak. ✓
- No schema/pack change; web unaffected (ignores the key). No new user-facing strings. ✓
