# Budgets per-account filter — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the (already-supported) account filter on budgets — a `BudgetSheet` account multi-select + a `BudgetDetailView` scope line — with a `budgetProgress` guard test.

**Architecture:** No engine/schema/projection/selector change. The account filter is already live (schema `account_ids`, `BudgetRow.accountIds`, `createBudget`/`updateBudget` persistence, `budgetProgress` account matching). (1) FinchCore: a guard test for the matching. (2) FinchApp: clone the category multi-select for accounts + show scope in detail.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), FinchCore, XcodeGen, XCTest.

## Global Constraints

- **No engine/schema/projection/`budgetProgress` change.** Matching is `(accountIds.isEmpty || tx.account ∈ accountIds) AND (categoryIds.isEmpty || tx.category ∈ categoryIds)`, both empty-means-all — already correct.
- Account source = `store.accounts` (active accounts); name `acct.name ?? "Account"`. Empty selection = all accounts.
- Persist `accountIds` exactly like `categoryIds` (JSON array via the `.array(...)` JSONValue), in both the update patch and create args.
- **Must build iOS AND macOS (FinchMac).** Sim `iPhone 17 Pro Max`. New files → `xcodegen generate`. FinchCore tests: `swift test`; FinchApp tests: `xcodebuild test`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit; **no `Co-Authored-By` trailer**.

---

## File Structure

**Create (tests):** `ios/FinchCore/Tests/FinchCoreTests/BudgetAccountFilterTests.swift`.
**Modify (FinchApp):** `ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetSheet.swift`, `ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetDetailView.swift`.

---

### Task 1: `budgetProgress` account-filter guard test (FinchCore)

**Files:**
- Create: `ios/FinchCore/Tests/FinchCoreTests/BudgetAccountFilterTests.swift`

**Interfaces:**
- Consumes: `Selectors.budgetProgress`, `Projection.budgets`/`Projection.run`, the `createAccount`/`addTransaction`/`createBudget` actions (existing).

- [ ] **Step 1: Write the test**

