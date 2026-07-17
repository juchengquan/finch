import SwiftUI
import FinchCore

enum TxSort: String, CaseIterable, Identifiable {
    case dateDesc, dateAsc, amountDesc, amountAsc
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dateDesc:   return "Newest first"
        case .dateAsc:    return "Oldest first"
        case .amountDesc: return "Largest amount"
        case .amountAsc:  return "Smallest amount"
        }
    }
    func sorted(_ txns: [Tx]) -> [Tx] {
        switch self {
        case .dateDesc:   return txns.sorted { $0.date != $1.date ? $0.date > $1.date : ($0.time ?? "") > ($1.time ?? "") }
        case .dateAsc:    return txns.sorted { $0.date != $1.date ? $0.date < $1.date : ($0.time ?? "") < ($1.time ?? "") }
        case .amountDesc: return txns.sorted { abs($0.amount) != abs($1.amount) ? abs($0.amount) > abs($1.amount) : $0.date > $1.date }
        case .amountAsc:  return txns.sorted { abs($0.amount) != abs($1.amount) ? abs($0.amount) < abs($1.amount) : $0.date > $1.date }
        }
    }
}

/// The Activity tab — the global transaction feed in its own navigation stack.
/// A thin wrapper around `ActivityFeedView`; the feed itself is reusable and is
/// also pushed from the Accounts tab's "All Transactions" row (which already
/// supplies a navigation stack), so the feed must NOT wrap one itself.
struct ActivityTab: View {
    var body: some View {
        NavigationStack { ActivityFeedView(consumesPendingFilter: true) }
    }
}

