import SwiftUI
import FinchCore

/// Add or edit a budget. `nil` budget = add (`createBudget`); otherwise edit
/// (`updateBudget`). Two shapes behind one `[Expense | Income]` toggle:
/// - **Expense** tracks spend against categories/accounts over a cycle (limit,
///   frequency, start, rollover).
/// - **Income** is a savings target (goal) funded by real matched transactions
///   across category/account/tag/merchant scopes, with `saved` as a pre-tracking
///   starting offset and an optional target date (`endDate`). It has no cycle or
///   rollover — those don't apply — so its form drops them and creates a one-shot
///   budget (`isRecurring = 0`).
/// Routes through FinchStore.apply.
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
    @State private var amount: String            // expense = limit; income = target
    @State private var frequency: String
    @State private var startDate: Date
    @State private var groupId: String              // "" = none
    @State private var selectedCategories: Set<String>
    @State private var selectedAccounts: Set<String>
    @State private var selectedTags: Set<String>            // income: match dimension (tags)
    @State private var selectedCounterparties: Set<String>  // income: match dimension (merchants)
    @State private var rollover: Bool
    @State private var rolloverCap: String
    @State private var savedText: String            // income: "saved so far" toward the target
    @State private var hasTargetDate: Bool          // income: whether an optional target date is set
    @State private var targetDate: Date             // income: the target date (endDate)
    @State private var errorMessage: String?

    private var isEdit: Bool { budget != nil }

    init(budget: BudgetRow? = nil) {
        self.budget = budget
        _name = State(initialValue: budget?.name ?? "")
        _kind = State(initialValue: (budget?.type == "income") ? .income : .expense)
        _amount = State(initialValue: budget.map { String(format: "%g", $0.amount) } ?? "")
        _frequency = State(initialValue: budget?.frequency ?? "monthly")
        _startDate = State(initialValue: budget.flatMap { AppDate.isoDay.date(from: $0.startDate) } ?? Date())
        _groupId = State(initialValue: budget?.groupId ?? "")
        _selectedCategories = State(initialValue: Set(budget?.categoryIds ?? []))
        _selectedAccounts = State(initialValue: Set(budget?.accountIds ?? []))
        _selectedTags = State(initialValue: Set(budget?.tagIds ?? []))
        _selectedCounterparties = State(initialValue: Set(budget?.counterpartyIds ?? []))
        _rollover = State(initialValue: (budget?.rollover ?? 0) != 0)
        _rolloverCap = State(initialValue: budget?.rolloverLimit.map { String(format: "%g", $0) } ?? "")
        // Income "saved so far": pre-fill on edit (a goal you've already partly funded).
        _savedText = State(initialValue: (budget?.type == "income" && (budget?.saved ?? 0) != 0)
            ? String(format: "%g", budget!.saved) : "")
        _hasTargetDate = State(initialValue: budget?.endDate != nil)
        _targetDate = State(initialValue: budget?.endDate.flatMap { AppDate.isoDay.date(from: $0) } ?? Date())
    }

    private var categories: [CategoryRow] {
        store.pickableCategories.filter { kind == .income ? $0.kind == "income" : $0.kind != "income" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { TxnTypeToolbar.caption(kind.label) }   // names the toolbar type control above
                if kind == .income { incomeFields } else { expenseFields }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle(isEdit ? "Edit Budget" : "Add Budget")
            .finchSheetForm()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .principal) {
                    TxnTypeToolbar.segmented(Kind.allCases, selection: $kind,
                        icon: { TxnKindIcon.icon(for: $0.rawValue) }, label: { $0.label })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save")
                        .confirmCheckmarkStyle()
                }
            }
        }
    }

    // MARK: field sets

    /// Income (savings goal): name + target + group, a pre-tracking "saved so far"
    /// offset and optional target date, then the transaction-matching scope
    /// (categories/accounts/tags/merchants) that funds progress. No cycle or rollover.
    @ViewBuilder private var incomeFields: some View {
        Section {
            TextField("Name", text: $name)
            HStack {
                Text("Target"); Spacer()
                TextField("0.00", text: $amount).numericInput($amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Picker("Group", selection: $groupId) {
                Text("None").tag("")
                ForEach(store.budgetGroups) { Text($0.name).tag($0.id) }
            }
        } header: {
            finchSectionHeader("Details")
        }
        Section {
            HStack {
                Text("Saved so far"); Spacer()
                TextField("0.00", text: $savedText).numericInput($savedText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Toggle("Set target date", isOn: $hasTargetDate)
            if hasTargetDate {
                DatePicker("Target date", selection: $targetDate, displayedComponents: .date)
            }
        } footer: {
            Text("\"Saved so far\" is money set aside before tracking began. Matching transactions add on top of it.")
        }
        Section {
            CategoryMultiPickerRow(
                title: "Categories",
                categories: categories,
                selection: $selectedCategories,
                emptyLabel: "Any category")
            MultiSelectPickerRow(
                title: "Accounts",
                options: store.accounts.map { PickerOption(id: $0.id, name: $0.name ?? "Account") },
                selection: $selectedAccounts,
                emptyLabel: "Any account")
            MultiSelectPickerRow(
                title: "Tags",
                options: store.tags.map { PickerOption(id: $0.id, name: $0.name) },
                selection: $selectedTags,
                emptyLabel: "Any tag")
            MultiSelectPickerRow(
                title: "Merchants",
                options: store.counterparties.map { PickerOption(id: $0.id, name: $0.name) },
                selection: $selectedCounterparties,
                emptyLabel: "Any merchant")
        } header: {
            finchSectionHeader("Matching")
        } footer: {
            Text("Real inflows matching these scopes fund the goal. Set at least one category, account, tag, or merchant.")
        }
    }

    /// Expense (spend cap): details, cycle, tracking scope, rollover.
    @ViewBuilder private var expenseFields: some View {
        Section {
            TextField("Name", text: $name)
            HStack {
                Text("Limit"); Spacer()
                TextField("0.00", text: $amount).numericInput($amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Picker("Group", selection: $groupId) {
                Text("None").tag("")
                ForEach(store.budgetGroups) { Text($0.name).tag($0.id) }
            }
        } header: {
            finchSectionHeader("Details")
        }

        Section {
            Picker("Frequency", selection: $frequency) {
                ForEach(frequencies, id: \.self) { Text($0.capitalized).tag($0) }
            }
            DatePicker("Start date", selection: $startDate, displayedComponents: .date)
        } header: {
            finchSectionHeader("Cycle")
        } footer: {
            if isEdit, budget?.isRecurring == 1 {
                Text("Changing the start date or frequency re-bases the cycle and clears any staged amount and rolled-over balance.")
            }
        }

        Section {
            CategoryMultiPickerRow(
                title: "Categories",
                categories: categories,
                selection: $selectedCategories,
                emptyLabel: "All categories")
            MultiSelectPickerRow(
                title: "Accounts",
                options: store.accounts.map { PickerOption(id: $0.id, name: $0.name ?? "Account") },
                selection: $selectedAccounts,
                emptyLabel: "All accounts")
        } header: {
            finchSectionHeader("Tracking")
        } footer: {
            Text("Leave empty to track all expense categories and accounts.")
        }

        Section {
            Toggle("Roll over unused budget", isOn: $rollover)
            if rollover {
                HStack {
                    Text("Cap"); Spacer()
                    TextField("Optional", text: $rolloverCap).numericInput($rolloverCap)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }
        } header: {
            finchSectionHeader("Rollover")
        } footer: {
            Text("Unspent budget carries into the next period. Set a cap to limit how much.")
        }
    }

    // MARK: save

    private func save() {
        errorMessage = nil
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter a name."; return }
        guard let value = DecimalInput.parse(amount), value > 0 else {
            errorMessage = kind == .income ? "Enter a target greater than 0." : "Enter a limit greater than 0."
            return
        }
        if kind == .income { saveIncome(target: value) } else { saveExpense(limit: value) }
    }

    /// Income = a savings goal funded by real matched transactions. `saved` is a
    /// pre-tracking offset, now set directly (patchable via updateBudget — the old
    /// contribute action is gone). Progress = saved + Σ matched inflows across the
    /// category/account/tag/merchant scopes, so require ≥1 scope (else it counts
    /// ALL income).
    private func saveIncome(target: Double) {
        guard !selectedCategories.isEmpty || !selectedAccounts.isEmpty
            || !selectedTags.isEmpty || !selectedCounterparties.isEmpty else {
            errorMessage = "Pick at least one category, account, tag, or merchant to match."
            return
        }
        let endDate: JSONValue = hasTargetDate ? .string(AppDate.isoDay.string(from: targetDate)) : .null
        let savedVal = max(0, DecimalInput.parse(savedText) ?? 0)
        let categoryIds: JSONValue = .array(selectedCategories.sorted().map { .string($0) })
        let accountIds: JSONValue = .array(selectedAccounts.sorted().map { .string($0) })
        let tagIds: JSONValue = .array(selectedTags.sorted().map { .string($0) })
        let counterpartyIds: JSONValue = .array(selectedCounterparties.sorted().map { .string($0) })

        if let budget {
            let patch: [String: JSONValue] = [
                "name": .string(name), "type": .string("income"),
                "amount": .double(target), "saved": .double(savedVal),
                "groupId": groupId.isEmpty ? .null : .string(groupId),
                "endDate": endDate,
                "categoryIds": categoryIds, "accountIds": accountIds,
                "tagIds": tagIds, "counterpartyIds": counterpartyIds,
            ]
            do {
                try store.apply(.updateBudget, Args(["id": .string(budget.id), "patch": .object(patch)]))
                dismiss()
            } catch { errorMessage = i18nMessage(error) }
        } else {
            // A one-shot savings goal: isRecurring defaults to 0 for income, and
            // frequency/startDate are inert but the columns are NOT NULL, so pass sane values.
            var args: [String: JSONValue] = [
                "ledgerId": .string(store.activeLedgerId), "name": .string(name),
                "type": .string("income"), "amount": .double(target),
                "startDate": .string(AppDate.isoDay.string(from: Date())),
                "categoryIds": categoryIds, "accountIds": accountIds,
                "tagIds": tagIds, "counterpartyIds": counterpartyIds,
            ]
            if !groupId.isEmpty { args["groupId"] = .string(groupId) }
            if savedVal > 0 { args["saved"] = .double(savedVal) }
            if hasTargetDate { args["endDate"] = .string(AppDate.isoDay.string(from: targetDate)) }
            do { try store.apply(.createBudget, Args(args)); dismiss() }
            catch { errorMessage = i18nMessage(error) }
        }
    }

    private func saveExpense(limit: Double) {
        let categoryIds: JSONValue = .array(selectedCategories.sorted().map { .string($0) })
        let accountIds: JSONValue = .array(selectedAccounts.sorted().map { .string($0) })
        let startDateStr = AppDate.isoDay.string(from: startDate)

        // Cap is optional and validated only when rollover is on and it's non-empty.
        let capValue: JSONValue
        if rollover && !rolloverCap.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let c = DecimalInput.parse(rolloverCap), c >= 0 else { errorMessage = "Enter a valid rollover cap."; return }
            capValue = .double(c)
        } else {
            capValue = .null
        }

        if let budget {
            // Changing the cycle anchor (frequency or start date) re-bases the
            // budget, so route those through updateBudgetCycle — it clears the
            // staged pending amount + accumulated rollover. Descriptive/scope
            // fields always go through updateBudget. (Combined "Change cycle" into
            // Edit; the web keeps these as two separate actions.)
            let cycleChanged = frequency != budget.frequency || startDateStr != budget.startDate
            var patch: [String: JSONValue] = [
                "name": .string(name), "type": .string("expense"),
                "categoryIds": categoryIds, "accountIds": accountIds,
                "groupId": groupId.isEmpty ? .null : .string(groupId),
                "rollover": .bool(rollover), "rolloverLimit": capValue,
            ]
            if !cycleChanged {
                // Cycle is unchanged → fold amount + frequency into the one patch.
                patch["amount"] = .double(limit)
                patch["frequency"] = .string(frequency)
            }
            do {
                try store.apply(.updateBudget, Args(["id": .string(budget.id), "patch": .object(patch)]))
                if cycleChanged {
                    try store.apply(.updateBudgetCycle, Args(["id": .string(budget.id), "patch": .object([
                        "frequency": .string(frequency),
                        "startDate": .string(startDateStr),
                        "amount": .double(limit),
                    ])]))
                }
                dismiss()
            } catch { errorMessage = i18nMessage(error) }
        } else {
            var args: [String: JSONValue] = [
                "ledgerId": .string(store.activeLedgerId), "name": .string(name),
                "type": .string("expense"), "amount": .double(limit), "frequency": .string(frequency),
                "startDate": .string(startDateStr), "rollover": .bool(rollover),
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
