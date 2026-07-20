import SwiftUI
import FinchCore

/// A category's transactions + aggregate stats. Pushed from the Categories page
/// when a row is tapped. Mirrors `CounterpartyDetailView` (the merchants analog):
/// membership matches the row's count badge (`categoryTransactions` ≙
/// `categoryTxCounts`, i.e. includes split legs, excludes pending).
struct CategoryDetailView: View {
    @EnvironmentObject private var store: FinchStore
    let category: CategoryRow
    @State private var editing: Tx?
    @State private var duplicating: Tx?   // Duplicate → Add sheet pre-filled
    @State private var pendingDelete: Tx?   // delete awaiting confirmation
    @State private var errorMessage: String?

    private var txns: [Tx] {
        Selectors.categoryTransactions(store.txns, category.id, store.activeLedgerId)
    }
    private var total: Double { txns.reduce(0) { $0 + $1.amount } }

    var body: some View {
        List {
            Section {
                LabeledContent("Transactions", value: "\(txns.count)")
                LabeledContent("Total", value: store.displayMoneyBase(total))
                if !txns.isEmpty {
                    LabeledContent("Average", value: store.displayMoneyBase(total / Double(txns.count)))
                }
            }
            if !txns.isEmpty {
                Section("Transactions") {
                    ForEach(txns) { tx in
                        Button { editing = tx } label: { TxRow(txn: tx, showRunningBalance: false).contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))   // denser rows
                            .txnSwipeActions(tx,
                                             duplicate: { duplicating = $0 },
                                             requestDelete: { pendingDelete = $0 },
                                             toggleStatus: { toggleStatus($0) },
                                             edit: { editing = $0 })
                    }
                }
            }
        }
        .navigationTitle(category.name)
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
            Text("\(tx.merchant) · \(store.displayMoneyBase(tx.amount))")
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
}
