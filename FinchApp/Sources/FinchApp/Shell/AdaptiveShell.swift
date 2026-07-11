import SwiftUI
import FinchCore

/// Phase 3 — one code base, three platforms. The chrome switches by horizontal
/// size class: iPhone (and iPad Slide Over / 1-3 split) keep the bottom tab bar;
/// iPad regular width + Mac get a sidebar + `NavigationSplitView`. The 6 tabs and
/// all Phase 2 write screens render in both. (Mac distribution target + menu bar
/// are deferred infra — see _PHASES_3_TO_8_OPEN_QUESTIONS.md.)
struct AdaptiveShell: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        Group {
            if sizeClass == .compact {
                TabBarShell()
            } else {
                SplitViewShell()
            }
        }
        .modifier(ExportCoordinator())
    }
}

/// The iPhone/compact shell — a five-slot bottom bar (Accounts, Budgets,
/// Scheduled, Insights, Settings). The Ledger is reached from a top-left
/// `books.vertical` corner control on every tab (`LedgerBarButton`) that pushes
/// the two-layer Ledger onto the current tab. `CompactTabRouting` bridges the bar
/// selection to the shared `DeepLinkRouter`; a `.ledger` router target (deep link
/// / ⌘K / intent / corner button) is converted to that push instead of selecting
/// a slot. Launch tab is Accounts.
struct TabBarShell: View {
    @EnvironmentObject private var router: DeepLinkRouter
    @EnvironmentObject private var store: FinchStore
    @State private var selected: CompactTab = .accounts

    var body: some View {
        TabView(selection: $selected) {
            tabContent(.accounts).modifier(AddTransactionFAB())
                .tabItem { Label(AppTab.accounts.title, systemImage: AppTab.accounts.icon) }
                .tag(CompactTab.accounts)
            tabContent(.budgets).modifier(AddTransactionFAB())
                .tabItem { Label(AppTab.budgets.title, systemImage: AppTab.budgets.icon) }
                .tag(CompactTab.budgets)
            tabContent(.scheduled).modifier(AddTransactionFAB())
                .tabItem { Label(AppTab.scheduled.title, systemImage: AppTab.scheduled.icon) }
                .tag(CompactTab.scheduled)
            tabContent(.insights).modifier(AddTransactionFAB())
                .tabItem { Label(AppTab.insights.title, systemImage: AppTab.insights.icon) }
                .tag(CompactTab.insights)
            tabContent(.settings)
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.icon) }
                .tag(CompactTab.settings)
        }
        // Activity is no longer a bottom-bar tab, but tx deep links / notifications
        // / Spotlight still route to `.activity` with a focused tx id — open that
        // transaction here (the bar lands on Accounts via CompactTabRouting).
        .sheet(item: focusedTx) { EditTransactionSheet(txn: $0) }
        .onAppear { syncFromRouter(router.selectedTab) }
        .onChange(of: router.selectedTab) { _, tab in syncFromRouter(tab) }
        .onChange(of: selected) { _, sel in
            router.showLedger = false
            if let tab = CompactTabRouting.routerTab(forSelected: sel, current: router.selectedTab) {
                router.selectedTab = tab
            }
        }
    }

    private func syncFromRouter(_ tab: AppTab) {
        // A `.ledger` route (deep link / ⌘K / intent / corner button) → push the
        // two-layer Ledger on the active tab; settle the bar on a real primary tab.
        if tab == .ledger {
            router.showLedger = true
            router.selectedTab = CompactTabRouting.appTab(for: selected) ?? .accounts
            return
        }
        let result = CompactTabRouting.sync(routerTab: tab, currentPath: [])
        if result.selected != .more, selected != result.selected { selected = result.selected }
    }

    /// A transaction targeted by a deep link / notification / Spotlight tap
    /// (router `.activity` + a focused tx id). Presenting clears the focus and
    /// settles the router on Accounts so the bar state stays consistent.
    private var focusedTx: Binding<Tx?> {
        Binding(
            get: {
                guard router.selectedTab == .activity, let id = router.focusedId else { return nil }
                return store.txns.first { $0.id == id }
            },
            set: { newValue in
                if newValue == nil {
                    router.focusedId = nil
                    if router.selectedTab == .activity { router.selectedTab = .accounts }
                }
            }
        )
    }
}

/// Set true by a tab whose content has entered multi-select (the Activity/Ledger
/// feed), so the floating add-`+` steps aside while the bulk-action bottom bar
/// occupies the bottom. Flows up from the content to the `AddTransactionFAB`
/// modifier that wraps it.
struct SelectionActiveKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// A floating "add transaction" button for the compact primary tabs — quick
/// capture from anywhere (it replaces the prominent `+` the removed Activity tab
/// used to provide). Triggers the same app-root sheet as ⌘N / the command
/// palette. Hidden until at least one account exists (you can't post without one).
/// The overlay sits inside the tab's content area, so it floats just above the
/// bottom bar automatically. Hidden while the content is in multi-select so it
/// doesn't overlap the bulk-action bar (see `SelectionActiveKey`).
private struct AddTransactionFAB: ViewModifier {
    @EnvironmentObject private var router: DeepLinkRouter
    @EnvironmentObject private var store: FinchStore
    @State private var selecting = false
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            // Hidden while the corner-pushed Ledger is up so that screen has the
            // same (FAB-free) chrome no matter which tab it was opened from.
            if !store.accounts.isEmpty, !selecting, !router.showLedger {
                Button { router.showAddTransaction = true } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor, in: Circle())
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                }
                .accessibilityLabel("Add Transaction")
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
        .onPreferenceChange(SelectionActiveKey.self) { selecting = $0 }
    }
}

