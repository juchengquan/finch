# Add Transaction: tags + status + receipt — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the Add Transaction form (expense/income) set tags, status (pending/confirmed), and a receipt photo, saved with the new transaction.

**Architecture:** `addTransaction` gains a `tagIds` field (tags inserted in the same write) and is refactored to return the new entry id; a new `applyReturningId` path surfaces that id to the app so the Add form can attach a receipt after the entry exists. Receipt-writing is shared with the Edit form via a new `AttachmentWriter` helper.

**Tech Stack:** Swift / SwiftUI, GRDB, XcodeGen; FinchCore (engine) + FinchApp (UI).

Spec: `plans/ios-macos/2026-06-22-add-tx-tags-status-receipt-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; run `cd ios && xcodegen generate` before app builds.
- Engine tests: `cd ios/FinchCore && swift test`. App build/test: scheme `FinchApp`, `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
- Commits: **no `Co-Authored-By` trailer**.
- Scope: **expense/income only**. Do NOT touch the transfer (`createTransfer`) or adjust (`adjustAccountBalance`) save paths.
- `Entries.Status` is exactly `pending | confirmed`. Default for an added tx stays **confirmed**.
- PR targets `feat/frontend`.

---

### Task 1: Engine — `tagIds` inline + surface the new entry id

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/Transactions.swift`
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Apply.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/FinchStore.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests/AddTransactionFieldsTests.swift` (create)

**Interfaces — Produces:**
- `Transactions.addTransactionReturningId(_ db: Database, _ args: Args) throws -> String`
- `Apply.applyReturningId(dbQueue: DatabaseQueue, action: String, args: Args) throws -> String?`
- `FinchStore.applyReturningId(_ action: ActionName, _ args: Args) throws -> String?`
- `AddInput.tagIds: [String]?`

- [ ] **Step 1: Write the failing engine tests**

Create `ios/FinchCore/Tests/FinchCoreTests/AddTransactionFieldsTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class AddTransactionFieldsTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue { try TestSeed.base() }   // l1 / a1 / c1

    private func addArgs(_ extra: [String: JSONValue] = [:]) -> Args {
        var d: [String: JSONValue] = [
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-12),
            "merchant": .string("Lunch"), "categoryId": .string("c1"), "date": .string("2026-06-01"),
        ]
        for (k, v) in extra { d[k] = v }
        return Args(d)
    }

    func test_addTransaction_writesTags() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createTag", args: Args(["id": .string("t1"), "ledgerId": .string("l1"), "name": .string("Work")]))
        let eid = try q.write { db in try Transactions.addTransactionReturningId(db, addArgs(["tagIds": .array([.string("t1")])])) }
        let n = try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry_tags WHERE entry_id = ? AND tag_id = ?", arguments: [eid, "t1"]) }
        XCTAssertEqual(n, 1)
    }

    func test_addTransaction_statusPendingAndDefault() throws {
        let q = try seeded()
        let pendingId = try q.write { db in try Transactions.addTransactionReturningId(db, addArgs(["status": .string("pending")])) }
        let defaultId = try q.write { db in try Transactions.addTransactionReturningId(db, addArgs()) }
        let pStatus = try q.read { db in try String.fetchOne(db, sql: "SELECT status FROM entries WHERE id = ?", arguments: [pendingId]) }
        let dStatus = try q.read { db in try String.fetchOne(db, sql: "SELECT status FROM entries WHERE id = ?", arguments: [defaultId]) }
        XCTAssertEqual(pStatus, "pending")
        XCTAssertEqual(dStatus, "confirmed")
    }

    func test_applyReturningId_addTransactionReturnsId_otherNil() throws {
        let q = try seeded()
        let id = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: addArgs())
        XCTAssertNotNil(id)
        let exists = try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE id = ?", arguments: [id!]) }
        XCTAssertEqual(exists, 1)
        let none = try Apply.applyReturningId(dbQueue: q, action: "createTag", args: Args(["id": .string("t2"), "ledgerId": .string("l1"), "name": .string("X")]))
        XCTAssertNil(none)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios/FinchCore && swift test --filter AddTransactionFieldsTests 2>&1 | tail -20`
Expected: FAIL — `addTransactionReturningId` / `applyReturningId` don't exist yet (compile error).

- [ ] **Step 3: Add `tagIds` to `AddInput`**

In `Transactions.swift`, in the `AddInput` struct (after `let skipRules: Bool?`), add:

```swift
        let tagIds: [String]?
```

- [ ] **Step 4: Refactor `addTransaction` to return the id + write tags**

