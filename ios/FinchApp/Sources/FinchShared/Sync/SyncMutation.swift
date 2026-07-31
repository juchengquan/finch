import Foundation
import FinchCore

// Phase 8 — the mutation-log content model for row-level sync.
//
// ⚠️ UNVERIFIED AT RUNTIME. Built without a provisioned CloudKit container (per
// the user's "build it anyway" decision, against the Phase 8 §5.1 recommendation
// to provision first). It COMPILES against the real SDK but has never been run /
// two-device tested; expect rework once a real `iCloud.com.juchengquan.finch`
// container exists. The pure pieces here (SyncMutation (de)serialization, the
// outbox ordering/dedup) ARE unit-tested; the CloudKit transport in
// CloudKitSync.swift / CloudKitSyncCoordinator.swift is the blind part.
//
// Model: finch syncs **mutations**, not raw rows. Every local write through the
// chokepoint (FinchStore.apply) becomes a `SyncMutation` (action + args + a
// per-device monotonic seq); it's pushed to CloudKit (recordType "Mutation",
// zone = ledger id). Other devices fetch new Mutation records and **replay** them
// through their own chokepoint (Apply.apply) — so the engine's invariants, audit
// gate, and dedup (`entries.dedup_hash`, replay-idempotent `postEntry`) all apply
// to remote writes exactly as to local ones. This respects the single chokepoint
// instead of reverse-mapping raw rows back into actions.

/// One replayable mutation: the action + its args, ordered by a per-device seq.
public struct SyncMutation: Codable, Equatable, Sendable {
    public let id: String          // CKRecord recordName (unique)
    public let seq: Int            // monotonic per device — replay order
    public let deviceId: String    // origin device (skip our own echoes)
    public let ledgerId: String    // CloudKit zone name
    public let action: String      // ActionName.rawValue
    public let argsJSON: String    // JSONEncoder(Args)
    public let ts: String          // ISO8601 (tiebreak / display)

    public init(id: String, seq: Int, deviceId: String, ledgerId: String,
                action: String, argsJSON: String, ts: String) {
        self.id = id; self.seq = seq; self.deviceId = deviceId
        self.ledgerId = ledgerId; self.action = action; self.argsJSON = argsJSON; self.ts = ts
    }

    /// Encode an Args bag to the stored JSON string (both are Codable).
    public static func encode(_ args: Args) -> String {
        (try? String(data: JSONEncoder().encode(args), encoding: .utf8) ?? "{}") ?? "{}"
    }
    /// Decode the stored args back into an Args bag for replay.
    public var args: Args? {
        guard let data = argsJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Args.self, from: data)
    }
    /// The action as an `ActionName`, or nil for an unknown/forward-compat action.
    public var actionName: ActionName? { ActionName(rawValue: action) }
}

/// This device's stable id (one per install), persisted in UserDefaults so a
/// device can recognise — and skip replaying — the mutations it authored.
public enum SyncDevice {
    private static let key = "finch.sync.deviceId"
    public static var id: String {
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }
}

/// File-backed outbox: the pending (not-yet-acked) outgoing mutations + the set
/// of already-applied REMOTE mutation ids (idempotency) + the monotonic seq.
/// Pure Foundation (no CloudKit) so it's unit-testable. Persisted next to the DB.
@MainActor
public final class SyncOutbox {
    public static let shared = SyncOutbox()

    private struct Persisted: Codable {
        var seq: Int = 0
        var pending: [SyncMutation] = []
        var appliedRemoteIds: [String] = []
    }
    private var state: Persisted
    private let url: URL
    private var appliedSet: Set<String>

    /// Test seam: an isolated outbox at a custom path.
    public init(fileURL: URL? = nil) {
        self.url = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sync-outbox.json")
        self.state = (try? JSONDecoder().decode(Persisted.self, from: Data(contentsOf: url))) ?? Persisted()
        self.appliedSet = Set(state.appliedRemoteIds)
    }

    public var pending: [SyncMutation] { state.pending }
    public func pendingMutation(id: String) -> SyncMutation? { state.pending.first { $0.id == id } }

    /// Append a freshly-authored local mutation (assigns id + seq) and persist.
    @discardableResult
    public func append(action: String, args: Args, ledgerId: String, ts: String) -> SyncMutation {
        state.seq += 1
        let m = SyncMutation(id: UUID().uuidString, seq: state.seq, deviceId: SyncDevice.id,
                             ledgerId: ledgerId, action: action,
                             argsJSON: SyncMutation.encode(args), ts: ts)
        state.pending.append(m)
        save()
        return m
    }

    /// Drop acked mutations (CloudKit confirmed the push).
    public func remove(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        state.pending.removeAll { ids.contains($0.id) }
        save()
    }

    /// Record a remote mutation as applied; returns false if it already was (so
    /// the caller skips a duplicate replay). Idempotency backstop in addition to
    /// the engine's dedup_hash.
    @discardableResult
    public func markApplied(id: String) -> Bool {
        guard !appliedSet.contains(id) else { return false }
        appliedSet.insert(id)
        state.appliedRemoteIds.append(id)
        // Bound the set so it can't grow forever (keep the most recent N).
        if state.appliedRemoteIds.count > 5000 {
            let drop = state.appliedRemoteIds.count - 5000
            for old in state.appliedRemoteIds.prefix(drop) { appliedSet.remove(old) }
            state.appliedRemoteIds.removeFirst(drop)
        }
        save()
        return true
    }
    public func hasApplied(id: String) -> Bool { appliedSet.contains(id) }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: url) }
    }
}
