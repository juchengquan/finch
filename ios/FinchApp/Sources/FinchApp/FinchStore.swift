import Foundation
import FinchCore
import GRDB

/// The in-memory working model behind the 4 tabs. Holds the projected state for
/// the active ledger and owns the import/export pipeline (DESIGN §4):
/// extract → migrate → **audit gate** → atomic swap into Application Support →
/// re-open → project. One GRDB connection type throughout: `DatabaseQueue`.
@MainActor
public final class FinchStore: ObservableObject {
    public static let shared = FinchStore()
    public init() {}

    @Published public private(set) var txns: [Tx] = []
    @Published public private(set) var accounts: [AccountRow] = []
    @Published public private(set) var budgets: [BudgetRow] = []
    @Published public private(set) var ledgers: [Ledger] = []
    @Published public private(set) var holdings: [Holding] = []
    @Published public private(set) var scheduled: [ScheduledTemplate] = []
    @Published public var activeLedgerId: String = "" {
        didSet { if oldValue != activeLedgerId { reprojectActiveLedger() } }  // switch → re-project
    }
    @Published public private(set) var auditProblems: [Audit.AuditProblem] = []
    @Published public private(set) var dbInfo: DatabaseInfo = .empty

    private var dbQueue: DatabaseQueue?
    private var categories: [CategoryRow] = []
    private var counterparties: [Counterparty] = []
    private var budgetGroupNames: [String: String] = [:]
    private var rateMap: [String: Double] = [:]

    /// A pack that FAILED the audit gate, retained on disk so the iOS-only
    /// `forceImportCurrentPack` (D7) can swap THAT staged DB in later.
    private struct PendingRejected {
        let stagedDB: URL
        let stagedAttachments: URL?
        let problems: [Audit.AuditProblem]
    }
    private var pendingRejected: PendingRejected?

