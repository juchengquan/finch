import SwiftUI
import FinchCore

/// Phase 4 — reconcile an account to a statement balance. Posts a one-leg
/// adjustment for the difference (reconcileAccount with postAdjustment: true).
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
                Picker("Account", selection: $accountId) {
                    ForEach(store.accounts) { Text($0.name ?? "—").tag($0.id) }
                }
                if let a = account {
                    LabeledContent("Current balance", value: store.displayMoney(a.balance, from: a.currency))
                }
                HStack {
                    Text("Statement balance"); Spacer()
                    TextField("0.00", text: $statementBalance).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                DatePicker("Statement date", selection: $date, displayedComponents: .date)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Reconcile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Reconcile", action: reconcile).bold() }
            }
            .onAppear { if accountId.isEmpty { accountId = preselect ?? store.accounts.first?.id ?? "" } }
        }
    }

    private func reconcile() {
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