Create `ios/FinchCore/Tests/FinchCoreTests/BudgetAccountFilterTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class BudgetAccountFilterTests: XCTestCase {
    func test_budget_account_scope_vs_all() throws {
        let q = try TestSeed.base()   // l1 / a1 / c1
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("a2"), "ledgerId": .string("l1"), "name": .string("Savings"),
            "type": .string("checking"), "currency": .string("USD")]))

        let day = "2026-06-10"
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-100),
            "merchant": .string("M1"), "categoryId": .string("c1"), "date": .string(day), "skipRules": .bool(true)]))
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a2"), "amount": .double(-40),
            "merchant": .string("M2"), "categoryId": .string("c1"), "date": .string(day), "skipRules": .bool(true)]))

        // budget scoped to a1 only
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
            "id": .string("b1"), "ledgerId": .string("l1"), "name": .string("A1 only"), "type": .string("expense"),
            "amount": .double(1000), "frequency": .string("monthly"), "startDate": .string("2026-06-01"),
            "accountIds": .array([.string("a1")])]))
        // budget across all accounts (empty accountIds)
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
            "id": .string("b2"), "ledgerId": .string("l1"), "name": .string("All"), "type": .string("expense"),
            "amount": .double(1000), "frequency": .string("monthly"), "startDate": .string("2026-06-01")]))

        let budgets = try Projection.budgets(dbQueue: q, ledgerId: "l1")
        let txns = try Projection.run(dbQueue: q, ledgerId: "l1")
        let today = "2026-06-15"
        let b1 = try XCTUnwrap(budgets.first { $0.id == "b1" })
        let b2 = try XCTUnwrap(budgets.first { $0.id == "b2" })

        XCTAssertEqual(b1.accountIds, ["a1"])
        XCTAssertEqual(Selectors.budgetProgress(b1, txns, today).used, 100, accuracy: 0.001)  // a1 only
        XCTAssertEqual(Selectors.budgetProgress(b2, txns, today).used, 140, accuracy: 0.001)  // both
    }
}
```
(If `createAccount`'s args differ, mirror an existing `AccountCrudTests` create call. `startDate: "2026-06-01"` + monthly keeps the cycle window over June regardless of the wall clock.)

- [ ] **Step 2: Run the test**

Run: `cd /Users/blackmount8/_repository/finch/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && swift test --filter BudgetAccountFilterTests`
Expected: PASS (the matching already exists; this characterizes it). If `.used` differs, the budget cycle window or sign convention is off — STOP and report the actual values (do not change the selector).

- [ ] **Step 3: Full FinchCore suite**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test`
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchCore/Tests/FinchCoreTests/BudgetAccountFilterTests.swift
git commit -m "test(ios): guard budgetProgress account-filter matching (scoped vs all)"
```

---

### Task 2: Account multi-select in `BudgetSheet` + scope line in `BudgetDetailView`

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetSheet.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetDetailView.swift`

**Interfaces:**
- Consumes: `store.accounts` (`[AccountRow]`, `.name`/`.id`); `BudgetRow.accountIds`; the existing `categoryIds` persistence pattern.

- [ ] **Step 1: Add `selectedAccounts` state + prefill**

In `BudgetSheet`, add after `@State private var selectedCategories: Set<String>`:
```swift
    @State private var selectedAccounts: Set<String>
```
In `init`, add after the `_selectedCategories` line:
```swift
        _selectedAccounts = State(initialValue: Set(budget?.accountIds ?? []))
```

- [ ] **Step 2: Add the account section + toggle**

In `body`, immediately after the categories `Section { … } header: { … } footer: { … }` block, add:
```swift
                Section {
                    ForEach(store.accounts) { acct in
                        Button { toggleAccount(acct.id) } label: {
                            HStack {
                                Text(acct.name ?? "Account").foregroundStyle(.primary)
                                Spacer()
                                if selectedAccounts.contains(acct.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Accounts")
                } footer: {
                    Text("Leave empty to track all accounts.")
                }
```
Add the toggle helper next to `toggle(_:)`:
```swift
    private func toggleAccount(_ id: String) {
        if selectedAccounts.contains(id) { selectedAccounts.remove(id) } else { selectedAccounts.insert(id) }
    }
```

- [ ] **Step 3: Persist `accountIds` in `save()`**

In `save()`, after the `let categoryIds: JSONValue = …` line, add:
```swift
        let accountIds: JSONValue = .array(selectedAccounts.sorted().map { .string($0) })
```
In the **update** `patch` dictionary, add `"accountIds": accountIds` (alongside `"categoryIds": categoryIds`).
In the **create** branch, after the `if !selectedCategories.isEmpty { args["categoryIds"] = categoryIds }` line, add:
```swift
            if !selectedAccounts.isEmpty { args["accountIds"] = accountIds }
```

- [ ] **Step 4: Show account scope in `BudgetDetailView`**

In `BudgetDetailView.progress(_:_:)`, inside the VStack after the final `HStack { … date range … }`, add:
```swift
            if !b.accountIds.isEmpty {
                let names = b.accountIds.compactMap { id in store.accounts.first { $0.id == id }?.name }.joined(separator: ", ")
                if !names.isEmpty {
                    Text("Accounts: \(names)").font(.caption).foregroundStyle(.secondary)
                }
            }
```
(`progress` already receives the budget as its first parameter `b`.)

- [ ] **Step 5: Build iOS + full FinchApp suite**

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

- [ ] **Step 6: Full FinchCore suite**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test 2>&1 | grep -iE "error:|Test Suite 'All tests'"`
Expected: all pass (incl. Task 1's test).

- [ ] **Step 7: Build macOS (FinchMac)**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Manual verification on the simulator**

Budgets:
- Add/Edit a budget → an **Accounts** section lists the ledger's accounts; toggle one or more → Save.
- Re-open Edit → the account selection persists (checkmarks restored).
- Budget detail shows **"Accounts: …"** when accounts are selected (and nothing when empty = all).
- Spend on a non-selected account does **not** count toward the budget's used (toggle to confirm the used figure changes).

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch -initialTab budgets
```

- [ ] **Step 9: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetSheet.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetDetailView.swift
git commit -m "feat(ios): budgets per-account filter (account multi-select + detail scope)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-26-ios-budget-account-filter-design.md`):
- Account multi-select in `BudgetSheet` (state, prefill, section, toggle, persist in patch + create) → Task 2 steps 1-3. ✓
- `BudgetDetailView` scope line (only when non-empty) → Task 2 step 4. ✓
- `budgetProgress` account guard test (scoped vs all) → Task 1. ✓
- No engine/schema/selector change; build iOS+macOS → Task 2 steps 5-7. ✓

**Placeholder scan:** No TBD/TODO; full code in every step; sim step concrete. ✓

**Type consistency:** `selectedAccounts: Set<String>` + `toggleAccount(_:)` mirror `selectedCategories`/`toggle(_:)`; `accountIds: JSONValue = .array(...)` matches `categoryIds`; persisted as `"accountIds"` in patch + create (the keys `createBudget`/`updateBudget` already accept); `store.accounts` is `[AccountRow]` with `.id`/`.name`; `BudgetRow.accountIds` consumed in detail. The guard test uses `Selectors.budgetProgress`/`Projection.budgets`/`Projection.run`. ✓

---

## Out of scope

Engine/schema/projection/`budgetProgress` changes; category-scope display; budget add-form frequency additions.
