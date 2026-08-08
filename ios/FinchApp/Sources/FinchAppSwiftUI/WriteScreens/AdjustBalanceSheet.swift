import SwiftUI
import FinchCore

/// Adjust an account's balance to a target value — posts an `adjustment`
/// entry for the difference via the engine's `adjustAccountBalance`. Reached
/// from the account detail's ⋯ menu (relocated out of the Add sheet, where it
/// occupied a 5th transaction type despite being account maintenance).
/// Locked to one account.
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
                        TextField(DecimalInput.zeroPlaceholder(fractionDigits: Currencies.minorUnits(for: account.currency ?? store.baseCurrency)),
                                  text: $targetBalance)
                            .moneyInput($targetBalance,
                                        currency: account.currency ?? store.baseCurrency,
                                        setsKeyboard: false)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Posts an adjustment for the difference from the account's current balance.")
                }
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
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
            .finchSectionSpacing()
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
                "time": .string(AppDate.isoTime.string(from: date)),
            ]
            if !note.isEmpty { args["note"] = .string(note) }
            try store.apply(.adjustAccountBalance, Args(args))
            Haptics.success()
            dismiss()
        } catch { Haptics.warning(); errorMessage = i18nMessage(error) }
    }
}
