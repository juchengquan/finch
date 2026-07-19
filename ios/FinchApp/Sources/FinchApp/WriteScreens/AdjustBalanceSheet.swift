import SwiftUI
import FinchCore

/// Adjust an account's balance to a target value — posts an `adjustment`
/// entry for the difference via the engine's `adjustAccountBalance`. Reached
/// from the account detail's ⋯ menu (relocated out of the Add sheet, where it
/// occupied a 5th transaction type despite being account maintenance; spec
/// `2026-07-17-adjust-balance-relocation-design.md`). Locked to one account.
struct AdjustBalanceSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let account: AccountRow
    @State private var targetBalance = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(account.name ?? "Account",
                                   value: store.displayMoney(account.balance, from: account.currency ?? store.baseCurrency))
                    HStack {
                        Text("New balance"); Spacer()
                        // numbersAndPunctuation allows a leading minus (e.g. a credit-card balance).
                        TextField("0.00", text: $targetBalance)
                            #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                            #endif
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Posts an adjustment for the difference from the account's current balance.")
                }
                Section {
                    // Date-only: adjustAccountBalance takes no time argument.
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                        .environment(\.locale, AppDate.h24Locale)
                    HStack {
                        Text("Note"); Spacer()
                        TextField("Optional", text: $note, axis: .vertical).multilineTextAlignment(.trailing)
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Adjust Balance")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save")
                        .confirmCheckmarkStyle()
                }
            }
        }
    }

    private func save() {
        errorMessage = nil
        guard let target = DecimalInput.parse(targetBalance) else { errorMessage = "Enter a new balance."; return }
        do {
            var args: [String: JSONValue] = [
                "accountId": .string(account.id), "targetBalance": .double(target),
                "date": .string(AppDate.isoDay.string(from: date)),
            ]
            if !note.isEmpty { args["note"] = .string(note) }
            try store.apply(.adjustAccountBalance, Args(args))
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
