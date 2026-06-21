import SwiftUI
import FinchCore

/// Add or edit a scheduled template (recurring transaction / installment plan).
/// `nil` template = add (`createScheduled`); otherwise edit (`updateScheduled`).
/// On edit, type / account / start date are not patchable (the engine omits
/// them), so they're shown read-only; name, amount, category, frequency,
/// day-of-month and the installment count are editable. Routes FinchStore.apply.
struct ScheduledSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    let template: ScheduledTemplate?

    enum Kind: String, CaseIterable, Identifiable {
        case expense, income, transfer
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
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
    private var categories: [CategoryRow] {
        store.pickableCategories.filter { kind == .income ? $0.kind == "income" : $0.kind != "income" }
    }
    private func accountName(_ id: String) -> String { accounts.first { $0.id == id }?.name ?? "—" }

    init(template: ScheduledTemplate? = nil) {
        self.template = template
        _name = State(initialValue: template?.name ?? "")
        _kind = State(initialValue: template.flatMap { Kind(rawValue: $0.type) } ?? .expense)
        _amount = State(initialValue: template?.amount.map { String(format: "%g", $0) } ?? "")
        _accountId = State(initialValue: template?.accountId ?? "")
        _fromAccountId = State(initialValue: template?.fromAccountId ?? "")
        _categoryId = State(initialValue: template?.categoryId ?? "")
        _frequency = State(initialValue: template?.frequency ?? "monthly")
        _dayOfMonth = State(initialValue: template?.dayOfMonth ?? 1)
        _startDate = State(initialValue: template?.startDate.flatMap { AppDate.isoDay.date(from: $0) } ?? Date())
        _installmentEnabled = State(initialValue: template?.installmentTotal != nil)
        _installmentTotal = State(initialValue: template?.installmentTotal.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    if isEdit {
                        LabeledContent("Type", value: kind.label)
                    } else {
                        Picker("Type", selection: $kind) { ForEach(Kind.allCases) { Text($0.label).tag($0) } }
                            .pickerStyle(.segmented)
                    }
                    HStack {
                        Text("Amount"); Spacer()
                        TextField("0.00", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    if !installmentEnabled {
                        Text("Leave empty for a variable amount (entered when posting).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    if isEdit {
                        // account is not patchable — show it read-only.
                        if kind == .transfer {
                            LabeledContent("From", value: accountName(fromAccountId))
                            LabeledContent("To", value: accountName(accountId))
                        } else {
                            LabeledContent("Account", value: accountName(accountId))
                            Picker("Category", selection: $categoryId) { ForEach(categories) { Text($0.name).tag($0.id) } }
                        }
                    } else if kind == .transfer {
                        Picker("From", selection: $fromAccountId) { ForEach(accounts) { Text($0.name ?? "—").tag($0.id) } }
                        Picker("To", selection: $accountId) { ForEach(accounts) { Text($0.name ?? "—").tag($0.id) } }
                    } else {
                        Picker("Account", selection: $accountId) { ForEach(accounts) { Text($0.name ?? "—").tag($0.id) } }
                        Picker("Category", selection: $categoryId) { ForEach(categories) { Text($0.name).tag($0.id) } }
                    }
                }

                Section {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(frequencies, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    if frequency == "monthly" {
                        Stepper("Day of month: \(dayOfMonth)", value: $dayOfMonth, in: 1...31)   // matches web (1–31); engine clamps to month length
                    }
                    if isEdit {
                        LabeledContent("Start", value: template?.startDate ?? "—")
                    } else {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    }
                }

                Section {
                    Toggle("Installment plan", isOn: $installmentEnabled)
                    if installmentEnabled {
                        HStack {
                            Text("Number of payments"); Spacer()
                            TextField("12", text: $installmentTotal).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle(isEdit ? "Edit Scheduled" : "Add Scheduled")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
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
        ]
        if frequency == "monthly" { args["dayOfMonth"] = .int(dayOfMonth) }   // integer field; matches the edit path
        if kind == .transfer { args["fromAccountId"] = .string(fromAccountId) }
        else if !categoryId.isEmpty { args["category"] = .string(categoryId) }
        if let n = installmentN { args["installmentTotal"] = .double(Double(n)) }
        do { try store.apply(.createScheduled, Args(args)); dismiss() }
        catch { errorMessage = i18nMessage(error) }
    }
}
