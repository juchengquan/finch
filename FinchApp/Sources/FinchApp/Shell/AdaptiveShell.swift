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

/// The iPad/Mac shell — a sidebar of the 6 tabs + a detail column rendering the
/// selected tab. Detail-screen drill-in (Transaction/Account Detail) lands with
/// Phase 4's detail views; until then the detail column shows the tab itself.
struct SplitViewShell: View {
    @EnvironmentObject private var router: DeepLinkRouter
    var body: some View {
        NavigationSplitView {
            List(AppTab.allCases, selection: Binding<AppTab?>(
                get: { router.selectedTab },
                set: { if let t = $0 { router.selectedTab = t } })) { tab in
                Label(tab.title, systemImage: tab.icon)
            }
            .navigationTitle("finch")
            .listStyle(.sidebar)
        } detail: {
            tabContent(router.selectedTab)
        }
        .navigationSplitViewStyle(.balanced)
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
