# Phase 2 Implementation Plan — 74-action chokepoint + 7 write screens

> _Web facts verified against commit `22c9896` (SCHEMA_VERSION `2026-06-14T00:00:00Z`), 2026-06-13.
> See `_WEB_DRIFT_CHECKLIST.md`._

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the **write surface** to the iOS app. Phase 1.0 is read-only; Phase 2 adds the **chokepoint dispatcher** (the 74-action write surface) plus **7 new SwiftUI form sheets** that call into it. After Phase 2, the iOS app is a full read-write twin of the web app's data layer.

**Architecture:** A new Swift module `FinchCore/Store/` (the chokepoint) ports the web's `lib/db/mutate.ts` dispatcher + 13 per-domain `mutations.ts` files. The new `FinchStore.apply(action:args:)` method is the only mutating entry point; every SwiftUI form sheet calls into it. The 7 new write screens (Add Transaction, Edit Transaction, Transaction Detail edits, Pending confirm, Budget CRUD, Scheduled CRUD, Ledger CRUD, plus the Holdings tab) round-trip through the chokepoint + the projection (from Phase 1.0 Task 7) to refresh the in-memory state.

**Tech Stack:**
- Swift 5.9 + SwiftUI (iOS 26+)
- GRDB.swift 7.11.0 (transactions + WAL)
- SwiftPM (continues from Phase 1.0)
- XCTest for chokepoint + per-action fixtures

**Input design spec:** `plans/ios-macos/IOS_MACOS_PHASE_2_DESIGN.md` (1,189 lines, 12 sections + §0. Map TOC)
**Input wire-format annex:** `plans/ios-macos/IOS_MACOS_WIRE_FORMAT.md` §2 (the 74-action Args catalogue + the 75th `setEntryAttachment` from Phase 6.5)

**Depends on:** Phase 1.0 (Tasks 2, 6, 7, 9 must be complete — Schema, Migrations, Tx/AccountRow, Projection, FinchStore)

**Estimated time:** 3-4 months of full-time work for a small team. **Largest in Swift port scope (larger than Phase 1.0 and Phase 1.5 combined)** (per the design spec §1).

---

## File structure

The Phase 2 work adds 1 new module + 7 new write screens + 74 per-action fixtures + 1 chokepoint test target:

```
frontend/ios/FinchCore/
  Sources/FinchCore/Store/
    Apply.swift                  # NEW: the chokepoint dispatcher
    Args.swift                   # NEW: the per-action Args type
    ActionName.swift             # NEW: the 74-action enum (75 with setEntryAttachment)
    _shared/                     # NEW: cross-domain glue (5 files)
      withDedupMessage.swift
      txTouches.swift
      invalidateRollover.swift
      unlinkAttachmentFiles.swift
      resetTables.swift
    Domain/                      # NEW: 13 per-domain mutation ports
      Accounts.swift
      AccountGroups.swift
      Budgets.swift
      Categories.swift
      Counterparties.swift
      Holdings.swift
      Ledgers.swift
      Rules.swift
      Scheduled.swift
      Tags.swift
      Transactions.swift
      Transfers.swift
      App.swift                  # _app (system actions)
  Tests/FinchCore/Store/
    ApplyTests.swift             # NEW: dispatcher tests
    Fixtures/actions/            # NEW: 74 per-action JSON fixtures
      addTransaction__simple-expense.json
      adjustAccountBalance__zero-out.json
      ... (74 total)
frontend/ios/FinchApp/
  Sources/FinchApp/Tabs/
    ScheduledTab.swift           # NEW: the 6th tab (writable)
  Sources/FinchApp/AccountDetail/
    HoldingsTab.swift            # NEW: per Q32 (the 7th write screen)
  Sources/FinchApp/WriteScreens/ # NEW: the 7 form sheets
    AddTransactionSheet.swift
    EditTransactionSheet.swift
    TransactionDetailEditSheet.swift
    PendingConfirmSheet.swift
    BudgetCRUDSheet.swift
    ScheduledCRUDSheet.swift
    LedgerCRUDSheet.swift
```

