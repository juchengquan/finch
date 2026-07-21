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
    private let retention = 14

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

    /// Coalesce a burst of writes into one pack a short interval later.
    public func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.debounceSeconds ?? 5))
            if Task.isCancelled { return }
            await self?.writeBackup()
        }
    }

    /// Immediate pack (manual "Back up now" / app backgrounding).
    public func flush() async {
        pending?.cancel()
        await writeBackup()
    }

    private func writeBackup() async {
        guard let store, !store.ledgers.isEmpty else { return }
        do {
            let data = try await store.buildPack()
            try FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
            let url = backupsDir.appendingPathComponent("finch-\(Self.stamp())-\(Self.deviceId).finch")
            try data.write(to: url)
            prune()
            WidgetSnapshotWriter.write(from: store)   // Phase 7: refresh the widget data
            ICloudSync.shared.push(data, name: url.lastPathComponent)   // Phase 5: push to iCloud Drive
            lastBackupAt = Date()
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    private func prune() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backupsDir.path))?
            .filter { $0.hasPrefix("finch-") && $0.hasSuffix(".finch") } ?? []
        for name in BackupPruner.toPrune(names, keep: retention) {
            try? FileManager.default.removeItem(at: backupsDir.appendingPathComponent(name))
            // Lockstep: drop this device's OWN snapshot from iCloud too (same
            // filename we pushed). Only ever prunes our own — other devices' names
            // aren't in our local dir, so they're never touched.
            ICloudSync.shared.delete(name: name)
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
