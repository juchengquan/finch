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
    @State private var path: [String] = []            // compact-mode push stack (budget ids)
    @State private var errorMessage: String?
    @State private var collapsedGroups: Set<String> = []   // loaded per active ledger on appear
    @State private var searchQuery = ""                // filters budget rows by name

    var body: some View {
        NavigationStack(path: $path) {
            listContent
            #if os(iOS)
            .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search budgets")
            #else
            .searchable(text: $searchQuery, prompt: "Search budgets")
            #endif
            .navigationTitle("Budgets")
            .ledgerPush()
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { LedgerBarButton() }
                #endif
                ToolbarItem(placement: .primaryAction) { PrivacyToggleButton() }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add Budget")
                        .disabled(store.ledgers.isEmpty)
                }
                // Group management moved off the + into the ⋯ overflow menu (matches Accounts).
                ToolbarItem(placement: .secondaryAction) {
                    Button { showingGroups = true } label: { Label("Manage Groups", systemImage: "folder") }
                }
            }
            .sheet(isPresented: $showingAdd) { BudgetSheet() }
            .sheet(item: $editing) { BudgetSheet(budget: $0) }
            .sheet(isPresented: $showingGroups) { NavigationStack { BudgetGroupsView() } }
            .errorAlert($errorMessage)
            .navigationDestination(for: String.self) { BudgetDetailView(budgetId: $0) }
            .onAppear { consumeFocus(); collapsedGroups = BudgetGroupCollapse.collapsed(ledger: store.activeLedgerId) }
            .onChange(of: router.focusedId) { _, _ in consumeFocus() }
            .onChange(of: store.activeLedgerId) { _, lid in collapsedGroups = BudgetGroupCollapse.collapsed(ledger: lid) }
        }
    }

    @ViewBuilder private var listContent: some View {
        if store.budgets.isEmpty {
            EmptyState(tab: .budgets,
                       description: store.ledgers.isEmpty ? nil : "Tap + to create a budget.")
        } else if let selection {
            List(selection: selection) {
                summarySection
                groupedSections { budget in
                    BudgetRowView(budget: budget)
                        .tag(budget.id)
                        .swipeActions(edge: .trailing) { rowActions(budget) }
                        .contextMenu { rowActions(budget) }
                }
            }
            #if os(macOS)
            .onDeleteCommand { if let id = selection.wrappedValue, let b = store.budgets.first(where: { $0.id == id }) { delete(b) } }
            #endif
        } else {
            List {
                summarySection
                groupedSections { budget in
                    // Plain Button (navigates via the path) instead of NavigationLink
                    // so there's no trailing disclosure chevron — same convention as
                    // the Accounts rows; contentShape keeps the whole row tappable.
                    Button { path.append(budget.id) } label: {
                        BudgetRowView(budget: budget).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) { rowActions(budget) }
                    .contextMenu { rowActions(budget) }
                }
            }
        }
    }

    /// Compact totals status pinned at the top: total spent / total budget across
    /// the active ledger (same StatusSummaryRow style as the Accounts summary).
    @ViewBuilder private var summarySection: some View {
        Section {
            let t = store.budgetTotalsDisplay
            StatusSummaryRow(leadingLabel: "Spent", leadingValue: t.used,
                             trailingLabel: "Budget", trailingValue: t.base)
        }
    }

    /// True while the user has typed a non-empty budget search.
    private var searchActive: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Budgets in `group`, narrowed by the search query (case-insensitive name
    /// contains). No query → the full group.
    private func filteredBudgets(in group: String) -> [BudgetRow] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let budgets = store.budgets(in: group)
        guard !q.isEmpty else { return budgets }
        return budgets.filter { $0.name.lowercased().contains(q) }
    }

    /// Ungrouped budgets, narrowed by the search query — rendered bare at the top.
    private var filteredUngroupedBudgets: [BudgetRow] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let buds = store.ungroupedBudgets
        guard !q.isEmpty else { return buds }
        return buds.filter { $0.name.lowercased().contains(q) }
    }

    /// Groups to render: all normally; while searching, only those with at least
    /// one matching budget.
    private var groupsToShow: [String] {
        searchActive ? store.budgetGroupsOrdered.filter { !filteredBudgets(in: $0).isEmpty }
                     : store.budgetGroupsOrdered
    }

    /// Grouped budget sections, shared by both layouts. (Totals live in the
    /// top summary section; see `summarySection`.)
    @ViewBuilder private func groupedSections<Row: View>(
        @ViewBuilder row: @escaping (BudgetRow) -> Row) -> some View {
        if searchActive && groupsToShow.isEmpty && filteredUngroupedBudgets.isEmpty {
            Section { ContentUnavailableView.search(text: searchQuery) }
        }
        // Ungrouped budgets: bare rows pinned to the top, no "Ungrouped" header.
        if !filteredUngroupedBudgets.isEmpty {
            Section { ForEach(filteredUngroupedBudgets) { budget in row(budget) } }
        }
        ForEach(groupsToShow, id: \.self) { groupName in
            // Tappable Button row (not a section header) so the chevron toggle
            // fires reliably and keeps the default list look — mirrors AccountsTab (#223).
            Section {
                Button {
                    toggleGroup(groupName)
                } label: {
                    HStack {
                        Image(systemName: collapsedGroups.contains(groupName) ? "chevron.right" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                        Text(groupName).fontWeight(.semibold)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(collapsedGroups.contains(groupName) ? "Collapsed" : "Expanded")
                .accessibilityHint(collapsedGroups.contains(groupName) ? "Double tap to expand" : "Double tap to collapse")

                // Collapse is bypassed while searching so matches always surface.
                if !collapsedGroups.contains(groupName) || searchActive {
                    ForEach(filteredBudgets(in: groupName)) { budget in row(budget) }
                }
            }
        }
    }

    /// Toggle a group's collapsed state and persist it.
    private func toggleGroup(_ group: String) {
        let nowCollapsed = !collapsedGroups.contains(group)
        withAnimation {
            if nowCollapsed { collapsedGroups.insert(group) } else { collapsedGroups.remove(group) }
        }
        BudgetGroupCollapse.setCollapsed(group, nowCollapsed, ledger: store.activeLedgerId)
    }

    @ViewBuilder private func rowActions(_ budget: BudgetRow) -> some View {
        Button { editing = budget } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
        Button(role: .destructive) { delete(budget) } label: { Label("Delete", systemImage: "trash") }
    }

    /// A deep link stashed a budget id + switched to this tab — open it.
    private func consumeFocus() {
        guard let id = router.focusedId, store.budgets.contains(where: { $0.id == id }) else { return }
        if let selection { selection.wrappedValue = id }
        else { path = [id] }
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