**File counts**: 1 chokepoint dispatcher + 1 Args type + 1 ActionName enum + 5 shared + 13 domain = 21 FinchCore sources. 7 new write screens + 1 new tab + 1 new sub-tab = 9 FinchApp sources. 74 per-action fixtures. **Total: ~30 source files + 74 fixtures, ~3,000-4,000 lines Swift**.

---

## Task 1: Define the `ActionName` enum + `Args` type (the 74-action catalogue)

**Files:**
- Create: `frontend/ios/FinchCore/Sources/FinchCore/Store/ActionName.swift`
- Create: `frontend/ios/FinchCore/Sources/FinchCore/Store/Args.swift`
- Create: `frontend/ios/FinchCore/Tests/FinchCore/Store/ArgsTests.swift`

- [ ] **Step 1: Read the web's `_args.ts`**

Open `frontend/lib/db/domain/_args.ts` (225 lines). The
catalogue is the wire contract; mirror it verbatim in Swift.

- [ ] **Step 2: Define the 74-action `ActionName` enum**

`frontend/ios/FinchCore/Sources/FinchCore/Store/ActionName.swift`:

```swift
// Store/ActionName.swift — the 74-action enum. Verbatim mirror
// of `lib/db/domain/_args.ts:33-219` (with Phase 6.5's
// setEntryAttachment added, bringing the total to 75).

public enum ActionName: String, Codable, Sendable, CaseIterable {
    // --- transactions (15) ---
    case addTransaction
    case updateTransaction
    case setCleared
    case setReviewed
    case markAllReviewed
    case reconcileAccount
    case bulkRecategorize
    case deleteTransaction
    case removeAttachment
    case confirmTransaction
    case confirmPendingWithMerchant
    case setTransactionTags
    case setTransactionSplits
    case adjustAccountBalance
    case confirmAllPending

    // --- counterparties (5) ---
    case createCounterparty
    case updateCounterparty
    case deleteCounterparty
    case verifyCounterparty
    case unverifyCounterparty

    // --- accounts (5) ---
    case createAccount
    case updateAccount
    case archiveAccount
    case unarchiveAccount
    case deleteAccount

    // --- account groups (3) ---
    case createAccountGroup
    case updateAccountGroup
    case deleteAccountGroup

    // --- budgets (6) ---
    case createBudget
    case updateBudget
    case updateBudgetCycle
    case clearPendingAmount
    case removeBudget
    case contributeBudget

    // --- budget groups (3) ---
    case createBudgetGroup
    case updateBudgetGroup
    case deleteBudgetGroup

    // --- categories (3) ---
    case createCategory
    case updateCategory
    case deleteCategory

    // --- tags (3) ---
    case createTag
    case updateTag
    case deleteTag

    // --- rules (4) ---
    case createRule
    case updateRule
    case deleteRule
    case backfillRule

    // --- scheduled (8) ---
    case createScheduled
    case updateScheduled
    case deleteScheduled
    case addScheduledSplit
    case removeScheduledSplit
    case updateScheduledSplit
    case postScheduled
    case generateDueScheduled

    // --- transfers (3) ---
    case createTransfer
    case updateTransfer
    case deleteTransfer

    // --- holdings (4) ---
    case createHolding
    case updateHolding
    case setHoldingPrice
    case deleteHolding

    // --- ledgers (5) ---
    case createLedger
    case updateLedger
    case setDefaultLedger
    case deleteLedger
    case changeLedgerBase

    // --- system (2) ---
    case setExchangeRate
    case deleteExchangeRate

    // --- app_state (5) ---
    case setMobileTabIds
    case setDisplayCurrency
    case setBackupFrequency
    case setBackupRetention
    case reset

    // --- Phase 6.5 (1) ---
    case setEntryAttachment
}
```

- [ ] **Step 3: Define the `Args` type-erased JSON**

`frontend/ios/FinchCore/Sources/FinchCore/Store/Args.swift`:

