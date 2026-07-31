import SwiftUI
import FinchCore

/// The per-tab selection that drives the regular-width detail column.
///
/// `SplitViewShell` held these as `@State`. The UIKit shell owns the split view now,
/// and the two columns are hosted separately, so the selection has to live somewhere
/// both can reach — and somewhere that survives the split view being rebuilt when the
/// column count changes. Hence a reference type owned by `SplitShellVC`.
final class SplitSelection: ObservableObject {
    @Published var account: String?
    @Published var budget: String?
    @Published var ledger: String?
    @Published var tx: String?
    @Published var scheduled: String?

    /// A ledger switch invalidates every id — except `ledger` itself, which indexes a
    /// global list, and whose detail column is where "make active" is pressed. Clearing
    /// it there would eject the user from the screen that caused the switch.
    func clearForLedgerSwitch() {
        account = nil
        budget = nil
        tx = nil
        scheduled = nil
    }
}

/// The middle (list) column: the tab's own list view, run in selection mode.
///
/// These are the SAME views the compact shell pushes — given a `selection` binding they
/// drive a split, given none they push. That dual mode is what Phase 3's "full" variant
/// would eventually remove; hosting them keeps this step behaviour-identical.
struct SplitListColumn: View {
    let tab: AppTab
    @ObservedObject var selection: SplitSelection

    var body: some View {
        switch tab {
        case .accounts:  AccountsTab(selection: $selection.account)
        case .budgets:   BudgetsTab(selection: $selection.budget)
        case .ledger:    LedgerTab(selection: $selection.ledger)
        case .activity:  ActivityFeedView(consumesPendingFilter: true, selection: $selection.tx)
        case .scheduled: ScheduledTab(selection: $selection.scheduled)
        default:         EmptyView()   // never installed for a two-column tab
        }
    }
}

/// The detail column: the selected row's screen, or the placeholder.
///
/// Every branch re-checks that the id still resolves. A selection can outlive the thing
/// it points at — a deleted transaction, a template removed on another device, a ledger
/// switch racing the clear — and rendering a detail for a missing id is how you get a
/// blank column or a crash rather than the placeholder.
struct SplitDetailColumn: View {
    let tab: AppTab
    @ObservedObject var selection: SplitSelection
    @EnvironmentObject private var store: FinchStore

    var body: some View {
        switch tab {
        case .accounts:
            if let id = selection.account, store.accounts.contains(where: { $0.id == id }) {
                AccountDetailView(accountId: id)
            } else {
                DetailPlaceholder(systemImage: "creditcard", label: "Select an account")
            }
        case .budgets:
            if let id = selection.budget, store.budgets.contains(where: { $0.id == id }) {
                BudgetDetailView(budgetId: id)
            } else {
                DetailPlaceholder(systemImage: "chart.pie", label: "Select a budget")
            }
        case .ledger:
            if let id = selection.ledger, store.ledgers.contains(where: { $0.id == id }) {
                LedgerDetailView(ledgerId: id)
            } else {
                DetailPlaceholder(systemImage: "books.vertical", label: "Select a ledger")
            }
        case .activity:
            if let id = selection.tx, store.txns.contains(where: { $0.id == id }) {
                TransactionDetailView(txId: id)
            } else {
                DetailPlaceholder(systemImage: "list.bullet", label: "Select a transaction")
            }
        case .scheduled:
            if let id = selection.scheduled, store.scheduled.contains(where: { $0.id == id }) {
                ScheduledDetailView(templateId: id)
            } else {
                DetailPlaceholder(systemImage: "calendar", label: "Select a scheduled item")
            }
        default:
            EmptyView()
        }
    }
}

/// The full-width content column for the dashboard / sheet-based tabs.
struct TabContentColumn: View {
    let tab: AppTab
    var body: some View { tabContent(tab) }
}
