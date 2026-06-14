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

/// The iPhone/compact shell — the existing bottom tab bar (Phase 1.0/1.5/2),
/// driven by the shared `DeepLinkRouter` so deep links / intents select tabs.
struct TabBarShell: View {
    @EnvironmentObject private var router: DeepLinkRouter
    var body: some View {
        TabView(selection: Binding(get: { router.selectedTab }, set: { router.selectedTab = $0 })) {
            ForEach(AppTab.allCases) { tab in
                tabContent(tab)
                    .tabItem { Label(tab.title, systemImage: tab.icon) }
                    .tag(tab)
            }
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
                    AccountsListColumn(selection: $accountSelection)
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
                    BudgetsListColumn(selection: $budgetSelection)
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