/// Transactions date-descending, grouped into day sections, paginated 50 rows
/// at a time. Search is client-side `merchant.contains` (mirrors
/// selectTransactions(opts.query); NO FTS5). Provides its own toolbar (add /
/// select / bulk-recategorize) but NOT a NavigationStack, so it can be hosted
/// either as the Activity tab or pushed inside another stack.
struct ActivityFeedView: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var router: DeepLinkRouter
    @Environment(\.horizontalSizeClass) private var sizeClass
    var consumesPendingFilter: Bool = false
    /// Non-nil → three-column selection mode (rows select and the shell renders
    /// the detail column); nil → rows open the edit sheet. Same convention as
    /// `AccountsTab`/`BudgetsTab`/`LedgerListView` (#414/#23).
    var selection: Binding<String?>? = nil
    @StateObject private var savedSearches = SavedSearchStore()
    @State private var showingSaveSearch = false
    @State private var newSearchName = ""
    @State private var searchQuery: String = ""
    @State private var filter = TxFilter()
    @State private var sort: TxSort = .dateDesc
    @AppStorage("finch.feed.groupByMonth") private var groupByMonth = true
    @State private var showingFilter = false
    @State private var visibleCount: Int = 50
    @State private var showingAdd = false
    @State private var editing: Tx?
    @State private var previewURL: URL?
    @State private var isSelecting = false
    @State private var selected: Set<String> = []
    @State private var duplicating: Tx?   // Duplicate → Add sheet pre-filled
    @State private var kbSel: String?            // macOS keyboard-open selection
    @State private var showingBulkCat = false
    @State private var errorMessage: String?
    // Memoized derived state: recomputed only when txns / query / visibleCount
    // change (via .onReceive/.onChange), not on every body render — the search
    // field re-rendered the whole list on each keystroke before.
    @State private var sections: [DaySection] = []
    @State private var dateShownIds: Set<String> = []
    @State private var hasMore = false
    @State private var filteredCount = 0
    @State private var confirmingBulkDelete = false
    @State private var pendingDelete: Tx?   // single-row delete awaiting confirmation

    struct DaySection: Identifiable { let id: String; let txns: [Tx] }

    var body: some View {
        Group {
            if store.txns.isEmpty {
                EmptyState(tab: .activity)
            } else {
                List(selection: selection ?? $kbSel) {
                    savedSearchRow
                    Text("\(filteredCount) transaction\(filteredCount == 1 ? "" : "s")")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                        .listRowBackground(Color.clear)
                    if sections.isEmpty {
                        ContentUnavailableView {
                            Label("No matching transactions", systemImage: "line.3.horizontal.decrease.circle")
                        } description: {
                            Text("Try adjusting your search or filters.")
                        } actions: {
                            if hasActiveQuery { Button("Clear filters & search") { searchQuery = ""; filter = TxFilter() } }
                        }
                        .listRowBackground(Color.clear)
                    }
                    if pendingCount > 0 {
                        Section {
                            Button {
                                run { try store.apply(.confirmAllPending, Args([:])) }
                            } label: {
                                Label("Confirm all \(pendingCount) pending", systemImage: "checkmark.circle")
                            }
                        }
                    }
                    if groupByMonth {
                        ForEach(sections) { section in
                            Section(monthLabel(section.id)) {
                                ForEach(section.txns) { txn in row(txn) }
                            }
                        }
                    } else {
                        ForEach(sections.flatMap { $0.txns }) { txn in row(txn) }
                    }
                    if hasMore {
                        Button("Load more") { visibleCount += 50 }
                    }
                }
                #if os(macOS)
                .onKeyPress(.return) {
                    // In three-column selection mode the selection already drives
                    // the detail column — ↵ falls through (kbSel is unused there).
                    if !isSelecting, selection == nil, let id = kbSel,
                       let txn = sections.flatMap({ $0.txns }).first(where: { $0.id == id }) { editing = txn; return .handled }
                    return .ignored
                }
                #endif
            }
        }
        #if os(iOS)
        .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search transactions")
        #else
        .searchable(text: $searchQuery, prompt: "Search transactions")
        #endif
        .navigationTitle("Activity")
        .errorAlert($errorMessage)
        .quickLookPreview($previewURL)
        // Leave selection mode behind when the feed is popped/dismissed so the
        // selection toolbar doesn't linger stale on return.
        .onDisappear { isSelecting = false; selected.removeAll() }
        .toolbar {
            // Trailing: Select (multi-select for bulk-recategorize). The add `+`
            // only appears on regular width — compact has the floating FAB, so a
            // nav-bar `+` would be redundant.
            ToolbarItem(placement: .primaryAction) {
                Button(isSelecting ? "Done" : "Select") {
                    isSelecting.toggle(); selected.removeAll()
                }.disabled(store.txns.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingFilter = true } label: {
                    Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(TxSort.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort")
            }
            if sizeClass != .compact {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add Transaction")
                        .disabled(store.accounts.isEmpty)
                }
            }
            if isSelecting {
                #if os(iOS)
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Confirm \(selected.count)") { bulkConfirm() }.disabled(selected.isEmpty)
                    Spacer()
                    Button("Recategorize \(selected.count)") { showingBulkCat = true }.disabled(selected.isEmpty)
                    Spacer()
                    Button("Delete \(selected.count)", role: .destructive) { confirmingBulkDelete = true }.disabled(selected.isEmpty)
                }
                #else
                ToolbarItemGroup(placement: .principal) {
                    Button("Confirm \(selected.count)") { bulkConfirm() }.disabled(selected.isEmpty)
                    Button("Recategorize \(selected.count)") { showingBulkCat = true }.disabled(selected.isEmpty)
                    Button("Delete \(selected.count)", role: .destructive) { confirmingBulkDelete = true }.disabled(selected.isEmpty)
                }
                #endif
            }
        }
        // Selection mode borrows the bottom for the bulk-action bar. Hide the
        // tab bar (compact) so it doesn't sit under/overlap that bar, and signal
        // the FAB to step aside — the Photos/Mail edit-mode idiom.
        #if os(iOS)
        .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
        #endif
        .preference(key: SelectionActiveKey.self, value: isSelecting)
        .sheet(isPresented: $showingAdd) { AddTransactionSheet() }
        .sheet(isPresented: $showingFilter) { TransactionFilterSheet(filter: $filter) }
        .sheet(item: $editing) { EditTransactionSheet(txn: $0) }
        .sheet(item: $duplicating) { AddTransactionSheet(prefill: $0) }
        .sheet(isPresented: $showingBulkCat) {
            BulkRecategorizeSheet(ids: Array(selected)) { isSelecting = false; selected.removeAll() }
        }
        .confirmationDialog("Delete \(selected.count) transaction\(selected.count == 1 ? "" : "s")?",
                            isPresented: $confirmingBulkDelete, titleVisibility: .visible) {
            Button("Delete \(selected.count)", role: .destructive) { bulkDelete() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete transaction?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { txn in
            Button("Delete", role: .destructive) { delete(txn) }
            Button("Cancel", role: .cancel) {}
        } message: { txn in
            Text("\(txn.merchant) · \(store.displayMoneyBase(txn.amount))")
        }
        .onAppear { consumeFocus(); consumePendingFilter(); recompute() }
        .onChange(of: router.focusedId) { _, _ in consumeFocus() }
        .onChange(of: router.pendingFilter) { _, _ in consumePendingFilter() }
        .onChange(of: searchQuery) { _, _ in recompute() }
        .onChange(of: filter) { _, _ in recompute() }
        .onChange(of: sort) { _, _ in recompute() }
        .onChange(of: groupByMonth) { _, _ in recompute() }
        .onChange(of: visibleCount) { _, _ in recompute() }
        .onReceive(store.$txns) { _ in recompute() }
    }

    private func monthLabel(_ key: String) -> String {
        guard let d = AppDate.isoDay.date(from: "\(key)-01") else { return key }
        return d.formatted(.dateTime.month(.wide).year())
    }

    /// Recompute the cached day-sections. Cheap to call; runs only on the inputs
    /// that actually affect the list (txns, query, page size).
    private func recompute() {
        let f = filteredTxns()
        filteredCount = f.count
        hasMore = f.count > visibleCount
        var order: [String] = []
        var byMonth: [String: [Tx]] = [:]
        for txn in f.prefix(visibleCount) {
            let key = String(txn.date.prefix(7))           // "yyyy-MM"
            if byMonth[key] == nil { order.append(key) }
            byMonth[key, default: []].append(txn)
        }
        sections = order.map { DaySection(id: $0, txns: byMonth[$0] ?? []) }
        var shown = Set<String>(); var last: String?
        for txn in sections.flatMap({ $0.txns }) {
            if txn.date != last { shown.insert(txn.id); last = txn.date }
        }
        dateShownIds = shown
    }

    /// A deep link / Spotlight / notification tap stashed a tx id + switched to
    /// this tab — open that transaction.
    private func consumeFocus() {
        // In three-column selection mode, SplitViewShell owns deep-link
        // consumption (routes focusedId into txSelection instead) — bail so we
        // don't double-consume the same id via this sheet-based path.
        guard selection == nil else { return }
        guard let id = router.focusedId, let tx = store.txns.first(where: { $0.id == id }) else { return }
        editing = tx
        router.focusedId = nil
    }

    private func consumePendingFilter() {
        guard consumesPendingFilter, let pending = router.pendingFilter else { return }
        searchQuery = ""
        filter = pending            // existing .onChange(of: filter) → recompute()
        router.pendingFilter = nil
    }

    private func toggle(_ txn: Tx) {
        if selected.contains(txn.id) { selected.remove(txn.id) } else { selected.insert(txn.id) }
    }

    private func previewReceipt(_ tx: Tx) {
        if let first = store.attachments(for: tx.id).first { previewURL = store.attachmentURL(for: first) }
    }

    @ViewBuilder
    private func row(_ txn: Tx) -> some View {
        Button {
            if isSelecting { toggle(txn) }
            else if let selection { selection.wrappedValue = txn.id }
            else { editing = txn }
        } label: {
            HStack {
                if isSelecting {
                    Image(systemName: selected.contains(txn.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected.contains(txn.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                TxRow(txn: txn, onPreviewReceipt: isSelecting ? nil : { previewReceipt($0) },
                      showDate: dateShownIds.contains(txn.id))
            }
            .contentShape(Rectangle())   // make the whole row tappable — without this the Spacer gap (middle) doesn't hit-test
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Reveal a Delete button; tapping it asks for confirmation (no
            // delete-on-full-swipe — destructive actions get a confirm step).
            Button(role: .destructive) { pendingDelete = txn } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            if txn.pending == true {
                Button { confirm(txn) } label: { Label("Confirm", systemImage: "checkmark.circle") }.tint(.green)
            }
            if ["expense", "income"].contains(txn.kind ?? "") {
                Button { duplicate(txn) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }.tint(.indigo)
            }
        }
        .contextMenu {   // right-click parity on Mac/iPad (swipe is touch-only)
            Button { editing = txn } label: { Label("Edit", systemImage: "pencil") }
            if ["expense", "income"].contains(txn.kind ?? "") {
                Button { duplicate(txn) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            }
            if !store.attachments(for: txn.id).isEmpty {
                Button { previewReceipt(txn) } label: { Label("Preview receipt", systemImage: "paperclip") }
            }
            if txn.pending == true {
                Button { confirm(txn) } label: { Label("Confirm", systemImage: "checkmark.circle") }
            }
            Button(role: .destructive) { pendingDelete = txn } label: { Label("Delete", systemImage: "trash") }
        }
        .tag(txn.id)
    }

    private func delete(_ txn: Tx) {
        run { try store.deleteTransaction(txn.id) }   // also unlinks receipt files
    }
    private func confirm(_ txn: Tx) {
        run { try store.apply(.confirmTransaction, Args(["id": .string(txn.id)])) }
    }
    /// Duplicate opens the Add sheet pre-filled from the source row — the
    /// user tweaks/confirms via Save (no silent write).
    private func duplicate(_ txn: Tx) {
        duplicating = txn
    }
    private func bulkConfirm() {
        run { for id in selected { try store.apply(.confirmTransaction, Args(["id": .string(id)])) } }
        isSelecting = false; selected.removeAll()
    }
    private func bulkDelete() {
        run { for id in selected { try store.deleteTransaction(id) } }   // also unlinks receipts
        isSelecting = false; selected.removeAll()
    }
    /// Run a mutation, surfacing a rejection as a localized error alert instead
    /// of silently no-op'ing (was `try?`).
    private func run(_ work: () throws -> Void) {
        do { try work() } catch { errorMessage = i18nMessage(error) }
    }
    private var pendingCount: Int { store.txns.filter { $0.pending == true }.count }
    private var hasActiveQuery: Bool { !searchQuery.isEmpty || filter.isActive }

    @ViewBuilder private var savedSearchRow: some View {
        let saved = savedSearches.all(ledgerId: store.activeLedgerId)
        if !saved.isEmpty || filter.isActive {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(saved) { s in
                        Button { filter = s.filter } label: { chipLabel(s.name, selected: filter == s.filter) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { savedSearches.remove(s.id) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    if filter.isActive, !saved.contains(where: { $0.filter == filter }) {
                        Button { newSearchName = ""; showingSaveSearch = true } label: { chipLabel("＋ Save", selected: false) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowBackground(Color.clear)
            .alert("Save search", isPresented: $showingSaveSearch) {
                TextField("Name", text: $newSearchName)
                Button("Cancel", role: .cancel) { newSearchName = "" }
                Button("Save") {
                    savedSearches.save(name: newSearchName, filter: filter, ledgerId: store.activeLedgerId)
                    newSearchName = ""
                }
            } message: { Text("Save the current filters as a named search.") }
        }
    }

    private func chipLabel(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(selected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(selected ? Color.white : Color.primary)
    }

    /// Build a `ListOptions` from the filter sheet + search box and route through
    /// the engine's `selectTransactions` (which scopes to the active ledger and
    /// applies the stable date-desc sort).
    private func filteredTxns() -> [Tx] {
        let base = filter.counterpartyId.map {
            Selectors.merchantTransactions(store.txns, store.merchants, $0, store.activeLedgerId)
        } ?? store.txns
        let opts = ListOptions(
            ledgerId: store.activeLedgerId,
            direction: filter.direction,
            query: searchQuery.isEmpty ? nil : searchQuery,
            accountId: filter.accountId,
            categoryId: filter.categoryId,
            status: filter.status,
            from: filter.fromYMD,
            to: filter.toYMD,
            minAmount: filter.minAmount,
            maxAmount: filter.maxAmount,
            tagIds: filter.tagIds.isEmpty ? nil : Array(filter.tagIds),
            tagsMatchAll: filter.tagsMatchAll)
        return sort.sorted(Selectors.selectTransactions(base, opts))
    }
}

struct TxRow: View {
    @EnvironmentObject private var store: FinchStore
    @AppStorage("finch.feed.relativeDates") private var relativeDates = true
    let txn: Tx
    var onPreviewReceipt: ((Tx) -> Void)? = nil
    var showDate: Bool = true

    private var rowTags: [TagRow] {
        guard let ids = txn.tags, !ids.isEmpty else { return [] }
        return ids.compactMap { id in store.tags.first { $0.id == id } }
    }

    private var receipts: [AttachmentRow] { store.attachments(for: txn.id) }

    /// Bottom-left line: the transaction's date, with its time appended when set.
    /// Shows relative dates (Today/Yesterday) or short format (Jun 25).
    private var dateTimeText: String {
        let base = relativeOrShort(txn.date)
        if let t = txn.time, !t.isEmpty { return "\(base) · \(t)" }
        return base
    }

    private func relativeOrShort(_ ymd: String) -> String {
        guard relativeDates else { return ymd }
        guard let d = AppDate.isoDay.date(from: ymd) else { return ymd }
        let today = AppDate.isoDay.date(from: store.wallToday) ?? Date()
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: today)).day ?? 0
        if days == 0 { return String(localized: "Today") }
        if days == 1 { return String(localized: "Yesterday") }
        let sameYear = cal.component(.year, from: d) == cal.component(.year, from: today)
        if sameYear {
            return d.formatted(.dateTime.month(.abbreviated).day())
        } else {
            return d.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }

    var body: some View {
        HStack {
            Image(systemName: TxnKindIcon.icon(for: txn.kind))
                .foregroundStyle(txn.amount < 0 ? .red : .green)
            VStack(alignment: .leading, spacing: 2) {
                // Top-left: merchant + status flags + category.
                HStack(spacing: 4) {
                    Text(txn.merchant)
                    if txn.pending == true {
                        Image(systemName: "clock").font(.caption2).foregroundStyle(.orange)
                    }
                    if store.isAnomaly(txn) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange)
                            .accessibilityLabel("Unusual amount")
                    }
                    if txn.kind == "refund" {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.uturn.left")
                            Text("Refund")
                        }
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                        .accessibilityLabel("Refund")
                    }
                    if let cat = store.categoryName(txn.category) {
                        Text(cat).font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                // Bottom-left: date·time + tags.
                HStack(spacing: 4) {
                    if showDate { Text(dateTimeText).font(.caption2).foregroundStyle(.secondary) }
                    ForEach(rowTags.prefix(3)) { tag in
                        Text(tag.name).font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((Color(hex: tag.color ?? "") ?? .secondary).opacity(0.2), in: Capsule())
                            .foregroundStyle(Color(hex: tag.color ?? "") ?? .secondary)
                    }
                    if rowTags.count > 3 {
                        Text("+\(rowTags.count - 3)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if let onPreviewReceipt, !receipts.isEmpty {
                Button { onPreviewReceipt(txn) } label: {
                    Image(systemName: "paperclip").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Preview receipt")
            }
            // Right: amount (top) + running account balance after this txn (bottom).
            VStack(alignment: .trailing, spacing: 2) {
                Text(store.displayMoneyBase(txn.amount)).fontWeight(.semibold)
                let remaining = store.runningBalanceBase(for: txn)
                Text(store.displayMoneyBase(remaining))
                    .font(.caption2)
                    .foregroundStyle(remaining < 0 ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .accessibilityLabel("Balance after")
            }
        }
    }
}
