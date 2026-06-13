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

/// The tab shell. Phase 2 adds Scheduled (the 6th, writable tab).
struct ContentTabs: View {
    var body: some View {
        TabView {
            AccountsTab()
                .tabItem { Label("Accounts", systemImage: "wallet.pass") }
            ActivityTab()
                .tabItem { Label("Activity", systemImage: "list.bullet") }
            BudgetsTab()
                .tabItem { Label("Budgets", systemImage: "chart.pie") }
            ScheduledTab()   // NEW in Phase 2
                .tabItem { Label("Scheduled", systemImage: "calendar") }
            InsightsTab()   // NEW in Phase 1.5
                .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }
            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
