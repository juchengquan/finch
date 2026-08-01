import Foundation
import FinchCore   // AppGroup, for the -resetStore wipe

/// The app's launch chores, in one place, because there are two entry points.
///
/// iOS boots from `UIKitShell`'s scene delegate; macOS boots from the SwiftUI
/// `FinchApp.task`. Phase 1 of the UIKit migration copied this sequence across by
/// hand — "the same work in the same order", as its comment put it — and that is
/// exactly how it went wrong: the launch-performance fix (#641) landed on the SwiftUI
/// copy alone, so the Mac got a fast launch and the iPhone kept blocking its spinner
/// on a full Spotlight re-index. Both entry points now call this. The order cannot
/// drift again because there is only one copy of it.
///
/// **The order is load-bearing.** `store.isHydrating` gates the "Loading…" overlay in
/// both shells — SwiftUI's at `FinchApp.swift`, UIKit's in `GlobalOverlay` — so every
/// line above `isHydrating = false` sits on the first-paint path and every line below
/// it does not. Measured at 20k legs: first paint went 637ms → 16ms by moving three
/// chores below that line. Adding work above it is a launch regression; if something
/// must run early, prove it with `LaunchTiming` marks rather than assuming.
@MainActor
enum LaunchSequence {

    static func run(store: FinchStore, router: DeepLinkRouter, gate: BiometricGate) async {
        #if DEBUG
        LaunchTiming.begin()

        // UI-test launch flags. They live HERE, above `bootstrap()`, for two reasons:
        // the wipe must happen before the database is opened (bootstrap is what opens
        // it — `FinchStore.init` is empty), and both entry points must honour them.
        // Putting them in the SwiftUI `App.init` is what made them dead code on iOS.
        if UserDefaults.standard.bool(forKey: "resetStore") {
            wipeLiveStateForTesting(store)
        }
        let disableNotifications = UserDefaults.standard.bool(forKey: "disableNotifications")

        // The navigation launch flags, for the same reason and by the same rule.
        // `-initialTab <accounts|activity|budgets|insights|scheduled|settings|ledger>`
        // opens straight to that tab, so simulator screenshots and UI checks can reach a
        // non-default one; `ledger` is not a bar slot, and both shells resolve it to the
        // corner push. `-openAdd YES` opens the Add-transaction sheet, the same state the
        // `finch://add` deep link sets. Foundation maps `-key value` launch arguments into
        // UserDefaults' argument domain.
        //
        // These sat in the SwiftUI `App.init` until now, which is precisely the dead-code
        // trap described above: `FinchApp.swift` is excluded from the iOS target, so the
        // flags worked on macOS and silently did nothing on iOS — the platform they exist
        // to drive. Setting the state here, before first paint, is picked up by both
        // shells: SwiftUI observes the router directly, and the UIKit shell's `bindRouter`
        // sinks on `$selectedTab` / `$showAddTransaction`.
        if let raw = UserDefaults.standard.string(forKey: "initialTab"),
           let tab = AppTab(rawValue: raw) {
            router.selectedTab = tab
        }
        if UserDefaults.standard.bool(forKey: "openAdd") {
            router.showAddTransaction = true
        }
        #else
        let disableNotifications = false
        #endif

        store.isHydrating = true
        store.bootstrap()   // re-open the persisted live DB + project the active ledger

        #if DEBUG
        // `-routeTo "account:everyday"` drives the SAME path a widget tap, a Spotlight
        // result or an App Intent takes — `route(to:)` picks the tab and sets
        // `focusedId`, and each converted list has a `focusedId` sink that pushes or
        // selects. Nothing could reach that path from a test before: `-initialTab` only
        // chooses a tab, and the `finch://` scheme handles `add` and nothing else, so
        // "a deep link opens the right record" was unverifiable rather than unverified.
        //
        // BELOW `bootstrap()`, unlike the flags above, and the placement is the whole
        // point: a real deep link arrives at a running app with its data loaded. Setting
        // `focusedId` above instead routes into an EMPTY store, every list's
        // `consumeFocus` finds no such record and drops it, and the test then reports a
        // broken deep link that no user could ever hit. Identifier shape is
        // `route(to:)`'s own: `<kind>:<id>`.
        if let target = UserDefaults.standard.string(forKey: "routeTo") {
            router.route(to: target)
        }
        #endif
        #if os(iOS)
        PhoneWatchLink.shared.activate()   // Watch CP1: WCSession link
        #endif
        gate.start()        // Phase 6.3: evaluate the lock BEFORE revealing content

        // FIRST PAINT. `bootstrap()` has published the cheap projection slices
        // (accounts, budgets, categories — each ~1ms), which is everything the launch
        // tab needs: balances and net worth read the stored `current_balance` column,
        // not the txns list. So drop the spinner here; the txns projection is still in
        // flight and lands via `txnsReady`.
        store.isHydrating = false
        #if DEBUG
        LaunchTiming.mark("first paint")
        #endif

        // Deferred off the first-paint path — these used to block the spinner on every
        // launch:
        //   • Audit — a full ledger sweep that only feeds the Settings "N problems"
        //     indicator, which nothing on screen at launch reads.
        //   • Spotlight — a full delete-all + re-index of every entity. Stays
        //     lock-gated: don't expose financial data to system-wide search while the
        //     app is locked. The lock-transition handler re-indexes on unlock.
        store.runAuditInBackground()
        if !gate.isLocked {
            Task(priority: .utility) {
                // Spotlight snapshots `store.txns`, and on launch that projection is
                // deferred — index without waiting and every transaction is missing
                // from system search until the next write happens to re-index.
                await store.awaitTxnsReady()
                await SpotlightIndexer.shared.indexAll(store: store)
                #if DEBUG
                LaunchTiming.mark("spotlight done")
                #endif
            }
        }

        // Phase 6.2: notifications. `configure` is always wired — it only installs the
        // delegate — but the prompt and the planner are skipped under
        // `-disableNotifications YES`: the demo seed dates transactions at
        // `store.today`, so the planner fires a budget alert immediately and the system
        // banner covers the accessibility tree a UI test is reading.
        NotificationService.shared.configure(store: store, router: router)
        if !disableNotifications {
            await NotificationService.shared.requestPermissionIfNeeded()
            // `refresh()` plans budget/spend alerts from `store.txns` — await the
            // deferred projection or it plans from an empty list and schedules nothing.
            // Detached so it doesn't stall the trailing chores by ~600ms.
            Task { await store.awaitTxnsReady(); await NotificationService.shared.refresh() }
        }

        AutoBackupManager.shared.configure(store: store)      // Phase 5
        ICloudSync.shared.start()                             // Phase 5: iCloud Drive sync
        await CloudKitSyncCoordinator.shared.start()          // Phase 8: row-level sync (scaffold; inert without an iCloud account)
        PendingAttachmentImporter.importPending(into: store)  // Phase 6.5: import shared receipts
    }

