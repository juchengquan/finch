# finch for iOS & macOS — Phase 6.4 Implementation Design (App Intents / Siri)

> **Status**: design spec — not yet an implementation plan. Once
> approved, this becomes the input to `writing-plans` to produce a
> step-by-step implementation plan for Phase 6.4.
>
> Companion documents:
>
> - `plans/IOS_MACOS_PLAN.md` — direction brief
> - `plans/IOS_MACOS_PHASE_1_DESIGN.md` through `IOS_MACOS_PHASE_5_DESIGN.md` —
>   Phases 1.0 through 5 full designs
> - `plans/IOS_MACOS_PHASE_6_1_DESIGN.md` — Phase 6.1 (Spotlight)
> - `plans/IOS_MACOS_PHASE_6_2_DESIGN.md` — Phase 6.2 (Notifications)
> - `plans/IOS_MACOS_PHASE_6_3_DESIGN.md` — Phase 6.3 (Biometric)
> - `plans/IOS_MACOS_PHASE_7_DESIGN.md` — Phase 7 (widgets + Watch)
> - `plans/IOS_MACOS_ROADMAP.md` — 8-phase arc
> - `plans/IOS_MACOS_PHASE_6_4_DESIGN.md` (this file) — Phase 6.4
>
> Phase 6 is decomposed into 5 sub-specs (6.1-6.5). This is
> 6.4: App Intents / Siri via the `AppIntents` framework.
> Phases 6.1-6.3 are independently shipped. Phase 6.5 ships
> in any order.
>
> _Audience: the engineers who will build the iOS app. Assumes
> Phases 1.0-5 are complete._

## §1. Goal & non-goals

**Goal** — Add **Siri** integration so the user can:

- **Add a transaction via voice**: "Hey Siri, add a $6
  coffee to Personal in finch" → an `AddTransaction` intent
  dispatches through the Phase 2 chokepoint
- **Check account balances via voice**: "Hey Siri, what's
  my Chase Checking balance in finch?" → a `CheckBalance`
  intent reads from the local DB
- **Mark transactions as cleared via voice**: "Hey Siri,
  mark my last 5 transactions as cleared in finch" → a
  `MarkCleared` intent dispatches through the chokepoint
