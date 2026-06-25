# Transaction kind reclassification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user change a transaction's kind (expense ↔ income ↔ refund) in the Edit sheet; the engine rebuilds the legs in place.

**Architecture:** No engine change — `updateTransaction` already accepts a `kind` patch + rebuilds single-account legs. (1) FinchCore tests lock that path for the net-new UI. (2) `EditTransactionSheet` gains a kind picker (gated to simple entries) that re-signs the amount + manages the refund link.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), FinchCore, XcodeGen, XCTest.

## Global Constraints

- **No engine/schema/action change.** `updateTransaction` (`Transactions.swift:324,340`) already: includes `kind` in `touchesMoney`, rejects transfers (`acctLegs > 1`), sets `ep.kind`, and rebuilds legs; refund requires the account-leg amount > 0 (`Entries.swift:290`).
- **Scope: expense ↔ income ↔ refund only** (same leg shape). Picker is **gated** to single-account, **non-split**, non-transfer/adjustment/opening entries.
- The UI sends a **kind-correct signed amount** (`expense → -|amt|`, `income/refund → +|amt|`) and sets/clears `refundedTransactionId`. Non-reclassifiable entries keep today's exact behavior.
- **Must build iOS AND macOS (FinchMac).** Sim `iPhone 17 Pro Max`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit; **no `Co-Authored-By` trailer**.

---

## File Structure

**Create (tests):** `ios/FinchCore/Tests/FinchCoreTests/KindReclassifyTests.swift`.
**Modify (FinchApp):** `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift`.

---

### Task 1: FinchCore — lock the `updateTransaction` kind-change path

**Files:**
- Test: `ios/FinchCore/Tests/FinchCoreTests/KindReclassifyTests.swift`

**Interfaces:** Consumes existing `updateTransaction` (no source change). Verifies expense→income→refund kind changes rebuild legs with the right sign, and the refund sign guard.

- [ ] **Step 1: Write the tests**

Create `ios/FinchCore/Tests/FinchCoreTests/KindReclassifyTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class KindReclassifyTests: XCTestCase {
    private func addExpense(_ q: DatabaseQueue) throws -> String {
        try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-25),
            "merchant": .string("Coffee"), "categoryId": .string("c1"), "date": .string("2026-06-01"),
            "skipRules": .bool(true)]))!
    }
    private func kind(_ q: DatabaseQueue, _ id: String) throws -> String? {
        try q.read { db in try String.fetchOne(db, sql: "SELECT kind FROM entries WHERE id = ?", arguments: [id]) }
    }
    private func acctAmount(_ q: DatabaseQueue, _ id: String) throws -> Double? {
        try q.read { db in try Double.fetchOne(db, sql: "SELECT amount FROM postings WHERE entry_id = ? AND account_id IS NOT NULL", arguments: [id]) }
    }
    private func update(_ q: DatabaseQueue, _ id: String, _ patch: [String: JSONValue]) throws {
        try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args(["id": .string(id), "patch": .object(patch)]))
    }

    func test_expense_to_income_resigns_positive() throws {
        let q = try TestSeed.base(); let id = try addExpense(q)
        try update(q, id, ["kind": .string("income"), "amount": .double(25)])
        XCTAssertEqual(try kind(q, id), "income")
        XCTAssertEqual(try acctAmount(q, id) ?? 0, 25, accuracy: 0.001)   // positive account leg
    }

    func test_expense_to_refund_positive() throws {
        let q = try TestSeed.base(); let id = try addExpense(q)
        try update(q, id, ["kind": .string("refund"), "amount": .double(25)])
        XCTAssertEqual(try kind(q, id), "refund")
        XCTAssertGreaterThan(try acctAmount(q, id) ?? 0, 0)
    }

    func test_refund_rejects_negative_amount() throws {
        let q = try TestSeed.base(); let id = try addExpense(q)
        XCTAssertThrowsError(try update(q, id, ["kind": .string("refund"), "amount": .double(-25)]))   // refund needs > 0
    }

    func test_refund_to_expense_resigns_negative_and_clears_link() throws {
        let q = try TestSeed.base(); let id = try addExpense(q)
        try update(q, id, ["kind": .string("refund"), "amount": .double(25)])
        try update(q, id, ["kind": .string("expense"), "amount": .double(-25), "refundedTransactionId": .null])
        XCTAssertEqual(try kind(q, id), "expense")
        XCTAssertEqual(try acctAmount(q, id) ?? 0, -25, accuracy: 0.001)   // negative account leg
        let link = try q.read { db in try String.fetchOne(db, sql: "SELECT refunded_entry_id FROM entries WHERE id = ?", arguments: [id]) }
        XCTAssertNil(link)
    }
}
```

