import SwiftUI
import FinchCore

/// Add Transaction — the flagship write screen (port of the web add-expense-form).
/// Expense/income post one account leg + an auto-balanced category leg through
/// `addTransaction`; transfer posts two account legs through `createTransfer`.
/// Everything routes the FinchStore.apply chokepoint, which re-derives the base
/// figure + applies rules. The amount field is in the account's own currency.
struct AddTransactionSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, CaseIterable, Identifiable {
        case expense, income, transfer
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    @State private var kind: Kind = .expense
    @State private var amount = ""
    @State private var merchant = ""
    @State private var categoryId = ""
    @State private var accountId = ""
    @State private var fromAccountId = ""
    @State private var toAccountId = ""
    @State private var received = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var errorMessage: String?

    private var accounts: [AccountRow] { store.accounts }

    /// Expense → expense categories; income → income categories.
    private var categories: [CategoryRow] {
        store.pickableCategories.filter { kind == .income ? $0.kind == "income" : $0.kind != "income" }
    }

    private func currency(of accountId: String) -> String {
        accounts.first { $0.id == accountId }?.currency ?? store.displayCurrency
    }
    private var transferIsCrossCurrency: Bool {
        kind == .transfer && currency(of: fromAccountId) != currency(of: toAccountId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if kind == .transfer {
                    transferFields
                } else {
                    expenseIncomeFields
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    TextField("Note (optional)", text: $note, axis: .vertical)
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
            .onAppear(perform: seedDefaults)
        }
    }

    @ViewBuilder private var expenseIncomeFields: some View {
        Section {
            amountField
            TextField(kind == .income ? "Source" : "Merchant", text: $merchant)
            Picker("Category", selection: $categoryId) {
                ForEach(categories) { Text($0.name).tag($0.id) }
            }
            Picker("Account", selection: $accountId) {
                ForEach(accounts) { Text($0.name ?? "—").tag($0.id) }
            }
        }
    }

    @ViewBuilder private var transferFields: some View {
        Section {
            amountField
            Picker("From", selection: $fromAccountId) {
                ForEach(accounts) { Text($0.name ?? "—").tag($0.id) }
            }
            Picker("To", selection: $toAccountId) {
                ForEach(accounts) { Text($0.name ?? "—").tag($0.id) }
            }
            if transferIsCrossCurrency {
                HStack {
                    Text("Received (\(currency(of: toAccountId)))")
                    Spacer()
                    TextField("0.00", text: $received).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var amountField: some View {
        HStack {
            Text("Amount")
            Spacer()
            TextField("0.00", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }

    /// Default the pickers to the first valid option (and the first two distinct
    /// accounts for a transfer) once the projected store is available.
    private func seedDefaults() {
        if accountId.isEmpty { accountId = accounts.first?.id ?? "" }
        if categoryId.isEmpty || !categories.contains(where: { $0.id == categoryId }) {
            categoryId = categories.first?.id ?? ""
        }
        if fromAccountId.isEmpty { fromAccountId = accounts.first?.id ?? "" }
        if toAccountId.isEmpty { toAccountId = accounts.dropFirst().first?.id ?? accounts.first?.id ?? "" }
    }

    private func save() {
        errorMessage = nil
        // Keep category valid when the type toggles between expense/income.
        if kind != .transfer, !categories.contains(where: { $0.id == categoryId }) {
            categoryId = categories.first?.id ?? ""
        }
        guard let value = Double(amount), value != 0 else { errorMessage = "Enter an amount."; return }
        let ymd = Self.day(date)
        let hm = Self.time(date)
        do {
            if kind == .transfer {
                guard fromAccountId != toAccountId else { errorMessage = "Pick two different accounts."; return }
                var args: [String: JSONValue] = [
                    "fromAccountId": .string(fromAccountId), "toAccountId": .string(toAccountId),
                    "fromAmount": .double(abs(value)), "date": .string(ymd), "time": .string(hm),
                ]
                if !note.isEmpty { args["note"] = .string(note) }
                if transferIsCrossCurrency {
                    guard let recv = Double(received), recv > 0 else {
                        errorMessage = "Enter the received amount."; return
                    }
                    args["toAmount"] = .double(recv)
                }
                try store.apply(.createTransfer, Args(args))
            } else {
                let signed = kind == .income ? abs(value) : -abs(value)
                let fallback = kind == .income ? "Income" : "Untitled"
                var args: [String: JSONValue] = [
                    "ledgerId": .string(store.activeLedgerId), "accountId": .string(accountId),
                    "amount": .double(signed), "merchant": .string(merchant.isEmpty ? fallback : merchant),
                    "categoryId": .string(categoryId), "date": .string(ymd), "time": .string(hm),
                ]
                if !note.isEmpty { args["note"] = .string(note) }
                try store.apply(.addTransaction, Args(args))
            }
            dismiss()
        } catch let e as I18nError {
            errorMessage = e.message
        } catch {
            errorMessage = "\(error)"
        }
    }

    // MARK: date/time formatting (local wall clock → stored columns)
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"; return f
    }()
    private static func day(_ d: Date) -> String { dayFmt.string(from: d) }
    private static func time(_ d: Date) -> String { timeFmt.string(from: d) }
}
