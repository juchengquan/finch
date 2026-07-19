import SwiftUI
import FinchCore

/// A category's transactions + aggregate stats. Pushed from the Categories page
/// when a row is tapped. Mirrors `CounterpartyDetailView` (the merchants analog):
/// membership matches the row's count badge (`categoryTransactions` ≙
/// `categoryTxCounts`), with a jump to the full Activity feed filter.
struct CategoryDetailView: View {
    @EnvironmentObject private var store: FinchStore
    let category: CategoryRow
    @State private var editing: Tx?
    @State private var duplicating: Tx?   // Duplicate → Add sheet pre-filled

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
                Section {
                    Button {
                        DeepLinkRouter.shared.pendingFilter = TxFilter(categoryId: category.id)
                        DeepLinkRouter.shared.selectedTab = .activity
                    } label: {
                        Label("See in Activity feed", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                Section("Transactions") {
                    ForEach(txns) { tx in
                        Button { editing = tx } label: { TxRow(txn: tx, showRunningBalance: false).contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))   // denser rows
                            .swipeActions(edge: .leading) {
                                if ["expense", "income"].contains(tx.kind ?? "") {
                                    Button { duplicate(tx) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }.tint(.indigo)
                                }
                            }
                            .contextMenu {
                                Button { editing = tx } label: { Label("Edit", systemImage: "pencil") }
                                if ["expense", "income"].contains(tx.kind ?? "") {
                                    Button { duplicate(tx) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle(category.name)
        .sheet(item: $editing) { EditTransactionSheet(txn: $0) }
        .sheet(item: $duplicating) { AddTransactionSheet(prefill: $0) }
    }

    private func duplicate(_ tx: Tx) {
        duplicating = tx   // opens the Add sheet pre-filled; Save posts it
    }
}
