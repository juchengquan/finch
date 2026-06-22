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
        if sizeClass == .compact {
            TabBarShell()
        } else {
            SplitViewShell()
        }
    }
}

/// The iPhone/compact shell — a four-slot bottom bar (Accounts, Budgets,
/// Scheduled, Insights). PROTOTYPE: the "More" tab is gone; Settings is reached
/// from a top-leading gear on every page (`SettingsBarButton`) that presents the
/// Settings screen as a sheet. `CompactTabRouting` still bridges the bar
/// selection to the shared `DeepLinkRouter`; a `.settings` router target (deep
/// link / ⌘K / intent) now presents the sheet instead of selecting a tab.
struct TabBarShell: View {
    @EnvironmentObject private var router: DeepLinkRouter
    @EnvironmentObject private var store: FinchStore
    @State private var selected: CompactTab = .ledger

    var body: some View {
        TabView(selection: $selected) {
            tabContent(.ledger).modifier(AddTransactionFAB())
                .tabItem { Label(AppTab.ledger.title, systemImage: AppTab.ledger.icon) }
                .tag(CompactTab.ledger)
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
        }
        // Activity is no longer a bottom-bar tab, but tx deep links / notifications
        // / Spotlight still route to `.activity` with a focused tx id — open that
        // transaction here (the bar lands on Accounts via CompactTabRouting).
        .sheet(item: focusedTx) { EditTransactionSheet(txn: $0) }
        // PROTOTYPE: Settings as a modal, opened by the top-left gear or a
        // `.settings` router target (deep link / ⌘K / intent).
        .sheet(isPresented: settingsSheet) {
            NavigationStack {
                SettingsTab()
                    #if os(iOS)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { settingsSheet.wrappedValue = false } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("Close")
                        }
                    }
                    #endif
            }
        }
        .onAppear { syncFromRouter(router.selectedTab) }
        .onChange(of: router.selectedTab) { _, tab in syncFromRouter(tab) }
        .onChange(of: selected) { _, sel in
            if let tab = CompactTabRouting.routerTab(forSelected: sel, current: router.selectedTab) {
                router.selectedTab = tab
            }
        }
    }

    /// Mirror a (possibly programmatic) router selection onto the bar. A
    /// `.settings` target is handled by `settingsSheet` (it has no bottom slot),
    /// so skip it here and leave the bar on its current primary tab.
    private func syncFromRouter(_ tab: AppTab) {
        guard tab != .settings else { return }
        let result = CompactTabRouting.sync(routerTab: tab, currentPath: [])
        if result.selected != .more, selected != result.selected { selected = result.selected }
    }

    /// Presents the Settings sheet for the top-left gear (`showSettings`) or a
    /// `.settings` router target; dismissing resets both so re-triggering works.
    private var settingsSheet: Binding<Bool> {
        Binding(
            get: { router.showSettings || router.selectedTab == .settings },
            set: { presented in
                if !presented {
                    router.showSettings = false
                    if router.selectedTab == .settings {
                        router.selectedTab = CompactTabRouting.appTab(for: selected) ?? .accounts
                    }
                }
            }
        )
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
                    if router.selectedTab == .activity { router.selectedTab = .ledger }
                }
            }
        )
    }
}

/// A floating "add transaction" button for the compact primary tabs — quick
/// capture from anywhere (it replaces the prominent `+` the removed Activity tab
/// used to provide). Triggers the same app-root sheet as ⌘N / the command
/// palette. Hidden until at least one account exists (you can't post without one).
/// The overlay sits inside the tab's content area, so it floats just above the
/// bottom bar automatically.
private struct AddTransactionFAB: ViewModifier {
    @EnvironmentObject private var router: DeepLinkRouter
    @EnvironmentObject private var store: FinchStore
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            if !store.accounts.isEmpty {
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
    }
}

/// PROTOTYPE: the top-leading gear shown on every compact primary tab. Replaces
/// the removed "More" tab — tapping it presents Settings as a sheet (handled by
/// `TabBarShell`). Compact-only, so the iPad/Mac sidebar (which lists Settings
/// itself) doesn't get a redundant button. Drop one in each tab's `.toolbar`:
/// `ToolbarItem(placement: .topBarLeading) { SettingsBarButton() }`.
struct SettingsBarButton: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var router: DeepLinkRouter
    var body: some View {
        if sizeClass == .compact {
            Button { router.showSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Settings")
        }
    }
}

/// The iPad/Mac shell. Accounts and Budgets get a true three-column
/// master–detail (sidebar │ list │ detail — see MasterDetailShell); the
/// dashboard / sheet-based tabs (Insights, Settings, Activity, Scheduled) keep
/// two columns (sidebar │ full-width content), which suits their wide layouts.
/// Selection persists per tab across section switches.
struct SplitViewShell: View {
    @EnvironmentObject private var router: DeepLinkRouter
    @EnvironmentObject private var store: FinchStore
    @State private var accountSelection: String?
    @State private var budgetSelection: String?

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
            default:
                NavigationSplitView {
                    SectionSidebar()
                } detail: {
                    tabContent(router.selectedTab)
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        // A ledger switch invalidates the per-tab selections.
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
