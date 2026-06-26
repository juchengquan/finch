# Opening-balance display — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Populate `AccountRow.openingBalanceBase` from the opening entry and show an "Opening balance" row in account detail.

**Architecture:** No schema/model change (the field already exists). (1) FinchCore: a correlated subquery in the accounts projection reads the `open-<id>` opening posting's `amount_base`; this also correctly feeds `Holdings` cost basis (latent fix). (2) FinchApp: an opening-balance row in `AccountDetailView`.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), FinchCore, XcodeGen, XCTest.

## Global Constraints

- **No schema/model change.** `AccountRow.openingBalanceBase: Double?` already exists; this only populates it.
- Opening balance source = the `open-<accountId>` opening entry's account-leg posting `amount_base` (base currency). NULL when no opening entry (opening was 0). `Projection.run` excludes opening entries, so it must be read from `postings` directly.
- Populating `openingBalanceBase` also feeds `Selectors.holdingValue` cost basis (currently 0) — **intended fix**. If a Holdings/Parity test now fails because cost basis includes the opening, update that test's expectation (do NOT revert the projection); report it.
- Detail-only display (opening balance is add-only). Display via `store.displayMoneyBase` (base amount).
- **Must build iOS AND macOS (FinchMac).** Sim `iPhone 17 Pro Max`. New files → `xcodegen generate`. FinchCore: `swift test`; FinchApp: `xcodebuild test`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit; **no `Co-Authored-By` trailer**.

---

## File Structure

**Modify (FinchCore):** `ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift` (accounts projection).
**Create (tests):** `ios/FinchCore/Tests/FinchCoreTests/OpeningBalanceProjectionTests.swift`.
**Modify (FinchApp):** `ios/FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift`.

---

### Task 1: Populate `openingBalanceBase` in the accounts projection

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests/OpeningBalanceProjectionTests.swift`

**Interfaces:**
- Produces: `AccountRow.openingBalanceBase` populated (base currency) for accounts with an opening entry; `nil` otherwise.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchCore/Tests/FinchCoreTests/OpeningBalanceProjectionTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class OpeningBalanceProjectionTests: XCTestCase {
    func test_projection_carries_opening_balance() throws {
        let q = try TestSeed.base()   // l1 (USD base)
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("a2"), "ledgerId": .string("l1"), "name": .string("Checking"),
            "type": .string("cash"), "currency": .string("USD"), "openingBalance": .double(500)]))
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("a3"), "ledgerId": .string("l1"), "name": .string("Empty"),
            "type": .string("cash"), "currency": .string("USD")]))   // no opening

        let accts = try Projection.accounts(dbQueue: q, ledgerId: "l1")
        let a2 = try XCTUnwrap(accts.first { $0.id == "a2" })
        let a3 = try XCTUnwrap(accts.first { $0.id == "a3" })
        XCTAssertEqual(a2.openingBalanceBase ?? -1, 500, accuracy: 0.001)
        XCTAssertNil(a3.openingBalanceBase)
    }
}
```
(If `TestSeed`'s l1 base currency isn't USD, set the account `currency` to the ledger base so `amount_base == 500`, or assert the actual converted value — report if it differs. If `createAccount` rejects `"cash"`, use a valid type: `savings`/`credit_card`/`investment`/`cash`/`fx`/`virtual`.)

- [ ] **Step 2: Run to verify failure**

