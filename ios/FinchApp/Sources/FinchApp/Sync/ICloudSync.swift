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
        for i in 0..<q.resultCount {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  let date = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date else { continue }
            if url.lastPathComponent == lastPushedName { continue }   // skip our own push
            if newest == nil || date > newest!.1 { newest = (url, date) }
        }
        // Surface a remote pack newer than anything we pushed this session.
        Task { @MainActor in self.newerRemotePack = newest?.0 }
    }
}
