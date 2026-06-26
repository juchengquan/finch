import SwiftUI
import FinchCore

/// Add or edit a budget. `nil` budget = add (`createBudget`); otherwise edit
/// (`updateBudget`). Expense budgets track spend against a set of categories;
/// income budgets track received income. Routes through FinchStore.apply.
struct BudgetSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    let budget: BudgetRow?

    enum Kind: String, CaseIterable, Identifiable {
        case expense, income
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }
    let frequencies = ["daily", "weekly", "biweekly", "monthly", "quarterly", "yearly"]

    @State private var name: String
    @State private var kind: Kind
    @State private var amount: String
    @State private var frequency: String
    @State private var groupId: String              // "" = none
    @State private var selectedCategories: Set<String>
    @State private var selectedAccounts: Set<String>
    @State private var rollover: Bool
    @State private var rolloverCap: String
    @State private var errorMessage: String?

    private var isEdit: Bool { budget != nil }

    init(budget: BudgetRow? = nil) {
        self.budget = budget
        _name = State(initialValue: budget?.name ?? "")
        _kind = State(initialValue: (budget?.type == "income") ? .income : .expense)
        _amount = State(initialValue: budget.map { String(format: "%g", $0.amount) } ?? "")
        _frequency = State(initialValue: budget?.frequency ?? "monthly")
        _groupId = State(initialValue: budget?.groupId ?? "")
        _selectedCategories = State(initialValue: Set(budget?.categoryIds ?? []))
        _selectedAccounts = State(initialValue: Set(budget?.accountIds ?? []))
        _rollover = State(initialValue: (budget?.rollover ?? 0) != 0)
        _rolloverCap = State(initialValue: budget?.rolloverLimit.map { String(format: "%g", $0) } ?? "")
    }

    private var categories: [CategoryRow] {
        store.pickableCategories.filter { kind == .income ? $0.kind == "income" : $0.kind != "income" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $kind) { ForEach(Kind.allCases) { Text($0.label).tag($0) } }
                        .pickerStyle(.segmented)
                    HStack {
                        Text("Amount"); Spacer()
                        TextField("0.00", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Picker("Frequency", selection: $frequency) {
                        ForEach(frequencies, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    Picker("Group", selection: $groupId) {
                        Text("None").tag("")
                        ForEach(store.budgetGroups) { Text($0.name).tag($0.id) }
                    }
                }

                Section {
                    ForEach(categories) { cat in
                        Button { toggle(cat.id) } label: {
                            HStack {
                                Text(cat.name).foregroundStyle(.primary)
                                Spacer()
                                if selectedCategories.contains(cat.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } header: {
                    Text(kind == .income ? "Income categories" : "Categories")
                } footer: {
                    Text("Leave empty to track all \(kind.rawValue) categories.")
                }

                Section {
                    ForEach(store.accounts) { acct in
                        Button { toggleAccount(acct.id) } label: {
                            HStack {
                                Text(acct.name ?? "Account").foregroundStyle(.primary)
                                Spacer()
                                if selectedAccounts.contains(acct.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Accounts")
                } footer: {
                    Text("Leave empty to track all accounts.")
                }

                if kind == .expense {
                    Section {
                        Toggle("Roll over unused budget", isOn: $rollover)
                        if rollover {
                            HStack {
                                Text("Cap"); Spacer()
                                TextField("Optional", text: $rolloverCap)
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            }
                        }
                    } footer: {
                        Text("Unspent budget carries into the next period. Set a cap to limit how much.")
                    }
                }

                if isEdit, budget?.isRecurring == 1 {
                    Section {
                        Text("Changing the amount on a recurring budget applies from the next cycle.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle(isEdit ? "Edit Budget" : "Add Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save").bold()
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if selectedCategories.contains(id) { selectedCategories.remove(id) } else { selectedCategories.insert(id) }
    }

    private func toggleAccount(_ id: String) {
        if selectedAccounts.contains(id) { selectedAccounts.remove(id) } else { selectedAccounts.insert(id) }
    }

    private func save() {
        errorMessage = nil
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter a name."; return }
        guard let value = DecimalInput.parse(amount), value > 0 else { errorMessage = "Enter an amount."; return }
        let categoryIds: JSONValue = .array(selectedCategories.sorted().map { .string($0) })
        let accountIds: JSONValue = .array(selectedAccounts.sorted().map { .string($0) })

        // Rollover is expense-only; cap is optional and validated only when set.
        let useRollover = kind == .expense && rollover
        let capValue: JSONValue
        if useRollover && !rolloverCap.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let c = DecimalInput.parse(rolloverCap), c >= 0 else { errorMessage = "Enter a valid rollover cap."; return }
            capValue = .double(c)
        } else {
            capValue = .null
        }

        if let budget {
            let patch: [String: JSONValue] = [
                "name": .string(name), "type": .string(kind.rawValue), "amount": .double(value),
                "frequency": .string(frequency), "categoryIds": categoryIds, "accountIds": accountIds,
                "groupId": groupId.isEmpty ? .null : .string(groupId),
                "rollover": .bool(useRollover), "rolloverLimit": capValue,
            ]
            do { try store.apply(.updateBudget, Args(["id": .string(budget.id), "patch": .object(patch)])); dismiss() }
            catch { errorMessage = i18nMessage(error) }
        } else {
            var args: [String: JSONValue] = [
                "ledgerId": .string(store.activeLedgerId), "name": .string(name),
                "type": .string(kind.rawValue), "amount": .double(value), "frequency": .string(frequency),
                "rollover": .bool(useRollover),
            ]
            if !groupId.isEmpty { args["groupId"] = .string(groupId) }
            if !selectedCategories.isEmpty { args["categoryIds"] = categoryIds }
            if !selectedAccounts.isEmpty { args["accountIds"] = accountIds }
            if case .double = capValue { args["rolloverLimit"] = capValue }
            do { try store.apply(.createBudget, Args(args)); dismiss() }
            catch { errorMessage = i18nMessage(error) }
        }
    }
}
