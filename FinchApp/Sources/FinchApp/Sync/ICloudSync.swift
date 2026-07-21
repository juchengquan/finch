import Foundation
import FinchCore

/// The user-**designated backup folder** — an off-device mirror of the local
/// `.finch` backups, chosen via a document picker and reached through a
/// **security-scoped bookmark**, so it needs no iCloud entitlement (commonly an
/// iCloud Drive folder, but any Files location works). Replaces the old
/// app-ubiquity-container path, which was inert on the free signing team. The
/// local `AutoBackupManager` store is always-on; this is the optional mirror.
/// Nil-safe: with no folder designated, every method is a no-op and backups stay
/// on-device only. (Type name kept for its many call sites.)
@MainActor
public final class ICloudSync: ObservableObject {
    public static let shared = ICloudSync()

    /// A folder is designated + resolvable.
    @Published public private(set) var available = false
    /// Display name of the designated folder (its last path component).
    @Published public private(set) var designatedFolderName: String?
    /// Every `.finch` pack in the designated folder (name + size + downloaded),
    /// for the merged backup history. Size comes from metadata — no download to browse.
    @Published public private(set) var remoteBackups: [ICloudBackup] = []
    /// The mirror is currently failing → drives the persistent "unavailable" banner.
    @Published public private(set) var mirrorFailing = false

    private let bookmarkKey = "finch.backupFolder.bookmark"

    #if os(macOS)
    private let resolveOpts: URL.BookmarkResolutionOptions = [.withSecurityScope]
    private let createOpts: URL.BookmarkCreationOptions = [.withSecurityScope]
    #else
    private let resolveOpts: URL.BookmarkResolutionOptions = []
    private let createOpts: URL.BookmarkCreationOptions = []
    #endif

    /// Resolve the designated folder from the stored bookmark, or nil if none/stale.
    /// The caller balances start/stop of the security scope around access.
    private func resolveFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: resolveOpts, relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// Load the designated folder on launch (called from FinchApp).
    public func start() {
        guard let url = resolveFolder() else { available = false; designatedFolderName = nil; return }
        available = true
        designatedFolderName = url.lastPathComponent
        refresh()
    }

    /// Designate a folder: persist a security-scoped bookmark, **backfill** the
    /// current local backups into it (immediate complete mirror), and refresh.
    public func setFolder(_ url: URL) {
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(options: createOpts, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Backfill the current on-device snapshots so the folder is a full mirror now.
        for lb in AutoBackupManager.shared.localBackups() {
            if let bytes = try? Data(contentsOf: AutoBackupManager.shared.url(forName: lb.name)) {
                try? bytes.write(to: url.appendingPathComponent(lb.name))
            }
        }
        available = true
        designatedFolderName = url.lastPathComponent
        mirrorFailing = false
        refresh()
    }

    /// Clear the designated folder (revert to local-only). Leaves its files intact.
    public func clearFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        available = false
        designatedFolderName = nil
        remoteBackups = []
        mirrorFailing = false
    }

    /// Mirror a freshly-built pack into the folder (best-effort). Local is always
    /// written by AutoBackupManager first; this only touches the mirror and applies
    /// the failure-episode policy (alert once per episode + persistent banner).
    public func push(_ data: Data, name: String) {
        guard let url = resolveFolder() else { return }   // no folder → nothing to mirror
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        var failed = true
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try data.write(to: url.appendingPathComponent(name))
            failed = false
        } catch { failed = true }
        let d = MirrorAlert.next(wasFailing: mirrorFailing, failed: failed)
        mirrorFailing = d.failing
        // One-shot, non-modal notification on the ok→fail transition (a modal alert
        // over whatever screen the user is on would be worse for a background write).
        // The persistent banner in Backup & Sync carries the ongoing state.
        if d.shouldAlert { ToastCenter.shared.show("Backup folder unavailable — saved on this device only.") }
        if !failed { refresh() }
    }

    /// Enumerate the designated folder for the merged history.
    public func refresh() {
        guard let url = resolveFolder() else { remoteBackups = []; return }
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path))?
            .filter { $0.hasPrefix("finch-") && $0.hasSuffix(".finch") } ?? []
        remoteBackups = names.map { name in
            let f = url.appendingPathComponent(name)
            let vals = try? f.resourceValues(forKeys: [.fileSizeKey, .ubiquitousItemDownloadingStatusKey])
            let size = (vals?.fileSize).map(Int64.init) ?? 0
            // A non-ubiquitous file (nil status) is present; an iCloud item counts
            // as downloaded only when `.current`.
            let downloaded = vals?.ubiquitousItemDownloadingStatus.map { $0 == .current } ?? true
            return ICloudBackup(name: name, size: size, downloaded: downloaded)
        }
    }

    /// URL of a named pack in the designated folder.
    public func url(forName name: String) -> URL? { resolveFolder()?.appendingPathComponent(name) }

    /// Download a folder pack's bytes (materializing an iCloud Drive item if
    /// needed, 30s ceiling), or nil — for restoring a folder-only snapshot.
    public func download(name: String) async -> Data? {
        guard let url = resolveFolder() else { return nil }
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        let file = url.appendingPathComponent(name)
        func present() -> Bool {
            let s = (try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
            return s == nil || s == .current
        }
        if !present() {
            try? FileManager.default.startDownloadingUbiquitousItem(at: file)
            for _ in 0..<60 where !present() { try? await Task.sleep(for: .milliseconds(500)) }
        }
        return try? Data(contentsOf: file)
    }

    /// Delete a named pack from the designated folder.
    public func delete(name: String) {
        guard let url = resolveFolder() else { return }
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.removeItem(at: url.appendingPathComponent(name))
    }

    /// Prune the designated folder to this device's own newest `keep` snapshots
    /// (matched by the device-id in the filename) — never another device's.
    public func pruneOwn(deviceId: String, keep: Int) {
        guard let url = resolveFolder() else { return }
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path))?
            .filter { $0.hasPrefix("finch-") && $0.hasSuffix(".finch") } ?? []
        for name in BackupPruner.toPruneOwn(names, deviceId: deviceId, keep: keep) {
            try? FileManager.default.removeItem(at: url.appendingPathComponent(name))
        }
        refresh()
    }
}
