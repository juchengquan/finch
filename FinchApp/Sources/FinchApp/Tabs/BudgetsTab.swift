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
/// One view, two layouts: with `selection == nil` (compact) budget rows push
/// `BudgetDetailView`; with a `selection` binding (the iPad/Mac three-column
/// shell) rows are selectable and drive the shell's detail column.
struct BudgetsTab: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var router: DeepLinkRouter
    /// Non-nil → three-column selection mode (drives the shell's detail column).
    var selection: Binding<String?>? = nil
    @State private var showingAdd = false
    @State private var showingGroups = false
    @State private var editing: BudgetRow?
    @State private var focused: BudgetRow?            // deep-link drill-in (push mode)
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            listContent
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

    @ViewBuilder private var listContent: some View {
        if store.budgets.isEmpty {
            ContentUnavailableView {
                Label("No budgets yet", systemImage: "chart.pie")
            } description: {
                Text(store.ledgers.isEmpty
                     ? "Import a .finch pack from Settings to get started."
                     : "Tap + to create a budget.")
            }
        } else if let selection {
            List(selection: selection) {
                groupedSections { budget in
                    BudgetRowView(budget: budget)
                        .tag(budget.id)
                        .swipeActions(edge: .trailing) { rowActions(budget) }
                        .contextMenu { rowActions(budget) }
                }
            }
        } else {
            List {
                groupedSections { budget in
                    NavigationLink { BudgetDetailView(budgetId: budget.id) } label: {
                        BudgetRowView(budget: budget)
                    }
                    .swipeActions(edge: .trailing) { rowActions(budget) }
                    .contextMenu { rowActions(budget) }
                }
            }
        }
    }

    /// Grouped budget sections + totals footer, shared by both layouts.
    @ViewBuilder private func groupedSections<Row: View>(
        @ViewBuilder row: @escaping (BudgetRow) -> Row) -> some View {
        ForEach(store.budgetGroupsOrdered, id: \.self) { groupName in
            Section(groupName) {
                ForEach(store.budgets(in: groupName)) { budget in row(budget) }
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

    @ViewBuilder private func rowActions(_ budget: BudgetRow) -> some View {
        Button { editing = budget } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
        Button(role: .destructive) { delete(budget) } label: { Label("Delete", systemImage: "trash") }
    }

    /// A deep link stashed a budget id + switched to this tab — open it.
    private func consumeFocus() {
        guard let id = router.focusedId, store.budgets.contains(where: { $0.id == id }) else { return }
        if let selection { selection.wrappedValue = id }
        else { focused = store.budgets.first { $0.id == id } }
        router.focusedId = nil
    }

    private func delete(_ budget: BudgetRow) {
        do {
            try store.apply(.removeBudget, Args(["id": .string(budget.id)]))
            if selection?.wrappedValue == budget.id { selection?.wrappedValue = nil }
        } catch { errorMessage = i18nMessage(error) }
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