    #if DEBUG
    /// Wipe the persistent live DB and App Group scratch, for `-resetStore YES` only.
    ///
    /// UI tests launch a SEPARATE host-app process, which does NOT load `XCTestCase` —
    /// so `FinchStore.isRunningTests` is false there and `liveDBURL` points at the real
    /// Application Support database, not the temp-dir one that protects unit tests.
    /// Without this a UI-test run would seed and mutate a development simulator's own
    /// data.
    ///
    /// The paths are DERIVED from `store.liveDBURL` rather than rebuilt by hand. A
    /// hand-mirrored copy of that path is silently wrong the day `liveDBURL` changes,
    /// and "silently wrong" here means wiping the wrong directory or wiping nothing.
    private static func wipeLiveStateForTesting(_ store: FinchStore) {
        let fm = FileManager.default
        let db = store.liveDBURL
        // WAL mode keeps committed frames in the sidecars; removing only the main file
        // leaves them to be replayed into the "fresh" database on the next open.
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: db.path + suffix))
        }
        try? fm.removeItem(at: AppGroup.widgetSnapshotURL)
        try? fm.removeItem(at: AppGroup.containerURL.appendingPathComponent("pending_attachments"))
        // The remembered ledger lives in UserDefaults, NOT in the database, so deleting
        // the file alone does not reset it — and the reseed reuses the same ledger ids,
        // so a run that switched to "travel" comes back up in Travel on every launch
        // afterwards, including the next test run. `-resetStore YES` has to mean a clean
        // slate or it is worse than nothing: a UI suite then fails with "no 'Checking'
        // row", which reads as the app being broken rather than as leftover state.
        UserDefaults.standard.removeObject(forKey: FinchStore.activeLedgerKey)
    }
    #endif
}
