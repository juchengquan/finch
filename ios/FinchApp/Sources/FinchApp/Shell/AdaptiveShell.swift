import SwiftUI

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

/// The iPhone/compact shell — a five-slot bottom bar: four primary tabs plus a
/// custom More tab (`MoreTabRoot`) that hosts Scheduled & Settings. This avoids
/// SwiftUI's system "More" overflow (which dropped titles / doubled the back
/// button on those screens). `CompactTabRouting` bridges the bar selection and
/// the More tab's push path to the shared `DeepLinkRouter`, so deep links /
/// intents / notifications / ⌘K still land on the right screen.
struct TabBarShell: View {
    @EnvironmentObject private var router: DeepLinkRouter
    @State private var selected: CompactTab = .accounts
    @State private var morePath: [AppTab] = []

    var body: some View {
        TabView(selection: $selected) {
            tabContent(.accounts)
                .tabItem { Label(AppTab.accounts.title, systemImage: AppTab.accounts.icon) }
                .tag(CompactTab.accounts)
            tabContent(.activity)
                .tabItem { Label(AppTab.activity.title, systemImage: AppTab.activity.icon) }
                .tag(CompactTab.activity)
            tabContent(.budgets)
                .tabItem { Label(AppTab.budgets.title, systemImage: AppTab.budgets.icon) }
                .tag(CompactTab.budgets)
            tabContent(.insights)
                .tabItem { Label(AppTab.insights.title, systemImage: AppTab.insights.icon) }
                .tag(CompactTab.insights)
            MoreTabRoot(path: $morePath)
                .tabItem { Label("More", systemImage: "ellipsis") }
                .tag(CompactTab.more)
        }
        .onAppear { syncFromRouter(router.selectedTab) }
        // `selectedTab` is @Published, so this only fires on a value *change*: a
        // repeat selection of the already-current tab (e.g. a second Scheduled
        // notification while already on More→Scheduled) won't re-push or pop.
        // Matches the prior system-More behavior; acceptable.
        .onChange(of: router.selectedTab) { _, tab in syncFromRouter(tab) }
        .onChange(of: selected) { _, sel in
            if let tab = CompactTabRouting.routerTab(forSelected: sel, current: router.selectedTab) {
                router.selectedTab = tab
            }
        }
    }

    /// Mirror a (possibly programmatic) router selection onto the bar + More path.
    private func syncFromRouter(_ tab: AppTab) {
        let result = CompactTabRouting.sync(routerTab: tab, currentPath: morePath)
        if selected != result.selected { selected = result.selected }
        if morePath != result.path { morePath = result.path }
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
    case .accounts: AccountsTab()
    case .activity: ActivityTab()
    case .budgets: BudgetsTab()
    case .insights: InsightsTab()
    case .scheduled: ScheduledTab()
    case .settings: SettingsTab()
    }
}
