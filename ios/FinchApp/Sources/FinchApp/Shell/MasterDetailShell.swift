import SwiftUI
import FinchCore

// Phase 3 / remediation #23 — true three-column master–detail on regular width
// (iPad / Mac). Only the tabs that have a real list→detail relationship —
// Accounts and Budgets — use three columns: sidebar (sections) │ list │ detail.
// The dashboard / sheet-based tabs (Insights, Settings, Activity, Scheduled)
// keep two columns (sidebar │ full-width content) — a dashboard squeezed into a
// narrow middle column would be worse. The COMPACT shell (iPhone) is unchanged:
// it still renders AccountsTab / BudgetsTab (NavigationStack + push).

/// The shared sections sidebar (column 1), driven by the router so deep links /
/// intents / ⌘1–6 keep selecting tabs.
struct SectionSidebar: View {
    @EnvironmentObject private var router: DeepLinkRouter
    var body: some View {
        List(AppTab.allCases, selection: Binding<AppTab?>(
            get: { router.selectedTab },
            set: { if let t = $0 { router.selectedTab = t } })) { tab in
            Label(tab.title, systemImage: tab.icon)
        }
        .navigationTitle("finch")
        .listStyle(.sidebar)
    }
}

/// Generic three-column container: shared sidebar + a list column + a detail
/// column. The list column drives selection; the detail column reads it.
struct ThreeColumnShell<ListColumn: View, DetailColumn: View>: View {
    @ViewBuilder var list: () -> ListColumn
    @ViewBuilder var detail: () -> DetailColumn
    var body: some View {
        NavigationSplitView {
            SectionSidebar()
        } content: {
            list()
        } detail: {
            detail()
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Accounts list column (regular width)

/// The Accounts list as a selectable middle column. Mirrors `AccountsTab`'s
/// list / toolbar / sheets, but rows drive `selection` (→ the detail column)
/// instead of pushing. (Compact width still uses `AccountsTab`.)
struct AccountsListColumn: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var router: DeepLinkRouter
    @Binding var selection: String?
    @State private var showingReconcile = false
    @State private var showingImport = false
    @State private var showingAdd = false
    @State private var showingGroups = false
    @State private var showingArchived = false
    @State private var editing: AccountRow?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {   // hosts the title/toolbar + Holdings push
            Group {
                if store.accounts.isEmpty {
                    EmptyState(tab: .accounts)
                } else {
                    List(selection: $selection) {
                        ForEach(store.accountGroupsOrdered, id: \.self) { groupName in
                            Section {
                                ForEach(store.accounts(in: groupName)) { account in
                                    AccountRowView(account: account)
                                        .tag(account.id)
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) { delete(account) } label: { Label("Delete", systemImage: "trash") }
                                            Button { editing = account } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                                            Button { archive(account) } label: { Label("Archive", systemImage: "archivebox") }.tint(.orange)
                                        }
                                        .contextMenu {
                                            Button { editing = account } label: { Label("Edit", systemImage: "pencil") }
                                            Button { archive(account) } label: { Label("Archive", systemImage: "archivebox") }
                                            Button(role: .destructive) { delete(account) } label: { Label("Delete", systemImage: "trash") }
                                        }
                                }
                            } header: {
                                HStack {
                                    Text(groupName)
                                    Spacer()
                                    Text(store.subtotalDisplay(for: groupName))
                                }
                            }
                        }
                        Section {
                            HStack {
                                Text("Net worth").fontWeight(.semibold)
                                Spacer()
                                Text(store.netWorthDisplay).fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingAdd = true } label: { Label("Add Account", systemImage: "plus") }
                        Button { showingGroups = true } label: { Label("Manage Groups", systemImage: "folder") }
                        Button { showingArchived = true } label: { Label("Archived Accounts", systemImage: "archivebox") }
                    } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add or manage accounts")
                }
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink { HoldingsView() } label: { Label("Holdings", systemImage: "chart.bar") }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button { showingReconcile = true } label: { Label("Reconcile", systemImage: "checkmark.circle") }
                        .disabled(store.accounts.isEmpty)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button { showingImport = true } label: { Label("Import statement (CSV)", systemImage: "doc.badge.plus") }
                        .disabled(store.accounts.isEmpty)
                }
            }
            .sheet(isPresented: $showingReconcile) { ReconcileSheet() }
            .sheet(isPresented: $showingImport) { ImportStatementView() }
            .sheet(isPresented: $showingAdd) { AccountSheet(defaultCurrency: store.baseCurrency) }
            .sheet(item: $editing) { AccountSheet(account: $0, defaultCurrency: store.baseCurrency) }
            .sheet(isPresented: $showingGroups) { NavigationStack { AccountGroupsView() } }
            .sheet(isPresented: $showingArchived) { NavigationStack { ArchivedAccountsView() } }
            .alert("Couldn't complete that", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .onAppear(perform: consumeFocus)
            .onChange(of: router.focusedId) { _, _ in consumeFocus() }
        }
    }

    /// A deep link / Spotlight tap stashed an id + switched here — select it.
    private func consumeFocus() {
        guard let id = router.focusedId, store.accounts.contains(where: { $0.id == id }) else { return }
        selection = id
        router.focusedId = nil
    }
    private func archive(_ a: AccountRow) {
        do { try store.apply(.archiveAccount, Args(["id": .string(a.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func delete(_ a: AccountRow) {
        do { try store.apply(.deleteAccount, Args(["id": .string(a.id)])); if selection == a.id { selection = nil } }
        catch { errorMessage = i18nMessage(error) }
    }
}

// MARK: - Budgets list column (regular width)

/// The Budgets list as a selectable middle column. Mirrors `BudgetsTab`.
struct BudgetsListColumn: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var router: DeepLinkRouter
    @Binding var selection: String?
    @State private var showingAdd = false
    @State private var showingGroups = false
    @State private var editing: BudgetRow?
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
                    List(selection: $selection) {
                        ForEach(store.budgetGroupsOrdered, id: \.self) { groupName in
                            Section(groupName) {
                                ForEach(store.budgets(in: groupName)) { budget in
                                    BudgetRowView(budget: budget)
                                        .tag(budget.id)
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
            .alert("Couldn't complete that", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .onAppear(perform: consumeFocus)
            .onChange(of: router.focusedId) { _, _ in consumeFocus() }
        }
    }

    private func consumeFocus() {
        guard let id = router.focusedId, store.budgets.contains(where: { $0.id == id }) else { return }
        selection = id
        router.focusedId = nil
    }
    private func delete(_ budget: BudgetRow) {
        do { try store.apply(.removeBudget, Args(["id": .string(budget.id)])); if selection == budget.id { selection = nil } }
        catch { errorMessage = i18nMessage(error) }
    }
}

/// The detail (third) column placeholder shown until the user picks a row.
struct DetailPlaceholder: View {
    let systemImage: String
    let label: LocalizedStringKey
    var body: some View {
        ContentUnavailableView(label, systemImage: systemImage)
    }
}
