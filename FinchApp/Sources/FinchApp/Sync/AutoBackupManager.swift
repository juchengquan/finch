import Foundation
import FinchCore

/// Pure retention policy (the tested core): given timestamped backup filenames
/// (sortable `finch-YYYYMMDD-HHmmss.finch`), return the ones to delete to keep
/// only the newest `keep`. Sorting by name is chronological by construction.
public enum BackupPruner {
    public static func toPrune(_ filenames: [String], keep: Int) -> [String] {
        let sorted = filenames.sorted(by: >)   // newest first
        guard sorted.count > max(0, keep) else { return [] }
        return Array(sorted.dropFirst(max(0, keep)))
    }

    /// Prune a SHARED folder to this device's own newest `keep`: filter to files
    /// carrying `deviceId`, then `toPrune`. Other devices' (and old suffix-less)
    /// names are never returned — so a device only ever deletes its own snapshots.
    public static func toPruneOwn(_ filenames: [String], deviceId: String, keep: Int) -> [String] {
        toPrune(filenames.filter { BackupHistory.deviceId(fromName: $0) == deviceId }, keep: keep)
    }
}

/// Phase 5 — auto-pack debounce: after each write, wait a short idle window then
/// write a `.finch` pack to a local Backups directory, pruning to a retention
/// count. Flush immediately on backgrounding / "Back up now". iCloud Drive sync
/// (NSMetadataQuery folder-watch + conflict resolution + the iCloud entitlement)
/// is deferred infra — see _PHASES_3_TO_8_OPEN_QUESTIONS.md; this writes locally.
@MainActor
public final class AutoBackupManager: ObservableObject {
    public static let shared = AutoBackupManager()

    @Published public private(set) var lastBackupAt: Date?
    @Published public private(set) var lastError: String?

    private weak var store: FinchStore?
    private var pending: Task<Void, Never>?
    private let debounceSeconds: TimeInterval = 5

    // Folder-archive prefs (UserDefaults; the Backups settings UI binds the same
    // keys via @AppStorage). Local always keeps just the latest (1); these govern
    // the OPT-IN folder archive only. Defaults: keep 14, daily.
    public static let retentionKey = "finch.backupRetention"
    public static let frequencyKey = "finch.backupFrequency"
    public static let defaultRetention = 14
    private static let lastFolderBackupKey = "finch.lastFolderBackupAt"
    private var retention: Int { let v = UserDefaults.standard.integer(forKey: Self.retentionKey); return v == 0 ? Self.defaultRetention : v }
    private var frequency: BackupFrequency { BackupFrequency(rawValue: UserDefaults.standard.string(forKey: Self.frequencyKey) ?? "") ?? .daily }
    /// When the folder archive was last written — persisted so the frequency
    /// throttle survives relaunch.
    private var lastFolderBackupAt: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastFolderBackupKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastFolderBackupKey) }
    }

    public var backupsDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups", isDirectory: true)
    }

    public func configure(store: FinchStore) {
        self.store = store
        lastBackupAt = (try? FileManager.default.contentsOfDirectory(atPath: backupsDir.path))?
            .filter { $0.hasSuffix(".finch") }.max()
            .flatMap { name in (try? FileManager.default.attributesOfItem(atPath: backupsDir.appendingPathComponent(name).path)[.modificationDate]) as? Date }
    }

    /// After each change (debounced): refresh the always-on LOCAL latest, and
    /// archive to the folder when synced + the frequency throttle allows.
    public func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.debounceSeconds ?? 5))
            guard let self, !Task.isCancelled else { return }
            await self.writeBackup()
        }
    }

    /// Forced immediate pack — manual "Back up now" and the pre-restore safety
    /// backup. Refreshes the local latest AND writes the folder (bypasses the throttle).
    public func flush() async {
        pending?.cancel()
        await writeBackup(forceFolder: true)
    }

    /// App-backgrounding: refresh the local latest (always) + archive to the folder
    /// if the frequency throttle allows.
    public func backupIfDue() async {
        pending?.cancel()
        await writeBackup()
    }

    /// Re-prune the FOLDER archive to the current retention (when the user lowers
    /// the count). Local is always 1, so it's unaffected.
    public func pruneNow() { ICloudSync.shared.pruneOwn(deviceId: Self.deviceId, keep: retention) }

    /// Write a pack. ALWAYS refreshes the single local latest; also archives to the
    /// designated folder when synced AND (forced OR the frequency throttle allows).
    private func writeBackup(forceFolder: Bool = false) async {
        guard let store, !store.ledgers.isEmpty else { return }
        do {
            let data = try await store.buildPack()
            let name = "finch-\(Self.stamp())-\(Self.deviceId).finch"
            // Local: always keep just the newest one (the always-on safety copy).
            try FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
            try data.write(to: backupsDir.appendingPathComponent(name))
            pruneLocal()
            WidgetSnapshotWriter.write(from: store)   // Phase 7: refresh the widget data
            lastBackupAt = Date()
            // Folder archive (opt-in): keep this device's newest `retention`,
            // throttled by frequency. Manual/pre-restore force it.
            if ICloudSync.shared.available,
               forceFolder || BackupSchedule.shouldAutoBackup(lastBackupAt: lastFolderBackupAt, frequency: frequency, now: Date()) {
                ICloudSync.shared.push(data, name: name)
                ICloudSync.shared.pruneOwn(deviceId: Self.deviceId, keep: retention)
                lastFolderBackupAt = Date()
            }
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    /// Keep only the newest local snapshot (the always-on safety copy).
    private func pruneLocal() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backupsDir.path))?
            .filter { $0.hasPrefix("finch-") && $0.hasSuffix(".finch") } ?? []
        for name in BackupPruner.toPrune(names, keep: 1) {
            try? FileManager.default.removeItem(at: backupsDir.appendingPathComponent(name))
        }
    }

    /// URL of a named local backup pack.
    public func url(forName name: String) -> URL { backupsDir.appendingPathComponent(name) }

    /// The on-device backup snapshots (name + size), for the merged history.
    public func localBackups() -> [LocalBackup] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: backupsDir.path))?
            .filter { $0.hasPrefix("finch-") && $0.hasSuffix(".finch") } ?? []
        return names.map { name in
            let attrs = try? fm.attributesOfItem(atPath: backupsDir.appendingPathComponent(name).path)
            return LocalBackup(name: name, size: (attrs?[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    /// A short, stable per-device id appended to backup filenames so two devices
    /// backing up in the same second never write the SAME filename into a shared
    /// backup folder (which would overwrite one and let a lockstep prune delete the
    /// other). Random hex, generated once, persisted per-device.
    static let deviceId: String = {
        let key = "finch.backupDeviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()
}
