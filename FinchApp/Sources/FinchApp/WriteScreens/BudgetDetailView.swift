import SwiftUI
import FinchCore

/// Budget drill-in: cycle progress (used/base/remaining + bar), this cycle's
/// matched transactions, contribute (income/goal budgets), and edit / clear-
/// pending / delete. Re-resolves from the store; pops when deleted. (Cycle edits
/// — frequency + start date — live in the Edit sheet, BudgetSheet.)
struct BudgetDetailView: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    let budgetId: String

    @State private var showingEdit = false
    @State private var showingContribute = false
    @State private var confirmingDelete = false
    @State private var showingAddTx = false   // budget-aware add (pre-filled category/account)
    @State private var editing: Tx?           // tapped cycle transaction → edit sheet
    @State private var errorMessage: String?

    private var budget: BudgetRow? { store.budgets.first { $0.id == budgetId } }

    var body: some View {
        Group {
            if let budget {
                let p = Selectors.budgetProgress(budget, store.txns, store.today, store.categoryNodes)
                List {
                    Section { progress(budget, p) }
                    historySection(budget)
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
                }
                .errorAlert($errorMessage)
                .navigationTitle(budget.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Budget-aware add: the sheet opens pre-filled with this
                    // budget's category (and account, when the budget is
                    // account-filtered), so the transaction lands in this budget.
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingAddTx = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Add Transaction")
                            .disabled(store.accounts.isEmpty)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button { showingEdit = true } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                        // Anchored on the ⋯ menu (iOS 26 positions popouts at their source).
                        .confirmationDialog("Delete this budget?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) { delete(budget) }
                        }
                    }
                }
                .sheet(isPresented: $showingEdit) { BudgetSheet(budget: budget) }
                .sheet(isPresented: $showingContribute) { ContributeSheet(budgetId: budget.id) }
                .sheet(isPresented: $showingAddTx) {
                    AddTransactionSheet(defaultAccountId: budget.accountIds.first,
                                        defaultCategoryId: budget.categoryIds.first)
                }
                .sheet(item: $editing) { EditTransactionSheet(txn: $0) }
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
            if b.carryForward > 0 {
                Text("+\(store.displayMoneyBase(b.carryForward)) carried over")
                    .font(.caption).foregroundStyle(.green)
            }
            ProgressView(value: min(Double(p.pct) / 100, 1.0))
                .tint(p.over ? .red : (p.pct >= 70 ? .yellow : .green))
            HStack {
                Text("\(store.displayMoneyBase(p.remaining)) left").font(.caption).foregroundStyle(.secondary)
                if b.rollover != 0 { Text("· Rolls over").font(.caption2).foregroundStyle(.secondary) }
                Spacer()
                Text("\(p.from) – \(p.to)").font(.caption2).foregroundStyle(.secondary)
            }
            if !b.accountIds.isEmpty {
                let names = b.accountIds.compactMap { id in store.accounts.first { $0.id == id }?.name }.joined(separator: ", ")
                if !names.isEmpty {
                    Text("Accounts: \(names)").font(.caption).foregroundStyle(.secondary)
                }
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
                    // Tap opens the editor — same behavior as the account
                    // detail's transaction rows.
                    Button { editing = t } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.merchant).lineLimit(1)
                                Text(t.date).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(store.displayMoneyBase(t.amount))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Spent-vs-budget bars across the trailing cycles (hidden for one-shots and
    /// when there's under 2 cycles of history — one bar answers nothing).
    @ViewBuilder private func historySection(_ b: BudgetRow) -> some View {
        let pts = Selectors.budgetCycleHistory(b, store.txns, store.today, store.categoryNodes)
        if pts.count >= 2 {
            Section("History") {
                BarChart(data: pts.map { p in
                    BarChart.DataPoint(label: cycleLabel(p.from, b.frequency),
                                       value: p.used,
                                       color: (p.over ? Color.red : Color.green)
                                           .opacity(p.isCurrent ? 0.45 : 1))
                }, xLabel: "Cycle", yLabel: "Spent", referenceLine: b.amount)
                .frame(height: 140)
                Text("Last \(pts.count) cycles · budget \(store.displayMoneyBase(b.amount))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Short x-axis label for a cycle start: month name for monthly, month + year
    /// for quarterly/yearly (labels must be UNIQUE across the ~6 windows — Swift
    /// Charts treats equal categorical labels as one x-band and stacks the bars),
    /// M/d for day-grained frequencies.
    private func cycleLabel(_ from: String, _ frequency: String) -> String {
        let parts = from.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]), (1...12).contains(m) else { return from }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        switch frequency {
        case "daily", "weekly", "biweekly": return "\(m)/\(d)"
        case "quarterly", "yearly": return "\(months[m - 1]) '\(parts[0].suffix(2))"   // e.g. "Jan '26" — year disambiguates repeats
        default: return months[m - 1]   // monthly — 6 consecutive months never repeat
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
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Add")
                        .confirmCheckmarkStyle()
                }
            }
        }
    }

    private func save() {
        errorMessage = nil
        guard let v = DecimalInput.parse(amount), v > 0 else { errorMessage = "Enter an amount greater than 0."; return }   // web guards amt > 0
        do { try store.apply(.contributeBudget, Args(["id": .string(budgetId), "amount": .double(v)])); dismiss() }
        catch { errorMessage = i18nMessage(error) }
    }
}

