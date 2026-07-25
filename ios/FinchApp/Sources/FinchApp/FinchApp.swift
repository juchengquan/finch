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
    @AppStorage(TextSize.systemKey) private var useSystemTextSize = true
    @AppStorage(TextSize.stepKey) private var textSizeStep = TextSize.defaultStep

    init() {
        #if DEBUG
        // Testing aid (DEBUG only — never in release): launch with
        // `-initialTab <accounts|activity|budgets|insights|scheduled|settings|ledger>`
        // to open straight to that tab (`ledger` resolves to the top-left corner
        // push, not a bar slot), so simulator screenshots / UI checks can
        // reach a non-default tab. Foundation maps `-key value` launch args into
        // UserDefaults' argument domain.
        if let raw = UserDefaults.standard.string(forKey: "initialTab"),
           let tab = AppTab(rawValue: raw) {
            DeepLinkRouter.shared.selectedTab = tab
        }
        // `-openAdd YES` opens the Add-transaction sheet on launch (same flag the
        // finch://add deep link sets) so sim screenshots can reach the sheet.
        if UserDefaults.standard.bool(forKey: "openAdd") {
            DeepLinkRouter.shared.showAddTransaction = true
        }
        // `-resetStore YES` wipes the live DB + App Group scratch before
        // FinchStore bootstraps so UI tests run hermetically. The XCTest
        // `isRunningTests` branch in FinchStore only protects *unit-test*
        // targets — UI tests launch a separate host-app process that does
        // NOT see XCTestCase, so the host process uses Application Support
        // and would clobber dev-sim data without an explicit reset. All
        // removes are `try?`-ignored so a clean install (no prior files)
        // is fine. DEBUG only — never ships to release.
        if UserDefaults.standard.bool(forKey: "resetStore") {
            Self.wipeLiveStateForTesting()
        }
        // `-disableNotifications YES` skips the permission prompt AND
        // NotificationService.refresh() at launch. The demo seed stamps
        // transactions dated `store.today`, so the planner fires budget
        // alerts immediately — the system banner blocks the accessibility
        // tree and breaks UI tests. DEBUG only — never ships to release.
        if UserDefaults.standard.bool(forKey: "disableNotifications") {
            Self.disableNotificationsForTesting = true
        }
        #endif
    }

    #if DEBUG
    /// In-memory flag the launch task reads to short-circuit notification
    /// scheduling. Toggled by the `-disableNotifications YES` launch arg in
    /// `init()`. Reset to `false` between test runs by process restart.
    private static var disableNotificationsForTesting = false
    #endif

    #if DEBUG
    /// Wipe the persistent live DB and the App Group scratch files. Intended
    /// only for the `-resetStore YES` UI-test launch flag; never call from
    /// production paths.
    private static func wipeLiveStateForTesting() {
        let fm = FileManager.default
        let dbBase = liveDBURLForTesting().deletingPathExtension()    // "finch"
        for ext in ["sqlite3", "sqlite3-wal", "sqlite3-shm"] {
            try? fm.removeItem(at: dbBase.appendingPathExtension(ext))
        }
        // AppGroup.containerURL falls back to Application Support when the
        // entitlement is absent (sim without App Group provisioning), so
        // removing the same directory again is harmless — but use the
        // shared AppGroup widget + pending paths so we only nuke files
        // we actually own.
        try? fm.removeItem(at: AppGroup.widgetSnapshotURL)
        try? fm.removeItem(at: AppGroup.containerURL.appendingPathComponent("pending_attachments"))
    }

    /// Mirror of `FinchStore.liveDBURL` *without* the XCTest temp-dir branch —
    /// the host app process spawned by UI tests does not see XCTestCase, so
    /// `isRunningTests` is false and `liveDBURL` already points at
    /// Application Support. Read it directly here to avoid coupling to
    /// FinchStore's private bootstrapping.
    private static func liveDBURLForTesting() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("finch.sqlite3")
    }
    #endif

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
            .modifier(TextSizeModifier(useSystem: useSystemTextSize, step: textSizeStep))
            .onReceive(idleTimer) { _ in gate.tick() }
            .task {
                store.isHydrating = true
                store.bootstrap()   // re-open the persisted live DB on launch
                #if os(iOS)
                PhoneWatchLink.shared.activate()   // Watch CP1: WCSession link
                #endif
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
                #if DEBUG
                if !Self.disableNotificationsForTesting {
                    await NotificationService.shared.requestPermissionIfNeeded()
                    await NotificationService.shared.refresh()
                }
                #else
                await NotificationService.shared.requestPermissionIfNeeded()
                await NotificationService.shared.refresh()
                #endif
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
                    Task { await AutoBackupManager.shared.backupIfDue() }   // Phase 5: throttled backup before kill (local daily, folder per frequency)
                case .active:
                    gate.didBecomeActive()
                    // Daily FX refresh (Frankfurter) — lock-gated like Spotlight below.
                    if !gate.isLocked { Task { await RateAutoUpdater.refreshIfDue(store: store) } }
                default: break
                }
            }
            #if os(macOS)
            .frame(minWidth: 720, minHeight: 480)   // keep the split view usable
            #endif
            // When the biometric lock engages, dismiss the global sheets so they
            // can't sit on top of the lock cover (the cover is a ZStack sibling).
            .onChange(of: gate.isLocked) { _, locked in
                if locked {
                    router.showCommandPalette = false; router.showAddTransaction = false
                    router.pendingAddAccountId = nil; router.pendingAddCategoryId = nil
                }
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
            .sheet(isPresented: $router.showAddTransaction, onDismiss: {
                router.pendingAddAccountId = nil; router.pendingAddCategoryId = nil
            }) {
                AddTransactionSheet(defaultAccountId: router.pendingAddAccountId,
                                    defaultCategoryId: router.pendingAddCategoryId)
                    .environmentObject(store).environmentObject(router)
            }
            // App-wide transient confirmations (ToastCenter). Hosted once, here.
            .toastOverlay()
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

        #if os(macOS)
        Settings {
            NavigationStack { SettingsRootList() }
                .environmentObject(store)
                .environmentObject(router)
                .environmentObject(gate)
                .frame(minWidth: 520, minHeight: 420)
        }
        #endif
    }
}

// The 6-tab shell now lives in Shell/AdaptiveShell.swift (Phase 3): TabBarShell
// for compact width, SplitViewShell for regular. Canonical order: Accounts,
// Activity, Budgets, Insights, Scheduled, Settings (a future Reports tab slots
// between Insights and Scheduled).
