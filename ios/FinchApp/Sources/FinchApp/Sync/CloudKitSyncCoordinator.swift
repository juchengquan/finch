import Foundation
import CloudKit
import FinchCore

// Phase 8 scaffold — the single user-facing sync control, the status model the
// Settings UI renders, the daemon skeleton, and the (pure) bootstrap table set.
//
// The LIVE network loop (delta pull, CKSubscription push, CKSyncEngine state
// serialization, the chokepoint→CloudKit mutation bus) is deliberately NOT built
// here. Per the Phase 8 design §5.1, writing it before the CloudKit container is
// provisioned (paid Apple Developer Program + a real iCloud account) would be
// "coding blind" — it compiles but can't be run or trusted, and would likely
// need rework once real CloudKit behavior is observed. Everything below is the
// CI-verifiable scaffold; the spots that resume after provisioning are marked
// `PROVISIONING-GATED`.
//
// Note: the Phase 5 iCloud-Drive *file* sync stays active for now. The design
// (§3.2) retires it only when CloudKit goes live — removing the working sync
// before its replacement functions would lose real multi-device sync.

/// The single sync switch. Stored per-device in UserDefaults (NOT app_state): a
/// synced "is sync on" flag would be circular, and each device decides locally
/// whether to participate. Same pattern as NotificationPrefs / BiometricSettings.
public enum SyncPreferences {
    private static let key = "finch.sync.enabled"
    public static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// The canonical tables row-level sync mirrors — every shared table except
/// `app_state` (per-device prefs: display currency, sync flag, …). Pure/derived.
public enum CloudKitBootstrap {
    public static let tables: [String] = Projection.canonicalTables.filter { $0 != "app_state" }
}

/// Status surfaced in Settings › Sync (design §4 mockup).
public struct SyncStatus: Equatable, Sendable {
    public var accountAvailable = false
    public var subscribedLedgers = 0
    public var pendingChanges = 0
    public var lastSyncAt: Date?
    public var lastError: String?
    public static let idle = SyncStatus()
}

/// The sync daemon's lifecycle + status. Owns the on/off switch and the status
/// the Settings section renders. Live CloudKit calls route through
/// `CloudKitSyncService`, which no-ops without an available iCloud account, so
/// this whole object is safe (and inert) on an unsigned simulator / in CI.
@MainActor
public final class CloudKitSyncCoordinator: ObservableObject {
    public static let shared = CloudKitSyncCoordinator()

    @Published public private(set) var enabled = SyncPreferences.enabled
    @Published public private(set) var status = SyncStatus.idle
    @Published public private(set) var isBootstrapping = false

    private let service = CloudKitSyncService.shared

    /// Launch hook. Refresh account availability; if sync was left ON, resume the
    /// daemon. No-op without an account.
    public func start() async {
        status.accountAvailable = await service.accountAvailable()
        if enabled { await resume() }
    }

    /// Flip the switch. ON → one-time bootstrap upload; OFF → stop (the local DB
    /// stays fully usable offline; nothing is deleted from CloudKit, so
    /// re-enabling resumes from the existing records). Design §3.1.
    public func setEnabled(_ on: Bool, store: FinchStore) async {
        enabled = on
        SyncPreferences.enabled = on
        status.lastError = nil
        if on { await bootstrap(store: store) } else { await suspend() }
    }

    /// The §4 "Resync ledger" recovery path — a forced full re-upload + re-pull.
    public func resync(store: FinchStore) async {
        guard enabled else { return }
        await bootstrap(store: store)
    }

    /// The chokepoint would call this after each write (the mutation bus). For
    /// now it just reflects a pending change in the status; the real per-row push
    /// is PROVISIONING-GATED.
    public func noteLocalMutation() {
        guard enabled else { return }
        status.pendingChanges += 1
        // PROVISIONING-GATED: enqueue the changed rows and push to CloudKit.
    }

    // MARK: - Daemon skeleton (live calls inert without an account)

    private func resume() async {
        status.accountAvailable = await service.accountAvailable()
        // PROVISIONING-GATED: register per-ledger CKSubscription(s), start the
        // pull loop / CKSyncEngine, subscribe to the chokepoint mutation bus.
    }

    private func suspend() async {
        // PROVISIONING-GATED: cancel subscriptions, unsubscribe the mutation bus.
        status.subscribedLedgers = 0
        status.pendingChanges = 0
    }

    /// One-time bootstrap: gather every syncable row and push it. The extraction
    /// (`store.syncableRows`) is pure + unit-tested; `service.push` no-ops
    /// without an account, so this is safe everywhere.
    private func bootstrap(store: FinchStore) async {
        guard await service.accountAvailable() else {
            status.accountAvailable = false
            status.lastError = "iCloud account required"
            return
        }
        status.accountAvailable = true
        isBootstrapping = true
        defer { isBootstrapping = false }
        for table in CloudKitBootstrap.tables {
            await service.push(table: table, rows: store.syncableRows(table: table))
        }
        // PROVISIONING-GATED: stamp lastSyncAt + subscribedLedgers from the real
        // operation's completion instead of leaving them at their defaults.
    }
}
