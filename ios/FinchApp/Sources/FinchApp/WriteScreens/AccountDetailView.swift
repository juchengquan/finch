import SwiftUI
import FinchCore

/// Account drill-in: header (name/type/balance), balance sparkline, holdings
/// (investment accounts), the account's transactions, and edit/reconcile/
/// archive/delete actions. Re-resolves the account from the store by id so edits
/// reflect live; pops when the account is archived or deleted.
struct AccountDetailView: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    let accountId: String

    @State private var showingEdit = false
    @State private var showingReconcile = false
    @State private var showingAddTx = false
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    private var account: AccountRow? { store.accounts.first { $0.id == accountId } }

    var body: some View {
        Group {
            if let account {
                List {
                    Section {
                        header(account)
                        reconcileBadge(account)
                    }
                    forecastSection(account)
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
                .confirmationDialog("Delete this account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { delete(account) }
                } message: {
                    Text("Accounts with transactions can't be deleted — archive instead.")
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
        let status = Selectors.reconcileStatus(a.lastReconciledAt, store.today)
        let bal = Money.format(a.lastReconciledBalance ?? 0, currency: a.currency ?? store.baseCurrency)
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

    /// 30-day projection from scheduled templates affecting this account —
    /// ending balance + the low-point (trough). Hidden when nothing is scheduled.
    @ViewBuilder private func forecastSection(_ a: AccountRow) -> some View {
        let f = Selectors.accountForecast(a, store.scheduled, store.today, 30)
        if !f.events.isEmpty {
            Section("30-day forecast") {
                LabeledContent("Projected balance", value: store.displayMoney(f.endingBalance, from: a.currency))
                LabeledContent("Low point") {
                    Text("\(store.displayMoney(f.trough.balance, from: a.currency)) · \(f.trough.date)")
                        .foregroundStyle(f.trough.balance < 0 ? .red : .secondary)
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

    @ViewBuilder private func txRow(_ t: Tx) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.merchant).lineLimit(1)
                Text(t.date).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(store.displayMoneyBase(t.amount)).fontWeight(.medium)
        }
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
