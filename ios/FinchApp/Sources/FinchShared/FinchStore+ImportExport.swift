import Foundation
import FinchCore
import GRDB
import WidgetKit

/// The pack import/export pipeline (DESIGN §4): extract → migrate → **audit
/// gate** → atomic swap into Application Support → re-open → project, and the
/// `VACUUM INTO` export. Split out of FinchStore.swift; the shared state it
/// touches (`dbQueue`, `pendingRejected`, `reprojectActiveLedger`, `makeDBInfo`)
/// is `internal` on the core type.
extension FinchStore {

    /// Import pipeline. Throws `PackError` on any failure; on `auditFailed` the
    /// live DB is UNTOUCHED (the gate is pre-swap).
    public func loadPack(from data: Data) async throws {
        isImporting = true
        defer { isImporting = false }
        // 1. parse + 2. extract to a staging dir.
        let parsed = try Pack.parse(data)
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-staging/\(UUID().uuidString)")
        let extracted = try Pack.extract(parsed, to: staging)

        // 3. open staged DB + migrate.
        let stagedQueue: DatabaseQueue
        do {
            stagedQueue = try DatabaseQueue(path: extracted.dbPath.path)
            try Migrations.runAll(on: stagedQueue)
        } catch {
            throw PackError.migrationFailed("open+migrate: \(error)")
        }

        // 4. AUDIT GATE — throw BEFORE the swap, but RETAIN the staged DB so
        //    forceImportCurrentPack (D7) can swap THAT in later.
        let problems = try Audit.run(on: stagedQueue)
        guard problems.isEmpty else {
            self.pendingRejected = PendingRejected(
                stagedDB: extracted.dbPath,
                stagedAttachments: extracted.attachmentsDir,
                problems: problems)
            throw PackError.auditFailed(problems)
        }

        // 5. atomic swap → re-open → project.
        self.pendingRejected = nil
        try swapInAndProject(stagedDB: extracted.dbPath,
                             stagedAttachments: extracted.attachmentsDir,
                             problems: problems)
    }

    /// D7 — iOS-only override: swap the RETAINED rejected pack's staged DB into
    /// the live location (a real import path that skips ONLY the audit gate).
    /// The rejected pack's problems are surfaced (not gated on). No-op if none.
    public func forceImportCurrentPack() throws {
        guard let pending = pendingRejected else { return }
        self.pendingRejected = nil
        // Propagate swap/reopen failures: a failed swap closes the live DB
        // (dbQueue = nil), so a swallowed error would leave the app broken with
        // no signal. The caller surfaces this and gates it behind Face ID.
        try swapInAndProject(stagedDB: pending.stagedDB,
                             stagedAttachments: pending.stagedAttachments,
                             problems: pending.problems)
    }

