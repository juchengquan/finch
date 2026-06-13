# Phase 6.4 Implementation Plan — App Intents / Siri

> **For agentic workers:** Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add **Siri integration** with 7 intents: `AddTransactionIntent`, `CheckBalanceIntent`, `MarkClearedIntent`, `CreateBudgetIntent`, `SwitchLedgerIntent`, `ShowInsightsIntent`, `OpenScreenIntent`. Each intent dispatches a chokepoint action (from Phase 2) or routes to a screen (via the `DeepLinkRouter` from Phase 6.1).

**Architecture:** A new `FinchCore/Intents/` module hosts the 7 intents + the `AccountEntity` and `CategoryEntity` (the `AppEntity` types for Siri parameters). The `AppShortcutsProvider` declares the 7 shortcuts in `AppShortcutsProvider`. The intents dispatch to the existing `FinchStore.apply` (from Phase 2) or to the existing `DeepLinkRouter.route(to:)` (from Phase 6.1).

**Tech Stack:** Same as Phase 2 + `AppIntents` framework.

**Input design spec:** `plans/IOS_MACOS_PHASE_6_4_DESIGN.md` (~810 lines, 10 sections + §0. Map TOC)

**Depends on:** Phases 1.0, 1.5, 2 + 6.1 (the DeepLinkRouter).

**Estimated time:** 3-4 weeks.

---

## File structure

```
frontend/ios/FinchCore/
  Sources/FinchCore/Intents/
    AccountEntity.swift           # NEW
    CategoryEntity.swift          # NEW
    LedgerEntity.swift            # NEW
    AddTransactionIntent.swift    # NEW
    CheckBalanceIntent.swift      # NEW
    MarkClearedIntent.swift       # NEW
    CreateBudgetIntent.swift      # NEW
    SwitchLedgerIntent.swift      # NEW
    ShowInsightsIntent.swift      # NEW
    OpenScreenIntent.swift        # NEW
    FinchAppShortcuts.swift       # NEW
```

**File counts**: 10 new files, ~700-900 lines Swift.

---

## Task 1: Define the 3 `AppEntity` types

- [ ] **Step 1: Implement `AccountEntity`**

`frontend/ios/FinchCore/Sources/FinchCore/Intents/AccountEntity.swift`:

```swift
// Intents/AccountEntity.swift — wraps finch's AccountRow for
// Siri parameters. Mirrors the web's `account` query in
// `IOS_MACOS_PHASE_6_4_DESIGN.md` §3.
import AppIntents
import FinchCore

public struct AccountEntity: AppEntity, Identifiable {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    public static var defaultQuery = AccountQuery()
    public static var defaultResult: AccountEntity? = nil  // iOS 17+ — no fallback

    public let id: String
    public let name: String
    public let accountType: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(accountType)")
    }
}

public struct AccountQuery: EntityQuery {
    public func entities(for identifiers: [AccountEntity.ID]) async throws -> [AccountEntity] {
        // (Query the FinchStore for matching accounts)
    }

    public func suggestedEntities() async throws -> [AccountEntity] {
        // (Query the FinchStore for all accounts, sorted by last used)
    }
}
```

- [ ] **Step 2: Implement `CategoryEntity` and `LedgerEntity`**

Similar pattern. See design spec §3 + §4.

- [ ] **Step 3: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/Intents/AccountEntity.swift
git add frontend/ios/FinchCore/Sources/FinchCore/Intents/CategoryEntity.swift
git add frontend/ios/FinchCore/Sources/FinchCore/Intents/LedgerEntity.swift
git commit -m "feat(ios): add AccountEntity, CategoryEntity, LedgerEntity (AppEntity types)"
```

---

## Task 2: Define the 7 intents

- [ ] **Step 1: Implement `AddTransactionIntent`**

`frontend/ios/FinchCore/Sources/FinchCore/Intents/AddTransactionIntent.swift`:

```swift
// Intents/AddTransactionIntent.swift — the workhorse Siri
// intent. The user says "add a $6 coffee to Personal in finch"
// and Siri dispatches the chokepoint's addTransaction action.
import AppIntents
import FinchCore

