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
    @State private var hasMore = false
    @State private var confirmingBulkDelete = false
    @State private var pendingDelete: Tx?   // single-row delete awaiting confirmation
    // Appended to the delete-confirmation message when the entry has more than
    // one account leg: deleting any one feed row deletes the whole entry, so the
    // user should know the other leg(s) go too. `accountLegCount > 1` is true for
    // BOTH a split purchase and a transfer, but they need different wording —
    // `transferGroupId` (set only for transfers; see Projection.enrichLegTxs)
    // picks the right one. Mirrors the web's deleteDialog transferHint/splitHint
    // precedence (transaction-detail.tsx).
    static let multiLegDeleteHint = String(localized: "This also deletes the other payments linked to this purchase.")
    static let transferDeleteHint = String(localized: "This also deletes the other side of the transfer.")

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
                // Distinguish "still projecting" (launch defers the txns list off the
                // first-paint path — see FinchStore.reprojectActiveLedger) from a
                // genuinely empty ledger, so we don't flash "No transactions".
                if !store.txnsReady {
                    ProgressView().controlSize(.large)
                } else {
                    EmptyState(tab: .activity)
                }
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
                                format: { store.displayExactBase($0) },
                                masked: store.privacyMode)
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
                    // Search/filters apply, so the bucket shows only matching rows.
                    //
                    // No "confirm all" here. It used to sit at the foot of this
                    // section and clear every pending row store-wide while the
                    // section header counted only the filtered ones — one tap, no
                    // prompt, no undo. Bulk confirming is multi-select's job.
                    if !pendingTxns.isEmpty {
                        Section("To confirm (\(pendingTxns.count))") {
                            ForEach(pendingTxns) { txn in row(txn) }
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
        .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        #else
        .searchable(text: $searchQuery, prompt: "Search")
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
                // Sort AND grouping, matching the UIKit screen's overflow menu. This
                // menu used to hold sort alone while `groupByMonth` was still read
                // below and shared through AppStorage with the UIKit screen — so
                // grouping was a live setting that nothing here could change, and this
                // screen silently inherited whatever the UIKit one last wrote.
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(TxSort.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Group by month", isOn: $groupByMonth)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Sort and grouping")
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
            // A split purchase (or a transfer) renders as one feed row per account
            // leg; deleting any one row deletes the whole entry. Warn whenever
            // there's a sibling leg, so the user isn't surprised the other payment
            // went too. Transfers get their own wording (transferGroupId) — "the
            // other payments linked to this purchase" is wrong for a transfer.
            if txn.transferGroupId != nil {
                Text("\(txn.merchant) · \(store.displayMoneyBase(txn.amount))") + Text(" " + Self.transferDeleteHint)
            } else if (txn.accountLegCount ?? 1) > 1 {
                Text("\(txn.merchant) · \(store.displayMoneyBase(txn.amount))") + Text(" " + Self.multiLegDeleteHint)
            } else {
                Text("\(txn.merchant) · \(store.displayMoneyBase(txn.amount))")
            }
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
            } message: {
                // The title counts what was SELECTED, which is what the user sees
                // ticked. Deleting works on whole purchases, so selecting one payment
                // of a split takes its siblings too — say so rather than let rows
                // vanish that were never ticked. Deliberately not a second count in
                // the title: two numbers disagreeing on one dialog reads as a bug.
                if selectionTakesUnselectedRows { Text(Self.multiLegDeleteHint) }
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
                      // Inert while selecting: a tap must add the row to the
                      // selection, not write to it.
                      onToggleStatus: isSelecting ? nil : { toggleStatus($0) },
                      showRunningBalance: false)
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
        // No animation when the row moves. Confirming lifts it out of the "To confirm"
        // section and into its month, and a SwiftUI List animates that by default. The
        // UIKit feed does not need this — its snapshots already apply with
        // `animatingDifferences: false`.
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { run { try txnToggleStatus(txn, store: store) } }
    }
    /// Duplicate opens the Add sheet pre-filled from the source row — the
    /// user tweaks/confirms via Save (no silent write).
    private func duplicate(_ txn: Tx) {
        duplicating = txn
    }
    private func bulkConfirm() {
        report(store.confirmTransactions(Array(selected)), of: selected.count)
        isSelecting = false; selected.removeAll()
    }
    /// Whether deleting the selection would also remove rows the user did not
    /// tick — a payment whose purchase has a sibling leg outside the selection.
    /// `selected` holds POSTING ids, and deletion is per purchase.
    private var selectionTakesUnselectedRows: Bool {
        let keys = Set(store.txns.filter { selected.contains($0.id) }.map(\.purchaseKey))
        return store.txns.contains { keys.contains($0.purchaseKey) && !selected.contains($0.id) }
    }

    private func bulkDelete() {
        report(store.deleteTransactions(Array(selected)), of: selected.count)   // also unlinks receipts
        isSelecting = false; selected.removeAll()
    }
    /// One write for the whole selection, so a row the engine rejects is skipped
    /// rather than abandoning the rest — which means the shortfall has to be said
    /// out loud, or a silently-skipped row looks like it worked.
    private func report(_ applied: Int, of requested: Int) {
        if applied < requested {
            errorMessage = String(localized: "\(requested - applied) of \(requested) couldn't be applied.")
        }
    }
    /// Run a mutation, surfacing a rejection as a localized error alert instead
    /// of silently no-op'ing (was `try?`).
    private func run(_ work: () throws -> Void) {
        do { try work() } catch { errorMessage = i18nMessage(error) }
    }
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

    /// The month section header — the month name, then net, in and out on one row,
    /// told apart by sign and reinforced by colour. One markup for the list lens and
    /// the calendar's month fallback.
    private func monthHeader(_ key: String, _ txns: [Tx]) -> some View {
        MonthFiguresHeader(label: MonthGrouping.label(key),
                           figures: store.monthHeaderFigures(txns),
                           accessibilityText: store.monthHeaderSpoken(txns))
            .textCase(nil)
    }

    @ViewBuilder private var savedSearchRow: some View {
        let saved = savedSearches.all(ledgerId: store.activeLedgerId)
        if !saved.isEmpty || filter.isActive {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(saved) { s in
                        Button { filter = s.filter } label: { chipLabel(s.name, selected: filter == s.filter) }
                            .buttonStyle(.plain)
                            // Long-press is the ONLY way to delete a chip, and
                            // VoiceOver does not surface a context menu — so without
                            // this a VoiceOver user can create saved searches and never
                            // remove one. Mirrored in SavedSearchChips (the UIKit feed).
                            .accessibilityAction(named: Text("Delete")) { pendingSearchDelete = s }
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
    /// Tapping the leading category glyph flips pending ⇄ confirmed.
    ///
    /// Optional for the same reason `onPreviewReceipt` is: a screen that has no
    /// business mutating status passes nil and the glyph stays inert. Multi-select
    /// passes nil too — while you are picking rows, a tap must select, not write.
    var onToggleStatus: ((Tx) -> Void)? = nil
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
            // Leading category icon — what the stripe used to stand in for, and now
            // also the status control. See `statusGlyph` for the appearance rules.
            //
            // It carries the KIND label, which is why the stripe below does not. The row
            // is one combined accessibility element (see `TxRowCell`), so its spoken
            // label follows LAYOUT order: with the stripe moved to the trailing edge, a
            // label left on it would announce the amount before saying whether the row
            // was income, a refund or a transfer — none of which the amount alone tells
            // you. Hanging it on the leading icon keeps speech opening with the kind, as
            // it did before, without a phantom zero-width view to carry it. (An empty
            // `Text` cannot: it contributes nothing to a combined label. Measured — the
            // kind vanished from the tree entirely.)
            // AN A11Y-HIDDEN BUTTON OVERLAY — the third design for this control, and
            // both predecessors are known-bad:
            //
            //  - a Button WRAPPING the glyph dropped the kind from every row's
            //    combined label (`children: .combine` does not merge an interactive
            //    child's label) — measured, 10 of 10 rows;
            //  - a `.simultaneousGesture(TapGesture())` here — hosted cell content —
            //    broke UICollectionView row selection OUTRIGHT, both size classes:
            //    compact rows stopped opening the editor and the iPad Activity
            //    column stopped selecting (post-merge red #744; bisected to this
            //    line, confirmed both directions by removing/restoring it). Same
            //    arbitration failure ActivityMonitor.swift documents at the root.
            //
            // So the glyph stays a PLAIN view and keeps carrying the kind label,
            // while an invisible Button OVERLAYS it to take the tap — an interactive
            // control, which UIHostingConfiguration arbitrates correctly against
            // cell selection where a bare gesture recognizer is not. It is hidden
            // from accessibility (the row's custom action in `TxRowCell` and the
            // context menu remain the accessible paths, same words — the swipe's
            // status action was one of them until it was removed as a duplicate of
            // this control) and exists only
            // when a screen passes `onToggleStatus`, so multi-select and read-only
            // screens keep a fully inert glyph.
            //
            // Guarded by TxRowTapTargetsUITests (compact: row body opens editor,
            // glyph confirms) and SplitMechanicsUITests (iPad: row selects). Run
            // BOTH before redesigning this control again.
            statusGlyph
                .overlay {
                    if let onToggleStatus {
                        Button {
                            // The state change goes FIRST. The haptic is feedback about
                            // work already done, and playing it first put the Taptic
                            // Engine's warm-up between the tap and the row moving.
                            onToggleStatus(txn)
                            // The row usually LEAVES the screen on tap — it moves to
                            // another section — so this is the only confirmation the
                            // press landed on the control rather than the row behind it.
                            Haptics.tap()
                        } label: {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHidden(true)
                    }
                }
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
                    // One purchase, several rows — either several payments on one
                    // transaction, or a grid's several transactions. The feed shows
                    // a row per payment deliberately (it is what you check against a
                    // statement), so this is what says the rows belong together.
                    //
                    // ONE symbol, one meaning: "part of one purchase". Deliberately
                    // NOT a promise about deleting — a grid row deletes on its own,
                    // while a split-tender payment takes its siblings. Neutral, and
                    // chosen not to read as the reconcile tick.
                    if (txn.accountLegCount ?? 1) > 1 || txn.groupId != nil {
                        Image(systemName: "square.on.square").font(.caption2).foregroundStyle(.secondary)
                            .accessibilityLabel("Part of one purchase")
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
                Text(store.displayMoneyBase(txn.amount))
                    .font(Metrics.rowAmountFont)   // one notch below the category — see Metrics
                    .fontWeight(Metrics.rowAmountWeight)
                // nil on a pending row — it has not cleared, so there is no
                // "balance after" to print.
                if showRunningBalance, let remaining = store.runningBalanceBase(for: txn) {
                    Text(store.displayMoneyBase(remaining))
                        .font(.caption2)
                        .foregroundStyle(remaining < 0 ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .accessibilityLabel("Balance after")
                }
            }
            // Thin kind/direction stripe, now at the TRAILING edge beside the amount.
            // Fixed width, so every amount shifts left by the same 11pt and the amount
            // column stays aligned across rows. Hidden from VoiceOver — the zero-width
            // element at the leading edge speaks the kind instead, keeping it first.
            //
            // Height is fixed too, and has to be: a shape is infinitely flexible, so
            // width alone let it fill the row's text block (measured 38pt) and read as a
            // rule between rows. `ScheduledRow` reads the same token — see Metrics.
            // The enclosing HStack centres it, which is where a marker belongs.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(kindColor)
                .frame(width: 3, height: Metrics.kindStripeHeight)
                .accessibilityHidden(true)
        }
    }

    /// `RowGlyph.Tint` → a real colour. The tint cases stay colour-free so the glyph
    /// choice can be unit-tested without a view; this is where they land.
    /// The leading glyph, faded while the row is pending.
    ///
    /// The clock badge remains the primary pending signal; this is the second one,
    /// and it exists so the CONTROL differs by state — a button that looks identical
    /// whatever it will do gives no feedback that a press registered, on a row that
    /// then leaves the section you were looking at. `RowStatusStyle.pendingOpacity`
    /// is the single knob if the treatment reads wrong: set it to 1.0 and the glyph
    /// goes back to looking the same in both states, with no other edit.
    ///
    /// The hit area fills the row's height while the glyph keeps its own width, so
    /// the text column, the tag-chip cascade and the 52pt row height are untouched.
    private var statusGlyph: some View {
        let g = store.rowGlyph(categoryId: txn.category, kind: txn.kind)
        return RowGlyphView(symbol: g.symbol, tint: glyphTint(g.tint), a11yLabel: kindA11yLabel)
            .opacity(RowStatusStyle.glyphOpacity(pending: txn.pending == true))
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
    }

    private func glyphTint(_ tint: RowGlyph.Tint) -> Color {
        switch tint {
        case .category(let hex): Color(hex: hex) ?? .secondary
        case .kind:              kindColor
        case .unset:             .secondary
        }
    }
}
