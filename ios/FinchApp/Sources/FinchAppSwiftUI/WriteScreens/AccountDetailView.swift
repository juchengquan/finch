import SwiftUI
import FinchCore

/// Account drill-in: name + balance (+ reconcile seal) in the nav-bar title —
/// always visible while scrolled — then straight into holdings (investment
/// accounts) and the account's transactions: searchable, month-sectioned
/// behind the shared group-by-month toggle, pending pinned on top. No header
/// cards — the type lives in the Edit sheet, the reconcile date in the
/// Reconcile sheet. Edit/reconcile/archive/delete via the toolbar.
/// Re-resolves the account from the store by id so edits reflect live; pops
/// when the account is archived or deleted.
struct AccountDetailView: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("finch.feed.groupByMonth") private var groupByMonth = true
    @AppStorage(ReconcileReminder.key) private var reconcileStaleDays = ReconcileReminder.defaultDays

    let accountId: String

    @State private var showingEdit = false
    @State private var showingReconcile = false
    @State private var showingAdjust = false
    @State private var showingAddTx = false
    @State private var confirmingDelete = false
    @State private var pendingTxDelete: Tx?   // single-transaction delete awaiting confirmation
    @State private var errorMessage: String?
    @State private var editing: Tx?
    @State private var duplicating: Tx?   // Duplicate → Add sheet pre-filled
    @State private var previewURL: URL?
    @State private var searchQuery = ""

    // Calendar lens (List default): the shared MonthCashCalendar with IN/OUT
    // semantics — at single-account grain the honest reading is a bank
    // statement's credits/debits, so transfers count on the side they move
    // (unlike Activity's wallet-level income/expense, where the two legs of a
    // transfer appear together). The math is the same sign-split; only the
    // meaning differs, hence the explanatory footer.
    private enum ViewMode: String, CaseIterable { case list = "List", calendar = "Calendar" }
    @State private var viewMode: ViewMode = .list
    @State private var calMonthAnchor: Date = MonthCashCalendar.firstOfMonth(forISO: nil)
    @State private var calSelectedDay: String?

    private var account: AccountRow? { store.accounts.first { $0.id == accountId } }

    var body: some View {
        Group {
            if let account {
                accountDetailContent(account)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        #if os(iOS)
        .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        #else
        .searchable(text: $searchQuery, prompt: "Search")
        #endif
    }

    @ViewBuilder
    private func accountDetailContent(_ account: AccountRow) -> some View {
        List {
            modePickerRow
            holdingsSection(account)
            if viewMode == .calendar {
                calendarSection(account)
            } else {
                transactionsSection(account)
            }
        }
        #if os(iOS)
        // A List opens with a top inset sized to sit under a LARGE title. This
        // screen's title is inline (name over balance, in the bar), so that inset
        // just read as a hole between the search field and the mode picker — about
        // 40pt more than the same picker has on All Transactions, which does have a
        // large title. Zero it so the two screens open the same way.
        .contentMargins(.top, 0, for: .scrollContent)
        #endif
        .errorAlert($errorMessage)
        .navigationTitle(account.name ?? "Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
                    // Name over balance — always visible while scrolled;
                    // privacy-aware via displayMoney. The reconcile seal sits
                    // beside the balance (same glyph/colors as the Accounts
                    // list rows); the absolute date lives in the Reconcile
                    // sheet, where you'd act on it.
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 0) {
                            Text(account.name ?? "—").font(.headline)
                            HStack(spacing: 3) {
                                Text(store.displayMoney(account.balance, from: account.currency))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let seal = titleSeal(account) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption2).foregroundStyle(seal)
                                }
                            }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingAddTx = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Add Transaction")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button { showingEdit = true } label: { Label("Edit", systemImage: "pencil") }
                            Button { showingReconcile = true } label: { Label("Reconcile", systemImage: "checkmark.circle") }
                            Button { showingAdjust = true } label: { Label("Adjust balance…", systemImage: TxnKindIcon.icon(for: "adjustment")) }
                            Button { archive(account) } label: { Label("Archive", systemImage: "archivebox") }
                            Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis") }
                        // Anchored on the ⋯ menu (iOS 26 positions popouts at their source).
                        .confirmationDialog("Delete this account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) { delete(account) }
                        } message: {
                            Text("Accounts with transactions can't be deleted — archive instead.")
                        }
                    }
                }
                .sheet(isPresented: $showingEdit) {
                    AccountSheet(account: account, defaultCurrency: store.baseCurrency)
                }
                .sheet(isPresented: $showingReconcile) { ReconcileSheet(preselect: account.id) }
                .sheet(isPresented: $showingAdjust) { AdjustBalanceSheet(account: account) }
                .sheet(isPresented: $showingAddTx) { AddTransactionSheet(defaultAccountId: account.id) }
                .sheet(item: $editing) { EditTransactionSheet(txn: $0) }
                .sheet(item: $duplicating) { AddTransactionSheet(prefill: $0) }
                // Tell the floating add button which account this page shows,
                // so it seeds the sheet the same way the toolbar `+` above does.
                .preference(key: AddTxContextKey.self, value: AddTxContext(accountId: account.id))
                .quickLookPreview($previewURL)
                // A centered ALERT, not a row-anchored confirmationDialog — see
                // ActivityTab (window-level survives swipe collapse / recycling).
                .alert("Delete transaction?", isPresented: Binding(
                    get: { pendingTxDelete != nil }, set: { if !$0 { pendingTxDelete = nil } }),
                    presenting: pendingTxDelete) { t in
                    Button("Delete", role: .destructive) { deleteTxn(t) }
                    Button("Cancel", role: .cancel) {}
                } message: { t in
                    // Same multi-leg warning as ActivityTab's delete alert: a split
                    // purchase (or a transfer) renders as one row per account leg,
                    // and deleting any one row deletes the whole entry.
                    if t.transferGroupId != nil {
                        Text("\(t.merchant) · \(store.displayMoneyBase(t.amount))") + Text(" " + ActivityFeedView.transferDeleteHint)
                    } else if (t.accountLegCount ?? 1) > 1 {
                        Text("\(t.merchant) · \(store.displayMoneyBase(t.amount))") + Text(" " + ActivityFeedView.multiLegDeleteHint)
                    } else {
                        Text("\(t.merchant) · \(store.displayMoneyBase(t.amount))")
                    }
        }
    }

    /// Seal color beside the title balance — same meaning as the Accounts
    /// list rows (green fresh / orange overdue / nil never).
    private func titleSeal(_ a: AccountRow) -> Color? {
        switch Selectors.reconcileStatus(a.lastReconciledAt, store.wallToday,
                                         staleDays: ReconcileReminder.staleDays(reconcileStaleDays)) {
        case .never: return nil
        case .fresh: return .green
        case .stale: return .orange
        }
    }

    @ViewBuilder private func holdingsSection(_ a: AccountRow) -> some View {
        let holdings = Selectors.holdingsForAccount(store.holdings, a.id)
        if !holdings.isEmpty {
            Section("Holdings") {
                ForEach(holdings) { h in
                    HStack {
                        Text(h.symbol)
                        Spacer()
                        Text(Selectors.holdingValue(h).map { store.displayMoney($0, from: h.currency) } ?? "—")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The List/Calendar toggle as a list row — the shared `ViewModePickerRow`.
    private var modePickerRow: some View {
        ViewModePickerRow(selection: $viewMode, options: [(.list, String(localized: "List")), (.calendar, String(localized: "Calendar"))])
    }

    /// Calendar lens: daily in/out cells over THIS account's rows (search
    /// applies, like the list), a tapped day's transactions beneath, and the
    /// anchored month's rows as the no-selection fallback.
    @ViewBuilder private func calendarSection(_ a: AccountRow) -> some View {
        let all = store.transactions(for: a.id)
        let txns = searchQuery.isEmpty ? all
            : Selectors.selectTransactions(all, ListOptions(ledgerId: store.activeLedgerId, query: searchQuery))
        Section {
            MonthCashCalendar(
                monthAnchor: $calMonthAnchor, selectedDay: $calSelectedDay,
                wallToday: store.wallToday,
                amountsForRange: { from, through in
                    MonthGrouping.dailyIncomeExpense(txns.filter { $0.date >= from && $0.date <= through })
                },
                format: { store.displayExactBase($0) },
                masked: store.privacyMode)
        } footer: {
            Text("Money in · out of this account, transfers included.")
        }
        if let day = calSelectedDay {
            let dayTx = txns.filter { $0.date == day }
            Section {
                if dayTx.isEmpty { Text("No transactions.").foregroundStyle(.secondary) }
                else { ForEach(dayTx, id: \.id) { t in txRow(t) } }
            } header: {
                Text(MonthCashCalendar.pretty(day)).textCase(nil)
            }
        } else {
            let key = String(format: "%04d-%02d",
                             AppDate.civil.component(.year, from: calMonthAnchor),
                             AppDate.civil.component(.month, from: calMonthAnchor))
            let monthTx = txns.filter { $0.date.hasPrefix(key) }
            if !monthTx.isEmpty {
                Section {
                    ForEach(monthTx, id: \.id) { t in txRow(t) }
                } header: {
                    // Same shape as the list lens, so the header does not change form
                    // when you flip to Calendar.
                    MonthFiguresHeader(label: MonthGrouping.label(key),
                                       figures: store.monthHeaderFigures(monthTx),
                                       accessibilityText: store.monthHeaderSpoken(monthTx))
                        .textCase(nil)
                }
            }
        }
    }

    @ViewBuilder private func transactionsSection(_ a: AccountRow) -> some View {
        // Search runs through the same engine matcher as the Activity feed
        // (merchant/note/category), scoped to this account's rows. Sections and
        // the pending bucket both filter; sections stay month-grouped.
        let all = store.transactions(for: a.id)
        let txns = searchQuery.isEmpty ? all
            : Selectors.selectTransactions(all, ListOptions(ledgerId: store.activeLedgerId, query: searchQuery))
        let pending = txns.filter { $0.pending == true }
        let confirmed = txns.filter { $0.pending != true }
        if !pending.isEmpty {
            Section("To confirm (\(pending.count))") {
                ForEach(pending, id: \.id) { t in txRow(t) }
            }
        }
        if confirmed.isEmpty {
            Section("Transactions") {
                if !store.txnsReady && searchQuery.isEmpty {
                    // Launch-only: txns projection deferred off first paint. The
                    // balance header above is already correct (current_balance),
                    // so only this list waits — spin rather than say "No transactions".
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    Text(searchQuery.isEmpty ? "No transactions" : "No matching transactions")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } else if groupByMonth {
            ForEach(MonthGrouping.sections(confirmed)) { section in
                Section {
                    ForEach(section.txns, id: \.id) { t in txRow(t) }
                } header: {
                    // The account's end-of-month balance used to sit here beside the
                    // net. It is gone deliberately — it answered a different question
                    // from the other figures (what the account was worth, not what the
                    // month did), and the screen's own header and rows carry it.
                    MonthFiguresHeader(label: MonthGrouping.label(section.id),
                                       figures: store.monthHeaderFigures(section.txns),
                                       accessibilityText: store.monthHeaderSpoken(section.txns))
                        .textCase(nil)
                }
            }
        } else {
            Section("Transactions") {
                ForEach(confirmed, id: \.id) { t in txRow(t) }
            }
        }
    }

    // Same behavior as the Activity feed: tap opens the editor; swipe / context
    // menu give delete + confirm + receipt preview. Reuses the feed's `TxRow`.
    @ViewBuilder private func txRow(_ t: Tx) -> some View {
        Button { editing = t } label: {
            TxRow(txn: t, onPreviewReceipt: { previewReceipt($0) })
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))   // denser rows
        .txnSwipeActions(t,
                         duplicate: { duplicateTxn($0) },
                         requestDelete: { pendingTxDelete = $0 },
                         toggleStatus: { toggleStatusTxn($0) },
                         edit: { editing = $0 },
                         previewReceipt: store.attachments(for: t.id).isEmpty ? nil : { previewReceipt($0) })
    }

    private func previewReceipt(_ txn: Tx) {
        if let first = store.attachments(for: txn.id).first { previewURL = store.attachmentURL(for: first) }
    }
    private func deleteTxn(_ txn: Tx) {
        do { try store.deleteTransaction(txn.id); Haptics.warning() } catch { errorMessage = i18nMessage(error) }
    }
    private func toggleStatusTxn(_ txn: Tx) {
        do { try txnToggleStatus(txn, store: store) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func duplicateTxn(_ t: Tx) {
        duplicating = t   // opens the Add sheet pre-filled; Save posts it
    }

    private func archive(_ a: AccountRow) {
        do { try store.apply(.archiveAccount, Args(["id": .string(a.id)])) }   // pops via account == nil
        catch { errorMessage = i18nMessage(error) }
    }

    private func delete(_ a: AccountRow) {
        do { try store.apply(.deleteAccount, Args(["id": .string(a.id)])); Haptics.warning() }
        catch { errorMessage = i18nMessage(error) }   // engine rejects if it has transactions
    }
}

/// Shared account-type label (also used by AccountSheet).
enum AccountSheetTypeLabel {
    static func label(_ t: String?) -> String {
        switch t {
        case "credit_card": return "Credit Card"
        case "fx": return "Foreign Currency"
        case .some(let s): return s.capitalized
        case .none: return "—"
        }
    }
}
