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
            .modifier(TextSizeModifier(useSystem: useSystemTextSize, step: textSizeStep))
            .onReceive(idleTimer) { _ in gate.tick() }
            .task {
                #if DEBUG
                LaunchTiming.begin()
                #endif
                store.isHydrating = true
                store.bootstrap()   // re-open the persisted live DB + project the active ledger
                #if os(iOS)
                PhoneWatchLink.shared.activate()   // Watch CP1: WCSession link
                #endif
                gate.start()        // Phase 6.3: evaluate the lock BEFORE revealing content
                // FIRST PAINT: the projection is ready, so drop the "Loading…" spinner
                // now. The heavy launch chores below no longer gate the UI.
                store.isHydrating = false
                #if DEBUG
                LaunchTiming.mark("first paint")
                #endif

                // Deferred off the first-paint path — both of these used to block the
                // spinner on every launch:
                //   • Audit — a full ledger sweep that only feeds the Settings indicator.
                //   • Spotlight — a full delete-all + re-index of every entity. Kept
                //     lock-gated (don't expose data to system search while locked); the
                //     lock-transition handler re-indexes on unlock.
                store.runAuditInBackground()
                if !gate.isLocked {
                    Task(priority: .utility) {
                        // Spotlight snapshots store.txns; on launch that projection is
                        // deferred off first paint, so wait for it or we'd index an empty
                        // txns set and leave transactions unsearchable until the next write.
                        await store.awaitTxnsReady()
                        await SpotlightIndexer.shared.indexAll(store: store)
                        #if DEBUG
                        LaunchTiming.mark("spotlight done")
                        #endif
                    }
                }
                // Phase 6.2: notifications
                NotificationService.shared.configure(store: store, router: router)
                await NotificationService.shared.requestPermissionIfNeeded()
                // refresh() plans budget/spend alerts from store.txns — await the
                // launch-deferred projection so we don't plan from an empty list.
                // Detached so it doesn't stall the trailing launch chores ~600ms.
                Task { await store.awaitTxnsReady(); await NotificationService.shared.refresh() }
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
