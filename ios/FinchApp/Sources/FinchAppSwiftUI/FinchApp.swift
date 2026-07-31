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
    @AppStorage(TextSize.stepKey) private var textSizeStep = TextSize.defaultStep

    init() {
        // The "Use system size" toggle is gone; seed the slider for anyone
        // upgrading from it BEFORE the first frame reads the preference.
        TextSize.migrateLegacySystemPreference(systemStep: TextSize.currentSystemStep)
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
            .modifier(TextSizeModifier(step: textSizeStep))
            .onReceive(idleTimer) { _ in gate.tick() }
            // Shared with the iOS UIKit entry point — see LaunchSequence, which owns
            // the ordering that keeps first paint off the heavy chores.
            .task { await LaunchSequence.run(store: store, router: router, gate: gate) }
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