In `Transactions.swift`, replace the whole `addTransaction` function:

```swift
    static func addTransaction(_ db: Database, _ args: Args) throws {
        _ = try addTransactionReturningId(db, args)
    }

    /// Like `addTransaction` but returns the new entry id (so callers can attach
    /// a receipt). Tags in `tagIds` are written in the same transaction.
    @discardableResult
    static func addTransactionReturningId(_ db: Database, _ args: Args) throws -> String {
      try Dedup.wrap {
        let a = try args.to(AddInput.self)
        // Cross-ledger counterparty guard: drop a counterparty from another ledger.
        var counterpartyId = a.counterpartyId
        if let cp = counterpartyId {
            let cpLedger = try String.fetchOne(db, sql: "SELECT ledger_id FROM counterparties WHERE id = ?", arguments: [cp])
            if cpLedger != a.ledgerId { counterpartyId = nil }
        }
        let kind = a.kind.flatMap(Entries.Kind.init(rawValue:)) ?? (a.amount > 0 ? Entries.Kind.income : .expense)

        let acctCcy = try String.fetchOne(db, sql: "SELECT currency FROM accounts WHERE id = ?", arguments: [a.accountId]) ?? "USD"
        let inputCcy = a.currency ?? acctCcy
        if inputCcy != acctCcy {
            let base = try String.fetchOne(db, sql: "SELECT base_currency FROM ledgers WHERE id = ?", arguments: [a.ledgerId]) ?? acctCcy
            let toAcct = try Entries.convertToBase(db, a.amount, inputCcy, acctCcy, a.date)
            let toBase = try Entries.convertToBase(db, toAcct.amountBase, acctCcy, base, a.date)
            let eid = try Entries.postEntry(db, Entries.NewEntry(
                ledgerId: a.ledgerId, date: a.date, time: a.time, description: a.merchant, kind: kind,
                status: a.status.flatMap(Entries.Status.init(rawValue:)),
                legs: [.account(Entries.AccountLeg(accountId: a.accountId, amount: toAcct.amountBase,
                    amountBase: toBase.amountBase, exchangeRate: toBase.rate,
                    origAmount: a.amount, origCurrency: inputCcy))],
                autoBalance: .category(a.categoryId),
                notes: (a.note?.isEmpty ?? true) ? nil : a.note,
                counterpartyId: counterpartyId, refundedEntryId: a.refundedTransactionId,
                skipRules: a.skipRules ?? false))
            try Budgets.invalidateForEntry(db, eid)
            try insertTags(db, entryId: eid, tagIds: a.tagIds)
            return eid
        }

        let eid = try Entries.postSimple(db, .init(
            ledgerId: a.ledgerId, accountId: a.accountId, amount: a.amount, date: a.date,
            description: a.merchant, categoryId: a.categoryId, kind: kind, time: a.time,
            notes: (a.note?.isEmpty ?? true) ? nil : a.note,
            status: a.status.flatMap(Entries.Status.init(rawValue:)),
            counterpartyId: counterpartyId, skipRules: a.skipRules ?? false,
            refundedEntryId: a.refundedTransactionId))
        try Budgets.invalidateForEntry(db, eid)
        try insertTags(db, entryId: eid, tagIds: a.tagIds)
        return eid
      }
    }

    private static func insertTags(_ db: Database, entryId: String, tagIds: [String]?) throws {
        for tagId in (tagIds ?? []) {
            try db.execute(sql: "INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) VALUES (?, ?)", arguments: [entryId, tagId])
        }
    }
```

- [ ] **Step 5: Add `applyReturningId` to `Apply`**

In `Apply.swift`, replace the `apply(dbQueue:action:args:)` function with:

```swift
    /// Apply a single action to the database. Mirrors the web's
    /// `applyMutation(exec, action, args)`.
    public static func apply(dbQueue: DatabaseQueue, action: String, args: Args) throws {
        _ = try applyReturningId(dbQueue: dbQueue, action: action, args: args)
    }

    /// Like `apply`, but returns the new entry id for `addTransaction` (nil for
    /// every other action) so callers can attach a receipt to the fresh entry.
    public static func applyReturningId(dbQueue: DatabaseQueue, action: String, args: Args) throws -> String? {
        guard let name = ActionName(rawValue: action) else {
            throw I18nError("error.unknownAction", ["action": action], "Unknown action \"\(action)\"")
        }
        guard let handler = registry[name] else {
            throw I18nError("error.notImplemented", ["action": action],
                            "Action \"\(action)\" is not implemented on iOS yet")
        }
        return try dbQueue.write { db in
            if name == .addTransaction {
                return try Transactions.addTransactionReturningId(db, args)
            }
            try handler(db, args)
            return nil
        }
    }
```