Run: `cd /Users/blackmount8/_repository/finch/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && swift test --filter OpeningBalanceProjectionTests`
Expected: FAIL — `a2.openingBalanceBase` is `nil` (projection doesn't populate it yet).

- [ ] **Step 3: Add the subquery + map**

In `Projections+State.swift` `accountRows(...)`:
- In the SELECT, after `a.last_reconciled_balance AS lastReconciledBalance`, add a comma and the subquery so the column list reads:
  ```sql
                       a.last_reconciled_at AS lastReconciledAt, a.last_reconciled_balance AS lastReconciledBalance,
                       (SELECT p.amount_base FROM postings p
                          WHERE p.entry_id = 'open-' || a.id AND p.account_id = a.id
                          LIMIT 1) AS openingBalanceBase
  ```
- In the `AccountRow(...)` init call, insert `openingBalanceBase:` **before** `lastReconciledAt:` (matching the init's declared parameter order — `sortOrder, openingBalanceBase, lastReconciledAt, lastReconciledBalance`):
  ```swift
                    sortOrder: r["sortOrder"],
                    openingBalanceBase: r["openingBalanceBase"],
                    lastReconciledAt: r["lastReconciledAt"], lastReconciledBalance: r["lastReconciledBalance"])
  ```

- [ ] **Step 4: Run the test**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter OpeningBalanceProjectionTests`
Expected: PASS (2 assertions).

- [ ] **Step 5: Full FinchCore suite (Holdings/Parity regression)**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test`
Expected: all pass. **If a Holdings or Parity test now fails** because cost basis includes the opening balance, that is the intended fix — update the test's expected value to the correct (opening-inclusive) figure and note it in the report; do NOT revert the projection. If the failure is something else, STOP and report.

- [ ] **Step 6: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift \
        ios/FinchCore/Tests/FinchCoreTests/OpeningBalanceProjectionTests.swift
git commit -m "feat(ios): populate AccountRow.openingBalanceBase from the opening entry"
```

---

### Task 2: "Opening balance" row in `AccountDetailView`

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift`

**Interfaces:**
- Consumes: `AccountRow.openingBalanceBase` (Task 1); `store.displayMoneyBase`.

- [ ] **Step 1: Add the opening-balance row**

In `AccountDetailView.body`, the first `Section` currently reads:
```swift
                    Section {
                        header(account)
                        reconcileBadge(account)
                    }
```
Add the opening-balance row after `reconcileBadge(account)`:
```swift
                    Section {
                        header(account)
                        reconcileBadge(account)
                        if let ob = account.openingBalanceBase, ob != 0 {
                            LabeledContent("Opening balance", value: store.displayMoneyBase(ob))
                        }
                    }
```

- [ ] **Step 2: Build iOS + full FinchApp suite**

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

- [ ] **Step 3: Full FinchCore suite**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test 2>&1 | grep -iE "error:|Test Suite 'All tests'"`
Expected: all pass (incl. Task 1's test).

- [ ] **Step 4: Build macOS (FinchMac)**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual verification on the simulator**

Open an account created with an opening balance → its detail shows an **"Opening balance"** row (under the header/reconcile rows). An account with no opening balance shows no such row.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch -initialTab accounts
```

- [ ] **Step 6: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift
git commit -m "feat(ios): show opening balance in account detail"
```

---

## Self-Review

**Spec coverage** (against `2026-06-26-ios-opening-balance-display-design.md`):
- Populate `openingBalanceBase` via the opening-posting subquery → Task 1 step 3. ✓
- Projection test (carries it; nil when none) → Task 1 step 1. ✓
- Holdings cost-basis side effect verified via full suite → Task 1 step 5. ✓
- "Opening balance" row in AccountDetailView (non-zero only) → Task 2 step 1. ✓
- No schema/model change; build iOS+macOS → Task 2 steps 2-4. ✓

**Placeholder scan:** No TBD/TODO; full code in every step; sim step concrete. ✓

**Type consistency:** `openingBalanceBase: r["openingBalanceBase"]` placed in declared order (before `lastReconciledAt:`); `AccountRow.openingBalanceBase: Double?` already exists; `store.displayMoneyBase(Double)` consumed in detail; the subquery columns (`postings.entry_id`/`account_id`/`amount_base`) match the schema. ✓

---

## Out of scope

Editing the opening balance (add-only); Add/Edit-sheet display; schema/model changes; web changes.
