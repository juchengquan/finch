import AppIntents
import Foundation
import FinchCore

// Phase 6.4 — the 7 Siri intents. Every write dispatches the Phase 2 chokepoint
// (FinchStore.apply) — the only write path. Reads use the projected store.

private func today() -> String { AppDate.today() }

/// Biometric gate for Siri/Shortcuts: refuse data actions when the app is locked
/// so Siri can't read balances or post writes past the lock. Re-evaluates (a
/// fresh intent process hasn't unlocked), and is a no-op when no lock is set.
@MainActor enum FinchIntentLock {
    static var unlocked: Bool {
        let gate = BiometricGate.shared
        if gate.settings.policy == .off { return true }
        gate.start()
        return !gate.isLocked
    }
}

/// "Add a $6 coffee to finch" → addTransaction (defaults to an expense).
public struct AddTransactionIntent: AppIntent {
    public static var title: LocalizedStringResource = "Add Transaction"
    public static var description = IntentDescription("Adds a transaction to your active finch ledger.")
    public static var openAppWhenRun = true

    @Parameter(title: "Amount") public var amount: Double
    @Parameter(title: "Merchant") public var merchant: String
    @Parameter(title: "Account") public var account: AccountEntity?
    @Parameter(title: "Category") public var category: CategoryEntity?
    @Parameter(title: "Note") public var note: String?
    public init() {}

    @MainActor public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FinchStore.shared
        store.bootstrap()
        guard FinchIntentLock.unlocked else { return .result(dialog: "Unlock finch first to do that.") }
        guard let accountId = account?.id ?? store.accounts.first?.id else {
            return .result(dialog: "Add an account in finch first.")
        }
        var args: [String: JSONValue] = [
            "ledgerId": .string(store.activeLedgerId), "accountId": .string(accountId),
            "amount": .double(-abs(amount)), "merchant": .string(merchant), "date": .string(today()),
        ]
        if let c = category?.id ?? store.pickableCategories.first?.id { args["categoryId"] = .string(c) }
        if let n = note { args["note"] = .string(n) }
        do { try store.apply(.addTransaction, Args(args)) }
        catch let e as I18nError { return .result(dialog: "Couldn't add it: \(e.message)") }
        DeepLinkRouter.shared.open(.activity)
        return .result(dialog: "Added \(merchant) to finch.")
    }
}

/// "What's my Cash balance?" → reads the projected balance (no write).
public struct CheckBalanceIntent: AppIntent {
    public static var title: LocalizedStringResource = "Check Balance"
    public static var description = IntentDescription("Tells you an account's balance.")
    @Parameter(title: "Account") public var account: AccountEntity
    public init() {}

    @MainActor public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FinchStore.shared
        store.bootstrap()
        guard FinchIntentLock.unlocked else { return .result(dialog: "Unlock finch first to do that.") }
        guard let a = store.accounts.first(where: { $0.id == account.id }) else {
            return .result(dialog: "I couldn't find that account.")
        }
        return .result(dialog: "\(a.name ?? "That account") is \(store.displayMoney(a.balance, from: a.currency)).")
    }
}

/// "Mark my last 5 transactions as cleared" → setCleared on the most-recent N.
public struct MarkClearedIntent: AppIntent {
    public static var title: LocalizedStringResource = "Mark Cleared"
    public static var description = IntentDescription("Marks your most recent transactions as cleared.")
    @Parameter(title: "How many", default: 5) public var count: Int
    public init() {}

    @MainActor public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FinchStore.shared
        store.bootstrap()
        guard FinchIntentLock.unlocked else { return .result(dialog: "Unlock finch first to do that.") }
        let ids = store.txns.prefix(max(1, count)).map(\.id)
        for id in ids { try? store.apply(.setCleared, Args(["id": .string(id), "cleared": .bool(true)])) }
        return .result(dialog: "Marked \(ids.count) transaction\(ids.count == 1 ? "" : "s") as cleared.")
    }
}

