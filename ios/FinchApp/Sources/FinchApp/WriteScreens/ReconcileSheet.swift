import SwiftUI
import FinchCore

/// Guided per-account reconcile: enter the statement balance, tick transactions as
/// cleared, and finish. (CP1: ticking + tracker + finish. CP2 adds quick-add + confirm-and-clear.)
struct ReconcileSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let preselect: String?
    @State private var accountId = ""
    @State private var statementBalance = ""
    @State private var date = Date()
    @State private var errorMessage: String?

    init(preselect: String? = nil) { self.preselect = preselect }

    private var account: AccountRow? { store.accounts.first { $0.id == accountId } }

    var body: some View {
        NavigationStack {
            Form {
                if preselect == nil {
                    Picker("Account", selection: $accountId) {
                        ForEach(store.accounts) { Text($0.name ?? "—").tag($0.id) }
                    }
                }
                if let a = account {
                    Section {
                        LabeledContent("Current balance", value: store.displayMoney(a.balance, from: a.currency))
                        HStack {
                            Text("Statement balance"); Spacer()
                            TextField("0.00", text: $statementBalance).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                        DatePicker("Statement date", selection: $date, displayedComponents: .date)
                    }
                    transactionsSection(a)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Reconcile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: finish) { Image(systemName: "checkmark") }.accessibilityLabel("Reconcile").bold()
                }
            }
            .onAppear { if accountId.isEmpty { accountId = preselect ?? store.accounts.first?.id ?? "" } }
        }
    }

    @ViewBuilder private func transactionsSection(_ a: AccountRow) -> some View {
        let txns = store.transactions(for: a.id).filter { $0.pending != true }
        Section("Transactions") {
            if txns.isEmpty {
                Text("No transactions").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(txns, id: \.id) { t in clearRow(a, t) }
            }
        }
    }

    @ViewBuilder private func clearRow(_ a: AccountRow, _ t: Tx) -> some View {
        let cleared = t.clearedAt != nil
        Button { toggleCleared(t, !cleared) } label: {
            HStack {
                Image(systemName: cleared ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(cleared ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.merchant).lineLimit(1)
                    Text(t.date).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(store.displayMoney(t.nativeAmount ?? t.amount, from: a.currency)).fontWeight(.medium)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(cleared ? Color.green.opacity(0.08) : nil)
    }

    private func toggleCleared(_ t: Tx, _ cleared: Bool) {
        do { try store.apply(.setCleared, Args(["id": .string(t.id), "cleared": .bool(cleared)])) }
        catch { errorMessage = i18nMessage(error) }
    }

    private func finish() {
        errorMessage = nil
        guard let bal = DecimalInput.parse(statementBalance) else { errorMessage = "Enter the statement balance."; return }
        do {
            try store.apply(.reconcileAccount, Args([
                "accountId": .string(accountId), "statementBalance": .double(bal),
                "statementDate": .string(AppDate.isoDay.string(from: date)), "postAdjustment": .bool(true)]))
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
