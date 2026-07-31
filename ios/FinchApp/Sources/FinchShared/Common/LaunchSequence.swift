import Foundation

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
        #endif

        store.isHydrating = true
        store.bootstrap()   // re-open the persisted live DB + project the active ledger
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

        // Phase 6.2: notifications
        NotificationService.shared.configure(store: store, router: router)
        await NotificationService.shared.requestPermissionIfNeeded()
        // `refresh()` plans budget/spend alerts from `store.txns` — await the deferred
        // projection or it plans from an empty list and schedules nothing. Detached so
        // it doesn't stall the trailing chores by ~600ms.
        Task { await store.awaitTxnsReady(); await NotificationService.shared.refresh() }

        AutoBackupManager.shared.configure(store: store)      // Phase 5
        ICloudSync.shared.start()                             // Phase 5: iCloud Drive sync
        await CloudKitSyncCoordinator.shared.start()          // Phase 8: row-level sync (scaffold; inert without an iCloud account)
        PendingAttachmentImporter.importPending(into: store)  // Phase 6.5: import shared receipts
    }
}
