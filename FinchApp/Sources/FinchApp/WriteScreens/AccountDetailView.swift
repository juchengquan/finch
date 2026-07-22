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
    @State private var swipeToken = 0
    @State private var visibleTxns: Set<String> = []
    @State private var scrollAnchor: String?
    @State private var savedScrollAnchor: String?

    private var account: AccountRow? { store.accounts.first { $0.id == accountId } }

    var body: some View {
        Group {
            if let account {
                ScrollViewReader { proxy in
                List {
                    holdingsSection(account)
                    transactionsSection(account)
                }
                .resetsSwipeAndRestoresScroll(enabled: true, token: $swipeToken,
                                              anchor: $scrollAnchor, savedAnchor: $savedScrollAnchor,
                                              proxy: proxy)
                .errorAlert($errorMessage)
                .navigationTitle(account.name ?? "Account")
                .navigationBarTitleDisplayMode(.inline)
                #if os(iOS)
                .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search transactions")
                #else
                .searchable(text: $searchQuery, prompt: "Search transactions")
                #endif
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
                    Text("\(t.merchant) · \(store.displayMoneyBase(t.amount))")
                }
                }
            } else {
                // Archived or deleted while open → pop back.
                Color.clear.onAppear { dismiss() }
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

    @ViewBuilder private func transactionsSection(_ a: AccountRow) -> some View {
        // Search runs through the same engine matcher as the Activity feed
        // (merchant/note/category), scoped to this account's rows. Sections and
        // the pending bucket both filter; sections stay month-grouped.
        let all = store.transactions(for: a.id)
        let txns = searchQuery.isEmpty ? all
            : Selectors.selectTransactions(all, ListOptions(ledgerId: store.activeLedgerId, query: searchQuery))
        let pending = txns.filter { $0.pending == true }
        let confirmed = txns.filter { $0.pending != true }
        let order: [String] = groupByMonth
            ? (pending + MonthGrouping.sections(confirmed).flatMap { $0.txns }).map(\.id)
            : (pending + confirmed).map(\.id)
        if !pending.isEmpty {
            Section("To confirm (\(pending.count))") {
                ForEach(pending, id: \.id) { t in txRow(t, order: order) }
            }
        }
        if confirmed.isEmpty {
            Section("Transactions") {
                Text(searchQuery.isEmpty ? "No transactions" : "No matching transactions")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else if groupByMonth {
            ForEach(MonthGrouping.sections(confirmed)) { section in
                Section {
                    ForEach(section.txns, id: \.id) { t in txRow(t, order: order) }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(MonthGrouping.label(section.id)).textCase(nil)
                            Spacer()
                            // net change · this account's balance at the end of the month.
                            // The section is date-descending, so its first (newest) row's
                            // running balance IS the end-of-month balance — same cache the
                            // row shows, so header and row agree exactly.
                            Text(store.displayMoneyBase(MonthGrouping.net(section.txns))
                                 + "  ·  "
                                 + store.displayMoneyBase(store.runningBalanceBase(for: section.txns.first!)))
                                .foregroundStyle(.secondary)
                        }
                        Text("Income \(store.displayMoneyBase(MonthGrouping.income(section.txns))) · Spent \(store.displayMoneyBase(MonthGrouping.expense(section.txns)))")
                            .font(.caption2).textCase(nil).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Section("Transactions") {
                ForEach(confirmed, id: \.id) { t in txRow(t, order: order) }
            }
        }
    }

    // Same behavior as the Activity feed: tap opens the editor; swipe / context
    // menu give delete + confirm + receipt preview. Reuses the feed's `TxRow`.
    @ViewBuilder private func txRow(_ t: Tx, order: [String]) -> some View {
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
        .tracksTopRow(id: t.id, order: order, visible: $visibleTxns, anchor: $scrollAnchor)
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
