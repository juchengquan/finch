import SwiftUI
import FinchCore

/// A merchant's transactions + aggregate stats. Pushed from the Merchants admin.
struct CounterpartyDetailView: View {
    @EnvironmentObject private var store: FinchStore
    let counterparty: Counterparty
    @State private var editing: Tx?
    @State private var duplicating: Tx?   // Duplicate → Add sheet pre-filled

    private var txns: [Tx] {
        Selectors.merchantTransactions(store.txns, store.merchants, counterparty.id, store.activeLedgerId)
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
                        DeepLinkRouter.shared.pendingFilter = TxFilter(counterpartyId: counterparty.id)
                        DeepLinkRouter.shared.selectedTab = .activity
                    } label: {
                        Label("See in Activity feed", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            if !txns.isEmpty {
                Section("Transactions") {
                    ForEach(txns) { tx in
                        Button { editing = tx } label: { TxRow(txn: tx).contentShape(Rectangle()) }
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
        .navigationTitle(counterparty.name)
        .sheet(item: $editing) { EditTransactionSheet(txn: $0) }
        .sheet(item: $duplicating) { AddTransactionSheet(prefill: $0) }
    }

    private func duplicate(_ tx: Tx) {
        duplicating = tx   // opens the Add sheet pre-filled; Save posts it
    }
}