    /// Shared tail of both import paths: atomic-swap → re-open → project.
    private func swapInAndProject(stagedDB: URL, stagedAttachments: URL?,
                                  problems: [Audit.AuditProblem]) throws {
        try atomicSwap(stagedDB: stagedDB, stagedAttachments: stagedAttachments)
        let live = try DatabaseQueue(path: liveDBURL.path)
        self.dbQueue = live
        self.auditProblems = problems
        self.ledgers = (try? Projection.ledgers(dbQueue: live)) ?? []
        // didSet on activeLedgerId re-projects accounts/txns/budgets.
        let first = ledgers.first?.id ?? ""
        if activeLedgerId == first { reprojectActiveLedger() } else { activeLedgerId = first }
        self.dbInfo = makeDBInfo()
        // Refresh OS surfaces for the new dataset: authoritative Spotlight
        // re-index (drops the old pack's entities) + widget snapshot.
        Task { await SpotlightIndexer.shared.indexAll(store: self) }
        WidgetSnapshotWriter.write(from: self)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// close live; rename live → finch.sqlite3.bak.<unix-ts>; move stagedDB →
    /// live; move staged attachments → Application Support/attachments/; on
    /// failure roll back from .bak and throw `PackError.swapFailed`.
    private func atomicSwap(stagedDB: URL, stagedAttachments: URL?) throws {
        let fm = FileManager.default
        let live = liveDBURL
        try? fm.createDirectory(at: live.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        self.dbQueue = nil   // close the live connection before swapping the file
        // Drop stale WAL/SHM sidecars so the swapped-in DB isn't shadowed.
        for sfx in ["-wal", "-shm"] { try? fm.removeItem(at: URL(fileURLWithPath: live.path + sfx)) }

        var backup: URL?
        if fm.fileExists(atPath: live.path) {
            let bak = live.deletingLastPathComponent()
                .appendingPathComponent("finch.sqlite3.bak")
            try? fm.removeItem(at: bak)
            do { try fm.moveItem(at: live, to: bak); backup = bak }
            catch { throw PackError.swapFailed("backup live DB: \(error)") }
        }
        do {
            try fm.moveItem(at: stagedDB, to: live)
        } catch {
            if let b = backup { try? fm.moveItem(at: b, to: live) }   // roll back
            throw PackError.swapFailed("move staged DB: \(error)")
        }
        // Replace the attachments dir with the imported pack's (the new DB owns
        // its own attachment set). Back the live dir up first and restore it if
        // the move fails, so a failed swap never just destroys existing receipts.
        if let src = stagedAttachments, fm.fileExists(atPath: src.path) {
            let dst = live.deletingLastPathComponent().appendingPathComponent("attachments")
            let attBak = live.deletingLastPathComponent().appendingPathComponent("attachments.bak")
            try? fm.removeItem(at: attBak)
            if fm.fileExists(atPath: dst.path) { try? fm.moveItem(at: dst, to: attBak) }
            do {
                try fm.moveItem(at: src, to: dst)
                try? fm.removeItem(at: attBak)   // success → drop the backup
            } catch {
                if fm.fileExists(atPath: attBak.path) { try? fm.moveItem(at: attBak, to: dst) }   // restore
            }
        }
    }

    // MARK: - Export (mirrors server.ts exportPackBytes → pack.ts buildPack)

    public func buildPack() async throws -> Data {
        guard let live = dbQueue else { throw PackError.exportFailed("no pack loaded") }
        do {
            // 1. VACUUM INTO a temp clone — through GRDB, not the raw sqlite3 C API.
            let cloneURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("export-\(UUID().uuidString).sqlite3")
            // VACUUM cannot run inside a transaction — writeWithoutTransaction.
            try await live.writeWithoutTransaction { db in
                try db.execute(sql: "VACUUM INTO ?", arguments: [cloneURL.path])
            }

            // 2. open the clone, stamp export metadata + checkpoint the WAL.
            let clone = try DatabaseQueue(path: cloneURL.path)
            let rowCounts = try Projection.rowCounts(dbQueue: clone)   // 15 canonical tables
            let exportedAt = ISO8601DateFormatter().string(from: Date())
            let rowCountsJSON = String(
                data: try JSONSerialization.data(withJSONObject: rowCounts), encoding: .utf8) ?? "{}"
            // Stamp + checkpoint without a transaction (wal_checkpoint can't run
            // inside one); each statement auto-commits.
            try await clone.writeWithoutTransaction { db in
                try db.execute(sql: """
                    UPDATE db_metadata SET exported_at = ?, exported_from = ?, row_counts = ?, updated_at = ?
                     WHERE id = 1
                    """, arguments: [exportedAt, "ios", rowCountsJSON, exportedAt])
                try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")  // self-contained single file
            }
            // 3. manifest db.sha256 = sha256 of the now-self-contained clone bytes.
            let dbBytes = try Data(contentsOf: cloneURL)
            return try Pack.build(Pack.BuildInput(
                dbBytes: dbBytes,
                attachmentFiles: liveAttachmentFiles(),   // bundle receipts so the pack is self-contained
                meta: Pack.BuildInput.Meta(
                    appVersion: FinchCore.version, schemaVersion: Schema.version,
                    exportedAt: exportedAt,
                    exportedFrom: PackManifest.ExportedFrom(device: "ios", deviceId: nil, deviceName: nil),
                    rowCounts: rowCounts))).bytes
        } catch let e as PackError {
            throw e
        } catch {
            throw PackError.exportFailed("\(error)")
        }
    }

    /// Every stored receipt as a `Pack.BuildInput.AttachmentFile`, so `buildPack` can bundle
    /// them and the exported `.finch` is self-contained. `rel_path` already
    /// includes the `attachments/` prefix; the on-disk file is at
    /// `<db dir>/<rel_path>`. Files missing on disk are skipped (best-effort)
    /// rather than failing the whole export.
    private func liveAttachmentFiles() throws -> [Pack.BuildInput.AttachmentFile] {
        guard let q = dbQueue else { return [] }
        let dir = liveDBURL.deletingLastPathComponent()
        let fm = FileManager.default
        let rows = try q.read { db in
            try Row.fetchAll(db, sql: "SELECT id, rel_path FROM entry_attachments ORDER BY rel_path")
        }
        return rows.compactMap { r in
            guard let id = r["id"] as String?, let rel = r["rel_path"] as String? else { return nil }
            let abs = rel.split(separator: "/").reduce(dir) { $0.appendingPathComponent(String($1)) }
            guard fm.fileExists(atPath: abs.path) else { return nil }
            return Pack.BuildInput.AttachmentFile(id: id, relPath: rel, absPath: abs)
        }
    }
}