- [ ] **Step 2: Run them**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter KindReclassifyTests`
Expected: PASS (4 tests). These assert *existing* engine behavior — if `addTransaction`'s positional args or a read-back column differs in practice (e.g. `TestSeed.base()` account/category ids, or the account-leg column), adjust the test to the real schema (it's `entries.kind` / `postings.amount` where `account_id IS NOT NULL` / `entries.refunded_entry_id`). If a test reveals the engine does **not** rebuild as expected, STOP and report — that changes the UI design.

- [ ] **Step 3: Full FinchCore suite**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test`
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchCore/Tests/FinchCoreTests/KindReclassifyTests.swift
git commit -m "test(ios): updateTransaction kind reclassification (expense/income/refund)"
```

---

### Task 2: `EditTransactionSheet` — kind picker + re-sign + refund link

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift`

**Interfaces:** Consumes the engine path verified in Task 1; uses existing `store.apply(.updateTransaction, …)`, `DecimalInput`, `RefundSourcePickerView`.

- [ ] **Step 1: Add the `EditKind` enum + state**

In `EditTransactionSheet`, add a nested enum (e.g. right after the `let txn: Tx` line) :
```swift
    enum EditKind: String, CaseIterable, Identifiable {
        case expense, income, refund
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }
```
And a state var, after `@State private var createCounterpartyOnSave = false`:
```swift
    @State private var selectedKind: EditKind
```

- [ ] **Step 2: Init `selectedKind`**

In `init`, after `_currencyCode = State(initialValue: txn.currency ?? "")`:
```swift
        _selectedKind = State(initialValue: EditKind(rawValue: txn.kind) ?? (txn.amount > 0 ? .income : .expense))
```

- [ ] **Step 3: Add `canReclassify` + `effectiveKind`; update the category filter**

Add computed vars (e.g. just above `categories`):
```swift
    /// Simple single-account entries can be re-typed expense/income/refund.
    private var canReclassify: Bool {
        !isSplit && txn.kind != "transfer" && txn.kind != "adjustment" && txn.kind != "opening"
    }
    private var effectiveKind: String { canReclassify ? selectedKind.rawValue : txn.kind }
```
Replace the `categories` filter body:
```swift
    private var categories: [CategoryRow] {
        store.pickableCategories.filter { effectiveKind == "income" ? $0.kind == "income" : $0.kind != "income" }
    }
```

- [ ] **Step 4: Add the kind Picker (top of the Amount & category section)**

In the non-split `Section("Amount & category")`, insert as its first row (before the Amount `HStack`):
```swift
                        if canReclassify {
                            Picker("Type", selection: $selectedKind) {
                                ForEach(EditKind.allCases) { Text($0.label).tag($0) }
                            }
                        }
```

- [ ] **Step 5: Drive the refund section off `effectiveKind`**

Replace `if txn.kind == "refund" {` (the `Section("Refund")` guard) with:
```swift
                if effectiveKind == "refund" {
```

- [ ] **Step 6: Re-sign + send `kind`/refund link in `save()`**

