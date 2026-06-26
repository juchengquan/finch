# Guided reconcile session CP1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the statement-balance-only reconcile with a guided per-account session: tick transactions cleared, watch a cleared-vs-target tracker, finish (Done / Post adjustment).

**Architecture:** No engine change (`setCleared` + `reconcileAccount` exist). (1) FinchCore: a pure `reconcileState` selector. (2) FinchApp: rewrite `ReconcileSheet` — statement inputs + a cleared-ticking transaction list, then a live tracker + conditional finish.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), FinchCore, XcodeGen, XCTest.

## Global Constraints

- **No engine/schema change.** Use `.setCleared` (`{id, cleared}`) and `.reconcileAccount` (`{accountId, statementBalance, statementDate, postAdjustment}`).
- `clearedBalance = account.balance − Σ(confirmed, *un*cleared account txns)` in **native** currency (`Tx.nativeAmount ?? Tx.amount`); `current_balance` excludes pending (verified). `balanced = |difference| < 0.005`.
- Per-account; keep an account **Picker only when `preselect == nil`** (AccountsTab global entry). When `preselect` is set (AccountDetailView), the account is fixed.
- Native money via `store.displayMoney(amount, from: account.currency)`.
- **CP2 (out of scope):** quick-add-missing, confirm-and-clear pending.
- **Must build iOS AND macOS (FinchMac).** Sim `iPhone 17 Pro Max`. New files → `xcodegen generate`. FinchCore: `swift test`; FinchApp: `xcodebuild test`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit; **no `Co-Authored-By` trailer**.

---

## File Structure

**Create (FinchCore):** `ios/FinchCore/Sources/FinchCore/Selectors/ReconcileState.swift`.
**Create (tests):** `ios/FinchCore/Tests/FinchCoreTests/ReconcileStateTests.swift`.
**Modify (FinchApp):** `ios/FinchApp/Sources/FinchApp/WriteScreens/ReconcileSheet.swift` (Tasks 2 & 3).

---

### Task 1: `reconcileState` selector + tests

**Files:**
- Create: `ios/FinchCore/Sources/FinchCore/Selectors/ReconcileState.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests/ReconcileStateTests.swift`

**Interfaces:**
- Produces: `ReconcileState { clearedBalance, difference, balanced, clearedCount, unclearedCount }`; `Selectors.reconcileState(_:_:_:) -> ReconcileState`.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchCore/Tests/FinchCoreTests/ReconcileStateTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class ReconcileStateTests: XCTestCase {
    func test_reconcile_state_cleared_vs_target() throws {
        let q = try TestSeed.base()   // l1 / c1 (USD base)
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("ra"), "ledgerId": .string("l1"), "name": .string("Checking"),
            "type": .string("cash"), "currency": .string("USD"), "openingBalance": .double(100)]))
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("ra"), "amount": .double(-30),
            "merchant": .string("Shop"), "categoryId": .string("c1"), "date": .string("2026-06-10"), "skipRules": .bool(true)]))
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("ra"), "amount": .double(50),
            "merchant": .string("Pay"), "categoryId": .string("c1"), "date": .string("2026-06-11"), "skipRules": .bool(true)]))

        // clear the +50 by its projected id
        let pre = try Projection.run(dbQueue: q, ledgerId: "l1")
        let pay = try XCTUnwrap(pre.first { $0.merchant == "Pay" && $0.account == "ra" })
        try Apply.apply(dbQueue: q, action: "setCleared", args: Args(["id": .string(pay.id), "cleared": .bool(true)]))

        let a = try XCTUnwrap(try Projection.accounts(dbQueue: q, ledgerId: "l1").first { $0.id == "ra" })
        let txns = try Projection.run(dbQueue: q, ledgerId: "l1")

        // balance = 100 − 30 + 50 = 120; clearedBalance = 120 − (−30) = 150 (= opening 100 + cleared 50)
        let s = Selectors.reconcileState(a, txns, 150)
        XCTAssertEqual(s.clearedBalance, 150, accuracy: 0.001)
        XCTAssertEqual(s.difference, 0, accuracy: 0.001)
        XCTAssertTrue(s.balanced)
        XCTAssertEqual(s.clearedCount, 1)     // the +50 (opening leg excluded from projected txns)
        XCTAssertEqual(s.unclearedCount, 1)   // the −30

        let s2 = Selectors.reconcileState(a, txns, 120)
        XCTAssertEqual(s2.difference, -30, accuracy: 0.001)   // 120 − 150
        XCTAssertFalse(s2.balanced)
    }
}
```
(If `createAccount` rejects `"cash"`, use another valid type — `savings`/`credit_card`/`investment`/`cash`/`fx`/`virtual`. The +50 is cleared by its projected `id` so we don't assume `addTransaction` accepts an explicit id.)

- [ ] **Step 2: Run to verify failure**

Run: `cd /Users/blackmount8/_repository/finch/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && swift test --filter ReconcileStateTests`
Expected: FAIL to compile — `ReconcileState`/`reconcileState` undefined.

- [ ] **Step 3: Implement `ReconcileState.swift`**

Create `ios/FinchCore/Sources/FinchCore/Selectors/ReconcileState.swift`:

```swift
import Foundation

