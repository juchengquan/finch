import Foundation
import CloudKit
import FinchCore
#if os(macOS)
import Security   // SecTask* — reading our own entitlements is macOS-SDK only
#endif

// Phase 8 — row-level CloudKit sync.
//
// ⚠️ THE LIVE LOOP BELOW IS UNVERIFIED AT RUNTIME. It compiles against the real
// SDK but has never run: there is no provisioned `iCloud.com.juchengquan.finch`
// container yet (built per the "build it anyway" decision, against the Phase 8
// §5.1 advice to provision first). Every method guards on `accountAvailable()`,
// so it's inert in CI / on a bare simulator. Expect rework — especially around
// CloudKit's exact change-feed semantics and the fresh-device down-sync seed —
// once a real container + two devices exist. The PURE pieces (CloudKitRecordMapper,
// CloudKitConflict, SyncMutation/SyncOutbox) ARE unit-tested.

/// Maps a canonical DB row to/from a `CKRecord` (used by the bootstrap row
/// upload). recordType = table name, recordName = the row's `id`. Pure.
public enum CloudKitRecordMapper {
    public static func record(table: String, row: [String: String]) -> CKRecord {
        let id = row["id"] ?? UUID().uuidString
        let record = CKRecord(recordType: table, recordID: CKRecord.ID(recordName: id))
        for (key, value) in row where key != "id" { record[key] = value as CKRecordValue }
        return record
    }
    public static func row(from record: CKRecord) -> [String: String] {
        var out: [String: String] = ["id": record.recordID.recordName]
        for key in record.allKeys() {
            if let v = record[key] as? String { out[key] = v }
            else if let v = record[key] { out[key] = "\(v)" }
        }
        return out
    }
}

/// Last-writer-wins on `updated_at`. A tie keeps local (idempotent). The audit
/// gate re-validates invariants after any merge, so a field merge never breaks
/// balance. Pure.
public enum CloudKitConflict {
    public enum Winner: Equatable { case local, remote }
    public static func resolve(localUpdatedAt: String?, remoteUpdatedAt: String?) -> Winner {
        switch (localUpdatedAt, remoteUpdatedAt) {
        case let (l?, r?): return r > l ? .remote : .local
        case (nil, _?):    return .remote
        default:           return .local
        }
    }
}

/// Mutation ↔ `CKRecord` ("Mutation" recordType; one record per local write,
/// stored in the ledger's zone). Pure.
public enum SyncMutationRecord {
    public static let recordType = "Mutation"

    public static func zoneID(ledgerId: String) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: ledgerId, ownerName: CKCurrentUserDefaultName)
    }

    public static func record(_ m: SyncMutation) -> CKRecord {
        let rec = CKRecord(recordType: recordType,
                           recordID: CKRecord.ID(recordName: m.id, zoneID: zoneID(ledgerId: m.ledgerId)))
        rec["seq"] = m.seq as CKRecordValue
        rec["deviceId"] = m.deviceId as CKRecordValue
        rec["ledgerId"] = m.ledgerId as CKRecordValue
        rec["action"] = m.action as CKRecordValue
        rec["argsJSON"] = m.argsJSON as CKRecordValue
        rec["ts"] = m.ts as CKRecordValue
        return rec
    }

    public static func mutation(from r: CKRecord) -> SyncMutation? {
        guard r.recordType == recordType,
              let seq = r["seq"] as? Int,
              let deviceId = r["deviceId"] as? String,
              let ledgerId = r["ledgerId"] as? String,
              let action = r["action"] as? String,
              let argsJSON = r["argsJSON"] as? String,
              let ts = r["ts"] as? String else { return nil }
        return SyncMutation(id: r.recordID.recordName, seq: seq, deviceId: deviceId,
                            ledgerId: ledgerId, action: action, argsJSON: argsJSON, ts: ts)
    }
}

/// The CloudKit transport. Operation-based (`modifyRecords` / `recordZoneChanges`
/// / `CKDatabaseSubscription`) rather than `CKSyncEngine` — more verbose but its
/// API surface is stable enough to get right without a runtime to iterate against.
/// Inert without an account.
@MainActor
public final class CloudKitSyncService {
    public static let shared = CloudKitSyncService()

