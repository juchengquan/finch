import SwiftUI
import FinchCore

// The Xcode app target's entry point (Task 12 / XcodeGen). NOT a SwiftPM target
// — `swift build` does not compile it; it's built via FinchApp.xcodeproj.
@main
struct FinchApp: App {
    @StateObject private var store = FinchStore.shared

    var body: some Scene {
        WindowGroup {
            ContentTabs()
                .environmentObject(store)
                .task { store.bootstrap() }   // re-open the persisted live DB on launch
        }
    }
}

/// The 6-tab shell, in the canonical display order: Accounts, Activity, Budgets,
/// Insights (1.5), Scheduled (2), Settings. A future Reports tab slots between
/// Insights and Scheduled (not built yet).
struct ContentTabs: View {
    var body: some View {
        TabView {
            AccountsTab()
                .tabItem { Label("Accounts", systemImage: "wallet.pass") }
            ActivityTab()
                .tabItem { Label("Activity", systemImage: "list.bullet") }
            BudgetsTab()
                .tabItem { Label("Budgets", systemImage: "chart.pie") }
            InsightsTab()   // NEW in Phase 1.5
                .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }
            ScheduledTab()   // NEW in Phase 2
                .tabItem { Label("Scheduled", systemImage: "calendar") }
            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
