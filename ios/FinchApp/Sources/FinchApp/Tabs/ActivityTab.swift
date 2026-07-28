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
    @State private var pendingSearchDelete: SavedSearch?   // saved search awaiting delete confirmation
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
    @State private var sections: [MonthGrouping.Section] = []
    @State private var pendingTxns: [Tx] = []   // pinned "To confirm" bucket (filtered)
    @State private var dateShownIds: Set<String> = []
    @State private var hasMore = false
    @State private var confirmingBulkDelete = false
    @State private var pendingDelete: Tx?   // single-row delete awaiting confirmation

    // Calendar lens (List is the default): a month grid of ACTUAL daily
    // income/expense over the filtered transactions — tap a day to see its rows.
    // (The Scheduled tab's calendar is the plan-side counterpart.)
    private enum ViewMode: String, CaseIterable { case list = "List", calendar = "Calendar" }
    @State private var viewMode: ViewMode = .list
    @State private var calMonthAnchor: Date = MonthCashCalendar.firstOfMonth(forISO: nil)
    @State private var calSelectedDay: String?

    var body: some View {
        Group {
            if store.txns.isEmpty {
                EmptyState(tab: .activity)
            } else {
                List(selection: selection ?? $kbSel) {
                    modePickerRow
                    if viewMode == .calendar {
                        Section {
                            MonthCashCalendar(
                                monthAnchor: $calMonthAnchor, selectedDay: $calSelectedDay,
                                wallToday: store.wallToday,
                                amountsForRange: { from, through in
                                    MonthGrouping.dailyIncomeExpense(filteredTxns().filter { $0.date >= from && $0.date <= through })
                                },
                                format: { store.displayExactBase($0) })
                        }
                        calendarDetail
                    } else {
                    savedSearchRow
                    if sections.isEmpty && pendingTxns.isEmpty {
                        ContentUnavailableView {
                            Label("No matching transactions", systemImage: "line.3.horizontal.decrease.circle")
                        } description: {
                            Text("Try adjusting your search or filters.")
                        } actions: {
                            if hasActiveQuery { Button("Clear filters & search") { searchQuery = ""; filter = TxFilter() } }
                        }
                        .listRowBackground(Color.clear)
                    }
                    // Pending pins above the months regardless of the sort menu —
                    // the same "To confirm" bucket the account detail shows.
                    // Search/filters apply (the bucket shows only matching rows);
                    // "Confirm all" still clears every pending row store-wide.
                    if !pendingTxns.isEmpty {
                        Section("To confirm (\(pendingTxns.count))") {
                            ForEach(pendingTxns) { txn in row(txn) }
                            Button {
                                run { try store.apply(.confirmAllPending, Args([:])) }
                            } label: {
                                Label("Confirm all \(pendingCount) pending", systemImage: "checkmark.circle")
                            }
                        }
                    }
                    if groupByMonth {
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.txns) { txn in row(txn) }
                            } header: {
                                monthHeader(section.id, section.txns)
                            }
                        }
                    } else {
                        ForEach(sections.flatMap { $0.txns }) { txn in row(txn) }
                    }
                    if hasMore {
                        Button("Load more") { visibleCount += 50 }
                    }
                    }   // viewMode == .list
                }
                #if os(macOS)
                .onKeyPress(.return) {
                    // In three-column selection mode the selection already drives
                    // the detail column — ↵ falls through (kbSel is unused there).
                    if !isSelecting, selection == nil, let id = kbSel,
                       let txn = (pendingTxns + sections.flatMap({ $0.txns })).first(where: { $0.id == id }) { editing = txn; return .handled }
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
                    bulkDeleteButton
                }
                #else
                ToolbarItemGroup(placement: .principal) {
                    Button("Confirm \(selected.count)") { bulkConfirm() }.disabled(selected.isEmpty)
                    Button("Recategorize \(selected.count)") { showingBulkCat = true }.disabled(selected.isEmpty)
                    bulkDeleteButton
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
        // A centered ALERT, not a row-anchored confirmationDialog: window-level,
        // so it presents instantly and survives swipe collapse / cell recycling
        // (row-anchored popouts kept getting torn down or pinning dead cells).
        .alert("Delete transaction?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete) { txn in
            Button("Delete", role: .destructive) { delete(txn) }
            Button("Cancel", role: .cancel) {}
        } message: { txn in
            Text("\(txn.merchant) · \(store.displayMoneyBase(txn.amount))")
        }
        .alert("Delete saved search?", isPresented: Binding(
            get: { pendingSearchDelete != nil }, set: { if !$0 { pendingSearchDelete = nil } }),
            presenting: pendingSearchDelete) { s in
            Button("Delete", role: .destructive) { savedSearches.remove(s.id) }
            Button("Cancel", role: .cancel) {}
        } message: { s in
            Text("\(s.name)")
        }
        .onAppear { consumeFocus(); consumePendingFilter(); recompute() }
        .onChange(of: router.focusedId) { _, _ in consumeFocus() }
        .onChange(of: router.pendingFilter) { _, _ in consumePendingFilter() }
        .onChange(of: searchQuery) { _, _ in recompute() }
        .onChange(of: filter) { _, _ in recompute() }
        .onChange(of: sort) { _, _ in recompute() }
        .onChange(of: groupByMonth) { _, _ in recompute() }
        .onChange(of: visibleCount) { _, _ in recompute() }
        // Deferred one runloop turn: @Published emits during willSet, so a
        // synchronous recompute here reads the OLD store.txns and rebuilds the
        // stale list (deleted rows lingered). After the hop the store is settled.
        .onReceive(store.$txns) { _ in DispatchQueue.main.async { recompute() } }
    }

    /// Recompute the cached day-sections. Cheap to call; runs only on the inputs
    /// that actually affect the list (txns, query, page size).
    private func recompute() {
        let f = filteredTxns()
        // Pending splits into its pinned bucket (newest first, whatever the sort
        // menu says); the month sections cover confirmed rows only.
        pendingTxns = TxSort.dateDesc.sorted(f.filter { $0.pending == true })
        let confirmed = f.filter { $0.pending != true }
        hasMore = confirmed.count > visibleCount
        sections = MonthGrouping.sections(Array(confirmed.prefix(visibleCount)))
        // Bucket rows always carry their date (no day-de-dup context up there).
        var shown = Set<String>(pendingTxns.map(\.id)); var last: String?
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
    /// The selection-bar Delete with its confirmation attached — so the iOS 26
    /// popout anchors at this button (shared by the iOS bottom bar and the
    /// macOS principal group).
    private var bulkDeleteButton: some View {
        Button("Delete \(selected.count)", role: .destructive) { confirmingBulkDelete = true }
            .disabled(selected.isEmpty)
            .confirmationDialog("Delete \(selected.count) transaction\(selected.count == 1 ? "" : "s")?",
                                isPresented: $confirmingBulkDelete, titleVisibility: .visible) {
                Button("Delete \(selected.count)", role: .destructive) { bulkDelete() }
                Button("Cancel", role: .cancel) {}
            }
    }

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
                      showDate: dateShownIds.contains(txn.id), showRunningBalance: false)
            }
            .contentShape(Rectangle())   // make the whole row tappable — without this the Spacer gap (middle) doesn't hit-test
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))   // denser rows
        .txnSwipeActions(txn,
                         duplicate: { duplicate($0) },
                         requestDelete: { pendingDelete = $0 },
                         toggleStatus: { toggleStatus($0) },
                         edit: { editing = $0 },
                         previewReceipt: store.attachments(for: txn.id).isEmpty ? nil : { previewReceipt($0) })
        .tag(txn.id)
    }

    private func delete(_ txn: Tx) {
        run { try store.deleteTransaction(txn.id) }   // also unlinks receipt files
    }
    private func toggleStatus(_ txn: Tx) {
        run { try txnToggleStatus(txn, store: store) }
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

    /// The List/Calendar toggle as a list row — the shared `ViewModePickerRow`
    /// (same row the Scheduled tab uses).
    private var modePickerRow: some View {
        ViewModePickerRow(selection: $viewMode, options: [(.list, String(localized: "List")), (.calendar, String(localized: "Calendar"))])
    }

    /// Below the calendar grid: the selected day's transactions, or the anchored
    /// month's when no day is selected — always the same filtered set the grid
    /// sums, so the cells and the rows can't disagree.
    @ViewBuilder private var calendarDetail: some View {
        let all = filteredTxns()
        if let day = calSelectedDay {
            let dayTx = all.filter { $0.date == day }
            Section {
                if dayTx.isEmpty {
                    Text("No transactions.").foregroundStyle(.secondary)
                } else {
                    ForEach(dayTx) { txn in row(txn) }
                }
            } header: {
                Text(MonthCashCalendar.pretty(day)).textCase(nil)
            }
        } else {
            let key = String(format: "%04d-%02d",
                             AppDate.civil.component(.year, from: calMonthAnchor),
                             AppDate.civil.component(.month, from: calMonthAnchor))
            let monthTx = all.filter { $0.date.hasPrefix(key) }
            if !monthTx.isEmpty {
                Section {
                    ForEach(monthTx) { txn in row(txn) }
                } header: {
                    monthHeader(key, monthTx)
                }
            }
        }
    }

    /// The month section header (wide label + net, "Income · Spent" caption) —
    /// one markup for the list lens and the calendar's month fallback.
    private func monthHeader(_ key: String, _ txns: [Tx]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(MonthGrouping.label(key)).textCase(nil)
                Spacer()
                Text(store.displayMoneyBase(MonthGrouping.net(txns)))
                    .foregroundStyle(.secondary)
            }
            Text("Income \(store.displayMoneyBase(MonthGrouping.income(txns))) · Spent \(store.displayMoneyBase(MonthGrouping.expense(txns)))")
                .font(.caption2).textCase(nil).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var savedSearchRow: some View {
        let saved = savedSearches.all(ledgerId: store.activeLedgerId)
        if !saved.isEmpty || filter.isActive {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(saved) { s in
                        Button { filter = s.filter } label: { chipLabel(s.name, selected: filter == s.filter) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { pendingSearchDelete = s } label: { Label("Delete", systemImage: "trash") }
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
            Selectors.merchantTransactions(store.txns, store.merchants, $0, store.activeLedgerId,
                                           includePending: true)   // the feed shows pending rows
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
        // Search matches what a row displays — the category title (TxRow's
        // title line) and tag chips, not just the merchant text — so the
        // id→name lookups ride along with the query.
        return sort.sorted(Selectors.selectTransactions(
            base, opts,
            categoryNames: Dictionary(uniqueKeysWithValues: store.categories.map { ($0.id, $0.name) }),
            tagNames: Dictionary(uniqueKeysWithValues: store.tags.map { ($0.id, $0.name) })))
    }
}

struct TxRow: View {
    @EnvironmentObject private var store: FinchStore
    @AppStorage("finch.feed.relativeDates") private var relativeDates = true
    let txn: Tx
    var onPreviewReceipt: ((Tx) -> Void)? = nil
    var showDate: Bool = true
    /// Running account balance under the amount — a ledger-style column that only
    /// reads sensibly when every row shares one account (Account Detail). Mixed-
    /// account lists (feed, counterparty) hide it.
    var showRunningBalance: Bool = true

    private var rowTags: [TagRow] {
        guard let ids = txn.tags, !ids.isEmpty else { return [] }
        return ids.compactMap { id in store.tags.first { $0.id == id } }
    }

    private var receipts: [AttachmentRow] { store.attachments(for: txn.id) }

    /// First `visible` tag chips + a "+N" count chip for the rest (if any).
    /// The ViewThatFits cascade in the title row calls this with 3→2→1→0.
    @ViewBuilder private func tagChips(showing visible: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(rowTags.prefix(visible)) { tag in
                Text(tag.name).font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((Color(hex: tag.color ?? "") ?? .secondary).opacity(0.2), in: Capsule())
                    .foregroundStyle(Color(hex: tag.color ?? "") ?? .secondary)
                    .lineLimit(1).fixedSize()
            }
            if rowTags.count > visible {
                Text("+\(rowTags.count - visible)").font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityLabel("\(rowTags.count - visible) more tags")
            }
        }
    }

    /// Bottom-left line: the transaction's date, with its time appended when set.
    /// Shows relative dates (Today/Yesterday) or short format (Jun 25).
    /// Stripe color by kind: expense red, income green, refund purple (money
    /// back, but distinct from income), transfer blue, adjustment gray.
    private var kindColor: Color {
        switch txn.kind {
        case "income": .green
        case "refund": .purple
        case "transfer": .blue
        case "adjustment": Color.gray
        default: .red
        }
    }

    private var kindA11yLabel: Text {
        switch txn.kind {
        case "income": Text("Income")
        case "refund": Text("Refund")
        case "transfer": Text("Transfer")
        case "adjustment": Text("Adjustment")
        default: Text("Expense")
        }
    }

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
        HStack(spacing: 8) {
            // Thin kind/direction stripe — the leading icon's replacement: near-zero
            // width, consistent on every row, scannable down the column.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(kindColor)
                .frame(width: 3)
                .accessibilityLabel(kindA11yLabel)
            VStack(alignment: .leading, spacing: 1) {
                // Top-left: category is the title (merchant lives in edit/detail
                // only, per user decision) + status flags + tag chips.
                HStack(spacing: 4) {
                    Group {
                        if let cat = store.categoryName(txn.category) {
                            Text(cat)
                        } else {
                            Text("Uncategorized").foregroundStyle(.secondary)
                        }
                    }
                    .layoutPriority(1)   // chips yield before the title truncates
                    if txn.pending == true {
                        Image(systemName: "clock").font(.caption2).foregroundStyle(.orange)
                    }
                    if store.isAnomaly(txn) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange)
                            .accessibilityLabel("Unusual amount")
                    }
                    // Tags: show chips while they fit, then a +N count for the
                    // hidden rest (ViewThatFits cascade, capped at 3 chips).
                    if !rowTags.isEmpty {
                        ViewThatFits(in: .horizontal) {
                            tagChips(showing: min(rowTags.count, 3))
                            if rowTags.count >= 2 { tagChips(showing: 2) }
                            if rowTags.count >= 1 { tagChips(showing: 1) }
                            tagChips(showing: 0)
                        }
                    }
                }
                // Bottom-left: date·time + optional note (truncated to one line).
                HStack(spacing: 4) {
                    if showDate { Text(dateTimeText).font(.footnote).foregroundStyle(.secondary) }
                    if let note = txn.note, !note.isEmpty {
                        Text(showDate ? "· \(note)" : note)
                            .font(.footnote).foregroundStyle(.secondary)
                            .lineLimit(1)
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
            VStack(alignment: .trailing, spacing: 1) {
                Text(store.displayMoneyBase(txn.amount)).fontWeight(.semibold)
                if showRunningBalance {
                    let remaining = store.runningBalanceBase(for: txn)
                    Text(store.displayMoneyBase(remaining))
                        .font(.caption2)
                        .foregroundStyle(remaining < 0 ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .accessibilityLabel("Balance after")
                }
            }
        }
    }
}
