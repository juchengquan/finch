import SwiftUI
import FinchCore

/// Account drill-in: header (name/type/balance), balance sparkline, holdings
/// (investment accounts), the account's transactions, and edit/reconcile/
/// archive/delete actions. Re-resolves the account from the store by id so edits
/// reflect live; pops when the account is archived or deleted.
struct AccountDetailView: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("finch.account.showOpeningBalance") private var showOpeningBalance = true

    let accountId: String

    @State private var showingEdit = false
    @State private var showingReconcile = false
    @State private var showingAddTx = false
    @State private var confirmingDelete = false
    @State private var pendingTxDelete: Tx?   // single-transaction delete awaiting confirmation
    @State private var errorMessage: String?
    @State private var editing: Tx?
    @State private var previewURL: URL?

    private var account: AccountRow? { store.accounts.first { $0.id == accountId } }

    var body: some View {
        Group {
            if let account {
                List {
                    Section {
                        header(account)
                        reconcileBadge(account)
                        if showOpeningBalance, let ob = account.openingBalanceBase, ob != 0 {
                            LabeledContent("Opening balance", value: store.displayMoneyBase(ob))
                        }
                    }
                    holdingsSection(account)
                    transactionsSection(account)
                }
                .errorAlert($errorMessage)
                .navigationTitle(account.name ?? "Account")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingAddTx = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Add Transaction")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button { showingEdit = true } label: { Label("Edit", systemImage: "pencil") }
                            Button { showingReconcile = true } label: { Label("Reconcile", systemImage: "checkmark.circle") }
                            Button { archive(account) } label: { Label("Archive", systemImage: "archivebox") }
                            Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
                .sheet(isPresented: $showingEdit) {
                    AccountSheet(account: account, defaultCurrency: store.baseCurrency)
                }
                .sheet(isPresented: $showingReconcile) { ReconcileSheet(preselect: account.id) }
                .sheet(isPresented: $showingAddTx) { AddTransactionSheet(defaultAccountId: account.id) }
                .sheet(item: $editing) { EditTransactionSheet(txn: $0) }
                .quickLookPreview($previewURL)
                .confirmationDialog("Delete this account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { delete(account) }
                } message: {
                    Text("Accounts with transactions can't be deleted — archive instead.")
                }
                .confirmationDialog("Delete transaction?",
                                    isPresented: Binding(get: { pendingTxDelete != nil },
                                                         set: { if !$0 { pendingTxDelete = nil } }),
                                    titleVisibility: .visible, presenting: pendingTxDelete) { t in
                    Button("Delete", role: .destructive) { deleteTxn(t) }
                    Button("Cancel", role: .cancel) {}
                } message: { t in
                    Text("\(t.merchant) · \(store.displayMoneyBase(t.amount))")
                }
            } else {
                // Archived or deleted while open → pop back.
                Color.clear.onAppear { dismiss() }
            }
        }
    }

    @ViewBuilder private func header(_ a: AccountRow) -> some View {
        HStack {
            Image(systemName: AccountTypeIcon.icon(for: a.type)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.name ?? "—").fontWeight(.medium)
                Text(AccountSheetTypeLabel.label(a.type)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(store.displayMoney(a.balance, from: a.currency)).fontWeight(.semibold)
        }
    }

    @ViewBuilder private func reconcileBadge(_ a: AccountRow) -> some View {
        let status = Selectors.reconcileStatus(a.lastReconciledAt, store.wallToday)
        let bal = store.displayNative(a.lastReconciledBalance ?? 0, currency: a.currency ?? store.baseCurrency)
        HStack(spacing: 6) {
            switch status {
            case .never:
                Image(systemName: "checkmark.seal").foregroundStyle(.secondary)
                Text("Never reconciled").foregroundStyle(.secondary)
            case .fresh(let d):
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("Reconciled to \(bal) · \(agoLabel(d))").foregroundStyle(.green)
            case .stale(let d):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Reconciled to \(bal) · \(agoLabel(d))").foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
    }

    private func agoLabel(_ d: Int) -> String { d == 0 ? "today" : d == 1 ? "1 day ago" : "\(d) days ago" }

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
        let txns = store.transactions(for: a.id)
        let pending = txns.filter { $0.pending == true }
        let confirmed = txns.filter { $0.pending != true }
        if !pending.isEmpty {
            Section("To confirm (\(pending.count))") {
                ForEach(pending, id: \.id) { t in txRow(t) }
            }
        }
        Section("Transactions") {
            if confirmed.isEmpty {
                Text("No transactions").font(.caption).foregroundStyle(.secondary)
            } else {
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Reveal a Delete button; tapping it asks for confirmation first.
            Button(role: .destructive) { pendingTxDelete = t } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            if t.pending == true {
                Button { confirmTxn(t) } label: { Label("Confirm", systemImage: "checkmark.circle") }.tint(.green)
            }
        }
        .contextMenu {
            Button { editing = t } label: { Label("Edit", systemImage: "pencil") }
            if !store.attachments(for: t.id).isEmpty {
                Button { previewReceipt(t) } label: { Label("Preview receipt", systemImage: "paperclip") }
            }
            if t.pending == true {
                Button { confirmTxn(t) } label: { Label("Confirm", systemImage: "checkmark.circle") }
            }
            Button(role: .destructive) { pendingTxDelete = t } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func previewReceipt(_ txn: Tx) {
        if let first = store.attachments(for: txn.id).first { previewURL = store.attachmentURL(for: first) }
    }
    private func deleteTxn(_ txn: Tx) {
        do { try store.deleteTransaction(txn.id) } catch { errorMessage = i18nMessage(error) }
    }
    private func confirmTxn(_ txn: Tx) {
        do { try store.apply(.confirmTransaction, Args(["id": .string(txn.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }

    private func archive(_ a: AccountRow) {
        do { try store.apply(.archiveAccount, Args(["id": .string(a.id)])) }   // pops via account == nil
        catch { errorMessage = i18nMessage(error) }
    }

    private func delete(_ a: AccountRow) {
        do { try store.apply(.deleteAccount, Args(["id": .string(a.id)])) }
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
