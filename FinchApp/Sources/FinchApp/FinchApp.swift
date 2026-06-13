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
        }
    }
}

/// The 4-tab shell. Mirrors Phase 1.0 §5.
struct ContentTabs: View {
    var body: some View {
        TabView {
            AccountsTab()
                .tabItem { Label("Accounts", systemImage: "wallet.pass") }
            ActivityTab()
                .tabItem { Label("Activity", systemImage: "list.bullet") }
            BudgetsTab()
                .tabItem { Label("Budgets", systemImage: "chart.pie") }
            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