/// Live reconcile tracker: how the cleared balance compares to the statement target.
public struct ReconcileState: Equatable, Sendable {
    public let clearedBalance: Double
    public let difference: Double      // statementBalance − clearedBalance
    public let balanced: Bool          // |difference| < 0.005
    public let clearedCount: Int
    public let unclearedCount: Int
    public init(clearedBalance: Double, difference: Double, balanced: Bool, clearedCount: Int, unclearedCount: Int) {
        self.clearedBalance = clearedBalance; self.difference = difference; self.balanced = balanced
        self.clearedCount = clearedCount; self.unclearedCount = unclearedCount
    }
}

extension Selectors {
    /// `statementBalance` and the result are in the account's native currency.
    /// clearedBalance = balance − Σ(confirmed, uncleared account-leg txns) — equals
    /// opening + Σ(confirmed cleared), since the opening leg is always cleared and the
    /// confirmed `balance` already includes it.
    public static func reconcileState(_ account: AccountRow, _ txns: [Tx], _ statementBalance: Double) -> ReconcileState {
        let acct = txns.filter { $0.account == account.id }
        let confirmed = acct.filter { $0.pending != true }
        let uncleared = confirmed.filter { $0.clearedAt == nil }
        let cleared = confirmed.filter { $0.clearedAt != nil }
        let nativeAmt: (Tx) -> Double = { $0.nativeAmount ?? $0.amount }
        let clearedBalance = r2(account.balance - uncleared.reduce(0) { $0 + nativeAmt($1) })
        let difference = r2(statementBalance - clearedBalance)
        return ReconcileState(
            clearedBalance: clearedBalance, difference: difference, balanced: abs(difference) < 0.005,
            clearedCount: cleared.count, unclearedCount: uncleared.count)
    }
}
```

- [ ] **Step 4: Run the test**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter ReconcileStateTests`
Expected: PASS. (If numbers differ, the issue is the native-amount field or the balance/pending assumption — report the actual values; do not fudge the selector.)

- [ ] **Step 5: Full FinchCore suite**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchCore/Sources/FinchCore/Selectors/ReconcileState.swift \
        ios/FinchCore/Tests/FinchCoreTests/ReconcileStateTests.swift
git commit -m "feat(ios): reconcileState selector (cleared-vs-target tracker math)"
```

---

### Task 2: Guided `ReconcileSheet` — inputs + cleared-ticking list

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/ReconcileSheet.swift`

**Interfaces:**
- Consumes: `store.transactions(for:)`, `Tx.clearedAt/pending/nativeAmount/amount/merchant/date`, `.setCleared`, `store.displayMoney(_:from:)`. Finish still uses `.reconcileAccount` (kept from the old flow; Task 3 makes it conditional).

- [ ] **Step 1: Rewrite the sheet body**

Replace the whole contents of `ReconcileSheet.swift` with:

