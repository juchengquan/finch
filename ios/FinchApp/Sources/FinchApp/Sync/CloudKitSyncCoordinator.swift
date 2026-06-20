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
    /// True while replaying a REMOTE mutation through the chokepoint, so the
    /// resulting `apply` doesn't re-enqueue it as a local change (echo guard).
    public private(set) var isReplaying = false

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

    /// The chokepoint (`FinchStore.apply`) calls this after every successful local
    /// write. Records the (action, args) as a mutation in the outbox and pushes.
    /// Skipped while replaying a remote mutation (echo guard), when sync is off,
    /// or when there's no iCloud account — the last guard stops the outbox from
    /// accumulating un-pushable mutations if the switch is on but unprovisioned.
    /// (`status.accountAvailable` is refreshed by start/resume/syncNow.)
    public func noteLocalMutation(action: ActionName, args: Args, ledgerId: String) {
        guard enabled, !isReplaying, status.accountAvailable else { return }
        SyncOutbox.shared.append(action: action.rawValue, args: args, ledgerId: ledgerId, ts: Self.nowISO())
        status.pendingChanges = SyncOutbox.shared.pending.count
        Task { await syncNow() }
    }

    /// Push pending local mutations, then pull + replay remote ones.
    public func syncNow() async {
        guard enabled, await service.accountAvailable() else { return }
        await service.pushPending()
        await service.pull(ledgerIds: FinchStore.shared.ledgers.map(\.id))
        status.pendingChanges = SyncOutbox.shared.pending.count
        status.lastSyncAt = Date()
    }

    // MARK: - Daemon (live calls inert without an account)

    private func resume() async {
        status.accountAvailable = await service.accountAvailable()
        guard status.accountAvailable else { return }
        // Replay remote mutations through the chokepoint (echo-guarded).
        service.replay = { [weak self] mutation in self?.applyRemote(mutation) }
        let ledgerIds = FinchStore.shared.ledgers.map(\.id)
        await service.ensureZones(ledgerIds: ledgerIds)
        await service.registerSubscription()
        status.subscribedLedgers = ledgerIds.count
        await syncNow()
    }

    private func suspend() async {
        // Local DB stays usable; nothing is deleted remotely (design §3.1).
        service.replay = nil
        status.subscribedLedgers = 0
        status.pendingChanges = 0
    }

    /// Replay a fetched remote mutation through the real chokepoint, so the audit
    /// gate + dedup apply to it exactly as to a local write. The echo guard stops
    /// the resulting `apply` from re-enqueuing it.
    private func applyRemote(_ m: SyncMutation) {
        guard let action = m.actionName, let args = m.args else {
            status.lastError = "Skipped an unknown remote mutation (\(m.action))"
            return
        }
        isReplaying = true
        defer { isReplaying = false }
        do { try FinchStore.shared.apply(action, args) }
        catch { status.lastError = i18nMessage(error) }   // e.g. a benign dedup rejection
    }

    /// One-time bootstrap: upload current state as row-mirror records (design §3.1
    /// keeps Entry/Posting records for late-joining devices). The extraction
    /// (`store.syncableRows`) is pure + unit-tested.
    ///
    /// The reverse — a FRESH device re-hydrating an empty DB from those records —
    /// is now built + tested as `FinchCore.DownSync.ingest` (two-phase seal +
    /// trigger-rebuilt balances + audit gate). Only the CloudKit *fetch* that
    /// feeds it `[table: rows]` is still PROVISIONING-GATED (needs an account).
    private func bootstrap(store: FinchStore) async {
        guard await service.accountAvailable() else {
            status.accountAvailable = false
            status.lastError = "iCloud account required"
            return
        }
        status.accountAvailable = true
        isBootstrapping = true
        defer { isBootstrapping = false }
        await service.ensureZones(ledgerIds: store.ledgers.map(\.id))
        for table in CloudKitBootstrap.tables {
            await service.push(table: table, rows: store.syncableRows(table: table))
        }
        await resume()
    }

    private static func nowISO() -> String { ISO8601DateFormatter().string(from: Date()) }
}
