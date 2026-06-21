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

    /// Optionally pre-select the account (e.g. when added from an account's
    /// detail screen). Falls back to the first account when nil.
    var defaultAccountId: String? = nil

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
    @State private var currencyCode = ""
    @State private var errorMessage: String?
    @State private var pendingDuplicate: DuplicateMatch?   // soft duplicate nudge
    @State private var dupConfirmed = false

    private var accounts: [AccountRow] { store.accounts }

    /// The account currency + any currency with a known rate — the choices for a
    /// foreign-currency entry. (When the picked currency ≠ the account's, the
    /// engine carries orig_amount/orig_currency and converts.)
    private var currencyOptions: [String] {
        var set = Set(accounts.compactMap { $0.currency })
        set.formUnion(store.exchangeRates.map { $0.currency })
        set.insert(currency(of: accountId))
        return set.sorted()
    }

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
                if kind == .transfer {
                    transferFields
                } else {
                    expenseIncomeFields
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, AppDate.h24Locale)   // 24-hour time wheel regardless of device setting
                    HStack {
                        Text("Note"); Spacer()
                        TextField("Optional", text: $note, axis: .vertical).multilineTextAlignment(.trailing)
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                // Transaction type sits in the title slot as an icon segmented control.
                ToolbarItem(placement: .principal) {
                    Picker("Type", selection: $kind) {
                        ForEach(Kind.allCases) { kind in
                            Image(systemName: TxnKindIcon.icon(for: kind.rawValue))
                                .accessibilityLabel(kind.label)
                                .tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
            .onAppear(perform: seedDefaults)
            // Auto-categorize from the merchant's history (the user can still override).
            .onChange(of: merchant) { _, m in
                guard kind != .transfer, !m.isEmpty else { return }
                if let s = Selectors.suggestCategory(store.txns, store.activeLedgerId, m),
                   categories.contains(where: { $0.id == s.categoryId }) {
                    categoryId = s.categoryId
                }
            }
            .confirmationDialog("Possible duplicate", isPresented: Binding(
                get: { pendingDuplicate != nil }, set: { if !$0 { pendingDuplicate = nil } }),
                presenting: pendingDuplicate) { _ in
                Button("Add anyway") { dupConfirmed = true; pendingDuplicate = nil; save() }
                Button("Cancel", role: .cancel) { pendingDuplicate = nil }
            } message: { m in
                Text("Looks like “\(m.merchant)” on \(m.date) already exists.")
            }
        }
    }

    @ViewBuilder private var expenseIncomeFields: some View {
        Section {
            amountField
            HStack {
                Text(kind == .income ? "Source" : "Merchant"); Spacer()
                TextField("", text: $merchant).multilineTextAlignment(.trailing)
            }
            Picker("Category", selection: $categoryId) {
                ForEach(categories) { Text($0.name).tag($0.id) }
            }
            Picker("Account", selection: $accountId) {
                ForEach(accounts) { Text($0.name ?? "—").tag($0.id) }
            }
            if currencyOptions.count > 1 {
                Picker("Currency", selection: $currencyCode) {
                    ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
                }
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
        if accountId.isEmpty {
            let preferred = defaultAccountId.flatMap { id in accounts.first { $0.id == id }?.id }
            accountId = preferred ?? accounts.first?.id ?? ""
        }
        if categoryId.isEmpty || !categories.contains(where: { $0.id == categoryId }) {
            categoryId = categories.first?.id ?? ""
        }
        if fromAccountId.isEmpty { fromAccountId = accounts.first?.id ?? "" }
        if toAccountId.isEmpty { toAccountId = accounts.dropFirst().first?.id ?? accounts.first?.id ?? "" }
        if currencyCode.isEmpty { currencyCode = currency(of: accountId) }
    }

    private func save() {
        errorMessage = nil
        // Keep category valid when the type toggles between expense/income.
        if kind != .transfer, !categories.contains(where: { $0.id == categoryId }) {
            categoryId = categories.first?.id ?? ""
        }
        guard let value = DecimalInput.parse(amount), value != 0 else { errorMessage = "Enter an amount."; return }
        let ymd = Self.day(date)
        let hm = Self.time(date)
        // Soft duplicate nudge (expense/income only) — show once, before posting.
        if kind != .transfer, !dupConfirmed,
           let m = Selectors.findDuplicate(store.txns, store.activeLedgerId,
               DuplicateDraft(merchant: merchant, amount: abs(value), accountId: accountId, date: ymd, excludeId: nil)) {
            pendingDuplicate = m
            return
        }
        do {
            if kind == .transfer {
                guard fromAccountId != toAccountId else { errorMessage = "Pick two different accounts."; return }
                var args: [String: JSONValue] = [
                    "fromAccountId": .string(fromAccountId), "toAccountId": .string(toAccountId),
                    "fromAmount": .double(abs(value)), "date": .string(ymd), "time": .string(hm),
                ]
                if !note.isEmpty { args["note"] = .string(note) }
                if transferIsCrossCurrency {
                    guard let recv = DecimalInput.parse(received), recv > 0 else {
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
                // Foreign-currency entry: pass the chosen currency so the engine
                // carries orig_* + converts to the account/base currency.
                if !currencyCode.isEmpty, currencyCode != currency(of: accountId) {
                    args["currency"] = .string(currencyCode)
                }
                try store.apply(.addTransaction, Args(args))
            }
            dismiss()
        } catch {
            errorMessage = i18nMessage(error)   // localizes I18nError (incl. zh), like every other write screen
        }
    }

    // MARK: date/time formatting (local wall clock → stored columns)
    private static let dayFmt = AppDate.isoDay
    private static let timeFmt = AppDate.isoTime
    private static func day(_ d: Date) -> String { dayFmt.string(from: d) }
    private static func time(_ d: Date) -> String { timeFmt.string(from: d) }
}