/// "Create a $300 Groceries budget" → createBudget.
public struct CreateBudgetIntent: AppIntent {
    public static var title: LocalizedStringResource = "Create Budget"
    public static var description = IntentDescription("Creates a monthly budget in your active finch ledger.")
    public static var openAppWhenRun = true
    @Parameter(title: "Name") public var name: String
    @Parameter(title: "Amount") public var amount: Double
    @Parameter(title: "Category") public var category: CategoryEntity?
    public init() {}

    @MainActor public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FinchStore.shared
        store.bootstrap()
        guard FinchIntentLock.unlocked else { return .result(dialog: "Unlock finch first to do that.") }
        var args: [String: JSONValue] = [
            "ledgerId": .string(store.activeLedgerId), "name": .string(name),
            "type": .string("expense"), "amount": .double(abs(amount)), "frequency": .string("monthly"),
        ]
        if let c = category?.id { args["categoryIds"] = .array([.string(c)]) }
        do { try store.apply(.createBudget, Args(args)) }
        catch let e as I18nError { return .result(dialog: "Couldn't create it: \(e.message)") }
        DeepLinkRouter.shared.open(.budgets)
        return .result(dialog: "Created the \(name) budget.")
    }
}

/// "Switch to my Business ledger" → setDefaultLedger + activate.
public struct SwitchLedgerIntent: AppIntent {
    public static var title: LocalizedStringResource = "Switch Ledger"
    public static var description = IntentDescription("Switches your active finch ledger.")
    public static var openAppWhenRun = true
    @Parameter(title: "Ledger") public var ledger: LedgerEntity
    public init() {}

    @MainActor public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FinchStore.shared
        store.bootstrap()
        guard FinchIntentLock.unlocked else { return .result(dialog: "Unlock finch first to do that.") }
        do { try store.apply(.setDefaultLedger, Args(["id": .string(ledger.id)])) }
        catch let e as I18nError { return .result(dialog: "Couldn't switch: \(e.message)") }
        store.activeLedgerId = ledger.id
        return .result(dialog: "Switched to \(ledger.name).")
    }
}

/// "Show my insights" → open the Insights tab.
public struct ShowInsightsIntent: AppIntent {
    public static var title: LocalizedStringResource = "Show Insights"
    public static var description = IntentDescription("Opens your finch insights.")
    public static var openAppWhenRun = true
    public init() {}
    @MainActor public func perform() async throws -> some IntentResult {
        DeepLinkRouter.shared.open(.insights)
        return .result()
    }
}

/// "Open budgets in finch" → open a screen by name.
public struct OpenScreenIntent: AppIntent {
    public static var title: LocalizedStringResource = "Open Screen"
    public static var description = IntentDescription("Opens a finch screen by name.")
    public static var openAppWhenRun = true
    @Parameter(title: "Screen") public var screen: ScreenAppEnum
    public init() {}
    @MainActor public func perform() async throws -> some IntentResult & ProvidesDialog {
        DeepLinkRouter.shared.open(screen.tab)
        return .result(dialog: "Opening \(screen.rawValue) in finch.")
    }
}

/// The 6 shipped tabs as a Siri-pickable enum (a future Reports joins this list).
public enum ScreenAppEnum: String, AppEnum {
    case accounts, activity, budgets, insights, scheduled, settings
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Screen"
    // AppIntents requires caseDisplayRepresentations to be a literal dictionary
    // (the metadata extractor parses it at compile time), so it stays spelled out.
    public static var caseDisplayRepresentations: [ScreenAppEnum: DisplayRepresentation] = [
        .accounts: "Accounts", .activity: "Activity", .budgets: "Budgets",
        .insights: "Insights", .scheduled: "Scheduled", .settings: "Settings",
    ]
    // Cases share rawValues with AppTab → derive the tab instead of a switch.
    var tab: AppTab { AppTab(rawValue: rawValue) ?? .accounts }
}