```swift
import SwiftUI
import FinchCore

/// Guided per-account reconcile: enter the statement balance, tick transactions as
/// cleared, and finish. (CP1: ticking + tracker + finish. CP2 adds quick-add + confirm-and-clear.)
struct ReconcileSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let preselect: String?
    @State private var accountId = ""
    @State private var statementBalance = ""
    @State private var date = Date()
    @State private var errorMessage: String?

    init(preselect: String? = nil) { self.preselect = preselect }

    private var account: AccountRow? { store.accounts.first { $0.id == accountId } }

    var body: some View {
        NavigationStack {
            Form {
                if preselect == nil {
                    Picker("Account", selection: $accountId) {
                        ForEach(store.accounts) { Text($0.name ?? "—").tag($0.id) }
                    }
                }
                if let a = account {
                    Section {
                        LabeledContent("Current balance", value: store.displayMoney(a.balance, from: a.currency))
                        HStack {
                            Text("Statement balance"); Spacer()
                            TextField("0.00", text: $statementBalance).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                        DatePicker("Statement date", selection: $date, displayedComponents: .date)
                    }
                    transactionsSection(a)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Reconcile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: finish) { Image(systemName: "checkmark") }.accessibilityLabel("Reconcile").bold()
                }
            }
            .onAppear { if accountId.isEmpty { accountId = preselect ?? store.accounts.first?.id ?? "" } }
        }
    }

    @ViewBuilder private func transactionsSection(_ a: AccountRow) -> some View {
        let txns = store.transactions(for: a.id).filter { $0.pending != true }
        Section("Transactions") {
            if txns.isEmpty {
                Text("No transactions").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(txns, id: \.id) { t in clearRow(a, t) }
            }
        }
    }

    @ViewBuilder private func clearRow(_ a: AccountRow, _ t: Tx) -> some View {
        let cleared = t.clearedAt != nil
        Button { toggleCleared(t, !cleared) } label: {
            HStack {
                Image(systemName: cleared ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(cleared ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.merchant).lineLimit(1)
                    Text(t.date).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(store.displayMoney(t.nativeAmount ?? t.amount, from: a.currency)).fontWeight(.medium)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(cleared ? Color.green.opacity(0.08) : nil)
    }

    private func toggleCleared(_ t: Tx, _ cleared: Bool) {
        do { try store.apply(.setCleared, Args(["id": .string(t.id), "cleared": .bool(cleared)])) }
        catch { errorMessage = i18nMessage(error) }
    }

    private func finish() {
        errorMessage = nil
        guard let bal = DecimalInput.parse(statementBalance) else { errorMessage = "Enter the statement balance."; return }
        do {
            try store.apply(.reconcileAccount, Args([
                "accountId": .string(accountId), "statementBalance": .double(bal),
                "statementDate": .string(AppDate.isoDay.string(from: date)), "postAdjustment": .bool(true)]))
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
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

- [ ] **Step 3: Build macOS (FinchMac)**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/WriteScreens/ReconcileSheet.swift
git commit -m "feat(ios): guided reconcile sheet — statement inputs + cleared-ticking list"
```

---

