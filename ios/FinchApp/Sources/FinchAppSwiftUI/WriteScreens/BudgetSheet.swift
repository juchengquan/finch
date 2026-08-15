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
        var label: String { KindLabel.label(rawValue) }
    }
    let frequencies = ["daily", "weekly", "biweekly", "monthly", "quarterly", "yearly"]

    private static let palette: [(hex: String, color: Color)] = [
        ("#1f3a5f", .blue), ("#2e7d32", .green), ("#c62828", .red),
        ("#6a1b9a", .purple), ("#ef6c00", .orange), ("#00838f", .teal),
    ]

    @State private var name: String
    // Detail fields (schema 2026-08-12). Budgets had no visual identity of their
    // own while budget GROUPS already carried a colour.
    @State private var icon = ""
    @State private var colorHex = ""
    @State private var notes = ""
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
        _icon = State(initialValue: budget?.icon ?? "")
        _colorHex = State(initialValue: budget?.color ?? "")
        _notes = State(initialValue: budget?.notes ?? "")
        _kind = State(initialValue: (budget?.type == "income") ? .income : .expense)
        _amount = State(initialValue: budget.map { DecimalInput.text($0.amount, currency: FinchStore.shared.baseCurrency) } ?? "")
        _frequency = State(initialValue: budget?.frequency ?? "monthly")
        // Date AND turnover time, in one Date. Seeding from the date alone would
        // show midnight for a budget that turns over at 09:30 — and then SAVE that,
        // silently wiping the time the user had set.
        _startDate = State(initialValue: budget.flatMap {
            AppDate.isoDateTime.date(from: "\($0.startDate) \($0.startTime ?? "00:00")")
                ?? AppDate.isoDay.date(from: $0.startDate)
        } ?? Date())
        _groupId = State(initialValue: budget?.groupId ?? "")
        _selectedCategories = State(initialValue: Set(budget?.categoryIds ?? []))
        _selectedAccounts = State(initialValue: Set(budget?.accountIds ?? []))
        _selectedTags = State(initialValue: Set(budget?.tagIds ?? []))
        _selectedCounterparties = State(initialValue: Set(budget?.counterpartyIds ?? []))
        _rollover = State(initialValue: (budget?.rollover ?? 0) != 0)
        _rolloverCap = State(initialValue: budget?.rolloverLimit.map { DecimalInput.text($0, currency: FinchStore.shared.baseCurrency) } ?? "")
        // Income "saved so far": pre-fill on edit (a goal you've already partly funded).
        _savedText = State(initialValue: (budget?.type == "income" && (budget?.saved ?? 0) != 0)
            ? DecimalInput.text(budget!.saved, currency: FinchStore.shared.baseCurrency) : "")
        _hasTargetDate = State(initialValue: budget?.endDate != nil)
        // Date AND time, so a goal saved for 18:00 does not reopen at midnight and
        // save that back — the same trap the Start picker had.
        _targetDate = State(initialValue: budget?.endDate.flatMap {
            AppDate.isoDateTime.date(from: "\($0) \(budget?.endTime ?? "00:00")")
                ?? AppDate.isoDay.date(from: $0)
        } ?? Date())
    }

    private var categories: [CategoryRow] {
        store.pickableCategories.filter { kind == .income ? $0.kind == "income" : $0.kind != "income" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { TxnTypeToolbar.caption(kind.label) }.finchCaptionSection()   // names the toolbar type control above
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
            FieldRow(glyph: .name, title: "Name") {
                TextField("Name", text: $name)
            }
            IconPickerRow(title: "Icon", glyph: .icon, selection: $icon)
            FieldRow(glyph: .amount, title: "Target",
                     help: kind == .income
                         ? "What you aim to put aside each cycle."
                         : "What you plan to spend each cycle.") {
                TextField(DecimalInput.zeroPlaceholder(fractionDigits: Currencies.minorUnits(for: store.baseCurrency)), text: $amount).moneyInput($amount, currency: store.baseCurrency)
            }
            FieldRow(glyph: .group, title: "Group", showsDefaultTrailing: false) {
                Picker("Group", selection: $groupId) {
                    Text("None").tag("")
                    ForEach(store.budgetGroups) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
            }
        }

        Section {
            FieldRow(glyph: .color, title: "Color") {
                HStack(spacing: 14) {
                    ForEach(Self.palette, id: \.hex) { swatch in
                        Circle().fill(swatch.color).frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.primary, lineWidth: colorHex == swatch.hex ? 2.5 : 0))
                            .onTapGesture { colorHex = (colorHex == swatch.hex ? "" : swatch.hex) }
                            .accessibilityLabel("Color \(swatch.hex)")
                    }
                }
            }
            FieldRow(glyph: .note, title: "Note") {
                TextField("Note (optional)", text: $notes, axis: .vertical)
            }
        }
        Section {
            FieldRow(glyph: .amount, title: "Saved so far") {
                TextField(DecimalInput.zeroPlaceholder(fractionDigits: Currencies.minorUnits(for: store.baseCurrency)), text: $savedText).moneyInput($savedText, currency: store.baseCurrency)
            }
            FieldRow(glyph: .status, title: "Set target date") {
                Toggle("Set target date", isOn: $hasTargetDate).switchOnlyToggles()
            }
            if hasTargetDate {
                FieldRow(glyph: .date, title: "Target date", showsDefaultTrailing: false) {
                    DatePicker("Target date", selection: $targetDate, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
            }
        } footer: {
            Text("\"Saved so far\" is money set aside before tracking began. Matching transactions add on top of it.")
        }
        Section {
            CategoryMultiPickerRow(
                title: "Categories",
                glyph: .category,
                categories: categories,
                selection: $selectedCategories,
                emptyLabel: "Any category")
            MultiSelectPickerRow(
                title: "Accounts",
                glyph: .account,
                accounts: store.accounts,
                selection: $selectedAccounts,
                emptyLabel: "Any account")
            MultiSelectPickerRow(
                title: "Tags",
                glyph: .tags,
                options: store.tags.map { PickerOption(id: $0.id, name: $0.name) },
                selection: $selectedTags,
                emptyLabel: "Any tag")
            MultiSelectPickerRow(
                title: "Merchants",
                glyph: .merchant,
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
            FieldRow(glyph: .name, title: "Name") {
                TextField("Name", text: $name)
            }
            IconPickerRow(title: "Icon", glyph: .icon, selection: $icon)
            FieldRow(glyph: .amount, title: "Limit") {
                TextField(DecimalInput.zeroPlaceholder(fractionDigits: Currencies.minorUnits(for: store.baseCurrency)), text: $amount).moneyInput($amount, currency: store.baseCurrency)
            }
            FieldRow(glyph: .group, title: "Group", showsDefaultTrailing: false) {
                Picker("Group", selection: $groupId) {
                    Text("None").tag("")
                    ForEach(store.budgetGroups) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
            }
        }

        Section {
            FieldRow(glyph: .color, title: "Color") {
                HStack(spacing: 14) {
                    ForEach(Self.palette, id: \.hex) { swatch in
                        Circle().fill(swatch.color).frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.primary, lineWidth: colorHex == swatch.hex ? 2.5 : 0))
                            .onTapGesture { colorHex = (colorHex == swatch.hex ? "" : swatch.hex) }
                            .accessibilityLabel("Color \(swatch.hex)")
                    }
                }
            }
            FieldRow(glyph: .note, title: "Note") {
                TextField("Note (optional)", text: $notes, axis: .vertical)
            }
        }

        Section {
            FieldRow(glyph: .frequency, title: "Frequency", showsDefaultTrailing: false) {
                Picker("Frequency", selection: $frequency) {
                    ForEach(frequencies, id: \.self) { Text(FrequencyLabel.label($0)).tag($0) }
                }
                .labelsHidden()
            }
            // Date AND time: the time is when the cycle turns over. Left at midnight
            // it behaves exactly as every budget did before.
            FieldRow(glyph: .date, title: "Start date", showsDefaultTrailing: false) {
                DatePicker("Start date", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
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
                glyph: .category,
                categories: categories,
                selection: $selectedCategories,
                emptyLabel: "All categories")
            MultiSelectPickerRow(
                title: "Accounts",
                glyph: .account,
                accounts: store.accounts,
                selection: $selectedAccounts,
                emptyLabel: "All accounts")
        } header: {
            finchSectionHeader("Tracking")
        } footer: {
            Text("Leave empty to track all expense categories and accounts.")
        }

        Section {
            FieldRow(glyph: .status, title: "Roll over unused budget") {
                Toggle("Roll over unused budget", isOn: $rollover).switchOnlyToggles()
            }
            if rollover {
                FieldRow(glyph: .amount, title: "Cap") {
                    TextField("Optional", text: $rolloverCap).moneyInput($rolloverCap, currency: store.baseCurrency)
                        .keyboardType(.decimalPad)
                }
            }
        } header: {
            finchSectionHeader("Rollover")
        } footer: {
            Text("Unspent budget carries into the next period. Set a cap to limit how much.")
        }
    }

    // MARK: save

    /// nil-when-blank, so clearing a field actually clears the column rather
    /// than storing an empty string.
    private var detailPatch: [String: JSONValue] {
        func t(_ v: String) -> JSONValue {
            let s = v.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? .null : .string(s)
        }
        return ["icon": t(icon), "color": t(colorHex), "notes": t(notes)]
    }

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
        let endTime: JSONValue = hasTargetDate ? .string(AppDate.isoTime.string(from: targetDate)) : .null
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
                "endDate": endDate, "endTime": endTime,
                "categoryIds": categoryIds, "accountIds": accountIds,
                "tagIds": tagIds, "counterpartyIds": counterpartyIds,
            ]
            do {
                try store.apply(.updateBudget, Args(["id": .string(budget.id),
                                                     "patch": .object(patch.merging(detailPatch) { a, _ in a })]))
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
            if hasTargetDate {
                args["endDate"] = .string(AppDate.isoDay.string(from: targetDate))
                args["endTime"] = .string(AppDate.isoTime.string(from: targetDate))
            }
            for (k, v) in detailPatch where v != .null { args[k] = v }
            do { try store.apply(.createBudget, Args(args)); dismiss() }
            catch { errorMessage = i18nMessage(error) }
        }
    }

    private func saveExpense(limit: Double) {
        let categoryIds: JSONValue = .array(selectedCategories.sorted().map { .string($0) })
        let accountIds: JSONValue = .array(selectedAccounts.sorted().map { .string($0) })
        let startDateStr = AppDate.isoDay.string(from: startDate)
        // Sent alongside the date: nil-equivalent (midnight) keeps the old behaviour,
        // any other value moves the cycle's turnover to that time of day.
        let startTimeStr = AppDate.isoTime.string(from: startDate)

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
            // The time counts as a cycle change: it only rides on the cycle patch,
            // so a time-only edit would otherwise be dropped. A budget with no time
            // compares against midnight, which is what it means.
            let cycleChanged = frequency != budget.frequency || startDateStr != budget.startDate
                || startTimeStr != (budget.startTime ?? "00:00")
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
                try store.apply(.updateBudget, Args(["id": .string(budget.id),
                                                     "patch": .object(patch.merging(detailPatch) { a, _ in a })]))
                if cycleChanged {
                    try store.apply(.updateBudgetCycle, Args(["id": .string(budget.id), "patch": .object([
                        "frequency": .string(frequency),
                        "startDate": .string(startDateStr), "startTime": .string(startTimeStr),
                        "amount": .double(limit),
                    ])]))
                }
                dismiss()
            } catch { errorMessage = i18nMessage(error) }
        } else {
            var args: [String: JSONValue] = [
                "ledgerId": .string(store.activeLedgerId), "name": .string(name),
                "type": .string("expense"), "amount": .double(limit), "frequency": .string(frequency),
                "startDate": .string(startDateStr), "startTime": .string(startTimeStr), "rollover": .bool(rollover),
            ]
            if !groupId.isEmpty { args["groupId"] = .string(groupId) }
            if !selectedCategories.isEmpty { args["categoryIds"] = categoryIds }
            if !selectedAccounts.isEmpty { args["accountIds"] = accountIds }
            if case .double = capValue { args["rolloverLimit"] = capValue }
            for (k, v) in detailPatch where v != .null { args[k] = v }
            do { try store.apply(.createBudget, Args(args)); dismiss() }
            catch { errorMessage = i18nMessage(error) }
        }
    }
}
