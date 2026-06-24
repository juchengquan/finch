# Add Transaction: refund creation + linking — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Refund" type to the Add form that records a positive, category-netting refund and can optionally link the original transaction it offsets.

**Architecture:** A 5th `Kind` (`.refund`) reuses the line-item fields; a new `RefundSourcePickerView` chooses the original expense. Save passes `kind: "refund"`, a positive amount, and `refundedTransactionId`. One parity-safe engine line normalizes that id (posting → entry) via `resolveEntryRef`.

**Tech Stack:** Swift / SwiftUI, GRDB, XcodeGen.

Spec: `plans/ios-macos/2026-06-24-add-refund-linking-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before app builds.
- Engine tests: `cd ios/FinchCore && swift test`. App build: scheme `FinchApp`, `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
- Commits: **no `Co-Authored-By` trailer**.
- Refund must be **positive** (engine validates). Scope: Add form only; **no split** on refund; transfer/adjust untouched; no refund badge / Edit link (follow-up).
- PR targets `feat/frontend`.

---

### Task 1: Engine — normalize `refundedTransactionId` + tests

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/Transactions.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests/RefundLinkTests.swift` (create)

**Interfaces — Produces:** `addTransaction` accepts `refundedTransactionId` as either a posting id or an entry id and stores the resolved **entry** id.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import GRDB
@testable import FinchCore

final class RefundLinkTests: XCTestCase {
    private func addExpense(_ q: DatabaseQueue) throws -> String {
        try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-80),
            "merchant": .string("Store"), "categoryId": .string("c1"), "date": .string("2026-06-01")]))!
    }
    private func refundedEntryId(_ q: DatabaseQueue, _ eid: String) throws -> String? {
        try q.read { db in try String.fetchOne(db, sql: "SELECT refunded_entry_id FROM entries WHERE id = ?", arguments: [eid]) }
    }

    func test_refund_linkedByEntryId_stored() throws {
        let q = try TestSeed.base()
        let expense = try addExpense(q)   // entry id (applyReturningId returns the entry id)
        let refund = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(30),
            "merchant": .string("Store"), "categoryId": .string("c1"), "date": .string("2026-06-05"),
            "kind": .string("refund"), "refundedTransactionId": .string(expense)]))!
        XCTAssertEqual(try refundedEntryId(q, refund), expense)
    }

    func test_refund_linkedByPostingId_resolvesToEntry() throws {
        let q = try TestSeed.base()
        let expense = try addExpense(q)
        let postingId = try q.read { db in
            try String.fetchOne(db, sql: "SELECT id FROM postings WHERE entry_id = ? AND account_id IS NOT NULL ORDER BY sort_order LIMIT 1", arguments: [expense]) }!
        let refund = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(30),
            "merchant": .string("Store"), "categoryId": .string("c1"), "date": .string("2026-06-05"),
            "kind": .string("refund"), "refundedTransactionId": .string(postingId)]))!
        XCTAssertEqual(try refundedEntryId(q, refund), expense)   // posting id normalized to entry id
    }
}
```

- [ ] **Step 2: Run — expect the posting-id test to FAIL**

Run: `cd ios/FinchCore && swift test --filter RefundLinkTests 2>&1 | tail -20`
Expected: `test_refund_linkedByEntryId_stored` PASSES (entry id stored as-is today), `test_refund_linkedByPostingId_resolvesToEntry` FAILS (a posting id is currently stored verbatim, ≠ entry id).

- [ ] **Step 3: Resolve the id in `addTransaction`**

In `Transactions.swift`, just after `let a = try args.to(AddInput.self)` (line ~222), add:

```swift
        let refundedEntryId = try a.refundedTransactionId.flatMap { try Entries.resolveEntryRef(db, $0)?.entryId }
```

Then replace **both** occurrences of `refundedEntryId: a.refundedTransactionId` (the foreign-currency `postEntry` call ~line 248 and the same-currency `postSimple` call ~line 261) with:

```swift
                refundedEntryId: refundedEntryId,
```
(foreign-currency branch — keep the trailing comma/args that follow) and