### Task 3: Cleared-vs-target tracker + conditional finish

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/ReconcileSheet.swift`

**Interfaces:**
- Consumes: `Selectors.reconcileState` (Task 1).

- [ ] **Step 1: Add the tracker section**

In `ReconcileSheet`, add a computed `recState` and a tracker section. After the statement-balance `Section { … }` (and before `transactionsSection(a)`), insert `trackerSection(a)`. Add these methods:

```swift
    private func recState(_ a: AccountRow) -> ReconcileState {
        Selectors.reconcileState(a, store.transactions(for: a.id), DecimalInput.parse(statementBalance) ?? 0)
    }

    @ViewBuilder private func trackerSection(_ a: AccountRow) -> some View {
        if DecimalInput.parse(statementBalance) != nil {
            let s = recState(a)
            Section {
                LabeledContent("Cleared", value: store.displayMoney(s.clearedBalance, from: a.currency))
                LabeledContent("Difference",
                    value: store.displayMoney(s.difference, from: a.currency))
                    .foregroundStyle(s.balanced ? .green : .orange)
                ProgressView(value: progress(s, parse(statementBalance)))
                    .tint(s.balanced ? .green : .orange)
                Text("Cleared \(s.clearedCount) · To review \(s.unclearedCount)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func parse(_ s: String) -> Double { DecimalInput.parse(s) ?? 0 }
    private func progress(_ s: ReconcileState, _ target: Double) -> Double {
        guard target != 0 else { return s.balanced ? 1 : 0 }
        return min(1, max(0, abs(s.clearedBalance / target)))
    }
```
And insert the call in the body — after the inputs `Section`:
```swift
                    transactionsSection(a)
```
becomes:
```swift
                    trackerSection(a)
                    transactionsSection(a)
```

- [ ] **Step 2: Make finish conditional (Done / Post adjustment)**

Replace the `.confirmationAction` toolbar item with two finish controls driven by `balanced`. Change the toolbar's confirmation item to:
```swift
                ToolbarItem(placement: .confirmationAction) {
                    if let a = account, parse(statementBalance) != 0 || !statementBalance.isEmpty {
                        let s = recState(a)
                        if s.balanced {
                            Button { finish(postAdjustment: false) } label: { Text("Done") }.bold()
                        } else {
                            Button { finish(postAdjustment: true) } label: {
                                Text("Adjust \(store.displayMoney(s.difference, from: a.currency))")
                            }
                        }
                    }
                }
```
And replace `finish()` with:
```swift
    private func finish(postAdjustment: Bool) {
        errorMessage = nil
        guard let bal = DecimalInput.parse(statementBalance) else { errorMessage = "Enter the statement balance."; return }
        do {
            try store.apply(.reconcileAccount, Args([
                "accountId": .string(accountId), "statementBalance": .double(bal),
                "statementDate": .string(AppDate.isoDay.string(from: date)), "postAdjustment": .bool(postAdjustment)]))
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
```
(Remove the old single `finish()` and its `.confirmationAction` `Button(action: finish)`.)

- [ ] **Step 3: Build iOS + full FinchApp suite**

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

- [ ] **Step 4: Full FinchCore suite + macOS build**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test 2>&1 | grep -iE "error:|Test Suite 'All tests'"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: FinchCore all pass; `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual verification on the simulator**

Open an account → Reconcile → enter the statement balance → tick transactions: the **Cleared / Difference** values + progress bar update and "Cleared N · To review M" changes. When the difference reaches 0, the toolbar shows **Done** (finishing stamps the checkpoint — the reconcile badge on the account updates); otherwise it shows **Adjust <difference>** (posts the residual adjustment).

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
git add ios/FinchApp/Sources/FinchApp/WriteScreens/ReconcileSheet.swift
git commit -m "feat(ios): reconcile tracker + conditional finish (Done / Post adjustment)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-26-ios-guided-reconcile-cp1-design.md`):
- `reconcileState` selector (clearedBalance native, difference, balanced, counts) + test → Task 1. ✓
- Guided sheet: statement inputs, confirmed-tx list with cleared checkboxes (→ setCleared), highlight, per-account (+ picker when no preselect) → Task 2. ✓
- Tracker (cleared/target/difference + progress + counts) + conditional finish (Done / Post adjustment) → Task 3. ✓
- Replace the old sheet; no engine change; build iOS+macOS → Tasks 2-3. ✓
- CP2 deferred (quick-add, confirm-and-clear). ✓

**Placeholder scan:** No TBD/TODO; full code in every step; sim step concrete. ✓

**Type consistency:** `reconcileState(_ AccountRow, _ [Tx], _ Double) -> ReconcileState` used by `recState`; `.setCleared` `{id, cleared}` + `.reconcileAccount` `{accountId, statementBalance, statementDate, postAdjustment}` match the engine; `Tx.id/clearedAt/pending/nativeAmount/amount/merchant/date`, `store.transactions(for:)`, `store.displayMoney(_:from:)`, `DecimalInput.parse`, `AppDate.isoDay` all exist; both callers (`ReconcileSheet()` / `ReconcileSheet(preselect:)`) still compile. ✓

---

## Out of scope (CP2)

Quick-add-missing (add → auto-clear); confirm-and-clear for pending rows; engine/schema changes.
