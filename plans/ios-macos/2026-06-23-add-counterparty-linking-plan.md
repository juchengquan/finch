# Add Transaction: counterparty linking — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the Add form (expense/income), suggest existing counterparties as the user types the merchant, and offer an explicit "Create" — so the transaction links to a counterparty.

**Architecture:** UI-only. The engine already resolves an existing counterparty by name on save (`Entries.postEntry` → `resolveCounterpartyIdByName`, web parity), and never auto-creates. So the form just (a) surfaces matches so the user types/picks the exact name, and (b) optionally calls `createCounterparty` before `addTransaction` so a new name exists for the resolver to link. No `counterpartyId` is passed; no engine change.

**Tech Stack:** Swift / SwiftUI, GRDB, XcodeGen.

Spec: `plans/ios-macos/2026-06-23-add-counterparty-linking-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before app builds.
- Engine tests: `cd ios/FinchCore && swift test`. App build: scheme `FinchApp`, `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
- Commits: **no `Co-Authored-By` trailer**.
- **No engine / `AddInput` / parity changes** — linking rides the existing `resolveCounterpartyIdByName`. Scope is **expense/income** only (transfer/adjust untouched).
- PR targets `feat/frontend`.

---

### Task 1: FinchCore confidence test — add links existing counterparty by name

