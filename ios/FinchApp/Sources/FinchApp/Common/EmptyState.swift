import SwiftUI

/// Per-tab "no pack loaded yet" placeholder (Phase 1.0 ships read-only; the
/// first thing a user does is import a `.finch` from Settings).
struct EmptyState: View {
    enum Tab { case accounts, activity, budgets }
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
        }
    }
    private var symbol: String {
        switch tab {
        case .accounts: "wallet.pass"
        case .activity: "list.bullet"
        case .budgets:  "chart.pie"
        }
    }
}
