import SwiftUI
import FinchCore

/// Budget drill-in: cycle progress (used/base/remaining + bar), this cycle's
/// matched transactions, contribute (income/goal budgets), and edit / change
/// cycle / clear-pending / delete. Re-resolves from the store; pops when deleted.
struct BudgetDetailView: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    let budgetId: String

    @State private var showingEdit = false
    @State private var showingContribute = false
    @State private var showingCycle = false
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    private var budget: BudgetRow? { store.budgets.first { $0.id == budgetId } }

    var body: some View {
        Group {
            if let budget {
                let p = Selectors.budgetProgress(budget, store.txns, store.today, store.categoryNodes)
                List {
                    Section { progress(budget, p) }
                    if budget.type == "income" {
                        Section("Goal") {
                            LabeledContent("Saved", value: store.displayMoneyBase(budget.saved))
                            Button("Contribute…") { showingContribute = true }
                        }
                    }
                    if let pending = budget.pendingAmount {
                        Section {
                            LabeledContent("Pending next cycle", value: store.displayMoneyBase(pending))
                            Button("Clear pending amount") { clearPending(budget) }
                        }
                    }
                    transactionsSection(budget)
                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                    }
                }
                .navigationTitle(budget.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button { showingEdit = true } label: { Label("Edit", systemImage: "pencil") }
                            Button { showingCycle = true } label: { Label("Change cycle", systemImage: "calendar") }
                            Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
                .sheet(isPresented: $showingEdit) { BudgetSheet(budget: budget) }
                .sheet(isPresented: $showingContribute) { ContributeSheet(budgetId: budget.id) }
                .sheet(isPresented: $showingCycle) { ChangeCycleSheet(budget: budget) }
                .confirmationDialog("Delete this budget?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { delete(budget) }
                }
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
    }

    @ViewBuilder private func progress(_ b: BudgetRow, _ p: BudgetProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(store.displayMoneyBase(p.used)) of \(store.displayMoneyBase(p.base))")
                    .fontWeight(.medium)
                Spacer()
                if p.over { Text("Over").font(.caption).foregroundStyle(.red) }
            }
            ProgressView(value: min(Double(p.pct) / 100, 1.0))
                .tint(p.over ? .red : (p.pct >= 70 ? .yellow : .green))
            HStack {
                Text("\(store.displayMoneyBase(p.remaining)) left").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(p.from) – \(p.to)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func transactionsSection(_ b: BudgetRow) -> some View {
        let txns = Selectors.budgetMatchedTransactions(b, store.txns, store.today, store.categoryNodes)
        Section("This cycle") {
            if txns.isEmpty {
                Text(b.type == "income" && b.isRecurring == 0 ? "Tracked via contributions" : "No matching transactions")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(txns, id: \.id) { t in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.merchant).lineLimit(1)
                            Text(t.date).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(store.displayMoneyBase(t.amount))
                    }
                }
            }
        }
    }

    private func clearPending(_ b: BudgetRow) {
        do { try store.apply(.clearPendingAmount, Args(["id": .string(b.id)])) } catch { errorMessage = i18nMessage(error) }
    }
    private func delete(_ b: BudgetRow) {
        do { try store.apply(.removeBudget, Args(["id": .string(b.id)])) } catch { errorMessage = i18nMessage(error) }
    }
}

/// Add to a goal/income budget's saved total (`contributeBudget`).
struct ContributeSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let budgetId: String
    @State private var amount = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    Text("Amount"); Spacer()
                    TextField("0.00", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Contribute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add", action: save).bold() }
            }
        }
    }

    private func save() {
        errorMessage = nil
        guard let v = DecimalInput.parse(amount), v != 0 else { errorMessage = "Enter an amount."; return }
        do { try store.apply(.contributeBudget, Args(["id": .string(budgetId), "amount": .double(v)])); dismiss() }
        catch { errorMessage = i18nMessage(error) }
    }
}

/// Change a budget's cycle (frequency + start date + amount) — `updateBudgetCycle`,
/// which also resets the staged pending amount + rollover.
struct ChangeCycleSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let budget: BudgetRow
    private let frequencies = ["daily", "weekly", "biweekly", "monthly", "quarterly", "yearly"]
    @State private var frequency: String
    @State private var startDate: Date
    @State private var amount: String
    @State private var errorMessage: String?

    init(budget: BudgetRow) {
        self.budget = budget
        _frequency = State(initialValue: budget.frequency)
        _startDate = State(initialValue: AppDate.isoDay.date(from: budget.startDate) ?? Date())
        _amount = State(initialValue: String(format: "%g", budget.amount))
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Frequency", selection: $frequency) {
                    ForEach(frequencies, id: \.self) { Text($0.capitalized).tag($0) }
                }
                DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                HStack {
                    Text("Amount"); Spacer()
                    TextField("0.00", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Change Cycle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
        }
    }

    private func save() {
        errorMessage = nil
        guard let v = DecimalInput.parse(amount), v > 0 else { errorMessage = "Enter an amount."; return }
        let patch: [String: JSONValue] = [
            "frequency": .string(frequency),
            "startDate": .string(AppDate.isoDay.string(from: startDate)),
            "amount": .double(v),
        ]
        do { try store.apply(.updateBudgetCycle, Args(["id": .string(budget.id), "patch": .object(patch)])); dismiss() }
        catch { errorMessage = i18nMessage(error) }
    }
}

/// Create / rename / delete budget groups (via the shared GroupAdminView).
struct BudgetGroupsView: View {
    @EnvironmentObject private var store: FinchStore
    var body: some View {
        GroupAdminView(
            title: "Budget Groups",
            groups: store.budgetGroups,
            onCreate: { try store.apply(.createBudgetGroup, Args(["ledgerId": .string(store.activeLedgerId), "name": .string($0)])) },
            onRename: { try store.apply(.updateBudgetGroup, Args(["id": .string($0), "patch": .object(["name": .string($1)])])) },
            onDelete: { try store.apply(.deleteBudgetGroup, Args(["id": .string($0)])) },
            onReorder: { ids in
                for (i, id) in ids.enumerated() {
                    try store.apply(.updateBudgetGroup, Args(["id": .string(id), "patch": .object(["sortOrder": .int(i)])]))
                }
            })
    }
}