- [ ] **Step 6: Add `applyReturningId` to `FinchStore`**

In `FinchStore.swift`, replace the `apply(_:_:)` method with a discard wrapper plus a returning variant that keeps the existing side-effect block. Replace:

```swift
    public func apply(_ action: ActionName, _ args: Args) throws {
        guard let q = dbQueue else { throw I18nError("error.noDatabase", [:], "No database is open") }
        try Apply.apply(dbQueue: q, action: action.rawValue, args: args)
```

with:

```swift
    public func apply(_ action: ActionName, _ args: Args) throws {
        _ = try applyReturningId(action, args)
    }

    /// Like `apply`, returning the new entry id for `addTransaction` (nil otherwise).
    @discardableResult
    public func applyReturningId(_ action: ActionName, _ args: Args) throws -> String? {
        guard let q = dbQueue else { throw I18nError("error.noDatabase", [:], "No database is open") }
        let newId = try Apply.applyReturningId(dbQueue: q, action: action.rawValue, args: args)
```

(Leave the rest of the method body — the re-projection + side-effects — unchanged, and add `return newId` as its last line.)

- [ ] **Step 7: Add `return newId` at the end of `applyReturningId`**

In `FinchStore.swift`, the side-effect block ends with the `CloudKitSyncCoordinator.shared.noteLocalMutation(...)` line. Immediately after it (still inside the method), add:

```swift
        return newId
```

- [ ] **Step 8: Run the engine tests**

Run: `cd ios/FinchCore && swift test --filter AddTransactionFieldsTests 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 9: Full engine + app build**

```bash
cd ios/FinchCore && swift test 2>&1 | tail -5
cd .. && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```
Expected: engine tests pass; `** BUILD SUCCEEDED **`.

- [ ] **Step 10: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Store/Domain/Transactions.swift \
        ios/FinchCore/Sources/FinchCore/Store/Apply.swift \
        ios/FinchApp/Sources/FinchApp/FinchStore.swift \
        ios/FinchCore/Tests/FinchCoreTests/AddTransactionFieldsTests.swift
git commit -m "feat(ios): addTransaction tagIds + applyReturningId surfaces new entry id"
```

---

### Task 2: Shared `AttachmentWriter` + Edit form refactor

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/WriteScreens/AttachmentWriter.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift:158-181`

**Interfaces — Produces:** `AttachmentWriter.write(item: PhotosPickerItem, entryId: String, store: FinchStore) async throws`

- [ ] **Step 1: Create the shared helper**

Create `ios/FinchApp/Sources/FinchApp/WriteScreens/AttachmentWriter.swift`:

```swift
import Foundation
import PhotosUI
import CryptoKit
import FinchCore