Replace the block from `if !isSplit {` through the refund-link `if` (the amount/status/account/currency/refund section, currently lines 279–294) with:
```swift
        let kindChanged = canReclassify && selectedKind.rawValue != txn.kind
        if !isSplit {
            guard let parsed = DecimalInput.parse(amountText), parsed > 0 else {
                errorMessage = "Enter an amount greater than 0."; return
            }
            // Sign by the (possibly new) kind: expense negative; income/refund positive.
            let sign: Double = canReclassify ? (selectedKind == .expense ? -1.0 : 1.0) : (originalNative < 0 ? -1.0 : 1.0)
            let signed = sign * parsed
            if abs(signed - originalNative) > 0.001 || kindChanged { patch["amount"] = .double(signed) }
            if !categoryId.isEmpty, categoryId != txn.category { patch["category"] = .string(categoryId) }
        }
        if kindChanged { patch["kind"] = .string(selectedKind.rawValue) }
        if status != (txn.pending == true ? .pending : .confirmed) { patch["status"] = .string(status.rawValue) }
        if txn.kind != "transfer", !accountId.isEmpty, accountId != txn.account { patch["account"] = .string(accountId) }
        if txn.kind != "transfer", !currencyCode.isEmpty, currencyCode != (txn.currency ?? accountCurrency) {
            patch["currency"] = .string(currencyCode)
        }
        // Refund link: set/update when (now) a refund; clear when leaving refund.
        if effectiveKind == "refund" {
            if refundedTxId != txn.refundedTransactionId || kindChanged {
                patch["refundedTransactionId"] = refundedTxId.map(JSONValue.string) ?? .null
            }
        } else if txn.kind == "refund" {
            patch["refundedTransactionId"] = .null
        }
```
(Non-reclassifiable entries: `canReclassify` is false → `kindChanged` false, `effectiveKind == txn.kind` → behaves exactly as before.)

- [ ] **Step 7: Build iOS + full FinchApp suite**

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

- [ ] **Step 8: Full FinchCore suite**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test 2>&1 | grep -iE "error:|Test Suite 'All tests'"`
Expected: all pass.

- [ ] **Step 9: Build macOS (FinchMac)**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 10: Manual verification on the simulator**

Open an **expense**'s Edit sheet:
- A **Type** picker (Expense/Income/Refund) appears at the top of Amount & category.
- Switch to **Income** → save → the row shows as income (positive); reopen → category list is income categories.
- Switch to **Refund** → a Refund source row appears; pick one → save.
- Switch back to **Expense** → save → negative again; the refund link is cleared.
- Open a **transfer**'s editor → **no** Type picker. Open a **split**'s editor → no Type picker.
- Attachments/tags on the edited entry survive the kind change.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch
```

- [ ] **Step 11: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift
git commit -m "feat(ios): reclassify transaction kind (expense/income/refund) in Edit"
```

---

## Self-Review

**Spec coverage** (against `2026-06-25-ios-kind-reclassification-design.md`):
- Kind picker (expense/income/refund), gated to single-account non-split non-transfer/adjustment → Task 2 steps 1,4 + `canReclassify`. ✓
- `effectiveKind` drives category filter + refund section → steps 3,5. ✓
- Re-signed amount + `kind` patch + refund link set/clear → step 6. ✓
- No engine change; existing path locked by tests → Task 1. ✓
- Non-reclassifiable entries unchanged → step 6 (canReclassify-gated). ✓
- Build iOS+macOS; full tests green → Task 2 steps 7-9. ✓

**Placeholder scan:** No TBD/TODO; full code in every step; sim step concrete. ✓

**Type consistency:** `EditKind` raw values (expense/income/refund) map to `Entries.Kind` strings the engine accepts; `selectedKind` init from `txn.kind`; `canReclassify`/`effectiveKind` used in `categories`, the refund section, and `save()`; `save()` sends `kind` (.string) + re-signed `amount` (.double) + `refundedTransactionId` (.string/.null) — all accepted by `updateTransaction`. Task-1 read-backs use real columns (`entries.kind`, `postings.amount`/`account_id`, `entries.refunded_entry_id`). ✓

---

## Out of scope

Transfer/adjustment/opening reclassification; delete-and-recreate; kind change on splits; web changes.
