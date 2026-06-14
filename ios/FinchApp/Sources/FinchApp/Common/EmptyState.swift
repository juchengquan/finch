import SwiftUI

/// Per-tab "no data yet" placeholder, shown before a ledger has any data — a new
/// user adds accounts/transactions directly or imports a `.finch` from Settings.
struct EmptyState: View {
    enum Tab { case accounts, activity, budgets, scheduled }
    let tab: Tab
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text("Import a .finch pack from Settings to get started.")
        }
    }
    private var title: String {
        switch tab {
        case .accounts: "No accounts yet"
        case .activity: "No activity yet"
        case .budgets:  "No budgets yet"
        case .scheduled: "No scheduled items yet"
        }
    }
    private var symbol: String {
        switch tab {
        case .accounts: "wallet.pass"
        case .activity: "list.bullet"
        case .budgets:  "chart.pie"
        case .scheduled: "calendar"
        }
    }
}