A regression test locking the engine contract this feature depends on. The behavior already exists, so the test **passes immediately** (it's a guardrail, not red-green).

**Files:**
- Test: `ios/FinchCore/Tests/FinchCoreTests/AddCounterpartyLinkTests.swift` (create)

- [ ] **Step 1: Write the test**

```swift
import XCTest
import GRDB
@testable import FinchCore

final class AddCounterpartyLinkTests: XCTestCase {
    private func addArgs(_ merchant: String) -> Args {
        Args(["ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-5),
              "merchant": .string(merchant), "categoryId": .string("c1"), "date": .string("2026-06-01")])
    }
    private func counterpartyId(_ q: DatabaseQueue, _ eid: String) throws -> String? {
        try q.read { db in try String.fetchOne(db, sql: "SELECT counterparty_id FROM entries WHERE id = ?", arguments: [eid]) }
    }

    func test_addTransaction_linksExistingCounterpartyByName_caseInsensitive() throws {
        let q = try TestSeed.base()   // l1 / a1 / c1
        try Apply.apply(dbQueue: q, action: "createCounterparty",
                        args: Args(["id": .string("cp1"), "ledgerId": .string("l1"), "name": .string("Starbucks")]))
        let eid = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: addArgs("starbucks"))
        XCTAssertEqual(try counterpartyId(q, eid!), "cp1")
    }

    func test_addTransaction_unknownMerchant_leavesCounterpartyNull_noAutoCreate() throws {
        let q = try TestSeed.base()
        let eid = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: addArgs("Nowhere"))
        XCTAssertNil(try counterpartyId(q, eid!))
        let cpCount = try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM counterparties WHERE ledger_id = 'l1'") }
        XCTAssertEqual(cpCount, 0)   // never auto-creates
    }
}
```

- [ ] **Step 2: Run the test (expect PASS — guardrail on existing behavior)**

Run: `cd ios/FinchCore && swift test --filter AddCounterpartyLinkTests 2>&1 | tail -15`
Expected: PASS (2 tests). If it FAILS, the engine contract differs from the design's assumption — STOP and report before touching the UI.

- [ ] **Step 3: Commit**

```bash
git add ios/FinchCore/Tests/FinchCoreTests/AddCounterpartyLinkTests.swift
git commit -m "test(ios): addTransaction links existing counterparty by name (guardrail)"
```

---

### Task 2: Add form — merchant suggestions + explicit create

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift`

**Interfaces — Consumes:** `store.counterparties: [Counterparty]` (`.id`, `.name`), `createCounterparty` action.

- [ ] **Step 1: Add state**

After `@State private var pickedPhoto: PhotosPickerItem?` (added in the prior tags/receipt feature), add:

```swift
    @State private var createCounterpartyOnSave = false   // set by the "Create <name>" row
```

- [ ] **Step 2: Add the suggestion rows under the Merchant field**

In `expenseIncomeFields`, replace this block:

```swift
            HStack {
                Text(kind == .income ? "Source" : "Merchant"); Spacer()
                TextField("", text: $merchant).multilineTextAlignment(.trailing)
            }
            SearchablePickerRow(title: "Category",
```

with:

```swift
            HStack {
                Text(kind == .income ? "Source" : "Merchant"); Spacer()
                TextField("", text: $merchant).multilineTextAlignment(.trailing)
            }
            merchantSuggestionRows
            SearchablePickerRow(title: "Category",
```

- [ ] **Step 3: Add the `merchantSuggestionRows` view + helpers**

Add these members to `AddTransactionSheet` (e.g. just after `expenseIncomeFields`):

```swift
    /// Existing counterparties (active ledger) whose name contains the typed
    /// merchant text, minus an exact match (nothing to suggest there). Capped at 5.
    private var matchingCounterparties: [Counterparty] {
        let t = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return [] }
        return Array(store.counterparties
            .filter { $0.name.localizedCaseInsensitiveContains(t)
                   && $0.name.caseInsensitiveCompare(t) != .orderedSame }
            .prefix(5))
    }

    /// Suggestion rows shown beneath the Merchant field: matching counterparties
    /// to pick (the engine links them by name on save), plus a "Create <name>" row
    /// for a brand-new name (flagged to create on save). Empty for non-expense/income
    /// or an empty/exact-match field.
    @ViewBuilder private var merchantSuggestionRows: some View {
        let t = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        if (kind == .expense || kind == .income), !t.isEmpty {
            ForEach(matchingCounterparties) { cp in
                Button { pickCounterparty(cp.name) } label: {
                    Label(cp.name, systemImage: "building.2").font(.callout)
                }
            }
            if !store.counterparties.contains(where: { $0.name.caseInsensitiveCompare(t) == .orderedSame }) {
                Button { createCounterpartyOnSave = true } label: {
                    Label("Create “\(t)”", systemImage: "plus.circle").font(.callout)
                }
            }
        }
    }

    private func pickCounterparty(_ name: String) {
        merchant = name
        createCounterpartyOnSave = false
    }
```

- [ ] **Step 4: Reset the create flag when the merchant text changes**

In the existing `.onChange(of: merchant)` closure, add the reset as its first line:

```swift
            .onChange(of: merchant) { _, m in
                createCounterpartyOnSave = false
                guard kind != .transfer, !m.isEmpty else { return }
                if let s = Selectors.suggestCategory(store.txns, store.activeLedgerId, m),
                   categories.contains(where: { $0.id == s.categoryId }) {
                    categoryId = s.categoryId
                }
            }
```

(Note: `pickCounterparty` sets `merchant`, which fires this and resets the flag to `false` — correct, since picking links an existing one without creating. Tapping "Create" doesn't change `merchant`, so the flag it just set survives.)

- [ ] **Step 5: Create the counterparty on save (before addTransaction)**

In `save()`'s expense/income `else` branch, immediately **before** the line
`let eid = try store.applyReturningId(.addTransaction, Args(args))`, insert:

```swift
                if createCounterpartyOnSave {
                    let cpName = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cpName.isEmpty,
                       !store.counterparties.contains(where: { $0.name.caseInsensitiveCompare(cpName) == .orderedSame }) {
                        try store.apply(.createCounterparty, Args([
                            "ledgerId": .string(store.activeLedgerId), "name": .string(cpName)]))
                    }
                }
```

(The `addTransaction` that follows resolves the now-existing name and links it — no `counterpartyId` argument needed. The `!contains` guard avoids a duplicate if it already exists.)

- [ ] **Step 6: Build**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift
git commit -m "feat(ios): Add form — counterparty suggestions + create (expense/income)"
```

---

### Task 3: Manual simulator verification

**Files:** none. Raise the iPhone 17 Pro window by name before taps (a 2nd sim may steal foreground).

- [ ] **Step 1: Install + launch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"; xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```

(Optional seed for the pick case: insert a counterparty so suggestions appear —
`sqlite3 <db> "INSERT INTO counterparties (id,ledger_id,name,is_verified,created_at,updated_at) VALUES ('cp-sb','<ledger>','Starbucks',0,datetime('now'),datetime('now'));"`)

- [ ] **Step 2: Verify**
  - Add → Expense, type "Star" → "Starbucks" suggested → tap → field fills → save → the tx links (appears under that merchant in Power Tools › Merchants / reports).
  - Type a new "Bakery Co" → a `Create "Bakery Co"` row appears → tap → save → "Bakery Co" now exists in Power Tools › Merchants and the tx links to it.
  - Type "oneoff" and DON'T tap Create → save → no new counterparty; tx unlinked.
  - Switch to **Transfer** / **Adjust** → no suggestion rows.
  - Screenshot evidence to `/tmp/cp-link-<state>.png`.

- [ ] **Step 3 (no commit):** report results; if any check fails, return to Task 2.

---

## Self-review notes
- Spec coverage: suggestions section (T2 S2-S3), explicit create flag + create-on-save (T2 S3/S5), flag reset on edit (T2 S4), expense/income gating (T2 S3), no-link case (engine default — covered by T1's null test), engine confidence (T1). ✓
- Type consistency: `createCounterpartyOnSave`, `matchingCounterparties`, `pickCounterparty`, `Counterparty.name` used consistently; `store.applyReturningId` is the existing call site from the prior feature. ✓
- No engine/AddInput edits (scope guard honored). ✓
