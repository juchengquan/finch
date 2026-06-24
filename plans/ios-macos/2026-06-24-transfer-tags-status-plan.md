# Transfer tags + status — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the Add form's **transfer** type carry tags + status (pending/confirmed).

**Architecture:** Add optional `status`/`tagIds` to `Entries.postTransfer` + `Transfers.create` (default = today's behavior, so web-parity fixtures are unaffected). In the Add form, show the Status + Tags sections for transfers (not just line items); the transfer save passes them. A deliberate iOS-ahead-of-web divergence.

**Tech Stack:** Swift / SwiftUI, GRDB, XcodeGen.

Spec: `plans/ios-macos/2026-06-24-transfer-tags-status-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before app builds.
- Engine tests: `cd ios/FinchCore && swift test`. App build: scheme `FinchApp`, `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
- Commits: **no `Co-Authored-By` trailer**.
- New engine params are **optional, default-nil** → existing callers (web parity `WRITE_SEQUENCE`, reconcile, scheduled) unchanged ⇒ **`ParityTests` must stay green**.
- Receipt is NOT added to transfers (stays `isLineItem`). Splits/counterparty on transfers out of scope.
- PR targets `feat/frontend`.

---

### Task 1: Engine — optional `status` + `tagIds` on transfers

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Entries.swift` (`postTransfer`)
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/Transfers.swift` (`create`)
- Test: `ios/FinchCore/Tests/FinchCoreTests/TransferTagsStatusTests.swift` (create)

- [ ] **Step 1: Write the tests**

```swift
import XCTest
import GRDB
@testable import FinchCore

final class TransferTagsStatusTests: XCTestCase {
    private func seededWithA2() throws -> DatabaseQueue {
        let q = try TestSeed.base()   // l1 / a1 / c1
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("a2"), "ledgerId": .string("l1"), "name": .string("Savings"),
            "type": .string("cash"), "currency": .string("USD")]))
        return q
    }
    private func transferEntryId(_ q: DatabaseQueue) throws -> String? {
        try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM entries WHERE kind='transfer' LIMIT 1") }
    }

    func test_createTransfer_withStatusAndTags() throws {
        let q = try seededWithA2()
        try Apply.apply(dbQueue: q, action: "createTag", args: Args(["id": .string("t1"), "ledgerId": .string("l1"), "name": .string("Trip")]))
        try Apply.apply(dbQueue: q, action: "createTransfer", args: Args([
            "fromAccountId": .string("a1"), "toAccountId": .string("a2"), "fromAmount": .double(50),
            "date": .string("2026-06-01"), "status": .string("pending"), "tagIds": .array([.string("t1")])]))
        let eid = try transferEntryId(q)!
        let status = try q.read { db in try String.fetchOne(db, sql: "SELECT status FROM entries WHERE id=?", arguments: [eid]) }
        let tagCount = try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry_tags WHERE entry_id=? AND tag_id='t1'", arguments: [eid]) }
        XCTAssertEqual(status, "pending")
        XCTAssertEqual(tagCount, 1)
    }

    func test_createTransfer_defaultsUnchanged() throws {
        let q = try seededWithA2()
        try Apply.apply(dbQueue: q, action: "createTransfer", args: Args([
            "fromAccountId": .string("a1"), "toAccountId": .string("a2"), "fromAmount": .double(50), "date": .string("2026-06-01")]))
        let eid = try transferEntryId(q)!
        let status = try q.read { db in try String.fetchOne(db, sql: "SELECT status FROM entries WHERE id=?", arguments: [eid]) }
        let tagCount = try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry_tags WHERE entry_id=?", arguments: [eid]) }
        XCTAssertEqual(status, "confirmed")
        XCTAssertEqual(tagCount, 0)
    }
}
```

- [ ] **Step 2: Run — expect the status/tags test to FAIL**

Run: `cd ios/FinchCore && swift test --filter TransferTagsStatusTests 2>&1 | tail -20`
Expected: `test_createTransfer_defaultsUnchanged` PASSES; `test_createTransfer_withStatusAndTags` FAILS (status is `confirmed`, 0 tags — the args are currently ignored). If `createAccount`/`createTag` arg shapes differ and setup errors, read `Accounts.swift`/`Tags.swift` and fix the setup args (keep the assertions).

- [ ] **Step 3: Add `status` + `tagIds` to `postTransfer`**

In `Entries.swift`, change the `postTransfer` signature's last param line from:

```swift
                                    sourceTemplateId: String? = nil, id: String? = nil,
                                    timestamp: String? = nil) throws -> String {
```
to:
```swift
                                    sourceTemplateId: String? = nil, id: String? = nil,
                                    timestamp: String? = nil,
                                    status: Status? = nil, tagIds: [String]? = nil) throws -> String {
```

Then change the entry creation at the end of `postTransfer` from:

```swift
        return try postEntry(db, NewEntry(
            id: id, ledgerId: lid, date: date, time: time, description: "Transfer", kind: .transfer,
            legs: [.account(AccountLeg(accountId: fromAccountId, amount: -fromAmt, memo: "Transfer to \(toName)")),
                   .account(AccountLeg(accountId: toAccountId, amount: toAmt, memo: "Transfer from \(fromName)"))],
            notes: note, sourceTemplateId: sourceTemplateId, timestamp: timestamp, skipRules: true))
    }
```
to:
```swift
        let eid = try postEntry(db, NewEntry(
            id: id, ledgerId: lid, date: date, time: time, description: "Transfer", kind: .transfer,
            status: status,
            legs: [.account(AccountLeg(accountId: fromAccountId, amount: -fromAmt, memo: "Transfer to \(toName)")),
                   .account(AccountLeg(accountId: toAccountId, amount: toAmt, memo: "Transfer from \(fromName)"))],
            notes: note, sourceTemplateId: sourceTemplateId, timestamp: timestamp, skipRules: true))
        for tagId in (tagIds ?? []) {
            try db.execute(sql: "INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) VALUES (?, ?)", arguments: [eid, tagId])
        }
        return eid
    }
```

- [ ] **Step 4: Thread them through `Transfers.create`**

In `Transfers.swift`, replace `create`:

```swift
    static func create(_ db: Database, _ args: Args) throws {
        struct A: Decodable {
            let fromAccountId: String; let toAccountId: String; let fromAmount: Double
            let toAmount: Double?; let date: String; let time: String?; let note: String?; let sourceTemplateId: String?
        }
        let a = try args.to(A.self)
        try Entries.postTransfer(db, fromAccountId: a.fromAccountId, toAccountId: a.toAccountId,
                                 fromAmount: a.fromAmount, toAmount: a.toAmount, date: a.date,
                                 time: a.time, note: a.note, sourceTemplateId: a.sourceTemplateId)
    }
```
with:
```swift
    static func create(_ db: Database, _ args: Args) throws {
        struct A: Decodable {
            let fromAccountId: String; let toAccountId: String; let fromAmount: Double
            let toAmount: Double?; let date: String; let time: String?; let note: String?; let sourceTemplateId: String?
            // iOS-ahead-of-web divergence: transfers can carry tags/status (the web
            // Transfer model has neither). Optional → web parity sequence is unaffected.
            let status: String?; let tagIds: [String]?
        }
        let a = try args.to(A.self)
        try Entries.postTransfer(db, fromAccountId: a.fromAccountId, toAccountId: a.toAccountId,
                                 fromAmount: a.fromAmount, toAmount: a.toAmount, date: a.date,
                                 time: a.time, note: a.note, sourceTemplateId: a.sourceTemplateId,
                                 status: a.status.flatMap(Entries.Status.init(rawValue:)), tagIds: a.tagIds)
    }
```

- [ ] **Step 5: Run the tests — expect PASS**

Run: `cd ios/FinchCore && swift test --filter TransferTagsStatusTests 2>&1 | tail -20`
Expected: both PASS.

- [ ] **Step 6: Full engine suite incl. ParityTests**

Run: `cd ios/FinchCore && swift test 2>&1 | tail -8`
Expected: all pass (optional params, defaults unchanged ⇒ ParityTests green). If ParityTests fail, STOP and report — do not weaken the change.

- [ ] **Step 7: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Store/Entries.swift \
        ios/FinchCore/Sources/FinchCore/Store/Domain/Transfers.swift \
        ios/FinchCore/Tests/FinchCoreTests/TransferTagsStatusTests.swift
git commit -m "feat(ios): postTransfer/createTransfer accept optional status + tagIds"
```

---

### Task 2: Add form — Status + Tags on transfers

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift`

- [ ] **Step 1: Show Status + Tags for transfers (split the extras gate)**

Replace the extras block (the `if isLineItem { … }` that wraps Status + Tags + Receipt) with two gates — Status/Tags for everything except adjust, Receipt for line items only:

```swift
                if kind != .adjust {
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
                }
                if isLineItem {
                    Section("Receipt") {
                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            Label(pickedPhoto == nil ? "Add receipt photo" : "Receipt photo selected", systemImage: "camera")
                        }
                    }
                }
```

- [ ] **Step 2: Pass status + tagIds in the transfer save branch**

In `save()`'s `if kind == .transfer { … }` branch, immediately **before** `try store.apply(.createTransfer, Args(args))`, add:

```swift
                args["status"] = .string(status.rawValue)
                if !selectedTags.isEmpty { args["tagIds"] = .array(selectedTags.map { .string($0) }) }
```

- [ ] **Step 3: Build**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift
git commit -m "feat(ios): Add form — Status + Tags on transfers"
```

---

### Task 3: Manual simulator verification

**Files:** none. Raise the iPhone 17 Pro window by name before taps. (A seeded tag helps — insert one into the sim DB's `tags` if none exist.)

- [ ] **Step 1: Install + launch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"; xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```

- [ ] **Step 2: Verify**
  - Add → **Transfer**: from/to/amount fields, **Status picker**, and **Tags** section appear; **no Receipt**, no Split.
  - Save a transfer marked **Pending** with a tag (needs ≥2 accounts + ≥1 tag) → the transfer shows as pending and carries the tag.
  - Expense/Income/Refund unchanged (still have Status/Tags/Receipt). **Adjust** shows neither Status nor Tags.
  - Screenshot evidence to `/tmp/xfer-<state>.png`.

- [ ] **Step 3 (no commit):** report results; if any check fails, return to the relevant task.

---

## Self-review notes
- Spec coverage: engine optional status/tagIds (T1 S3-S4), tests incl. default-path guard + ParityTests (T1 S1/S6), Status+Tags gate widened to `kind != .adjust` with Receipt kept `isLineItem` (T2 S1), transfer save passes them (T2 S2), manual (T3). ✓
- Type consistency: `Entries.Status`, `tagIds`, `status.rawValue`, `selectedTags` consistent with the existing tags/status feature. ✓
- Parity: new params optional/default-nil ⇒ existing callers + fixtures unchanged. ✓
