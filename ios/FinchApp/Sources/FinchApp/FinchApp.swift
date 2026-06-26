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
    // Foreground idle timer so an `.onIdle` lock timeout fires while the app
    // stays open; tick() is a no-op for the other policies.
    private let idleTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    @AppStorage("finch.appearance") private var appearanceRaw = AppearancePreference.system.rawValue

    init() {
        #if DEBUG
        // Testing aid (DEBUG only — never in release): launch with
        // `-initialTab <accounts|activity|budgets|insights|scheduled|settings>`
        // to open straight to that tab, so simulator screenshots / UI checks can
        // reach a non-default tab. Foundation maps `-key value` launch args into
        // UserDefaults' argument domain.
        if let raw = UserDefaults.standard.string(forKey: "initialTab"),
           let tab = AppTab(rawValue: raw) {
            DeepLinkRouter.shared.selectedTab = tab
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                AdaptiveShell()   // Phase 3: tab bar (compact) ↔ sidebar+split (regular)
                    .environmentObject(store)
                    .environmentObject(router)
                    .environmentObject(gate)
                // Reset the idle clock on interaction. Uses a platform-level
                // passive observer (ActivityMonitor) instead of a SwiftUI
                // `.simultaneousGesture(TapGesture())`, which swallowed taps on
                // List rows / NavigationLinks and broke drill-in navigation.
                ActivityMonitor()
                if gate.isLocked {   // Phase 6.3: biometric cover
                    LockView().environmentObject(gate)
                }
                if store.isImporting || store.isHydrating {
                    ProgressView(store.isImporting ? "Importing…" : "Loading…")
                        .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .preferredColorScheme((AppearancePreference(rawValue: appearanceRaw) ?? .system).colorScheme)
            .onReceive(idleTimer) { _ in gate.tick() }
            .task {
                store.isHydrating = true
                store.bootstrap()   // re-open the persisted live DB on launch
                gate.start()        // Phase 6.3: evaluate lock state
                // Don't expose financial data in system-wide Spotlight while the
                // app is locked — index only when unlocked (the lock-transition
                // handler below clears on lock and re-indexes on unlock).
                if !gate.isLocked {
                    await SpotlightIndexer.shared.indexAll(store: store)   // Phase 6.1 (can be slow on large data)
                }
                store.isHydrating = false
                // Phase 6.2: notifications
                NotificationService.shared.configure(store: store, router: router)
                await NotificationService.shared.requestPermissionIfNeeded()
                await NotificationService.shared.refresh()
                AutoBackupManager.shared.configure(store: store)   // Phase 5
                ICloudSync.shared.start()                           // Phase 5: iCloud Drive sync
                await CloudKitSyncCoordinator.shared.start()        // Phase 8: row-level sync (scaffold; inert without an iCloud account)
                PendingAttachmentImporter.importPending(into: store)   // Phase 6.5: import shared receipts
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                    router.route(to: id)
                }
            }
            .onOpenURL { router.handle($0) }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    gate.didEnterBackground()
                    Task { await AutoBackupManager.shared.flush() }   // Phase 5: flush before kill
                case .active: gate.didBecomeActive()
                default: break
                }
            }
            #if os(macOS)
            .frame(minWidth: 720, minHeight: 480)   // keep the split view usable
            #endif
            // When the biometric lock engages, dismiss the global sheets so they
            // can't sit on top of the lock cover (the cover is a ZStack sibling).
            .onChange(of: gate.isLocked) { _, locked in
                if locked { router.showCommandPalette = false; router.showAddTransaction = false }
                // Privacy: drop the Spotlight index while locked; rebuild it on unlock.
                Task {
                    if locked { await SpotlightIndexer.shared.clearAll() }
                    else { await SpotlightIndexer.shared.indexAll(store: store) }
                }
            }
            // Surface a non-recoverable load/migration/projection failure.
            .alert("Data problem", isPresented: Binding(
                get: { store.dataError != nil },
                set: { if !$0 { store.dataError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.dataError ?? "")
            }
            // Phase 3 (Mac/⌘K): global palette + new-transaction presentation.
            .sheet(isPresented: $router.showCommandPalette) {
                CommandPalette().environmentObject(router)
            }
            .sheet(isPresented: $router.showAddTransaction) {
                AddTransactionSheet().environmentObject(store).environmentObject(router)
            }
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
        #endif
        .commands {
            FinchCommands()
            #if os(macOS)
            SidebarCommands()   // ⌃⌘S toggle sidebar + a View menu entry
            #endif
        }
    }
}

// The 6-tab shell now lives in Shell/AdaptiveShell.swift (Phase 3): TabBarShell
// for compact width, SplitViewShell for regular. Canonical order: Accounts,
// Activity, Budgets, Insights, Scheduled, Settings (a future Reports tab slots
// between Insights and Scheduled).
