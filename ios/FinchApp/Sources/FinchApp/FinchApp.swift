import SwiftUI
import CoreSpotlight
import FinchCore

// The Xcode app target's entry point (Task 12 / XcodeGen). NOT a SwiftPM target
// — `swift build` does not compile it; it's built via FinchApp.xcodeproj.
@main
struct FinchApp: App {
    @StateObject private var store = FinchStore.shared
    @StateObject private var router = DeepLinkRouter.shared
    @StateObject private var gate = BiometricGate.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentTabs()
                    .environmentObject(store)
                    .environmentObject(router)
                    .environmentObject(gate)
                if gate.isLocked {   // Phase 6.3: biometric cover
                    LockView().environmentObject(gate)
                }
            }
            .task {
                store.bootstrap()   // re-open the persisted live DB on launch
                gate.start()        // Phase 6.3: evaluate lock state
                await SpotlightIndexer.shared.indexAll(store: store)   // Phase 6.1
                // Phase 6.2: notifications
                NotificationService.shared.configure(store: store, router: router)
                await NotificationService.shared.requestPermissionIfNeeded()
                await NotificationService.shared.refresh()
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                    router.route(to: id)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: gate.didEnterBackground()
                case .active: gate.didBecomeActive()
                default: break
                }
            }
        }
    }
}

/// The 6-tab shell, in the canonical display order: Accounts, Activity, Budgets,
/// Insights (1.5), Scheduled (2), Settings. A future Reports tab slots between
/// Insights and Scheduled (not built yet).
struct ContentTabs: View {
    @EnvironmentObject private var router: DeepLinkRouter
    var body: some View {
        TabView(selection: Binding(get: { router.selectedTab }, set: { router.selectedTab = $0 })) {
            AccountsTab()
                .tabItem { Label("Accounts", systemImage: "wallet.pass") }.tag(AppTab.accounts)
            ActivityTab()
                .tabItem { Label("Activity", systemImage: "list.bullet") }.tag(AppTab.activity)
            BudgetsTab()
                .tabItem { Label("Budgets", systemImage: "chart.pie") }.tag(AppTab.budgets)
            InsightsTab()   // NEW in Phase 1.5
                .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }.tag(AppTab.insights)
            ScheduledTab()   // NEW in Phase 2
                .tabItem { Label("Scheduled", systemImage: "calendar") }.tag(AppTab.scheduled)
            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gear") }.tag(AppTab.settings)
        }
    }
}
