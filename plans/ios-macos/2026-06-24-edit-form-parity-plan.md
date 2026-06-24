# Edit Transaction parity (status + account + refund link) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the Edit Transaction sheet change a transaction's status (pending↔confirmed), account, and (for refunds) the linked original transaction.

**Architecture:** UI controls on `EditTransactionSheet` fold into its existing `updateTransaction` patch. One parity-safe engine line makes `updateTransaction` resolve the refund-link id (posting→entry) like `addTransaction` already does.

**Tech Stack:** Swift / SwiftUI, GRDB, XcodeGen.

Spec: `plans/ios-macos/2026-06-24-edit-form-parity-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before app builds.
- Engine tests: `cd ios/FinchCore && swift test`. App build: scheme `FinchApp`, `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
- Commits: **no `Co-Authored-By` trailer**.
- Account + Refund rows: **expense/income/refund only** (hidden for transfers). Status: any kind. Currency / counterparty-in-Edit / kind-change: **out of scope**.
- PR targets `feat/frontend`.

---

### Task 1: Engine — resolve the refund-link patch in `updateTransaction`

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/Transactions.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests/UpdateRefundLinkTests.swift` (create)

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import GRDB
@testable import FinchCore

final class UpdateRefundLinkTests: XCTestCase {
    private func add(_ q: DatabaseQueue, _ amount: Double) throws -> String {
        try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(amount),
            "merchant": .string("M"), "categoryId": .string("c1"), "date": .string("2026-06-01")]))!
    }

    func test_updateTransaction_resolvesRefundLinkPostingIdToEntry() throws {
        let q = try TestSeed.base()
        let e1 = try add(q, -80)          // the original purchase (entry id)
        let e2 = try add(q, 30)           // the row we attach the link to (entry id)
        let posting = try q.read { db in try String.fetchOne(db, sql:
            "SELECT id FROM postings WHERE entry_id = ? AND account_id IS NOT NULL ORDER BY sort_order LIMIT 1",
            arguments: [e1]) }!
        try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(e2), "patch": .object(["refundedTransactionId": .string(posting)])]))
        let ref = try q.read { db in try String.fetchOne(db, sql:
            "SELECT refunded_entry_id FROM entries WHERE id = ?", arguments: [e2]) }
        XCTAssertEqual(ref, e1)           // posting id normalized to the entry id

        // Clearing still works (null → null).
        try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(e2), "patch": .object(["refundedTransactionId": .null])]))
        let cleared = try q.read { db in try String.fetchOne(db, sql:
            "SELECT refunded_entry_id FROM entries WHERE id = ?", arguments: [e2]) }
        XCTAssertNil(cleared)
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `cd ios/FinchCore && swift test --filter UpdateRefundLinkTests 2>&1 | tail -15`
Expected: FAIL — `ref` is the posting id, not `e1` (today the patch is stored verbatim).

- [ ] **Step 3: Resolve the id**

In `Transactions.swift`, replace the refund-link line in `updateTransaction` (≈ line 341):

```swift
        if has("refundedTransactionId") { ep.refundedEntryId = .set(strOrNil(patch["refundedTransactionId"])) }
```
with:
```swift
        if has("refundedTransactionId") {
            ep.refundedEntryId = .set(try strOrNil(patch["refundedTransactionId"]).flatMap { try Entries.resolveEntryRef(db, $0)?.entryId })
        }
```

- [ ] **Step 4: Run — expect PASS**

Run: `cd ios/FinchCore && swift test --filter UpdateRefundLinkTests 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 5: Full engine suite incl. ParityTests**

Run: `cd ios/FinchCore && swift test 2>&1 | tail -8`
Expected: all pass (idempotent for entry ids → ParityTests green). If ParityTests fail, STOP and report.

- [ ] **Step 6: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Store/Domain/Transactions.swift \
        ios/FinchCore/Tests/FinchCoreTests/UpdateRefundLinkTests.swift
git commit -m "feat(ios): updateTransaction resolves refundedTransactionId via resolveEntryRef"
```

---

### Task 2: Edit sheet — Status picker + Account picker + Refund link

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift`

**Interfaces — Consumes:** `Entries.Status`, `store.accounts`, `RefundSourcePickerView(onPick:)`, the engine resolve from Task 1.

- [ ] **Step 1: Add state**

After `@State private var pickedPhoto: PhotosPickerItem?`, add:

```swift
    @State private var status: Entries.Status
    @State private var accountId: String
    @State private var refundedTxId: String?
    @State private var showingRefundPicker = false
```

- [ ] **Step 2: Initialize them in `init`**

In `init(txn:)`, after `_selectedTags = State(initialValue: Set(txn.tags ?? []))`, add:

```swift
        _status = State(initialValue: txn.pending == true ? .pending : .confirmed)
        _accountId = State(initialValue: txn.account)
        _refundedTxId = State(initialValue: txn.refundedTransactionId)
```