```swift
            refundedEntryId: refundedEntryId))
```
(same-currency branch — it's the last arg, so keep the `))`). Use the surrounding text to match each exactly.

- [ ] **Step 4: Run the tests — expect PASS**

Run: `cd ios/FinchCore && swift test --filter RefundLinkTests 2>&1 | tail -20`
Expected: both PASS.

- [ ] **Step 5: Run the full engine suite incl. ParityTests**

Run: `cd ios/FinchCore && swift test 2>&1 | tail -8`
Expected: all pass (the resolve is idempotent for entry ids, so `ParityTests` are unaffected).

- [ ] **Step 6: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Store/Domain/Transactions.swift \
        ios/FinchCore/Tests/FinchCoreTests/RefundLinkTests.swift
git commit -m "feat(ios): addTransaction normalizes refundedTransactionId via resolveEntryRef"
```

---

### Task 2: Add form — Refund type + source picker + save

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/WriteScreens/RefundSourcePickerView.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift`

**Interfaces — Consumes:** `RefundSourcePickerView(onPick:)`, `store.txns`, `store.applyReturningId`, the engine resolve from Task 1.

- [ ] **Step 1: Create the source picker**

Create `ios/FinchApp/Sources/FinchApp/WriteScreens/RefundSourcePickerView.swift`:

```swift
import SwiftUI
import FinchCore

/// Picks the original expense a refund offsets. Lists recent expenses in the active
/// ledger (newest first), searchable by merchant. `onPick(nil)` clears the link.
struct RefundSourcePickerView: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let onPick: (String?) -> Void
    @State private var query = ""

    private var expenses: [Tx] {
        store.txns
            .filter { $0.ledgerId == store.activeLedgerId && ($0.kind == "expense" || $0.amount < 0) }
            .filter { query.isEmpty || $0.merchant.localizedCaseInsensitiveContains(query) }
            .sorted { ($0.date, $0.time ?? "") > ($1.date, $1.time ?? "") }
    }

    var body: some View {
        NavigationStack {
            List {
                Button("None (no link)") { onPick(nil); dismiss() }
                ForEach(expenses) { tx in
                    Button {
                        onPick(tx.id); dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.merchant.isEmpty ? "—" : tx.merchant).foregroundStyle(.primary)
                                Text(tx.date).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(store.displayMoney(tx.amount, from: tx.currency ?? store.baseCurrency))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle("Refunded transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
```

- [ ] **Step 2: Add `.refund` to the `Kind` enum**

In `AddTransactionSheet.swift`, change:

```swift
        case expense, income, transfer, adjust
```
to:
```swift
        case expense, income, transfer, adjust, refund
```
(The `iconName` already uses `rawValue` → `TxnKindIcon.icon(for: "refund")` = `arrow.uturn.left.circle`; `label` → "Refund". No other enum change.)

- [ ] **Step 3: Add state + the `isLineItem` helper**

After `@State private var showingSplit = false`, add:

```swift
    @State private var refundedTxId: String? = nil
    @State private var showingRefundPicker = false
```

Add the helper near the other computed vars (e.g. after `accounts`):

```swift
    /// Expense / income / refund all post a single account leg + category — they
    /// share the line-item field set and the status/tags/receipt/merchant extras.
    private var isLineItem: Bool { kind == .expense || kind == .income || kind == .refund }
```

- [ ] **Step 4: Route refund through the line-item field set + extras**

In `body`, the extras gate `if kind == .expense || kind == .income {` (≈ line 96) → `if isLineItem {`.
(The dispatch `else { expenseIncomeFields }` already covers refund; the adjust branch is `kind == .adjust`.)

In `merchantSuggestionRows`, the gate `if (kind == .expense || kind == .income), !t.isEmpty {` → `if isLineItem, !t.isEmpty {`.

- [ ] **Step 5: Add the refunded-transaction row (refund only)**

In `expenseIncomeFields`, after the Account `SearchablePickerRow` (and the currency `Picker` block) — still inside that `Section` — add:

```swift
            if kind == .refund {
                Button { showingRefundPicker = true } label: {
                    HStack {
                        Text("Refunds")
                        Spacer()
                        Text(refundedSummary).foregroundStyle(.secondary)
                    }
                }
            }
```

Add the summary helper (near `isLineItem`):

```swift
    private var refundedSummary: String {
        guard let id = refundedTxId, let tx = store.txns.first(where: { $0.id == id }) else { return "Optional" }
        return tx.merchant.isEmpty ? tx.date : tx.merchant
    }
```

- [ ] **Step 6: Present the picker + reset on type change**

Next to the other `.sheet`/`.onChange` modifiers in `body`, add:

```swift
            .sheet(isPresented: $showingRefundPicker) {
                RefundSourcePickerView { refundedTxId = $0 }
            }
            .onChange(of: kind) { _, k in if k != .refund { refundedTxId = nil } }
```

- [ ] **Step 7: Wire the save (refund branch)**

In `save()`'s expense/income `else` branch:

Change the sign + fallback:

```swift
                let signed = (kind == .income || kind == .refund) ? abs(value) : -abs(value)
                let fallback = kind == .income ? "Income" : (kind == .refund ? "Refund" : "Untitled")
```

Then, after the `args["status"] = …` / `tagIds` lines and **before** `let eid = try store.applyReturningId(.addTransaction, Args(args))`, add:

```swift
                if kind == .refund {
                    args["kind"] = .string("refund")
                    if let refundedTxId { args["refundedTransactionId"] = .string(refundedTxId) }
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
git add ios/FinchApp/Sources/FinchApp/WriteScreens/RefundSourcePickerView.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift
git commit -m "feat(ios): Add form — Refund type + optional refunded-transaction link"
```

---

### Task 3: Manual simulator verification

**Files:** none. Raise the iPhone 17 Pro window by name before taps.

- [ ] **Step 1: Install + launch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"; xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```

- [ ] **Step 2: Verify**
  - Add type picker shows a 5th **Refund** segment (uturn icon).
  - Pick **Refund**: line-item fields show (amount/merchant/category/account), plus Status/Tags/Receipt; a **"Refunds"** row appears; **no Split** row.
  - Tap **Refunds** → searchable list of recent expenses (+ "None"); pick one → row shows its merchant; enter amount + category → save.
  - The saved refund is **positive**, nets its category; (data) `refunded_entry_id` points at the chosen expense's entry.
  - Leave the picker "None" → saves an unlinked refund.
  - Switch to Expense/Income/Transfer/Adjust → no "Refunds" row; refund link cleared.
  - Screenshot evidence to `/tmp/refund-<state>.png`.

- [ ] **Step 3 (no commit):** report results; if any check fails, return to the relevant task.

---

## Self-review notes
- Spec coverage: engine resolve + tests (T1), `.refund` Kind (T2 S2), `isLineItem` field/extra gating (T2 S3-S4), source picker (T2 S1/S5/S6), positive amount + explicit kind + link in save (T2 S7), reset on type change (T2 S6), no-split-on-refund (split gate left as expense/income), manual (T3). ✓
- Type consistency: `refundedTxId`, `isLineItem`, `RefundSourcePickerView(onPick:)`, `refundedTransactionId` arg, `resolveEntryRef` used consistently. ✓
- `store.displayMoney(_:from:)` confirmed in use elsewhere (e.g. ScheduledRow). Tuple comparison `($0.date, $0.time ?? "") > …` is valid for `(String, String)`. ✓
