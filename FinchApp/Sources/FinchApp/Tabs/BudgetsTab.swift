import SwiftUI
import FinchCore

/// Budgets grouped by budget group, each row's figures from
/// Selectors.budgetProgress (used/base/pct/over). `pct` is an INTEGER 0–100, so
/// ProgressView needs pct/100 and thresholds compare against 70/90.
///
/// Native enhancements (NOT web parity): the green/yellow/red 3-color banding
/// (green < 70, yellow 70–90, red > 90) and the "N days left" caption. The web
/// budget bar is 2-state (over ? destructive : primary) with remaining-amount
/// text and no day countdown.
struct BudgetsTab: View {
    @EnvironmentObject private var store: FinchStore
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if store.budgets.isEmpty {
                    ContentUnavailableView {
                        Label("No budgets yet", systemImage: "chart.pie")
                    } description: {
                        Text(store.ledgers.isEmpty
                             ? "Import a .finch pack from Settings to get started."
                             : "Tap + to create a budget.")
                    }
                } else {
                    List {
                        ForEach(store.budgetGroupsOrdered, id: \.self) { groupName in
                            Section(groupName) {
                                ForEach(store.budgets(in: groupName)) { budget in
                                    BudgetRowView(budget: budget)
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) { delete(budget) } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                        Section {
                            let t = store.budgetTotalsDisplay
                            HStack {
                                Text("Total").fontWeight(.semibold)
                                Spacer()
                                Text("\(t.used) / \(t.base)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add Budget")
                        .disabled(store.ledgers.isEmpty)
                }
            }
            .sheet(isPresented: $showingAdd) { AddBudgetSheet() }
        }
    }

    private func delete(_ budget: BudgetRow) {
        try? store.apply(.removeBudget, Args(["id": .string(budget.id)]))
    }
}

struct BudgetRowView: View {
    @EnvironmentObject private var store: FinchStore
    let budget: BudgetRow
    var body: some View {
        let progress = Selectors.budgetProgress(budget, store.txns, store.today, store.categoryNodes)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(budget.name)
                Spacer()
                Text("\(store.displayMoneyBase(progress.used)) / \(store.displayMoneyBase(progress.base))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: min(Double(progress.pct) / 100, 1.0))
                .tint(thresholdColor(progress.pct))   // native enhancement
            HStack {
                Text("\(store.daysLeft(until: progress.to)) days left")
                    .font(.caption2).foregroundStyle(.secondary)
                if progress.over {
                    Spacer()
                    Text("Over").font(.caption2).foregroundStyle(.red)
                }
            }
        }
    }
    /// Native 3-color banding (NOT web parity). pct is an INTEGER 0–100.
    private func thresholdColor(_ pct: Int) -> Color {
        pct > 90 ? .red : (pct >= 70 ? .yellow : .green)
    }
}
