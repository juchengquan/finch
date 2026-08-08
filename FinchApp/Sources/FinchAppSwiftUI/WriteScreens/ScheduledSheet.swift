import SwiftUI
import FinchCore

/// Add or edit a scheduled template (recurring transaction / installment plan).
/// `nil` template = add (`createScheduled`); otherwise edit (`updateScheduled`).
/// On edit, type and account are not patchable (the engine omits them), so they're
/// shown read-only; name, amount, category, frequency, day-of-month, START DATE and
/// the installment count are editable. Routes FinchStore.apply.
struct ScheduledSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    let template: ScheduledTemplate?

    enum Kind: String, CaseIterable, Identifiable {
        case expense, income, transfer
        var id: String { rawValue }
        var label: String { KindLabel.label(rawValue) }
    }
    let frequencies = ["daily", "weekly", "biweekly", "monthly", "quarterly", "yearly", "once"]

    @State private var name: String
    @State private var kind: Kind
    @State private var amount: String
    @State private var accountId: String
    @State private var fromAccountId: String
    @State private var categoryId: String
    @State private var frequency: String
    @State private var dayOfMonth: Int
    @State private var startDate: Date
    @State private var installmentEnabled: Bool
    @State private var installmentTotal: String
    @State private var errorMessage: String?

    private var isEdit: Bool { template != nil }
    private var accounts: [AccountRow] { store.accounts }
    /// The typed amount is denominated in the template account's currency.
    /// `templateCurrency` for callers without the environment — `init` cannot
    /// read `@EnvironmentObject`, and the store there is always `.shared`
    /// (both shells hand out that one instance).
    private static func currency(forAccount id: String?) -> String {
        let store = FinchStore.shared
        return store.accounts.first { $0.id == id }?.currency ?? store.baseCurrency
    }

    private var templateCurrency: String {
        accounts.first { $0.id == accountId }?.currency ?? store.baseCurrency
    }
    private var categories: [CategoryRow] {
        store.pickableCategories.filter { kind == .income ? $0.kind == "income" : $0.kind != "income" }
    }
    private func accountName(_ id: String) -> String { accounts.first { $0.id == id }?.name ?? "—" }

    init(template: ScheduledTemplate? = nil, prefillStart: Date? = nil) {
        self.template = template
        _name = State(initialValue: template?.name ?? "")
        _kind = State(initialValue: template.flatMap { Kind(rawValue: $0.type) } ?? .expense)
        // `templateCurrency` needs the environment, which init does not have —
        // the same store, reached the only way available here.
        _amount = State(initialValue: template?.amount.map {
            DecimalInput.text($0, currency: ScheduledSheet.currency(forAccount: template?.accountId))
        } ?? "")
        _accountId = State(initialValue: template?.accountId ?? "")
        _fromAccountId = State(initialValue: template?.fromAccountId ?? "")
        _categoryId = State(initialValue: template?.categoryId ?? "")
        _frequency = State(initialValue: template?.frequency ?? "monthly")
        _dayOfMonth = State(initialValue: template?.dayOfMonth ?? 1)
        // Seed from the template's date AND its intended time, so opening the sheet
        // shows what it will actually post at rather than midnight.
        let seeded: Date? = template?.startDate.flatMap { d in
            if let t = template?.startTime, !t.isEmpty { return AppDate.isoDateTime.date(from: "\(d) \(t)") }
            return AppDate.isoDay.date(from: d)
        }
        _startDate = State(initialValue: seeded ?? prefillStart ?? Date())
        _installmentEnabled = State(initialValue: template?.installmentTotal != nil)
        _installmentTotal = State(initialValue: template?.installmentTotal.map { String($0) } ?? "")
    }

    init(fromCharge c: RecurringCharge) {
        self.template = nil
        _name = State(initialValue: c.merchantName)
        _kind = State(initialValue: .expense)
        _amount = State(initialValue: DecimalInput.text(c.averageAmount,
                                                        currency: ScheduledSheet.currency(forAccount: c.accountId)))
        _accountId = State(initialValue: c.accountId ?? "")
        _fromAccountId = State(initialValue: "")
        _categoryId = State(initialValue: c.categoryId ?? "")
        _frequency = State(initialValue: c.cadence)
        _dayOfMonth = State(initialValue: Int(c.nextEstimatedDate.split(separator: "-").last ?? "1") ?? 1)
        _startDate = State(initialValue: AppDate.isoDay.date(from: c.nextEstimatedDate) ?? Date())
        _installmentEnabled = State(initialValue: false)
        _installmentTotal = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { TxnTypeToolbar.caption(kind.label) }.finchCaptionSection()   // names the toolbar type control above
                Section {
                    FieldRow(glyph: .name, title: "Name") {
                        TextField("Name", text: $name)
                    }
                    FieldRow(glyph: .amount, title: "Amount") {
                        TextField(DecimalInput.zeroPlaceholder(fractionDigits: Currencies.minorUnits(for: templateCurrency)),
                                  text: $amount)
                            .moneyInput($amount, currency: templateCurrency)
                    }
                } footer: {
                    if !installmentEnabled {
                        Text("Leave empty for a variable amount (entered when posting).")
                    }
                }

                Section {
                    if isEdit {
                        // account / from / to are not patchable — show them read-only.
                        if kind == .transfer {
                            FieldRow(glyph: .fromAccount, title: "From") { Text(accountName(fromAccountId)) }
                            FieldRow(glyph: .toAccount, title: "To") { Text(accountName(accountId)) }
                        } else {
                            FieldRow(glyph: .account, title: "Account") { Text(accountName(accountId)) }
                            CategoryPickerRow(title: "Category", glyph: .category, categories: categories, selection: $categoryId)
                        }
                    } else if kind == .transfer {
                        SearchablePickerRow(title: "From", glyph: .fromAccount,
                            accounts: accounts, selection: $fromAccountId)
                        SearchablePickerRow(title: "To", glyph: .toAccount,
                            accounts: accounts, selection: $accountId)
                    } else {
                        SearchablePickerRow(title: "Account", glyph: .account,
                            accounts: accounts, selection: $accountId)
                        CategoryPickerRow(title: "Category", glyph: .category, categories: categories, selection: $categoryId)
                    }
                } header: {
                    finchSectionHeader("Account")
                }

                Section {
                    FieldRow(glyph: .frequency, title: "Frequency", showsDefaultTrailing: false) {
                        Picker("Frequency", selection: $frequency) {
                            ForEach(frequencies, id: \.self) { Text(FrequencyLabel.label($0)).tag($0) }
                        }
                        .labelsHidden()
                    }
                    if frequency == "monthly" {
                        FieldRow(glyph: .date, title: "Day of month") {
                            Stepper("Day of month: \(dayOfMonth)", value: $dayOfMonth, in: 1...31)   // matches web (1–31); engine clamps to month length
                        }
                    }
                    // Date AND time: the time is when this schedule posts. Left
                    // unset it posts at whatever moment it fires, which is what
                    // every existing template does.
                    FieldRow(glyph: .date, title: "Start", showsDefaultTrailing: false) {
                        DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                } header: {
                    finchSectionHeader("Schedule")
                }

                Section {
                    FieldRow(glyph: .status, title: "Installment plan") {
                        Toggle("Installment plan", isOn: $installmentEnabled).switchOnlyToggles()
                    }
                    if installmentEnabled {
                        FieldRow(glyph: .amount, title: "Number of payments") {
                            TextField("12", text: $installmentTotal).numericInput($installmentTotal, allowsDecimal: false).keyboardType(.numberPad)
                        }
                    }
                } header: {
                    finchSectionHeader("Installment")
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle(isEdit ? "Edit Scheduled" : "Add Scheduled")
            .finchSheetForm()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                // Type — the shared glass control (TxnTypeToolbar). Editable on add;
                // immutable on edit (the engine omits type), so a locked segment.
                ToolbarItem(placement: .principal) {
                    if isEdit {
                        TxnTypeToolbar.locked(icon: TxnKindIcon.icon(for: kind.rawValue), label: kind.label)
                    } else {
                        TxnTypeToolbar.segmented(Kind.allCases, selection: $kind,
                            icon: { TxnKindIcon.icon(for: $0.rawValue) }, label: { $0.label })
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save")
                        .confirmCheckmarkStyle()
                }
            }
            .onAppear(perform: seedDefaults)
        }
    }

    private func seedDefaults() {
        guard !isEdit else { return }
        if accountId.isEmpty { accountId = accounts.first?.id ?? "" }
        if fromAccountId.isEmpty { fromAccountId = accounts.dropFirst().first?.id ?? accounts.first?.id ?? "" }
        if categoryId.isEmpty || !categories.contains(where: { $0.id == categoryId }) {
            categoryId = categories.first?.id ?? ""
        }
    }

    private func save() {
        errorMessage = nil
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter a name."; return }

        // Amount is optional: an empty field means a variable-amount template (the
        // amount is supplied when posting). A non-empty entry must be > 0. Mirrors
        // web, where amount == null is a variable template.
        let amountValue: Double?
        if amount.trimmingCharacters(in: .whitespaces).isEmpty {
            amountValue = nil
        } else {
            guard let v = DecimalInput.parse(amount), v > 0 else { errorMessage = "Enter an amount greater than 0."; return }
            amountValue = v
        }

        // Installments: when enabled, the count must be a whole number > 0. iOS used
        // to silently drop a fractional/≤0 entry (creating no plan); web blocks it.
        // A plan also needs a fixed amount to divide, so disallow variable + plan.
        var installmentN: Int?
        if installmentEnabled {
            guard let n = Int(installmentTotal.trimmingCharacters(in: .whitespaces)), n > 0 else {
                errorMessage = "Enter a whole number of payments greater than 0."; return
            }
            guard amountValue != nil else { errorMessage = "Installment plans need a fixed amount."; return }
            installmentN = n
        }

        if let template {
            var patch: [String: JSONValue] = [
                "name": .string(name), "amount": amountValue.map { JSONValue.double($0) } ?? .null,
                "frequency": .string(frequency),
            ]
            if frequency == "monthly" { patch["dayOfMonth"] = .int(dayOfMonth) }
            // Moving the start moves the schedule: occurrences are derived from it.
            patch["startDate"] = .string(AppDate.isoDay.string(from: startDate))
            patch["startTime"] = .string(AppDate.isoTime.string(from: startDate))
            if kind != .transfer { patch["category"] = categoryId.isEmpty ? .null : .string(categoryId) }
            patch["installmentTotal"] = installmentN.map { JSONValue.int($0) } ?? .null
            do { try store.apply(.updateScheduled, Args(["id": .string(template.id), "patch": .object(patch)])); dismiss() }
            catch { errorMessage = i18nMessage(error) }
            return
        }

        if kind == .transfer, fromAccountId == accountId { errorMessage = "Pick two different accounts."; return }
        var args: [String: JSONValue] = [
            "ledgerId": .string(store.activeLedgerId), "name": .string(name),
            "type": .string(kind.rawValue), "amount": amountValue.map { JSONValue.double($0) } ?? .null,
            "accountId": .string(accountId), "frequency": .string(frequency),
            "startDate": .string(AppDate.isoDay.string(from: startDate)),
            "startTime": .string(AppDate.isoTime.string(from: startDate)),
        ]
        if frequency == "monthly" { args["dayOfMonth"] = .int(dayOfMonth) }   // integer field; matches the edit path
        if kind == .transfer { args["fromAccountId"] = .string(fromAccountId) }
        else if !categoryId.isEmpty { args["category"] = .string(categoryId) }
        if let n = installmentN { args["installmentTotal"] = .double(Double(n)) }
        do { try store.apply(.createScheduled, Args(args)); dismiss() }
        catch { errorMessage = i18nMessage(error) }
    }
}
