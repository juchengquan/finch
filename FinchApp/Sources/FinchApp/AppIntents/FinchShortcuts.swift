import AppIntents

/// Phase 6.4 — surfaces the intents to Siri / the Shortcuts app with spoken
/// trigger phrases. ${applicationName} resolves to "finch".
public struct FinchShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddTransactionIntent(), phrases: [
            "Add a transaction to \(.applicationName)",
            "Log an expense in \(.applicationName)",
        ], shortTitle: "Add Transaction", systemImageName: "plus.circle")

        AppShortcut(intent: CheckBalanceIntent(), phrases: [
            "Check my balance in \(.applicationName)",
            "What's my balance in \(.applicationName)",
        ], shortTitle: "Check Balance", systemImageName: "dollarsign.circle")

        AppShortcut(intent: MarkClearedIntent(), phrases: [
            "Mark my transactions cleared in \(.applicationName)",
        ], shortTitle: "Mark Cleared", systemImageName: "checkmark.circle")

        AppShortcut(intent: CreateBudgetIntent(), phrases: [
            "Create a budget in \(.applicationName)",
        ], shortTitle: "Create Budget", systemImageName: "chart.pie")

        AppShortcut(intent: SwitchLedgerIntent(), phrases: [
            "Switch ledger in \(.applicationName)",
        ], shortTitle: "Switch Ledger", systemImageName: "books.vertical")

        AppShortcut(intent: ShowInsightsIntent(), phrases: [
            "Show my insights in \(.applicationName)",
        ], shortTitle: "Show Insights", systemImageName: "chart.line.uptrend.xyaxis")

        AppShortcut(intent: OpenScreenIntent(), phrases: [
            "Open a screen in \(.applicationName)",
        ], shortTitle: "Open Screen", systemImageName: "rectangle.stack")
    }
}
