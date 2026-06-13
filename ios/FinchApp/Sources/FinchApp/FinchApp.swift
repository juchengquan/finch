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
                AdaptiveShell()   // Phase 3: tab bar (compact) ↔ sidebar+split (regular)
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
                AutoBackupManager.shared.configure(store: store)   // Phase 5
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                    router.route(to: id)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    gate.didEnterBackground()
                    Task { await AutoBackupManager.shared.flush() }   // Phase 5: flush before kill
                case .active: gate.didBecomeActive()
                default: break
                }
            }
        }
    }
}

// The 6-tab shell now lives in Shell/AdaptiveShell.swift (Phase 3): TabBarShell
// for compact width, SplitViewShell for regular. Canonical order: Accounts,
// Activity, Budgets, Insights, Scheduled, Settings (a future Reports tab slots
// between Insights and Scheduled).
