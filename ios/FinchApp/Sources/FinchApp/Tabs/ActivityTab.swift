import SwiftUI
import FinchCore

/// Transactions date-descending, grouped into day sections, paginated 50 rows
/// at a time. Search is client-side `merchant.contains` (mirrors
/// selectTransactions(opts.query); NO FTS5). Detail view deferred (D4).
struct ActivityTab: View {
    @EnvironmentObject private var store: FinchStore
    @State private var searchQuery: String = ""
    @State private var visibleCount: Int = 50
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if store.txns.isEmpty {
                    EmptyState(tab: .activity)
                } else {
                    List {
                        ForEach(daySections, id: \.date) { section in
                            Section(section.date) {
                                ForEach(section.txns) { txn in
                                    TxRow(txn: txn)
                                }
                            }
                        }
                        if filtered.count > visibleCount {
                            Button("Load more") { visibleCount += 50 }
                        }
                    }
                }
            }
            .searchable(text: $searchQuery)
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add Transaction")
                        .disabled(store.accounts.isEmpty)
                }
            }
            .sheet(isPresented: $showingAdd) { AddTransactionSheet() }
        }
    }

    /// Client-side filter mirroring selectTransactions(opts.query):
    /// merchant.lowercased().contains(query). NO FTS5.
    private var filtered: [Tx] {
        guard !searchQuery.isEmpty else { return store.txns }
        let q = searchQuery.lowercased()
        return store.txns.filter { $0.merchant.lowercased().contains(q) }
    }

    /// First `visibleCount` of the (already date-desc) filtered txns, grouped by
    /// `date`, preserving order.
    private var daySections: [(date: String, txns: [Tx])] {
        var order: [String] = []
        var byDay: [String: [Tx]] = [:]
        for txn in filtered.prefix(visibleCount) {
            if byDay[txn.date] == nil { order.append(txn.date) }
            byDay[txn.date, default: []].append(txn)
        }
        return order.map { ($0, byDay[$0] ?? []) }
    }
}

struct TxRow: View {
    @EnvironmentObject private var store: FinchStore
    let txn: Tx
    var body: some View {
        HStack {
            Image(systemName: TxnKindIcon.icon(for: txn.kind))
                .foregroundStyle(txn.amount < 0 ? .red : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(txn.merchant)
                if let cat = store.categoryName(txn.category) {
                    Text(cat).font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            Spacer()
            Text(store.displayMoneyBase(txn.amount)).fontWeight(.semibold)
        }
    }
}