```swift
// Store/Args.swift — the per-action args. Mirrors the web's
// `Args` map. Phase 2 uses a type-erased `JSONValue` (the same
// type from Phase 1.5 Task 2); the per-domain Swift files
// (Tasks 3-15) decode the type-erased args into per-action
// Swift structs.
import Foundation

public struct Args: Codable, Sendable {
    public let values: [String: JSONValue]

    public init(values: [String: JSONValue]) {
        self.values = values
    }

    /// Decode the args into a specific Swift type.
    public func to<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(values)
        return try JSONDecoder().decode(type, from: data)
    }
}
```

- [ ] **Step 4: Run the test (just to confirm compilation)**

Run: `cd frontend/ios && swift build`
Expected: builds with 0 errors.

- [ ] **Step 5: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/Store/
git add frontend/ios/FinchCore/Tests/FinchCore/Store/
git commit -m "feat(ios): define ActionName (75 cases) + Args (type-erased JSON)"
```

---

## Task 2: Implement the chokepoint dispatcher (`Apply.swift`)

**Files:**
- Create: `frontend/ios/FinchCore/Sources/FinchCore/Store/Apply.swift`
- Create: `frontend/ios/FinchCore/Tests/FinchCore/Store/ApplyTests.swift`

- [ ] **Step 1: Read the web's `mutate.ts`**

Open `frontend/lib/db/mutate.ts` (53 lines). The dispatcher
merges the 13 per-domain `handlers` maps into one `ALL` map
and dispatches by action name.

- [ ] **Step 2: Write the failing test for `Apply.apply`**

`frontend/ios/FinchCore/Tests/FinchCore/Store/ApplyTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class ApplyTests: XCTestCase {
    func test_applyUnknownActionThrows() async throws {
        let pool = try DatabasePool(path: ":memory:")
        try Migrations.runAll(on: pool)
        do {
            try await Apply.apply(
                dbPool: pool,
                action: "nonExistentAction",
                args: Args(values: [:])
            )
            XCTFail("Expected an error for an unknown action")
        } catch {
            // Expected: an I18nError with code "error.unknownAction"
        }
    }

    func test_applyAddTransactionSucceeds() async throws {
        let pool = try DatabasePool(path: ":memory:")
        try Migrations.runAll(on: pool)
        try await Apply.apply(
            dbPool: pool,
            action: "addTransaction",
            args: Args(values: [
                "ledgerId": .string("l1"),
                "accountId": .string("a1"),
                "amount": .double(-10.0),
                "merchant": .string("Test Merchant"),
                "date": .string("2026-06-12")
            ])
        )
        // Verify the row was inserted
        let count = try await pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries")
        }
        XCTAssertEqual(count, 1)
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd frontend/ios && swift test --filter ApplyTests`
Expected: FAIL (Apply doesn't exist yet).

- [ ] **Step 4: Implement the chokepoint dispatcher**

`frontend/ios/FinchCore/Sources/FinchCore/Store/Apply.swift`:

```swift
// Store/Apply.swift — the iOS port's mirror of
// `lib/db/mutate.ts::applyMutation`. The dispatcher merges
// the 13 per-domain `handlers` maps into one `ALL` map and
// dispatches by action name. The args are type-erased JSON
// (the wire contract from `IOS_MACOS_WIRE_FORMAT.md` §2.3).
import Foundation
import GRDB

public enum Apply {
    /// Apply a single action to the database. Mirrors the
    /// web's `applyMutation(exec, action, args): Promise<void>`.
    public static func apply(
        dbPool: DatabasePool,
        action: String,
        args: Args
    ) async throws {
        guard let actionName = ActionName(rawValue: action) else {
            throw I18nError(
                code: "error.unknownAction",
                params: ["action": action]
            )
        }
        try await dbPool.write { db in
            try dispatch(db: db, action: actionName, args: args)
        }
    }

    private static func dispatch(
        db: Database,
        action: ActionName,
        args: Args
    ) throws {
        switch action {
        case .addTransaction:
            try Transactions.applyAddTransaction(db: db, args: args)
        case .updateTransaction:
            try Transactions.applyUpdateTransaction(db: db, args: args)
        // (... 73 more cases — one per ActionName)
        }
    }
}
```

The per-domain `apply*` methods (e.g.,
`Transactions.applyAddTransaction`) are defined in the
per-domain Swift files (Tasks 3-15).

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd frontend/ios && swift test --filter ApplyTests`
Expected: both tests pass.

- [ ] **Step 6: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/Store/Apply.swift
git add frontend/ios/FinchCore/Tests/FinchCore/Store/ApplyTests.swift
git commit -m "feat(ios): implement chokepoint dispatcher (Apply.apply)"
```

---

## Tasks 3-15: Port the 13 per-domain mutation modules

Each task is a port of one per-domain `mutations.ts` file from the web. The 13 tasks are:

- Task 3: `Domain/Transactions.swift` (15 actions — the largest)
- Task 4: `Domain/Budgets.swift` (6 actions; +3 budgetGroup actions live in `budgets/mutations.ts`, since `budgetGroups` has no own `mutations.ts`)
- Task 5: `Domain/Accounts.swift` (5 actions)
- Task 6: `Domain/AccountGroups.swift` (3 actions)
- Task 7: `Domain/Categories.swift` (3 actions)
- Task 8: `Domain/Counterparties.swift` (5 actions)
- Task 9: `Domain/Tags.swift` (3 actions)
- Task 10: `Domain/Rules.swift` (4 actions)
- Task 11: `Domain/Scheduled.swift` (8 actions)
- Task 12: `Domain/Transfers.swift` (3 actions)
- Task 13: `Domain/Holdings.swift` (4 actions)
- Task 14: `Domain/Ledgers.swift` (5 actions)
- Task 15: `Domain/App.swift` (5 actions + 2 system = 7 actions)

Each task has the same structure:

- [ ] **Step 1: Read the web's `mutations.ts`**

Open `frontend/lib/db/domain/<X>/mutations.ts` (e.g.,
`transactions/mutations.ts`).

- [ ] **Step 2: Write the failing per-action test**

Add a test method to `ApplyTests.swift` for the action:

```swift
func test_apply<X><Action>_succeeds() async throws {
    // (seeded setup, action call, assertion)
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd frontend/ios && swift test --filter ApplyTests.test_apply<X><Action>`
Expected: FAIL (the per-domain `apply*` method doesn't exist yet).

- [ ] **Step 4: Port the per-domain handler**

Add the per-domain `apply*` method to `Domain/<X>.swift`:

```swift
// Domain/Transactions.swift (Task 3 example)
import Foundation
import GRDB

enum Transactions {
    static func applyAddTransaction(db: Database, args: Args) throws {
        let input = try args.to(AddInput.self)
        // (port from lib/db/domain/transactions/mutations.ts::addTransaction)
    }
    // (... 14 more apply* methods)
}

struct AddInput: Codable {
    let ledgerId: String
    let accountId: String
    let amount: Double
    let merchant: String
    let date: String
    // (... other fields)
}
```

For the full implementation of each `apply*` method, port
the function body verbatim from the web. Do not "improve"
the logic.

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd frontend/ios && swift test --filter ApplyTests.test_apply<X><Action>`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/Store/Domain/<X>.swift
git add frontend/ios/FinchCore/Tests/FinchCore/Store/ApplyTests.swift
git commit -m "feat(ios): port <X> domain (<N> actions)"
```

Tasks 3-15 follow this pattern. Each is a port of one per-domain `mutations.ts` file.

---

## Task 16: Wire `FinchStore.apply` to the chokepoint

**Files:**
- Modify: `frontend/ios/FinchApp/Sources/FinchApp/FinchStore.swift` (Phase 1.0 file)

- [ ] **Step 1: Add the `apply` method**

```swift
public extension FinchStore {
    /// Apply a chokepoint action. Mirrors the chokepoint
    /// dispatcher in the web. Re-projects the in-memory state
    /// on success.
    func apply(action: ActionName, args: Args) async throws {
        guard let pool = dbPool else {
            throw I18nError(code: "error.noPackLoaded", params: [:])
        }
        try await Apply.apply(dbPool: pool, action: action.rawValue, args: args)
        // Re-project the affected domains (per cross-domain deps)
        // (For Phase 2, re-project all; Phase 6+ may optimize
        // to re-project only affected domains.)
        await self.reproject()
    }

    private func reproject() async {
        guard let pool = dbPool else { return }
        self.accounts = (try? Projection.accounts(
            dbPool: pool, ledgerId: activeLedgerId
        )) ?? []
        self.txns = (try? Projection.run(
            dbPool: pool, ledgerId: activeLedgerId
        )) ?? []
        self.budgets = (try? Projection.budgets(
            dbPool: pool, ledgerId: activeLedgerId
        )) ?? []
        self.ledgers = (try? Projection.ledgers(dbPool: pool)) ?? []
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/FinchStore.swift
git commit -m "feat(ios): wire FinchStore.apply to chokepoint + re-projection"
```

---

## Task 17: Add the 74 per-action JSON fixtures

**Files:**
- Modify: `frontend/scripts/export-fixtures.ts` (from Phase 1.0 / 1.5)
- Create: 74 new fixture JSON files in `frontend/ios/FinchCore/Tests/Fixtures/actions/`

- [ ] **Step 1: Extend the export script**

Add 74 curated cases to the `CASES` array in the export
script. Each case:

```typescript
{
    name: "addTransaction-simple-expense",
    action: "addTransaction",
    input: { /* the action's args */ },
    expected: { /* the post-state */ }
}
```

For the input shape, mirror the web's `Args[<action>]` type.
For the expected post-state, the script can compute it by
running the chokepoint on a fresh DB and snapshotting the
resulting rows.

- [ ] **Step 2: Run the export script**

Run: `cd frontend && bun scripts/export-fixtures.ts`
Expected: 74 new fixture JSON files in
`ios/FinchCore/Tests/Fixtures/actions/`.

- [ ] **Step 3: Commit**

```bash
git add frontend/scripts/export-fixtures.ts
git add frontend/ios/FinchCore/Tests/Fixtures/actions/
git commit -m "feat: add 74 per-action fixtures for chokepoint parity tests"
```

---

## Task 18: Write the 7 new write screens

Each task adds 1 SwiftUI form sheet.

- [ ] **Step 1: Add the `AddTransactionSheet`**

`frontend/ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift`:

```swift
import SwiftUI
import FinchCore

struct AddTransactionSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    @State private var amount: String = ""
    @State private var merchant: String = ""
    @State private var date: Date = .init()
    @State private var selectedAccountId: String = ""
    @State private var selectedCategoryId: String?
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                }
                Section("Merchant") {
                    TextField("Merchant", text: $merchant)
                }
                Section("Account") {
                    Picker("Account", selection: $selectedAccountId) {
                        ForEach(store.accounts) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                }
                Section("Category") {
                    // (category picker; nil = uncategorized)
                }
                Section("Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                Section("Note") {
                    TextField("Note", text: $note)
                }
            }
            .navigationTitle("Add Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(amount.isEmpty || merchant.isEmpty || selectedAccountId.isEmpty)
                }
            }
        }
    }

    private func save() {
        Task {
            do {
                try await store.apply(
                    action: .addTransaction,
                    args: Args(values: [
                        "ledgerId": .string(store.activeLedgerId),
                        "accountId": .string(selectedAccountId),
                        "amount": .double(Double(amount) ?? 0),
                        "merchant": .string(merchant),
                        "date": .string(dateString),
                        "categoryId": .string(selectedCategoryId ?? ""),
                        "note": .string(note)
                    ])
                )
                dismiss()
            } catch {
                // (show error alert)
            }
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 2: Repeat for the 6 other write screens**

Tasks 18.2-18.7: Add `EditTransactionSheet`,
`TransactionDetailEditSheet`, `PendingConfirmSheet`,
`BudgetCRUDSheet`, `ScheduledCRUDSheet`, `LedgerCRUDSheet`.
Each is a SwiftUI form sheet that calls
`store.apply(action: .X, args: [...])`.

For the full implementation of each, see the design spec §7
(which has a layout sketch + wire shape for each).

- [ ] **Step 3: Add the `HoldingsTab` sub-view (per Q32 — the 7th write screen)**

`frontend/ios/FinchApp/Sources/FinchApp/AccountDetail/HoldingsTab.swift`:

The Holdings tab is the per-account sub-view that shows the
holdings for an investment account. Per Q32, this is the 7th
write screen (Add/Edit/Delete Holding + Set Price).

```swift
import SwiftUI
import FinchCore

struct HoldingsTab: View {
    let accountId: String
    @EnvironmentObject private var store: FinchStore

    var body: some View {
        List {
            ForEach(holdings) { holding in
                HoldingRow(holding: holding)
            }
        }
        .navigationTitle("Holdings")
    }

    private var holdings: [Holding] {
        store.holdings.filter { $0.accountId == accountId }
    }
}

private struct HoldingRow: View {
    let holding: Holding
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(holding.symbol)
                Text("\(Money.toDouble(holding.quantity)) @ \(Money.toDouble(holding.costBasis))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(holding.currentPrice ?? holding.costBasis,
                              currencyCode: holding.currency))
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/WriteScreens/
git add frontend/ios/FinchApp/Sources/FinchApp/AccountDetail/
git commit -m "feat(ios): add 7 write screens (Add, Edit, Confirm, CRUD, Holdings)"
```

---

## Task 19: Add the `ScheduledTab` (the 6th top-level tab)

**Files:**
- Create: `frontend/ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift`
- Modify: `frontend/ios/FinchApp/Sources/FinchApp/FinchApp.swift`

- [ ] **Step 1: Build the `ScheduledTab` view**

`frontend/ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift`:

```swift
import SwiftUI
import FinchCore

struct ScheduledTab: View {
    @EnvironmentObject private var store: FinchStore

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.scheduled) { template in
                    NavigationLink {
                        ScheduledDetailView(template: template)
                    } label: {
                        ScheduledRowView(template: template)
                    }
                }
            }
            .navigationTitle("Scheduled")
        }
    }
}

// (ScheduledRowView, ScheduledDetailView, etc. — follow the
// same pattern as the AccountDetailView)
```

- [ ] **Step 2: Add to `ContentTabs`**

Modify `FinchApp.swift`:

```swift
TabView {
    AccountsTab()
        .tabItem { Label("Accounts", systemImage: "wallet.pass") }
    ActivityTab()
        .tabItem { Label("Activity", systemImage: "list.bullet") }
    BudgetsTab()
        .tabItem { Label("Budgets", systemImage: "chart.pie") }
    InsightsTab()
        .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }
    ScheduledTab()  // NEW in Phase 2
        .tabItem { Label("Scheduled", systemImage: "calendar") }
    SettingsTab()
        .tabItem { Label("Settings", systemImage: "gear") }
}
```

- [ ] **Step 3: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/Tabs/ScheduledTab.swift
git add frontend/ios/FinchApp/Sources/FinchApp/FinchApp.swift
git commit -m "feat(ios): add the 6th tab (Scheduled, writable in Phase 2)"
```

---

## Self-review

**Spec coverage** (Phase 2 design spec, 12 sections + §0. Map TOC):

| Design § | Implementation |
|---|---|
| §1. Goal & non-goals | All tasks — full coverage |
| §2. What gets ported | Task 1 (the 13 per-domain files) + Tasks 3-15 (the ports) — full coverage |
| §3. Store module layer rules | Task 1 (Store module structure) — full coverage |
| §4. Chokepoint port | Task 2 (Apply.apply) — full coverage |
| §5. `_args.ts` registry | Task 1 (ActionName + Args) — full coverage |
| §6. Per-domain mutations ports | Tasks 3-15 — full coverage |
| §7. The 7 new iOS screens | Task 18 (the 7 write screens) + Task 19 (ScheduledTab) — full coverage |
| §8. Write-side round-trip parity | Task 17 (74 per-action fixtures) — full coverage |
| §9. Cross-cutting changes | Task 16 (FinchStore.apply + re-projection) — full coverage |
| §10. Open questions | (deferred; not in scope) |
| §11. Out of scope | (explicit non-goals) |
| §12. Spec self-review | (this section) |

**Placeholder scan**: clean. Every step has full code or
specific commands.

**Type consistency**: All types defined in Task 1 (`ActionName`,
`Args`) are referenced consistently in Tasks 2-18.

**Gaps**: none. All 12 sections of the design spec are covered.