/// Writes a picked photo into the live attachments tree under an entry id and
/// records it via `setEntryAttachment`. Shared by Add + Edit (the in-app
/// counterpart to the Share Extension flow).
enum AttachmentWriter {
    static func write(item: PhotosPickerItem, entryId: String, store: FinchStore) async throws {
        guard let data = try await item.loadTransferable(type: Data.self) else { return }
        let attId = "att-\(UUID().uuidString.prefix(8).lowercased())"
        let dir = store.attachmentsRoot.appendingPathComponent(entryId, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rel = "attachments/\(entryId)/\(attId).jpg"
        try data.write(to: store.attachmentsRoot.deletingLastPathComponent().appendingPathComponent(rel))
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try store.apply(.setEntryAttachment, Args([
            "entryId": .string(entryId), "kind": .string("image"), "relPath": .string(rel),
            "mimeType": .string("image/jpeg"), "byteSize": .double(Double(data.count)), "sha256": .string(sha)]))
    }
}
```

- [ ] **Step 2: Point the Edit form at the helper**

In `EditTransactionSheet.swift`, replace the body of `addReceipt(_ item:)` (keep the function signature) with:

```swift
    private func addReceipt(_ item: PhotosPickerItem) async {
        errorMessage = nil
        do {
            try await AttachmentWriter.write(item: item, entryId: txn.id, store: store)
            attachments = store.attachments(for: txn.id)
            pickedPhoto = nil
        } catch { errorMessage = i18nMessage(error) }
    }
```

- [ ] **Step 3: Build + run app tests**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD FAILED|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **` (Edit behavior unchanged, just relocated).

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/AttachmentWriter.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift
git commit -m "refactor(ios): extract shared AttachmentWriter (Edit uses it)"
```

---

### Task 3: Add form — status Picker + tags + receipt (expense/income)

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift`

**Interfaces — Consumes:** `FinchStore.applyReturningId`, `AttachmentWriter.write`.

- [ ] **Step 1: Imports + new state**

In `AddTransactionSheet.swift`, change the imports at the top from:

```swift
import SwiftUI
import FinchCore
```

to:

```swift
import SwiftUI
import PhotosUI
import FinchCore
```

Then, after the `@State private var dupConfirmed = false` line, add:

```swift
    @State private var status: Entries.Status = .confirmed
    @State private var selectedTags: Set<String> = []
    @State private var pickedPhoto: PhotosPickerItem?
```

- [ ] **Step 2: Add the three controls (expense/income only)**

In `AddTransactionSheet.swift`, find the Date/Note `Section` (contains `DatePicker("Date", …)` and the Note field). Immediately **after** that whole `Section { … }` block, add:

```swift
                if kind == .expense || kind == .income {
                    Section {
                        Picker("Status", selection: $status) {
                            Text("Confirmed").tag(Entries.Status.confirmed)
                            Text("Pending").tag(Entries.Status.pending)
                        }
                    }
                    if !store.tags.isEmpty {
                        Section("Tags") {
                            ForEach(store.tags) { tag in
                                Button { toggleTag(tag.id) } label: {
                                    HStack {
                                        Text(tag.name).foregroundStyle(.primary)
                                        Spacer()
                                        if selectedTags.contains(tag.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                    }
                                }
                            }
                        }
                    }
                    Section("Receipt") {
                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            Label(pickedPhoto == nil ? "Add receipt photo" : "Receipt photo selected", systemImage: "camera")
                        }
                    }
                }
```

- [ ] **Step 3: Add the `toggleTag` helper**

In `AddTransactionSheet.swift`, add near `seedDefaults()`:

```swift
    private func toggleTag(_ id: String) {
        if selectedTags.contains(id) { selectedTags.remove(id) } else { selectedTags.insert(id) }
    }
```

- [ ] **Step 4: Wire the expense/income save path**

In `AddTransactionSheet.swift` `save()`, in the `else` branch (the expense/income branch that currently ends with `try store.apply(.addTransaction, Args(args))`), make these changes inside that branch:

First, after the existing `if !currencyCode.isEmpty, currencyCode != currency(of: accountId) { args["currency"] = .string(currencyCode) }` block, add the new fields:

```swift
                args["status"] = .string(status.rawValue)
                if !selectedTags.isEmpty { args["tagIds"] = .array(selectedTags.map { .string($0) }) }
```

Then replace `try store.apply(.addTransaction, Args(args))` with:

```swift
                let eid = try store.applyReturningId(.addTransaction, Args(args))
                if let eid, let photo = pickedPhoto {
                    Task { try? await AttachmentWriter.write(item: photo, entryId: eid, store: store) }
                }
```

(The `dismiss()` after the `if/else` stays; the receipt write completes in the background and the store re-projects — same fire-and-forget shape the Edit form uses.)

- [ ] **Step 5: Build**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift
git commit -m "feat(ios): Add form — status Picker + tags + receipt (expense/income)"
```

---

### Task 4: Manual simulator verification

**Files:** none. Reference: `ios/docs/simulator-ui-driving.md` (raise the iPhone 17 Pro window by name before taps; a 2nd sim may steal foreground).

- [ ] **Step 1: Install + launch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"; xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```

- [ ] **Step 2: Verify**
  - Add → Expense: Status picker (Confirmed/Pending), a Tags section (if tags exist), and a Receipt photo picker all appear.
  - Switch type to **Transfer** / **Adjust Balance** → the three new fields are **hidden**.
  - Save an expense with a tag + Pending + a receipt → open it in Edit: the tag is checked, it shows pending (a "Confirm transaction" button appears), and the receipt is listed.
  - Screenshot evidence to `/tmp/addtx-<state>.png`.

- [ ] **Step 3 (no commit):** report results; if any check fails, return to the relevant task.

---

## Self-review notes
- Spec coverage: tagIds inline (T1 S4), applyReturningId (T1 S5-7), status already in AddInput + UI (T3 S2/S4), tags UI (T3 S2/S4), receipt via shared helper (T2 + T3 S4), expense/income-only gating (T3 S2), DRY AttachmentWriter (T2), tests (T1 S1, T4). ✓
- Type consistency: `addTransactionReturningId`, `applyReturningId`, `AttachmentWriter.write(item:entryId:store:)`, `Entries.Status` used identically across tasks. ✓