- [ ] **Step 3: Add the `refundedSummary` helper**

Near `originalNative` / `isSplit`, add:

```swift
    private var refundedSummary: String {
        guard let id = refundedTxId, let t = store.txns.first(where: { $0.id == id }) else { return "Optional" }
        return t.merchant.isEmpty ? t.date : t.merchant
    }
```

- [ ] **Step 4: Add the Account + Refund sections**

In `body`, immediately **after** the `if isSplit { … } else { … }` amount/category block (and before the Tags section), add:

```swift
                if txn.kind != "transfer" {
                    Section("Account") {
                        SearchablePickerRow(title: "Account",
                            options: store.accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $accountId)
                    }
                }
                if txn.kind == "refund" {
                    Section("Refund") {
                        Button { showingRefundPicker = true } label: {
                            HStack {
                                Text("Refunds"); Spacer()
                                Text(refundedSummary).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
```

- [ ] **Step 5: Add a Status picker + remove the one-way Confirm button**

In `body`, replace the lifecycle `Section` (the one with the Confirm/reviewed/delete buttons):

```swift
                Section {
                    if txn.pending == true {
                        Button("Confirm transaction") { run(.confirmTransaction, ["id": .string(txn.id)]) }
                    }
                    Button(txn.reviewedAt == nil ? "Mark reviewed" : "Unmark reviewed") {
                        run(.setReviewed, ["id": .string(txn.id), "reviewed": .bool(txn.reviewedAt == nil)])
                    }
                    Button("Delete transaction", role: .destructive) { confirmingDelete = true }
                }
```
with:
```swift
                Section {
                    Picker("Status", selection: $status) {
                        Text("Confirmed").tag(Entries.Status.confirmed)
                        Text("Pending").tag(Entries.Status.pending)
                    }
                }
                Section {
                    Button(txn.reviewedAt == nil ? "Mark reviewed" : "Unmark reviewed") {
                        run(.setReviewed, ["id": .string(txn.id), "reviewed": .bool(txn.reviewedAt == nil)])
                    }
                    Button("Delete transaction", role: .destructive) { confirmingDelete = true }
                }
```

- [ ] **Step 6: Present the refund picker sheet**

Find the existing `.sheet(isPresented: $showingSplit) { SplitEditorView(txn: txn) }` and add immediately after it:

```swift
            .sheet(isPresented: $showingRefundPicker) { RefundSourcePickerView { refundedTxId = $0 } }
```

- [ ] **Step 7: Fold status/account/refund into the save patch**

In `save()`, after the `if !isSplit { … }` block and **before** `do { try store.apply(.updateTransaction, …) }`, add:

```swift
        if status != (txn.pending == true ? .pending : .confirmed) { patch["status"] = .string(status.rawValue) }
        if txn.kind != "transfer", !accountId.isEmpty, accountId != txn.account { patch["account"] = .string(accountId) }
        if txn.kind == "refund", refundedTxId != txn.refundedTransactionId {
            patch["refundedTransactionId"] = refundedTxId.map(JSONValue.string) ?? .null
        }
```

- [ ] **Step 8: Build**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift
git commit -m "feat(ios): Edit sheet — status picker + account + refund link"
```

---

### Task 3: Manual simulator verification

**Files:** none. Raise the iPhone 17 Pro window by name before taps; press elements via accessibility (AXPress) where coordinate taps miss.

- [ ] **Step 1: Install + launch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"; xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```

- [ ] **Step 2: Verify**
  - Open an existing expense in Edit → a **Status** picker (Confirmed/Pending) shows; flip it → save → reopen: it persisted (and flips back).
  - Edit shows an **Account** picker pre-set to the tx's account; change it → save → the transaction moved accounts.
  - Open a **refund** tx (create one via Add → Refund first) → Edit shows a **"Refunds"** row with the linked purchase → change/clear it → save → the link updated.
  - A **transfer** opened in Edit shows **no** Account/Refund rows (Status may still show).
  - Screenshot evidence to `/tmp/editparity-<state>.png`.

- [ ] **Step 3 (no commit):** report; if any check fails, return to the relevant task.

---

## Self-review notes
- Spec coverage: engine resolve + test (T1), status picker replacing Confirm (T2 S5), account picker hidden-for-transfer (T2 S4), refund row for kind==refund (T2 S4/S6), save patch for all three (T2 S7), manual incl. transfer-hides-rows (T3). ✓
- Type consistency: `Entries.Status`, `accountId`/`txn.account` (both account ids), `refundedTxId`/`txn.refundedTransactionId`, `RefundSourcePickerView(onPick:)`, `resolveEntryRef` consistent. ✓
- Scope guard: transfers/currency/kind-change excluded. ✓
