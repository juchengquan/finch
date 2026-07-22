import SwiftUI
import FinchCore

/// Budget drill-in: cycle progress (used/base/remaining + bar), a History chart
/// whose past-cycle bars tap through to that cycle's numbers + transactions,
/// this cycle's matched transactions, and edit / clear-pending / delete. Income
/// goals fund from real matched inflows (no Contribute). Re-resolves from the
/// store; pops when deleted. (Cycle edits — frequency + start date — live in
/// the Edit sheet, BudgetSheet.)
struct BudgetDetailView: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss

    let budgetId: String

    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var showingAddTx = false   // budget-aware add (pre-filled category/account)
    @State private var editing: Tx?           // tapped cycle transaction → edit sheet
    @State private var errorMessage: String?
    @AppStorage("finch.feed.groupByMonth") private var groupByMonth = true
    // Tapped History bar → that past cycle's numbers + transactions (keyed by
    // the cycle's `from` so it survives reprojection; current cycle never
    // selects — its details are already on the page).
    @State private var selectedCycleFrom: String?

    private var budget: BudgetRow? { store.budgets.first { $0.id == budgetId } }

    var body: some View {
        Group {
            if let budget {
                let p = Selectors.budgetProgress(budget, store.txns, store.today, store.categoryNodes)
                List {
                    Section { progress(budget, p) }
                    historySection(budget)
                    if budget.type == "income" {
                        Section("Income") {
                            LabeledContent("Saved", value: store.displayMoneyBase(budget.saved))
                            if let end = budget.endDate, let d = AppDate.isoDay.date(from: end) {
                                LabeledContent("Target date", value: d.formatted(date: .abbreviated, time: .omitted))
                            }
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
        let secs = MonthGrouping.sections(txns)
        if txns.isEmpty {
            Section("This cycle") {
                Text("No matching transactions").font(.caption).foregroundStyle(.secondary)
            }
        } else if groupByMonth && secs.count > 1 {
            // Only a multi-month cycle (quarterly/yearly, or off-calendar) benefits from
            // sectioning; a monthly cycle is one month, so it stays a flat "This cycle".
            ForEach(secs) { monthSection($0) }
        } else {
            Section("This cycle") {
                ForEach(txns, id: \.id) { t in txnRow(t) }
            }
        }
    }

    /// One month bucket of budget-matched transactions, headed by the month label and
    /// the month's net change (no running balance — a budget has none). Shared by the
    /// current-cycle and drill-in past-cycle lists.
    @ViewBuilder private func monthSection(_ section: MonthGrouping.Section) -> some View {
        Section {
            ForEach(section.txns, id: \.id) { t in txnRow(t) }
        } header: {
            HStack {
                Text(MonthGrouping.label(section.id)).textCase(nil)
                Spacer()
                Text(store.displayMoneyBase(MonthGrouping.net(section.txns)))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One matched-transaction row — tap opens the editor (same behavior as the
    /// account detail's transaction rows).
    @ViewBuilder private func txnRow(_ t: Tx) -> some View {
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

    /// Spent-vs-budget bars across the trailing cycles (hidden for one-shots and
    /// when there's under 2 cycles of history — one bar answers nothing).
    /// Tapping a past-cycle bar opens that cycle's drill-in section below;
    /// tapping it again (or the current bar) clears it.
    @ViewBuilder private func historySection(_ b: BudgetRow) -> some View {
        let pts = Selectors.budgetCycleHistory(b, store.txns, store.today, store.categoryNodes)
        if pts.count >= 2 {
            let selected = pts.first { $0.from == selectedCycleFrom && !$0.isCurrent }
            Section("History") {
                BarChart(data: pts.map { p in
                    BarChart.DataPoint(label: cycleLabel(p.from, b.frequency),
                                       value: p.used,
                                       color: (p.over ? Color.red : Color.green)
                                           .opacity(barOpacity(p, selected: selected)))
                }, xLabel: "Cycle", yLabel: "Spent", referenceLine: b.amount,
                   onBarTap: { i in
                    guard i < pts.count else { return }
                    let p = pts[i]
                    selectedCycleFrom = (p.isCurrent || p.from == selectedCycleFrom) ? nil : p.from
                })
                .frame(height: 140)
                Text("Last \(pts.count) cycles · budget \(store.displayMoneyBase(b.amount))")
                    .font(.caption).foregroundStyle(.secondary)
                if selected == nil {
                    Text("Tap a bar to view a past cycle")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let selected { cycleSection(b, selected) }
        }
    }

    /// Selected bar stays full-strength and the rest recede; with no selection,
    /// the current cycle is the muted one (it's provisional — still filling).
    private func barOpacity(_ p: Selectors.BudgetCyclePoint, selected: Selectors.BudgetCyclePoint?) -> Double {
        if let selected { return p.from == selected.from ? 1 : 0.3 }
        return p.isCurrent ? 0.45 : 1
    }

    /// Drill-in for a tapped past cycle: the same used/base/remaining block as
    /// the header (windowed), then that cycle's matched transactions.
    @ViewBuilder private func cycleSection(_ b: BudgetRow, _ c: Selectors.BudgetCyclePoint) -> some View {
        let txns = Selectors.budgetMatchedTransactions(b, store.txns, from: c.from, to: c.to, store.categoryNodes)
        let secs = MonthGrouping.sections(txns)
        let sectioned = groupByMonth && secs.count > 1
        let pct = c.base != 0 ? Int((c.used / c.base * 100).rounded()) : 0
        Section("Selected cycle") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(store.displayMoneyBase(c.used)) of \(store.displayMoneyBase(c.base))")
                        .fontWeight(.medium)
                    Spacer()
                    if c.over { Text("Over").font(.caption).foregroundStyle(.red) }
                }
                ProgressView(value: min(Double(pct) / 100, 1.0))
                    .tint(c.over ? .red : (pct >= 70 ? .yellow : .green))
                HStack {
                    Text("\(store.displayMoneyBase(c.base - c.used)) left").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(c.from) – \(c.to)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            // When the cycle spans >1 month, its transactions render as month sections
            // BELOW this summary; otherwise they stay flat inside it.
            if !sectioned {
                if txns.isEmpty {
                    Text("No matching transactions").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(txns, id: \.id) { t in txnRow(t) }
                }
            }
        }
        if sectioned {
            ForEach(secs) { monthSection($0) }
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

