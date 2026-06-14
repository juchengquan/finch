import SwiftUI
import FinchCore

/// Transactions date-descending, grouped into day sections, paginated 50 rows
/// at a time. Search is client-side `merchant.contains` (mirrors
/// selectTransactions(opts.query); NO FTS5). Detail view deferred (D4).
struct ActivityTab: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var router: DeepLinkRouter
    @State private var searchQuery: String = ""
    @State private var visibleCount: Int = 50
    @State private var showingAdd = false
    @State private var editing: Tx?
    @State private var isSelecting = false
    @State private var selected: Set<String> = []
    @State private var showingBulkCat = false
    @State private var savedSearches: [SavedSearch] = []

    var body: some View {
        NavigationStack {
            Group {
                if store.txns.isEmpty {
                    EmptyState(tab: .activity)
                } else {
                    List {
                        if pendingCount > 0 {
                            Section {
                                Button {
                                    try? store.apply(.confirmAllPending, Args([:]))
                                } label: {
                                    Label("Confirm all \(pendingCount) pending", systemImage: "checkmark.circle")
                                }
                            }
                        }
                        ForEach(daySections, id: \.date) { section in
                            Section(section.date) {
                                ForEach(section.txns) { txn in
                                    row(txn)
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
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        if !searchQuery.isEmpty {
                            Button("Save “\(searchQuery)”") { SavedSearches.save(name: searchQuery, query: searchQuery); savedSearches = SavedSearches.all() }
                        }
                        if !savedSearches.isEmpty {
                            Section("Saved") {
                                ForEach(savedSearches) { s in
                                    Button(s.name) { searchQuery = s.query }
                                }
                            }
                        }
                    } label: { Label("Saved searches", systemImage: "bookmark") }
                        .onAppear { savedSearches = SavedSearches.all() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSelecting ? "Done" : "Select") {
                        isSelecting.toggle(); selected.removeAll()
                    }.disabled(store.txns.isEmpty)
                }
                if isSelecting {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Recategorize \(selected.count)") { showingBulkCat = true }
                            .disabled(selected.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showingAdd) { AddTransactionSheet() }
            .sheet(item: $editing) { EditTransactionSheet(txn: $0) }
            .sheet(isPresented: $showingBulkCat) {
                BulkRecategorizeSheet(ids: Array(selected)) { isSelecting = false; selected.removeAll() }
            }
            .onAppear(perform: consumeFocus)
            .onChange(of: router.focusedId) { _, _ in consumeFocus() }
        }
    }

    /// A deep link / Spotlight / notification tap stashed a tx id + switched to
    /// this tab — open that transaction.
    private func consumeFocus() {
        guard let id = router.focusedId, let tx = store.txns.first(where: { $0.id == id }) else { return }
        editing = tx
        router.focusedId = nil
    }

    private func toggle(_ txn: Tx) {
        if selected.contains(txn.id) { selected.remove(txn.id) } else { selected.insert(txn.id) }
    }

    @ViewBuilder
    private func row(_ txn: Tx) -> some View {
        Button { isSelecting ? toggle(txn) : (editing = txn) } label: {
            HStack {
                if isSelecting {
                    Image(systemName: selected.contains(txn.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected.contains(txn.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                TxRow(txn: txn)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(txn) } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            if txn.pending == true {
                Button { confirm(txn) } label: { Label("Confirm", systemImage: "checkmark.circle") }.tint(.green)
            }
        }
        .contextMenu {   // right-click parity on Mac/iPad (swipe is touch-only)
            Button { editing = txn } label: { Label("Edit", systemImage: "pencil") }
            if txn.pending == true {
                Button { confirm(txn) } label: { Label("Confirm", systemImage: "checkmark.circle") }
            }
            Button(role: .destructive) { delete(txn) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func delete(_ txn: Tx) {
        try? store.deleteTransaction(txn.id)   // also unlinks receipt files
    }
    private func confirm(_ txn: Tx) {
        try? store.apply(.confirmTransaction, Args(["id": .string(txn.id)]))
    }
    private var pendingCount: Int { store.txns.filter { $0.pending == true }.count }

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
                HStack(spacing: 4) {
                    Text(txn.merchant)
                    if txn.pending == true {
                        Image(systemName: "clock").font(.caption2).foregroundStyle(.orange)
                    }
                    if store.isAnomaly(txn) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange)
                            .accessibilityLabel("Unusual amount")
                    }
                }
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
