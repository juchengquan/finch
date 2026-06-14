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
    @EnvironmentObject private var router: DeepLinkRouter
    @State private var showingAdd = false
    @State private var showingGroups = false
    @State private var editing: BudgetRow?
    @State private var focused: BudgetRow?            // deep-link drill-in
    @State private var errorMessage: String?

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
                                    NavigationLink { BudgetDetailView(budgetId: budget.id) } label: {
                                        BudgetRowView(budget: budget)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) { delete(budget) } label: { Label("Delete", systemImage: "trash") }
                                        Button { editing = budget } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                                    }
                                    .contextMenu {
                                        Button { editing = budget } label: { Label("Edit", systemImage: "pencil") }
                                        Button(role: .destructive) { delete(budget) } label: { Label("Delete", systemImage: "trash") }
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
                    Menu {
                        Button { showingAdd = true } label: { Label("Add Budget", systemImage: "plus") }
                        Button { showingGroups = true } label: { Label("Manage Groups", systemImage: "folder") }
                    } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add or manage budgets")
                        .disabled(store.ledgers.isEmpty)
                }
            }
            .sheet(isPresented: $showingAdd) { BudgetSheet() }
            .sheet(item: $editing) { BudgetSheet(budget: $0) }
            .sheet(isPresented: $showingGroups) { NavigationStack { BudgetGroupsView() } }
            .errorAlert($errorMessage)
            .navigationDestination(item: $focused) { BudgetDetailView(budgetId: $0.id) }
            .onAppear(perform: consumeFocus)
            .onChange(of: router.focusedId) { _, _ in consumeFocus() }
        }
    }

    /// A deep link stashed a budget id + switched to this tab — open it.
    private func consumeFocus() {
        guard let id = router.focusedId, let b = store.budgets.first(where: { $0.id == id }) else { return }
        focused = b
        router.focusedId = nil
    }

    private func delete(_ budget: BudgetRow) {
        do { try store.apply(.removeBudget, Args(["id": .string(budget.id)])) }
        catch { errorMessage = i18nMessage(error) }
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
