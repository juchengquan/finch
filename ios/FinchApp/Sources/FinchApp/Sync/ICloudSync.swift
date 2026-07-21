import Foundation
import FinchCore

/// Phase 5 — iCloud Drive sync of the `.finch` pack. The auto-backup pushes each
/// pack here; an `NSMetadataQuery` watches the container for newer packs written
/// by *other* devices and surfaces them for import (manual, to avoid silently
/// replacing the live DB mid-session — the conflict-safe choice). Nil-safe: when
/// no iCloud account is present (e.g. a bare simulator) the ubiquity container is
/// nil and every method is a no-op, so the local Backups path is unaffected.
@MainActor
public final class ICloudSync: ObservableObject {
    public static let shared = ICloudSync()

    @Published public private(set) var available = false
    @Published public private(set) var newerRemotePack: URL?
    /// Every `.finch` pack in iCloud Drive (for the merged backup history) — name +
    /// size + whether the bytes are already downloaded. Size/date come from
    /// metadata, so browsing the history needs no download.
    @Published public private(set) var remoteBackups: [ICloudBackup] = []

    private let containerId = "iCloud.com.juchengquan.finch"
    private var query: NSMetadataQuery?
    private var lastPushedName: String?

    /// iCloud Drive `Documents/finch/` — visible to the user in the Files app.
    public var documentsDir: URL? {
        guard let base = FileManager.default.url(forUbiquityContainerIdentifier: containerId) else { return nil }
        return base.appendingPathComponent("Documents/finch", isDirectory: true)
    }

    public func start() {
        available = documentsDir != nil
        guard available else { return }
        if let dir = documentsDir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        startWatch()
    }

    /// Push a freshly-built pack to iCloud (called by AutoBackupManager).
    public func push(_ data: Data, name: String) {
        guard let dir = documentsDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        lastPushedName = name
        try? data.write(to: dir.appendingPathComponent(name))
    }

    /// Read the newer remote pack's bytes for import.
    public func dataForImport() -> Data? {
        guard let url = newerRemotePack else { return nil }
        // Ensure it's downloaded (iCloud may have only the metadata locally).
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        return try? Data(contentsOf: url)
    }

    public func clearPendingImport() { newerRemotePack = nil }

    /// URL of a named pack in iCloud Drive (may be metadata-only until downloaded).
    public func url(forName name: String) -> URL? { documentsDir?.appendingPathComponent(name) }

    /// Download a named pack's bytes, waiting for iCloud to materialize it (30s
    /// ceiling); nil if unavailable. For restoring an iCloud-only snapshot.
    public func download(name: String) async -> Data? {
        guard let url = url(forName: name) else { return nil }
        func isDownloaded() -> Bool {
            (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus == .current
        }
        if !isDownloaded() {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            for _ in 0..<60 where !isDownloaded() { try? await Task.sleep(for: .milliseconds(500)) }
        }
        return try? Data(contentsOf: url)
    }

    /// Delete a named pack from iCloud Drive. Used by the lockstep prune — a device
    /// only prunes names it wrote locally (its own backups), never another device's.
    public func delete(name: String) {
        guard let url = url(forName: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func startWatch() {
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K LIKE '*.finch'", NSMetadataItemFSNameKey)
        NotificationCenter.default.addObserver(self, selector: #selector(queryUpdated(_:)),
                                               name: .NSMetadataQueryDidFinishGathering, object: q)
        NotificationCenter.default.addObserver(self, selector: #selector(queryUpdated(_:)),
                                               name: .NSMetadataQueryDidUpdate, object: q)
        q.start()
        self.query = q
    }

    @objc private func queryUpdated(_ note: Notification) {
        guard let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }
        var newest: (URL, Date)?
        var all: [ICloudBackup] = []
        for i in 0..<q.resultCount {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let name = url.lastPathComponent
            let size = (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value ?? 0
            let downloaded = (item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String)
                == NSMetadataUbiquitousItemDownloadingStatusCurrent
            all.append(ICloudBackup(name: name, size: size, downloaded: downloaded))
            if let date = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date,
               name != lastPushedName, newest == nil || date > newest!.1 { newest = (url, date) }
        }
        // Surface a remote pack newer than anything we pushed this session + the
        // full list for the merged backup history.
        Task { @MainActor in
            self.newerRemotePack = newest?.0
            self.remoteBackups = all
        }
    }
}