    /// The persistent live DB location (survives relaunch).
    public var liveDBURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("finch.sqlite3")
    }

    // MARK: - Launch bootstrap

    /// Open the persisted live DB on launch so imported (and locally-written)
    /// data survives relaunch. On first launch (or any DB with no ledgers) it
    /// seeds the minimal starter — a Personal/USD ledger + a Cash account + a few
    /// common categories — so the write screens are usable immediately. A later
    /// import atomically replaces whatever this opened. Idempotent.
    public func bootstrap() {
        guard dbQueue == nil else { return }
        try? FileManager.default.createDirectory(
            at: liveDBURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let live = try? DatabaseQueue(path: liveDBURL.path) else { return }
        try? Migrations.runAll(on: live)
        self.dbQueue = live
        if (try? Projection.ledgers(dbQueue: live))?.isEmpty ?? true {
            try? seedMinimalStarter(live)
        }
        self.auditProblems = (try? Audit.run(on: live)) ?? []
        self.ledgers = (try? Projection.ledgers(dbQueue: live)) ?? []
        let first = ledgers.first?.id ?? ""
        if activeLedgerId == first { reprojectActiveLedger() } else { activeLedgerId = first }
        self.dbInfo = makeDBInfo()
    }

    /// Minimal starter so a brand-new install can write immediately (per the
    /// first-launch product decision): one default Personal/USD ledger, a Cash
    /// account, and Food/Transport/Shopping/Income categories — all through the
    /// chokepoint so the system categories + invariants are seeded correctly.
    private func seedMinimalStarter(_ q: DatabaseQueue) throws {
        try Apply.apply(dbQueue: q, action: "createLedger",
                        args: Args(["id": .string("personal"), "name": .string("Personal"), "base": .string("USD")]))
        try Apply.apply(dbQueue: q, action: "setDefaultLedger", args: Args(["id": .string("personal")]))
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("cash"), "ledgerId": .string("personal"),
            "name": .string("Cash"), "type": .string("cash"), "currency": .string("USD")]))
        for (name, kind) in [("Food", "expense"), ("Transport", "expense"), ("Shopping", "expense"), ("Income", "income")] {
            try Apply.apply(dbQueue: q, action: "createCategory",
                            args: Args(["ledgerId": .string("personal"), "name": .string(name), "type": .string(kind)]))
        }
    }

    // MARK: - Mutations (Task 16: the single mutating entry point)

    /// Route a write through the FinchCore chokepoint, then re-project the active
    /// ledger so the published state reflects the change. Throws `I18nError` on a
    /// rejected mutation (forms surface `.message`). Every write screen calls this.
    public func apply(_ action: ActionName, _ args: Args) throws {
        guard let q = dbQueue else { throw I18nError("error.noDatabase", [:], "No database is open") }
        try Apply.apply(dbQueue: q, action: action.rawValue, args: args)
        self.ledgers = (try? Projection.ledgers(dbQueue: q)) ?? ledgers
        reprojectActiveLedger()
        self.dbInfo = makeDBInfo()
        // Phase 6.1: keep Spotlight in sync (idempotent full re-index; the
        // in-memory store is the UI's source of truth regardless).
        Task { await SpotlightIndexer.shared.indexAll(store: self) }
    }

    // MARK: - Import (DESIGN §4)

    /// Import pipeline. Throws `PackError` on any failure; on `auditFailed` the
    /// live DB is UNTOUCHED (the gate is pre-swap).
    public func loadPack(from data: Data) async throws {
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
    public func forceImportCurrentPack() {
        guard let pending = pendingRejected else { return }
        self.pendingRejected = nil
        try? swapInAndProject(stagedDB: pending.stagedDB,
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
    }

    private func reprojectActiveLedger() {
        guard let q = dbQueue else { return }
        self.txns     = (try? Projection.run(dbQueue: q)) ?? []   // all ledgers; views filter
        self.accounts = (try? Projection.accounts(dbQueue: q, ledgerId: activeLedgerId)) ?? []
        self.budgets  = (try? Projection.budgets(dbQueue: q, ledgerId: activeLedgerId)) ?? []
        self.categories = (try? Projection.categories(dbQueue: q, ledgerId: activeLedgerId)) ?? []
        self.counterparties = (try? Projection.counterparties(dbQueue: q, ledgerId: activeLedgerId)) ?? []
        self.budgetGroupNames = (try? Projection.budgetGroupNames(dbQueue: q, ledgerId: activeLedgerId)) ?? [:]
        self.holdings = (try? Projection.holdings(dbQueue: q, ledgerId: activeLedgerId)) ?? []
        self.scheduled = (try? Projection.scheduledTemplates(dbQueue: q, ledgerId: activeLedgerId)) ?? []
        self.rateMap = Money.latestRateMap((try? Projection.exchangeRates(dbQueue: q)) ?? [])
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
        // Move attachments (best-effort; overwrite on id collision).
        if let src = stagedAttachments, fm.fileExists(atPath: src.path) {
            let dst = live.deletingLastPathComponent().appendingPathComponent("attachments")
            try? fm.removeItem(at: dst)
            try? fm.moveItem(at: src, to: dst)
        }
    }

    private func makeDBInfo() -> DatabaseInfo {
        guard let q = dbQueue else { return .empty }
        let size = (try? FileManager.default.attributesOfItem(atPath: liveDBURL.path)[.size] as? Int) ?? 0
        let counts = (try? Projection.rowCounts(dbQueue: q)) ?? [:]
        let meta: (schema: String, exportedAt: String?)? = try? q.read { db in
            let r = try Row.fetchOne(db, sql: "SELECT schema_version, exported_at FROM db_metadata WHERE id = 1")
            return (r?["schema_version"] ?? "—", r?["exported_at"])
        }
        let lastImported: Date? = meta?.exportedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        return DatabaseInfo(
            filename: liveDBURL.lastPathComponent, sizeBytes: size ?? 0,
            schemaVersion: meta?.schema ?? Schema.version,
            lastImportedAt: lastImported, rowCounts: counts)
    }

    // MARK: - Export (DESIGN §4; mirrors server.ts exportPackBytes → pack.ts buildPack)

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
                attachmentFiles: [],   // Phase 1.0: no attachments
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

    // MARK: - View helpers (one definition; all money via Money + the rate map)

    private var baseCurrency: String {
        ledgers.first { $0.id == activeLedgerId }?.base ?? Money.hubCurrency
    }
    /// Per-ledger display currency — Phase 1.0 defaults to the active ledger base.
    public var displayCurrency: String { baseCurrency }

    /// `today` for budget windows = the max confirmed-tx date (the web anchors
    /// the window on the data, so the oracle's budgetProgress lines up); falls
    /// back to the wall clock only when there are no transactions.
    public var today: String { txns.map(\.date).max() ?? Self.isoDay(Date()) }

    public var categoryNodes: [CategoryNode] {
        categories.map { CategoryNode(id: $0.id, parentId: $0.parentId) }
    }
    /// Non-system categories for the active ledger (write-screen pickers), in
    /// projection order. System equity categories (opening/adjustment/fx) are
    /// excluded — they're booked by the engine, never picked by the user.
    public var pickableCategories: [CategoryRow] {
        categories.filter { ($0.kind ?? "") != "equity" }
    }
    /// Counterparties ("merchants") for the active ledger — read surface for
    /// Spotlight indexing and merchant pickers.
    public var merchants: [Counterparty] { counterparties }
    public func categoryName(_ id: String?) -> String? {
        guard let id else { return nil }
        return categories.first { $0.id == id }?.name
    }

    private func toBase(_ amount: Double, from currency: String?) -> Double {
        Money.convert(amount, from: currency ?? baseCurrency, to: baseCurrency, rates: rateMap) ?? amount
    }
    /// ledger base → display.
    public func displayMoneyBase(_ baseAmount: Double) -> String {
        let v = Money.convert(baseAmount, from: baseCurrency, to: displayCurrency, rates: rateMap) ?? baseAmount
        return Money.format(v, currency: displayCurrency)
    }
    /// account currency → base → display.
    public func displayMoney(_ amount: Double, from currency: String?) -> String {
        displayMoneyBase(toBase(amount, from: currency))
    }

    // ---- Accounts grouping ----
    public var accountGroupsOrdered: [String] {
        var seen = Set<String>(); var out: [String] = []
        for a in accounts { let g = a.groupName ?? "Ungrouped"; if seen.insert(g).inserted { out.append(g) } }
        return out
    }
    public func accounts(in group: String) -> [AccountRow] {
        accounts.filter { ($0.groupName ?? "Ungrouped") == group }
    }
    public func subtotalDisplay(for group: String) -> String {
        displayMoneyBase(accounts(in: group).reduce(0.0) { $0 + toBase($1.balance, from: $1.currency) })
    }
    public var netWorthDisplay: String {
        displayMoneyBase(accounts.filter { ($0.includeInNetWorth ?? 1) == 1 }
            .reduce(0.0) { $0 + toBase($1.balance, from: $1.currency) })
    }

    // ---- Budgets grouping ----
    public var budgetGroupsOrdered: [String] {
        var seen = Set<String>(); var out: [String] = []
        for b in budgets {
            let g = b.groupId.flatMap { budgetGroupNames[$0] } ?? "Ungrouped"
            if seen.insert(g).inserted { out.append(g) }
        }
        return out
    }
    public func budgets(in group: String) -> [BudgetRow] {
        budgets.filter { (($0.groupId.flatMap { budgetGroupNames[$0] }) ?? "Ungrouped") == group }
    }
    public var budgetTotalsDisplay: (used: String, base: String) {
        var used = 0.0, base = 0.0
        for b in budgets {
            let p = Selectors.budgetProgress(b, txns, today, categoryNodes)
            used += p.used; base += p.base
        }
        return (displayMoneyBase(used), displayMoneyBase(base))
    }

    /// Whole days from `today` to `ymd` (UTC), floored at 0.
    public func daysLeft(until ymd: String) -> Int {
        guard let to = Self.parseDay(ymd), let now = Self.parseDay(today) else { return 0 }
        return max(0, Int((to.timeIntervalSince(now) / 86_400).rounded(.up)))
    }

    // MARK: - UTC day helpers
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static func isoDay(_ d: Date) -> String { dayFormatter.string(from: d) }
    private static func parseDay(_ s: String) -> Date? { dayFormatter.date(from: String(s.prefix(10))) }
}

/// Settings › Database info. Amounts/dates formatted for the rows.
public struct DatabaseInfo: Equatable, Sendable {
    public let filename: String
    public let sizeBytes: Int
    public let schemaVersion: String
    public let lastImportedAt: Date?
    public let rowCounts: [String: Int]
    public static let empty = DatabaseInfo(
        filename: "—", sizeBytes: 0, schemaVersion: "—", lastImportedAt: nil, rowCounts: [:])
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
    public var lastImportedAtDisplay: String {
        guard let d = lastImportedAt else { return "—" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }
    public var rowCountsOrdered: [(String, Int)] {
        rowCounts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}