    static let containerID = "iCloud.com.juchengquan.finch"

    /// nil when this build can't use CloudKit — most importantly the unsigned
    /// simulator / CI build (`CODE_SIGNING_ALLOWED=NO`, no team), whose binary
    /// carries no iCloud entitlement. CloudKit does NOT throw in that case — it TRAPS
    /// (`_os_crash` → `EXC_BREAKPOINT`): `CKContainer(identifier:)` traps when the id
    /// isn't in `com.apple.developer.icloud-container-identifiers`, and the first
    /// container *use* traps when `com.apple.developer.icloud-services` lacks
    /// "CloudKit". Both crashed the app at launch. So we must detect the missing
    /// entitlement up front and skip construction; there's nothing to catch.
    /// `accountAvailable()` returns false when this is nil, so every method no-ops.
    private let container: CKContainer? = CloudKitSyncService.hasCloudKitEntitlement
        ? CKContainer(identifier: CloudKitSyncService.containerID) : nil
    private var db: CKDatabase? { container?.privateCloudDatabase }

    /// Whether the running binary may talk to CloudKit at all.
    ///
    /// macOS: read the `com.apple.developer.icloud-services` entitlement directly via
    /// `SecTask` (macOS-SDK only). This is exact — false on the unsigned build, and
    /// it does NOT confuse the *user's* iCloud login (which on macOS is visible even
    /// to an unentitled app) with the *app's* entitlement.
    ///
    /// iOS: there's no public API to read your own entitlements. The
    /// `ubiquityIdentityToken` heuristic used previously is NOT reliable: on an
    /// iCloud-signed-in DEVICE the token can be non-nil even when this binary
    /// carries no iCloud entitlements (observed 2026-07-18 on a personal-team
    /// device build with stripped entitlements — `CKContainer` then trapped at
    /// launch). So read the truth from the **embedded provisioning profile**
    /// (present in development / ad-hoc / TestFlight builds — exactly the ones
    /// that can be mis-provisioned). Builds without an embedded profile fall
    /// back to the token heuristic: App Store builds are always signed with the
    /// project's full entitlements (which include CloudKit), and unsigned
    /// simulator builds have no account, so the token is nil there.
    private static var hasCloudKitEntitlement: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                  task, "com.apple.developer.icloud-services" as CFString, nil),
              let services = value as? [String]
        else { return false }
        return services.contains("CloudKit") || services.contains("CloudKit-Anonymous")
        #else
        if let ents = embeddedProvisioningEntitlements() {
            return cloudKitPermitted(byEntitlements: ents, containerID: containerID)
        }
        return FileManager.default.ubiquityIdentityToken != nil
        #endif
    }

    /// Whether an entitlements dict permits our CloudKit use: the services array
    /// must include CloudKit (or -Anonymous) AND our container id must be listed.
    /// (Both matter — `CKContainer(identifier:)` traps on a missing container id,
    /// first use traps on missing services.)
    nonisolated static func cloudKitPermitted(byEntitlements ents: [String: Any], containerID: String) -> Bool {
        guard let services = ents["com.apple.developer.icloud-services"] as? [String],
              services.contains("CloudKit") || services.contains("CloudKit-Anonymous"),
              let ids = ents["com.apple.developer.icloud-container-identifiers"] as? [String],
              ids.contains(containerID)
        else { return false }
        return true
    }

    /// The Entitlements dict from `embedded.mobileprovision` (nil when the build
    /// embeds none — App Store and simulator). The profile is a CMS blob wrapping
    /// an XML plist; extract the plist bytes and read its "Entitlements" key.
    private nonisolated static func embeddedProvisioningEntitlements() -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return parseProvisioningEntitlements(from: data)
    }

    /// Pure CMS-blob → Entitlements-dict extraction (internal for unit tests).
    nonisolated static func parseProvisioningEntitlements(from data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
              let dict = plist as? [String: Any]
        else { return nil }
        return dict["Entitlements"] as? [String: Any]
    }

    /// Set by the coordinator: replay a fetched remote mutation through the
    /// chokepoint. Not called for our own device's echoes.
    public var replay: ((SyncMutation) -> Void)?

    public func accountAvailable() async -> Bool {
        guard let container else { return false }
        return (try? await container.accountStatus()) == .available
    }

    // MARK: - Zones + subscription

    /// Create the per-ledger record zones (zone name = ledger id). Idempotent.
    public func ensureZones(ledgerIds: [String]) async {
        guard await accountAvailable(), !ledgerIds.isEmpty else { return }
        let zones = ledgerIds.map { CKRecordZone(zoneID: SyncMutationRecord.zoneID(ledgerId: $0)) }
        _ = try? await db?.modifyRecordZones(saving: zones, deleting: [])
    }

    /// Register a database subscription so other devices' pushes wake this one.
    /// (The APS handler that calls `pull()` is PROVISIONING-GATED — it needs the
    /// real push certificate + a device.)
    public func registerSubscription() async {
        guard await accountAvailable() else { return }
        let sub = CKDatabaseSubscription(subscriptionID: "finch-mutations")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true   // silent push → background pull
        sub.notificationInfo = info
        _ = try? await db?.save(sub)
    }

    // MARK: - Push

    /// Push the outbox's pending mutations; drop the ones CloudKit acks.
    public func pushPending() async {
        guard await accountAvailable() else { return }
        let pending = SyncOutbox.shared.pending
        guard !pending.isEmpty else { return }
        await ensureZones(ledgerIds: Array(Set(pending.map(\.ledgerId))))
        let records = pending.map(SyncMutationRecord.record)
        guard let db, let results = try? await db.modifyRecords(saving: records, deleting: []) else { return }
        var acked = Set<String>()
        for (id, result) in results.saveResults {
            if case .success = result { acked.insert(id.recordName) }
        }
        SyncOutbox.shared.remove(ids: acked)
    }

    /// One-time bootstrap: upload current state as row-mirror records (the design
    /// also keeps Entry/Posting records for late-joining devices). The fresh-device
    /// DOWN-sync that re-seeds a new install from these records is the riskiest
    /// blind piece and is left PROVISIONING-GATED in the coordinator.
    public func push(table: String, rows: [[String: String]]) async {
        guard await accountAvailable(), !rows.isEmpty else { return }
        let records = rows.map { CloudKitRecordMapper.record(table: table, row: $0) }
        _ = try? await db?.modifyRecords(saving: records, deleting: [])
    }

    // MARK: - Pull

    /// Fetch new Mutation records for each ledger zone since the saved change
    /// token, and replay each foreign mutation through the chokepoint. Persists
    /// the new token per zone so the next pull is incremental.
    public func pull(ledgerIds: [String]) async {
        guard await accountAvailable() else { return }
        for ledgerId in ledgerIds {
            let zoneID = SyncMutationRecord.zoneID(ledgerId: ledgerId)
            guard let db, let result = try? await db.recordZoneChanges(inZoneWith: zoneID, since: loadToken(zoneID)) else { continue }
            // Replay foreign mutations in seq order; skip our own + already-applied.
            let mutations = result.modificationResultsByID.values
                .compactMap { try? $0.get().record }
                .compactMap(SyncMutationRecord.mutation(from:))
                .filter { $0.deviceId != SyncDevice.id }
                .sorted { $0.seq < $1.seq }
            for m in mutations where SyncOutbox.shared.markApplied(id: m.id) {
                replay?(m)
            }
            saveToken(result.changeToken, zoneID)
        }
    }

    // MARK: - Change-token persistence (per zone, UserDefaults)

    private func tokenKey(_ zoneID: CKRecordZone.ID) -> String { "finch.sync.token.\(zoneID.zoneName)" }
    private func loadToken(_ zoneID: CKRecordZone.ID) -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: tokenKey(zoneID)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }
    private func saveToken(_ token: CKServerChangeToken, _ zoneID: CKRecordZone.ID) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: tokenKey(zoneID))
    }
}