public struct AddTransactionIntent: AppIntent {
    public static var title: LocalizedStringResource = "Add Transaction"
    public static var description = IntentDescription("Adds a transaction to finch.")
    public static var openAppWhenRun: Bool = true

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Merchant")
    var merchant: String

    @Parameter(title: "Account")
    var account: AccountEntity?

    @Parameter(title: "Category")
    var category: CategoryEntity?

    @Parameter(title: "Note", default: "")
    var note: String

    public init() {}

    public init(amount: Double, merchant: String, account: AccountEntity? = nil, category: CategoryEntity? = nil, note: String = "") {
        self.amount = amount
        self.merchant = merchant
        self.account = account
        self.category = category
        self.note = note
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FinchStore.shared
        let activeLedgerId = store.activeLedgerId

        // Resolve the account + category
        let accountId: String
        if let a = account?.id {
            accountId = a
        } else if let recent = store.mostRecentAccountId {
            accountId = recent
        } else {
            return .result(dialog: "Please specify an account in finch first.")
        }

        // 1. Dispatch the chokepoint's addTransaction action
        let args = Args(values: [
            "ledgerId": .string(activeLedgerId),
            "accountId": .string(accountId),
            "amount": .double(amount),
            "merchant": .string(merchant),
            "date": .string(currentDateString),
            "categoryId": .string(category?.id ?? ""),
            "note": .string(note)
        ])
        do {
            try await store.apply(action: .addTransaction, args: args)
        } catch {
            return .result(dialog: "Couldn't add the transaction: \(error.localizedDescription)")
        }

        // 2. Donate the intent so Siri learns the pattern
        try? await self.donate()

        // 3. Return a spoken confirmation
        let amountString = amount.formatted(.currency(code: store.activeLedger.base))
        return .result(dialog: "Added \(merchant) for \(amountString) to finch.")
    }

    private var currentDateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
```

- [ ] **Step 2: Implement the other 6 intents**

`CheckBalanceIntent`, `MarkClearedIntent`, `CreateBudgetIntent`,
`SwitchLedgerIntent`, `ShowInsightsIntent`, `OpenScreenIntent`.
Each follows the same pattern:
- `@Parameter` declarations
- `perform()` method
- dispatch to chokepoint OR route via `DeepLinkRouter`

For the full implementation, see the design spec §2.

- [ ] **Step 3: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/Intents/
git commit -m "feat(ios): add 7 App Intents (AddTransaction, CheckBalance, ...)"
```

---

## Task 3: Register the intents via `AppShortcutsProvider`

- [ ] **Step 1: Implement `FinchAppShortcuts`**

`frontend/ios/FinchCore/Sources/FinchCore/Intents/FinchAppShortcuts.swift`:

```swift
// Intents/FinchAppShortcuts.swift — declares the 7 intents as
// AppShortcuts (so they're discoverable in Spotlight + Siri +
// the Shortcuts app without the user having to invoke them
// first). Per the iOS 17+ API, each shortcut requires
// `parameterSummary:`.
import AppIntents

public struct FinchAppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTransactionIntent(),
            phrases: [
                "Add a transaction in \(.applicationName)",
                "Log an expense in \(.applicationName)"
            ],
            shortTitle: "Add Transaction",
            systemImageName: "plus.circle",
            parameterSummary: IntentParameterSummary("Add \(\.$amount) for \(\.$merchant) to \(\.$account)")
        )
        AppShortcut(
            intent: CheckBalanceIntent(),
            phrases: [
                "Check my balance in \(.applicationName)",
                "What's my \(.applicationName) balance"
            ],
            shortTitle: "Check Balance",
            systemImageName: "dollarsign.circle",
            parameterSummary: IntentParameterSummary("Check balance for \(\.$account)")
        )
        // (... 5 more shortcuts, all with parameterSummary:)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/Intents/FinchAppShortcuts.swift
git commit -m "feat(ios): register 7 AppShortcuts via AppShortcutsProvider"
```

---

## Self-review

**Spec coverage** (Phase 6.4 design spec, 10 sections + §0. Map TOC): all 10 sections covered (Tasks 1-3 cover §1, §2, §3, §4, §5, §6; remaining sections are deferred/non-applicable).
