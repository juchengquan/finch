import SwiftUI
import FinchCore

/// A merchant's transactions + aggregate stats. Pushed from the Merchants admin.
struct CounterpartyDetailView: View {
    @EnvironmentObject private var store: FinchStore
    let counterparty: Counterparty
    @State private var editing: Tx?
    @State private var duplicating: Tx?   // Duplicate → Add sheet pre-filled
    @State private var pendingDelete: Tx?   // delete awaiting confirmation
    @State private var errorMessage: String?

    /// One row per PURCHASE, not per payment. This screen answers "what did I
    /// spend on this" — a purchase paid on two cards is one shop, not two half
    /// shops, and which card paid is not the question being asked here. An
    /// account's own screen is the opposite and deliberately does NOT collapse.
    /// Collapsing here also keeps the count, total and average agreeing with the
    /// list they sit above.
    private var txns: [Tx] {
        Selectors.byPurchase(Selectors.merchantTransactions(store.txns, store.merchants, counterparty.id, store.activeLedgerId))
    }
    private var total: Double { txns.reduce(0) { $0 + $1.amount } }
    /// Pending items are excluded from `txns` (and so from the summary + the count
    /// pill on the parent page). Queried separately so they can be surfaced on top
    /// rather than silently omitted — the same "To confirm" treatment
    /// AccountDetailView gives them.
    private var pendingTxns: [Tx] {
        Selectors.byPurchase(Selectors.merchantTransactions(store.txns, store.merchants, counterparty.id, store.activeLedgerId, includePending: true)
            .filter { $0.pending == true })
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Transactions", value: "\(txns.count)")
                LabeledContent("Total", value: store.displayMoneyBase(total))
                if !txns.isEmpty {
                    LabeledContent("Average", value: store.displayMoneyBase(total / Double(txns.count)))
                }
            }
            if !pendingTxns.isEmpty {
                Section("To confirm (\(pendingTxns.count))") {
                    ForEach(pendingTxns) { row($0) }
                }
            }
            if !txns.isEmpty {
                Section("Transactions") {
                    ForEach(txns) { row($0) }
                }
            }
        }
        .navigationTitle(counterparty.name)
        .sheet(item: $editing) { EditTransactionSheet(txn: $0) }
        .sheet(item: $duplicating) { AddTransactionSheet(prefill: $0) }
        // Window-level ALERT, not a row-anchored confirmationDialog — see
        // ActivityTab (row recycling tears the popout down).
        .alert("Delete transaction?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete) { tx in
            Button("Delete", role: .destructive) { delete(tx) }
            Button("Cancel", role: .cancel) {}
        } message: { tx in
            // Same multi-leg warning as ActivityTab's delete alert: a split
            // purchase (or a transfer) renders as one row per account leg,
            // and deleting any one row deletes the whole entry.
            if tx.transferGroupId != nil {
                Text("\(tx.merchant) · \(store.displayMoneyBase(tx.amount))") + Text(" " + ActivityFeedView.transferDeleteHint)
            } else if (tx.accountLegCount ?? 1) > 1 {
                Text("\(tx.merchant) · \(store.displayMoneyBase(tx.amount))") + Text(" " + ActivityFeedView.multiLegDeleteHint)
            } else {
                Text("\(tx.merchant) · \(store.displayMoneyBase(tx.amount))")
            }
        }
        .errorAlert($errorMessage)
    }

    private func toggleStatus(_ tx: Tx) {
        do { try txnToggleStatus(tx, store: store) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func delete(_ tx: Tx) {
        do { try store.deleteTransaction(tx.id); Haptics.warning() }   // also unlinks receipts
        catch { errorMessage = i18nMessage(error) }
    }

    @ViewBuilder private func row(_ tx: Tx) -> some View {
        Button { editing = tx } label: { TxRow(txn: tx, showRunningBalance: false).contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
            .txnSwipeActions(tx,
                             duplicate: { duplicating = $0 },
                             requestDelete: { pendingDelete = $0 },
                             toggleStatus: { toggleStatus($0) },
                             edit: { editing = $0 })
    }
}