/// The top-left Ledger control on every compact primary tab — pushes the
/// two-layer Ledger onto the current tab (via `.ledgerPush()`). Compact-only, so
/// the iPad/Mac sidebar (which lists Ledger itself) doesn't get a redundant
/// button. Drop one in each tab's `.toolbar`:
/// `ToolbarItem(placement: .topBarLeading) { LedgerBarButton() }`.
struct LedgerBarButton: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var router: DeepLinkRouter
    var body: some View {
        if sizeClass == .compact {
            Button { router.showLedger = true } label: { Image(systemName: "books.vertical") }
                .accessibilityLabel("Ledger")
        }
    }
}

/// Pushes the two-layer Ledger onto the enclosing NavigationStack when
/// `router.showLedger` is set (by the corner button or a `.ledger` route).
/// Compact-only — iPad/Mac reach the Ledger via the sidebar.
private struct LedgerPush: ViewModifier {
    @EnvironmentObject private var router: DeepLinkRouter
    @Environment(\.horizontalSizeClass) private var sizeClass
    func body(content: Content) -> some View {
        #if os(iOS)
        content.navigationDestination(isPresented: Binding(
            get: { sizeClass == .compact && router.showLedger },
            set: { if !$0 { router.showLedger = false } })) {
            LedgerListView()   // titles itself "Ledgers" — don't override with a second (dead) title
        }
        #else
        content
        #endif
    }
}

extension View {
    /// Apply inside a compact tab's NavigationStack so the top-left Ledger control
    /// (and a `.ledger` route) pushes the Ledger there.
    func ledgerPush() -> some View { modifier(LedgerPush()) }
}

/// The iPad/Mac shell. Accounts, Budgets, and Ledger get a true three-column
/// master–detail (sidebar │ list │ detail — see MasterDetailShell); the
/// dashboard / sheet-based tabs (Insights, Settings, Activity, Scheduled) keep
/// two columns (sidebar │ full-width content), which suits their wide layouts.
/// Selection persists per tab across section switches.
struct SplitViewShell: View {
    @EnvironmentObject private var router: DeepLinkRouter
    @EnvironmentObject private var store: FinchStore
    @State private var accountSelection: String?
    @State private var budgetSelection: String?
    @State private var ledgerSelection: String?

    var body: some View {
        Group {
            switch router.selectedTab {
            case .accounts:
                ThreeColumnShell {
                    AccountsTab(selection: $accountSelection)
                } detail: {
                    // Guard against a stale selection (e.g. after a ledger switch).
                    if let id = accountSelection, store.accounts.contains(where: { $0.id == id }) {
                        NavigationStack { AccountDetailView(accountId: id) }
                    } else {
                        DetailPlaceholder(systemImage: "creditcard", label: "Select an account")
                    }
                }
            case .budgets:
                ThreeColumnShell {
                    BudgetsTab(selection: $budgetSelection)
                } detail: {
                    if let id = budgetSelection, store.budgets.contains(where: { $0.id == id }) {
                        NavigationStack { BudgetDetailView(budgetId: id) }
                    } else {
                        DetailPlaceholder(systemImage: "chart.pie", label: "Select a budget")
                    }
                }
            case .ledger:
                ThreeColumnShell {
                    LedgerTab(selection: $ledgerSelection)
                } detail: {
                    // Guard against a stale selection (e.g. a deleted ledger).
                    if let id = ledgerSelection, store.ledgers.contains(where: { $0.id == id }) {
                        NavigationStack { LedgerDetailView(ledgerId: id) }
                    } else {
                        DetailPlaceholder(systemImage: "books.vertical", label: "Select a ledger")
                    }
                }
            default:
                NavigationSplitView {
                    SectionSidebar()
                } detail: {
                    tabContent(router.selectedTab)
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        // A ledger switch invalidates the per-tab selections. (`ledgerSelection`
        // deliberately survives — the ledger list is global, and "make active"
        // from the detail column must not eject the selection.)
        .onChange(of: store.activeLedgerId) { _, _ in
            accountSelection = nil
            budgetSelection = nil
        }
    }
}

/// The content view for a tab — shared by both shells.
@ViewBuilder
func tabContent(_ tab: AppTab) -> some View {
    switch tab {
    case .ledger: LedgerTab()
    case .accounts: AccountsTab()
    case .activity: ActivityTab()
    case .budgets: BudgetsTab()
    case .insights: InsightsTab()
    case .scheduled: ScheduledTab()
    case .settings: SettingsTab()
    }
}