- **Siri Suggestions**: the intents are donated to Siri
  on first use; the system learns the user's habitual
  entries (e.g., the user's morning "add coffee" pattern)

**The intent dispatches through the chokepoint — there is
no other write path.** This is the plan's §7 explicit
constraint.

**Non-goals (firm)**:

- **No new tabs / write screens / power features** — the 6
  tabs + 6 write screens + 7 power features are unchanged.
  Phase 6.4 adds a **voice surface** that dispatches
  existing actions.
- **No new selectors** — the Phase 1.5 selectors are the
  full set. The intents read from the in-memory `Tx[]` +
  `AccountRow[]` + `Category[]` caches.
- **No new chokepoint actions** — the chokepoint is
  unchanged. The intents dispatch the existing 74
  actions.
- **No Siri on Mac** — macOS supports Siri, but the
  App Intents framework is iOS / iPadOS / watchOS focused.
  The Mac equivalent is **Shortcuts** (the macOS Sonoma+
  feature). Phase 6.4 is iOS-only; Shortcuts is a
  follow-up.
- **No natural-language parsing of arbitrary phrases** —
  the intents are **explicit** (the user invokes
  "add a $6 coffee to Personal in finch" and Siri matches
  it to the `AddTransaction` intent). The user doesn't
  need to guess the phrasing. If Siri can't disambiguate
  (e.g., "which account?"), the `IntentDialog` API asks
  for clarification.
- **No Shortcuts on Mac** — that's a future phase.
- **No Siri dictation for free-form text** — Siri's
  natural language is for the intent's structured
  parameters; free-form text in the intent's `note`
  field is supported via the standard Siri
  dictation-to-text flow.
- **No biometric re-auth for Siri intents** — the
  proposal doesn't require biometric re-auth for
  Siri-dispatched actions (the user is already
  authenticated by their device's biometric to invoke
  Siri). A future phase may add per-intent biometric
  re-auth for sensitive actions.

**Estimated scope**: ~1,000-1,400 lines Swift (the 7 intents
+ 3 AppEntity types + the intent donation + the dialog
flow) + ~300 lines tests. **3-4 weeks of full-time work**
for a small team.

## §2. The 7 intents

Phase 6.4 ships **7 intents** (the plan's §7 list, verbatim):
AddTransaction, CheckBalance, MarkCleared, CreateBudget,
SwitchLedger, ShowInsights, OpenScreen. The 3 in the
proposal were the minimum useful set; the resolution-pass
expanded to the full 7.

### 2.1 — `AddTransactionIntent`

```swift
// ios/FinchApp/AppIntents/AddTransactionIntent.swift
import AppIntents

public struct AddTransactionIntent: AppIntent {
    public static var title: LocalizedStringResource = "Add Transaction"
    public static var description = IntentDescription(
        "Adds a new transaction to your active finch ledger."
    )
    public static var openAppWhenRun: Bool = true  // opens the iOS app to show the result

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Description")
    var description: String

    @Parameter(title: "Account", default: nil)
    var account: AccountEntity?

    @Parameter(title: "Category", default: nil)
    var category: CategoryEntity?

    @Parameter(title: "Note", default: nil)
    var note: String?

    public init() {}

    public init(amount: Double, description: String, account: AccountEntity? = nil, category: CategoryEntity? = nil, note: String? = nil) {
        self.amount = amount
        self.description = description
        self.account = account
        self.category = category
        self.note = note
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        // 1. Resolve the active ledger + active account
        let store = FinchStore.shared
        guard let activeLedgerId = store.activeLedgerId else {
            return .result(dialog: "Please open finch and select a ledger first.")
        }
        // If account is nil, use the most-recently-used account
        let accountId = account?.id ?? store.mostRecentAccountId ?? {
            return .result(dialog: "Please specify an account in finch first.")
        }()
        // If category is nil, use the most-recently-used category
        let categoryId = category?.id ?? store.mostRecentCategoryId

        // 2. Dispatch the chokepoint
        let args: [String: Any] = [
            "ledgerId": activeLedgerId,
            "accountId": accountId,
            "amount": amount,
            "date": ISO8601DateFormatter().string(from: Date()),
            "description": description,
            "categoryId": categoryId as Any,
            "note": note as Any
        ]
        do {
            try await store.apply(action: "addTransaction", args: args)
        } catch {
            return .result(dialog: "Couldn't add the transaction: \(error.localizedDescription)")
        }

        // 3. Donate the intent so Siri learns the pattern
        let donation = IntentDonation(self)
        try? await IntentDonationDonor.shared.donate(donation)

        // 4. Return a spoken confirmation
        let amountString = NumberFormatter.localizedString(from: NSNumber(value: amount), number: .currency)
        return .result(dialog: "Added \(description) for \(amountString) to finch.")
    }
}
```

The intent's `perform()`:
1. Resolves the active ledger + the specified (or
   default) account and category
2. Dispatches the chokepoint's `addTransaction` action
3. Donates the intent (so Siri learns the user's
   pattern)
4. Returns a spoken confirmation via `ProvidesDialog`

If the user invokes the intent with insufficient
parameters (e.g., "Hey Siri, add a transaction in finch"
without amount / description), the system shows a
disambiguation dialog (handled by the `IntentDialog`
machinery + the iOS app's intent confirmation flow).

### 2.2 — `CheckBalanceIntent`

```swift
public struct CheckBalanceIntent: AppIntent {
    public static var title: LocalizedStringResource = "Check Balance"
    public static var description = IntentDescription("Reads your finch account balance.")
    public static var openAppWhenRun: Bool = false  // pure read; no app open needed

    @Parameter(title: "Account")
    var account: AccountEntity?

    public init() {}

    public init(account: AccountEntity? = nil) {
        self.account = account
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let store = FinchStore.shared
        let accountId: String
        if let account = account {
            accountId = account.id
        } else if let defaultId = store.defaultAccountId {
            accountId = defaultId
        } else {
            return .result(value: 0, dialog: "No active account in finch.")
        }

        let balance = store.accounts.first(where: { $0.id == accountId })?.currentBalance ?? 0
        let balanceString = NumberFormatter.localizedString(from: NSNumber(value: balance), number: .currency)
        let accountName = store.accounts.first(where: { $0.id == accountId })?.name ?? "your account"
        return .result(value: balance, dialog: "Your \(accountName) balance is \(balanceString).")
    }
}
```

The intent reads from the in-memory `AccountRow[]` cache
(Phase 1.0). `openAppWhenRun: false` — the intent
returns a spoken response without opening the iOS app.

### 2.3 — `MarkClearedIntent`

```swift
public struct MarkClearedIntent: AppIntent {
    public static var title: LocalizedStringResource = "Mark Transactions Cleared"
    public static var description = IntentDescription("Marks recent transactions as cleared in finch.")
    public static var openAppWhenRun: Bool = true

    @Parameter(title: "How many recent transactions", default: 5)
    var count: Int

    public init() {}

    public init(count: Int = 5) {
        self.count = count
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FinchStore.shared
        let recent = store.txns.sorted(by: { $0.date > $1.date }).prefix(count)
        var count = 0
        for tx in recent {
            do {
                try await store.apply(action: "setCleared", args: ["id": tx.id, "cleared": true])
                count += 1
            } catch {
                // Continue with the next transaction
            }
        }
        return .result(dialog: "Marked \(count) transactions as cleared in finch.")
    }
}
```

The intent dispatches `setCleared` for each of the N
most-recent transactions. If a transaction is already
cleared, the chokepoint's `setCleared` is a no-op (the
action is idempotent). `openAppWhenRun: true` — the user
sees the result in the Activity tab.

### 2.4 — `CreateBudgetIntent`

```swift
public struct CreateBudgetIntent: AppIntent {
    public static var title: LocalizedStringResource = "Create Budget"
    public static var description = IntentDescription(
        "Creates a new budget in your active finch ledger."
    )
    public static var openAppWhenRun: Bool = true

    @Parameter(title: "Budget name")
    var name: String

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Period", default: "monthly")
    var period: String

    @Parameter(title: "Category", default: nil)
    var category: CategoryEntity?

    public init() {}

    public init(name: String, amount: Double, period: String = "monthly", category: CategoryEntity? = nil) {
        self.name = name
        self.amount = amount
        self.period = period
        self.category = category
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FinchStore.shared
        guard let activeLedgerId = store.activeLedgerId else {
            return .result(dialog: "Please open finch and select a ledger first.")
        }
        let args: [String: Any] = [
            "ledgerId": activeLedgerId,
            "name": name,
            "limit": amount,
            "period": period,
            "categoryId": category?.id as Any
        ]
        do {
            try await store.apply(action: "createBudget", args: args)
        } catch {
            return .result(dialog: "Couldn't create the budget: \(error.localizedDescription)")
        }
        return .result(dialog: "Created \(name) budget for \(amount) per \(period) in finch.")
    }
}
```

### 2.5 — `SwitchLedgerIntent`

```swift
public struct SwitchLedgerIntent: AppIntent {
    public static var title: LocalizedStringResource = "Switch Ledger"
    public static var description = IntentDescription("Switches the active finch ledger.")
    public static var openAppWhenRun: Bool = true

    @Parameter(title: "Ledger")
    var ledger: LedgerEntity

    public init() {}

    public init(ledger: LedgerEntity) {
        self.ledger = ledger
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FinchStore.shared
        store.setActiveLedger(id: ledger.id)
        return .result(dialog: "Switched to \(ledger.name) in finch.")
    }
}
```

`LedgerEntity` is a new `AppEntity` (Phase 6.4 adds it
alongside the 7 intents). It wraps the 4 ledgers from the
web's `MOCK` data.

### 2.6 — `ShowInsightsIntent`

```swift
public struct ShowInsightsIntent: AppIntent {
    public static var title: LocalizedStringResource = "Show Insights"
    public static var description = IntentDescription("Opens the finch Insights tab.")
    public static var openAppWhenRun: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FinchStore.shared
        let router = DeepLinkRouter.shared
        router.route(to: "insights")
        return .result(dialog: "Opening your insights in finch.")
    }
}
```

This is a pure navigation intent; no DB read or write.

### 2.7 — `OpenScreenIntent`

```swift
public struct OpenScreenIntent: AppIntent {
    public static var title: LocalizedStringResource = "Open Screen"
    public static var description = IntentDescription("Opens a finch screen by name.")
    public static var openAppWhenRun: Bool = true

    @Parameter(title: "Screen name")
    var screen: String

    public init() {}

    public init(screen: String) {
        self.screen = screen
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let router = DeepLinkRouter.shared
        switch screen.lowercased() {
        case "accounts", "activity", "budgets", "insights", "scheduled", "settings":
            router.route(to: screen.lowercased())
            return .result(dialog: "Opening \(screen) in finch.")
        default:
            return .result(dialog: "Unknown screen: \(screen). Try accounts, activity, budgets, insights, scheduled, or settings.")
        }
    }
}
```

This is a more general form of `ShowInsightsIntent`; the
user can say "open my activity in finch" or "open budgets
in finch" and the intent handles all 6 tabs.

### 2.8 — `LedgerEntity`

```swift
public struct LedgerEntity: AppEntity, Identifiable {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Ledger"
    public static var defaultQuery = LedgerQuery()

    public let id: String
    public let name: String
    public let base: String  // base currency

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(base)")
    }
}

public struct LedgerQuery: EntityQuery {
    public func entities(for identifiers: [LedgerEntity.ID]) async throws -> [LedgerEntity] {
        let store = FinchStore.shared
        return store.ledgers
            .filter { identifiers.contains($0.id) }
            .map { LedgerEntity(id: $0.id, name: $0.name, base: $0.baseCurrency) }
    }

    public func suggestedEntities() async throws -> [LedgerEntity] {
        let store = FinchStore.shared
        return store.ledgers.map { LedgerEntity(id: $0.id, name: $0.name, base: $0.baseCurrency) }
    }
}
```

The `LedgerEntity` is referenced by `SwitchLedgerIntent`. The
4 ledgers from the web's `MOCK` data (Personal, Business,
Family, Taxes) are the suggested entities.

## §3. The `AccountEntity` and `CategoryEntity`

The intents reference `AccountEntity` and `CategoryEntity`
— these are `AppEntity` types that wrap finch's accounts
and categories, making them available as Siri parameters.

### 3.1 — `AccountEntity`

```swift
public struct AccountEntity: AppEntity, Identifiable {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    public static var defaultQuery = AccountQuery()

    public let id: String
    public let name: String
    public let accountType: String  // "checking", "savings", etc.

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(accountType)")
    }

    public static var defaultQuery = AccountQuery()
}

public struct AccountQuery: EntityQuery {
    public func entities(for identifiers: [AccountEntity.ID]) async throws -> [AccountEntity] {
        let store = FinchStore.shared
        return store.accounts
            .filter { identifiers.contains($0.id) }
            .map { AccountEntity(id: $0.id, name: $0.name, accountType: $0.type) }
    }

    public func suggestedEntities() async throws -> [AccountEntity] {
        // The 5 most-recently-used accounts (for the Siri
        // suggestions list)
        let store = FinchStore.shared
        return store.accounts
            .sorted(by: { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) })
            .prefix(5)
            .map { AccountEntity(id: $0.id, name: $0.name, accountType: $0.type) }
    }
}
```

`AccountQuery` is the standard `EntityQuery` protocol that
Siri uses to look up accounts by id (when the user says
"Chase Checking") and to suggest accounts (when the user
starts the "Add Transaction" intent).

### 3.2 — `CategoryEntity`

Similar to `AccountEntity` but for categories:

```swift
public struct CategoryEntity: AppEntity, Identifiable {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    public static var defaultQuery = CategoryQuery()

    public let id: String
    public let name: String
    public let parentName: String?  // e.g., "Food" for "Groceries"

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: parentName ?? "Top-level"
        )
    }
}

public struct CategoryQuery: EntityQuery {
    public func entities(for identifiers: [CategoryEntity.ID]) async throws -> [CategoryEntity] {
        let store = FinchStore.shared
        return store.categories
            .filter { identifiers.contains($0.id) }
            .map { CategoryEntity(id: $0.id, name: $0.name, parentName: $0.parentName) }
    }

    public func suggestedEntities() async throws -> [CategoryEntity] {
        let store = FinchStore.shared
        return store.categories
            .sorted(by: { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) })
            .prefix(10)
            .map { CategoryEntity(id: $0.id, name: $0.name, parentName: $0.parentName) }
    }
}
```

## §4. Intent donation

After a successful intent execution, the iOS app donates
the intent to Siri so the system can learn the user's
patterns:

```swift
let donation = IntentDonation(self)
try? await IntentDonationDonor.shared.donate(donation)
```

Siri uses the donations to:
- Surface **Siri Suggestions** in the iOS system
  (e.g., "Add a $6 coffee" appears in Spotlight + the
  iOS home screen widgets)
- Improve **voice recognition** for the user's habitual
  phrases (e.g., the user's specific "coffee" pattern)
- Provide **Shortcuts** integration (the user can pin
  "Add a $6 coffee" as a home-screen Shortcut)

Donation is **automatic** for `AddTransaction` (the user
adds transactions frequently; donation helps Siri
learn the pattern). `CheckBalance` and `MarkCleared`
are not donated by default (they're less frequent; the
user can manually pin a Shortcut).

## §5. The `AppShortcuts` provider

iOS 16+ supports **`AppShortcuts`** — a way to expose the
app's intents to the system Spotlight + Siri without
requiring the user to manually discover them. The
`AppShortcutsProvider` declares the app's shortcuts:

```swift
public struct FinchAppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTransactionIntent(),
            phrases: [
                "Add a transaction in \(.applicationName)",
                "Log an expense in \(.applicationName)"
            ],
            shortTitle: "Add Transaction",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: CheckBalanceIntent(),
            phrases: [
                "Check my balance in \(.applicationName)",
                "What's my \(.applicationName) balance"
            ],
            shortTitle: "Check Balance",
            systemImageName: "dollarsign.circle"
        )
        AppShortcut(
            intent: MarkClearedIntent(),
            phrases: [
                "Mark transactions cleared in \(.applicationName)",
                "Reconcile in \(.applicationName)"
            ],
            shortTitle: "Mark Cleared",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: CreateBudgetIntent(),
            phrases: [
                "Create a budget in \(.applicationName)",
                "Add a budget in \(.applicationName)"
            ],
            shortTitle: "Create Budget",
            systemImageName: "target"
        )
        AppShortcut(
            intent: SwitchLedgerIntent(),
            phrases: [
                "Switch ledger in \(.applicationName)",
                "Change ledger in \(.applicationName)"
            ],
            shortTitle: "Switch Ledger",
            systemImageName: "rectangle.stack"
        )
        AppShortcut(
            intent: ShowInsightsIntent(),
            phrases: [
                "Show my insights in \(.applicationName)",
                "Open my insights in \(.applicationName)"
            ],
            shortTitle: "Show Insights",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: OpenScreenIntent(),
            phrases: [
                "Open a screen in \(.applicationName)",
                "Go to a tab in \(.applicationName)"
            ],
            shortTitle: "Open Screen",
            systemImageName: "arrow.up.forward.app"
        )
    }
}
```

`AppShortcuts` makes the intents **discoverable** by
Spotlight + Siri without the user having to invoke them
first. The user can:
- Search "Add Transaction finch" in Spotlight and see the
  shortcut
- Pin the shortcut to the home screen as a Shortcut
- Say "Hey Siri, add a transaction in finch" and Siri
  matches the phrase to the `AddTransactionIntent`

## §6. The `IntentDialog` flow

When the user invokes an intent with insufficient
parameters (e.g., "Hey Siri, add a transaction in finch"
without amount / description), Siri shows a
disambiguation dialog. The iOS app's intent can provide
custom dialogs via the `IntentDialog` API:

```swift
public func perform() async throws -> some IntentResult & ProvidesDialog {
    // If amount is missing (the user said "add a transaction
    // in finch" without specifying an amount), ask via dialog.
    if amount == 0 {
        let amountDialog = IntentDialog("How much?")
        return .result(dialog: amountDialog)
    }
    // ... continue
}
```

The dialog is **spoken** by Siri ("How much?") and the
user can respond with the amount. Siri then re-invokes
the intent with the updated parameters.

For complex disambiguation (e.g., "which account?"), the
`@Parameter` macro automatically generates a picker
dialog (the user sees a list of accounts from
`AccountQuery.suggestedEntities()`).

## §7. CI changes

The macos job from Phase 1.0's `IOS_MACOS_PHASE_1_DESIGN §9`
extends with:

- An **AddTransaction intent test**: build a DB with 1
  account + 1 category; invoke `AddTransactionIntent.perform()`
  with amount=6.00, description="Coffee", account=Chase
  Checking, category=Coffee; assert the chokepoint's
  `addTransaction` was dispatched with the right args
- A **CheckBalance intent test**: build a DB with 1
  account with balance=$100; invoke
  `CheckBalanceIntent.perform()`; assert the result is
  $100 + the dialog text
- A **MarkCleared intent test**: build a DB with 10
  un-cleared transactions; invoke
  `MarkClearedIntent.perform()` with count=5; assert
  exactly 5 `setCleared` actions were dispatched
- An **intent donation test**: invoke
  `AddTransactionIntent.perform()`; assert an
  `IntentDonation` was created
- A **disambiguation dialog test**: invoke
  `AddTransactionIntent.perform()` with amount=0; assert
  the result contains an `IntentDialog("How much?")`

The intent tests use a **mock `FinchStore`** that
captures the dispatched actions without invoking the real
chokepoint.

## §8. Open questions

**Not blocking Phase 6.4 (decide later)**:

- **Intent surface**: the proposal ships 7 intents
  (per Q12). More intents are possible (e.g.,
  `CreateRecurring`, `MarkReviewed`) — a future phase can
  add intents; the proposal doesn't preclude it.
- **Siri on Mac via Shortcuts**: macOS supports Siri but
  the App Intents framework is iOS / iPadOS / watchOS
  focused. A future phase can add a macOS Shortcuts
  integration; the proposed intents are designed to be
  Shortcut-compatible (the `@Parameter` macro + the
  `AppEntity` types are cross-platform).
- **Natural-language disambiguation**: the proposal uses
  Siri's standard `IntentDialog` + `EntityQuery` machinery.
  A more sophisticated disambiguation (e.g., the user
  says "add the usual" and Siri infers the merchant /
  amount) is a future phase.
- **Intent chaining**: the proposal has 7 single-step
  intents. A "shorter" (multi-step intent) is a future
  phase. The proposal doesn't preclude it; the intents
  are designed to be composable.
- **Biometric re-auth for sensitive intents** (Q19) — **resolved**:
  no re-auth. The user is already biometric-authenticated by
  the device to invoke Siri. A future phase can add
  per-intent biometric gating (e.g., `MarkCleared` requires
  biometric; `CheckBalance` doesn't) if user research
  shows it's needed.

**Specifically for the donation**:

- **Donation retention**: Siri's donations expire after
  ~30 days of inactivity. The user can manually pin a
  Shortcut to make it permanent. The proposal doesn't
  re-donate on a schedule.
- **Per-ledger active-ledger awareness**: the intents
  dispatch to the **active ledger** (Phase 1.0's
  `useLedger()` provider). If the user has multiple
  ledgers, the intent dispatches to whichever is
  currently active. The `SwitchLedgerIntent` is a
  future enhancement.

**Not blocking Phase 6.4 because they're Phase 6.5+ by design**:

- **Share Extension receipts** — Phase 6.5
- **Widgets / Live Activities / Watch** — Phase 7
- **Row-level sync** — Phase 8

## §9. Out of scope (firm)

These are explicitly NOT in Phase 6.4:

- **No Siri on Mac** — iOS / iPadOS / watchOS only
- **No new tabs / write screens / power features** — the 6
  tabs + 6 write screens + 7 power features are unchanged
- **No new selectors** — the Phase 1.5 selectors are the
  full set
- **No new chokepoint actions** — the chokepoint is
  unchanged; the intents dispatch the existing 74 actions
- **No Shortcuts on Mac** — a future phase
- **No natural-language disambiguation beyond Siri's
  standard** — the proposal uses Siri's built-in
  `IntentDialog` + `EntityQuery`
- **No biometric re-auth for Siri intents** — the
  proposal doesn't require it
- **No additional intents beyond the 7** — `AddTransaction`,
  `CheckBalance`, `MarkCleared`, `CreateBudget`,
  `SwitchLedger`, `ShowInsights`, `OpenScreen` are the 7
- **No intent chaining** — single-step intents only

## §10. Spec self-review

(Inline review at write time; not part of the published
spec.)

- **Placeholders**: none. Every section has concrete
  content. The 7 intents (§2) each have a code sketch.
  The 3 `AppEntity` types (§3 — `AccountEntity`,
  `CategoryEntity`, `LedgerEntity`) have concrete code. The
  `AppShortcuts` provider (§5) is concrete. The
  `IntentDialog` flow (§6) has a concrete example.
- **Internal consistency**: §2.1's `AddTransactionIntent`
  dispatches `addTransaction` (Phase 2). §2.2's
  `CheckBalanceIntent` reads from the in-memory
  `AccountRow[]` cache (Phase 1.0). §3's `AccountEntity`
  and `CategoryEntity` use the standard `AppEntity` /
  `EntityQuery` pattern. The `FinchStore` is from Phase
  2.
- **Scope**: focused on Phase 6.4 only. Phases 6.1-6.3
  are referenced as separately shipped specs. Phase 6.5
  is referenced as a separate spec. Phase 7+ are
  explicitly out of scope (§9). The estimated scope
  (3-4 weeks) reflects the 7 intents + the 3 entity
  types + the donation flow.
- **Ambiguity**: §2's 7 intents have concrete code. §3's
  entity types have concrete code. §4's donation flow
  is concrete. §5's `AppShortcuts` provider is concrete.
  §6's `IntentDialog` flow is concrete. §7 enumerates
  the CI test cases. §8 enumerates the open questions
  with proposed answers.
