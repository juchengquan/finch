import Foundation
import FinchCore
import GRDB
import WidgetKit

/// The in-memory working model behind the tabs. Holds the projected state for the
/// active ledger and owns the mutation chokepoint + (in `FinchStore+ImportExport`)
/// the import/export pipeline. One GRDB connection type throughout: `DatabaseQueue`.
///
/// Split across files: this file is the core (state + bootstrap + `apply` +
/// reprojection); `FinchStore+ImportExport.swift` is the pack pipeline;
/// `FinchStore+ViewHelpers.swift` is the read/format surface the views call.
/// Members shared across those extensions are `internal` (not `private`) by
/// necessity — the encapsulation boundary is the module.
@MainActor
public final class FinchStore: ObservableObject {
    public static let shared = FinchStore()
    public init() {}

    @Published public private(set) var txns: [Tx] = []
    @Published public private(set) var accounts: [AccountRow] = []
    @Published public private(set) var accountGroups: [AccountGroupRow] = []   // ordered id+name (incl. empty groups)
    @Published public internal(set) var isImporting = false   // drives the import spinner (set by ImportExport)
    @Published public internal(set) var isHydrating = false   // drives the launch spinner (set by FinchApp.task)
    @Published public private(set) var budgets: [BudgetRow] = []
    @Published public private(set) var budgetGroups: [GroupRow] = []   // ordered id+name (incl. empty groups)
    @Published public internal(set) var ledgers: [Ledger] = []   // set by core + ImportExport
    @Published public private(set) var holdings: [Holding] = []
    @Published public private(set) var scheduled: [ScheduledTemplate] = []
    @Published public private(set) var exchangeRates: [ExchangeRate] = []   // Phase 4 FX editor
    @Published public private(set) var rules: [RuleSummary] = []            // Phase 4 rules manager
    @Published public private(set) var tags: [TagRow] = []                  // Phase 4 tag admin
    /// UserDefaults key for the last-active ledger — a per-device viewing
    /// preference (not ledger data), restored in `bootstrap()`.
    static let activeLedgerKey = "finch.activeLedgerId"
    /// Privacy mode — a per-device viewing preference that masks every rendered
    /// amount (web parity: #416). Mirrors the web's localStorage key name; lives
    /// in UserDefaults only — never the DB, never `.finch` exports.
    static let privacyKey = "finch.privacy"
    /// What every masked amount renders as (web's MONEY_MASK).
    public static let moneyMask = "••••"
    @Published public var privacyMode: Bool = UserDefaults.standard.bool(forKey: FinchStore.privacyKey) {
        didSet {
            guard oldValue != privacyMode else { return }
            UserDefaults.standard.set(privacyMode, forKey: FinchStore.privacyKey)
        }
    }
    @Published public var activeLedgerId: String = "" {
        didSet {
            guard oldValue != activeLedgerId else { return }
            reprojectActiveLedger()                                    // switch → re-project
            if !activeLedgerId.isEmpty {                               // remember across launches
                UserDefaults.standard.set(activeLedgerId, forKey: Self.activeLedgerKey)
            }
        }
    }
    @Published public internal(set) var auditProblems: [Audit.AuditProblem] = []   // set by core + ImportExport
    @Published public internal(set) var dbInfo: DatabaseInfo = .empty               // set by core + ImportExport
    /// A non-recoverable load/migration/projection failure, surfaced to the user
    /// instead of silently degrading on a broken DB. Nil when healthy.
    @Published public internal(set) var dataError: String?

    // Shared with the ImportExport / ViewHelpers extensions (hence internal).
    var dbQueue: DatabaseQueue?
    var categories: [CategoryRow] = []
    var counterparties: [Counterparty] = []
    var budgetGroupNames: [String: String] = [:]
    var rateMap: [String: Double] = [:]
    var displayCurrencyByLedger: [String: String] = [:]
    var budgetOrderByLedger: [String: [String]] = [:]   // per-ledger manual budget order (app_state)
    var trackedCurrencies: [String]?                    // global FX auto-update fetch list (app_state); nil = seeded default
    var merchantStatsCache: [String: MerchantStats]?   // lazily built; invalidated each reproject
    var runningBalanceCache: [String: Double]?          // txn.id → account balance (base) after that txn; lazy, invalidated each reproject

    /// A pack that FAILED the audit gate, retained on disk so the iOS-only
    /// `forceImportCurrentPack` (D7) can swap THAT staged DB in later.
    struct PendingRejected {
        let stagedDB: URL
        let stagedAttachments: URL?
        let problems: [Audit.AuditProblem]
    }
    var pendingRejected: PendingRejected?

    /// True when the process is hosting XCTest (the test bundle injects the
    /// XCTestCase class). Checked once — it can't change mid-process.
    private static let isRunningTests = NSClassFromString("XCTestCase") != nil

    /// The persistent live DB location (survives relaunch). Under XCTest it
    /// moves to a temp directory — the import tests swap packs into the live
    /// DB by design, and attachmentsRoot lives next door, so pointing this at
    /// Application Support would let every test run clobber the app's real
    /// data on a development simulator.
    public var liveDBURL: URL {
        let dir = Self.isRunningTests
            ? FileManager.default.temporaryDirectory.appendingPathComponent("finch-tests", isDirectory: true)
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("finch.sqlite3")
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
        guard let live = try? DatabaseQueue(path: liveDBURL.path) else {
            dataError = "Couldn't open the finch database."
            return
        }
        do {
            try Migrations.runAll(on: live)
        } catch {
            // A failed migration leaves the schema in an unknown state — don't
            // operate on it. Surface the error instead of silently degrading.
            dataError = "Database migration failed: \(error.localizedDescription). Restore a backup or reinstall."
            return
        }
        self.dbQueue = live
        if (try? Projection.ledgers(dbQueue: live))?.isEmpty ?? true {
            #if targetEnvironment(simulator)
            // Simulator builds get a richer demo dataset so the tabs are populated
            // for development/screenshots. Production keeps the minimal starter.
            do { try SimulatorDemoSeed.seed(live) } catch { try? seedMinimalStarter(live) }
            #else
            try? seedMinimalStarter(live)
            #endif
        }
        self.auditProblems = (try? Audit.run(on: live)) ?? []
        self.ledgers = (try? Projection.ledgers(dbQueue: live)) ?? []
        let first = ledgers.first?.id ?? ""
        // Restore the last-active ledger if it still exists; else the default (first).
        let saved = UserDefaults.standard.string(forKey: Self.activeLedgerKey)
        let target = (saved.map { s in ledgers.contains { $0.id == s } } ?? false) ? saved! : first
        if activeLedgerId == target { reprojectActiveLedger() } else { activeLedgerId = target }
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
        _ = try applyReturningId(action, args)
    }

    /// Like `apply`, returning the new entry id for `addTransaction` (nil otherwise).
    @discardableResult
    public func applyReturningId(_ action: ActionName, _ args: Args) throws -> String? {
        try write(action, args) { try Apply.applyReturningId(dbQueue: $0, action: action.rawValue, args: args) }
    }

    /// Like `apply`, returning how many rows the action created — only the copy
    /// actions report a real count (see `Apply.applyReturningCount`), which the
    /// Categories/Tags copy affordances use to confirm "N added".
    @discardableResult
    public func applyReturningCount(_ action: ActionName, _ args: Args) throws -> Int {
        try write(action, args) { try Apply.applyReturningCount(dbQueue: $0, action: action.rawValue, args: args) }
    }

    /// The one write path: run `body` through the FinchCore chokepoint, then fire
    /// every post-write side effect. Both public variants funnel through here so a
    /// new return flavour can't quietly skip re-projection, Spotlight, widgets,
    /// backups, or the CloudKit outbox.
    private func write<T>(_ action: ActionName, _ args: Args,
                          _ body: (DatabaseQueue) throws -> T) throws -> T {
        guard let q = dbQueue else { throw I18nError("error.noDatabase", [:], "No database is open") }
        let result = try body(q)
        self.ledgers = (try? Projection.ledgers(dbQueue: q)) ?? ledgers
        reprojectActiveLedger()
        self.dbInfo = makeDBInfo()
        // Phase 6.1: keep Spotlight in sync (idempotent full re-index; the
        // in-memory store is the UI's source of truth regardless).
        Task { await SpotlightIndexer.shared.indexAll(store: self) }
        // Phase 6.2: re-plan notifications from the new state.
        Task { await NotificationService.shared.refresh() }
        // Tier 2/3: refresh the home-screen + Watch widget on every write (was
        // only on backup, so the widget could show stale figures for up to an hour).
        WidgetSnapshotWriter.write(from: self)
        WidgetCenter.shared.reloadAllTimelines()
        // Phase 5: debounce an auto-backup pack.
        AutoBackupManager.shared.schedule()
        // Phase 8: publish this write to the CloudKit mutation log (no-op when
        // sync is off or while replaying a remote mutation — the echo guard).
        CloudKitSyncCoordinator.shared.noteLocalMutation(action: action, args: args, ledgerId: activeLedgerId)
        return result
    }

    // MARK: - Projection

    /// Rebuild the published state for the active ledger. Transactions are scoped
    /// to the active ledger (a mutation only ever touches the active ledger);
    /// `Projection.run(ledgerId:)` keeps it from rebuilding every ledger's txns.
    func reprojectActiveLedger() {
        guard let q = dbQueue else { return }
        // All-or-nothing: compute every slice first, then publish a consistent
        // snapshot. On any query failure, keep the last-good state and surface
        // the error rather than silently publishing stale-or-empty data.
        do {
            let id = activeLedgerId
            let txns     = try Projection.run(dbQueue: q, ledgerId: id)
            let accounts = try Projection.accounts(dbQueue: q, ledgerId: id)
            let accountGroups = try Projection.accountGroups(dbQueue: q, ledgerId: id)
            let budgets  = try Projection.budgets(dbQueue: q, ledgerId: id)
            let categories = try Projection.categories(dbQueue: q, ledgerId: id)
            let counterparties = try Projection.counterparties(dbQueue: q)
            let budgetGroupNames = try Projection.budgetGroupNames(dbQueue: q, ledgerId: id)
            let budgetGroups = try Projection.budgetGroups(dbQueue: q, ledgerId: id)
            let holdings = try Projection.holdings(dbQueue: q, ledgerId: id)
            let scheduled = try Projection.scheduledTemplates(dbQueue: q, ledgerId: id)
            let exchangeRates = try Projection.exchangeRates(dbQueue: q)
            let rules = try Projection.rules(dbQueue: q, ledgerId: id)
            let tags = try Projection.tags(dbQueue: q, ledgerId: id)
            let displayCurrencyByLedger = try Projection.displayCurrencyByLedger(dbQueue: q)
            let budgetOrderByLedger = try Projection.budgetOrderByLedger(dbQueue: q)
            let trackedCurrencies = try Projection.trackedCurrencies(dbQueue: q)

            self.txns = txns; self.accounts = accounts; self.accountGroups = accountGroups
            self.budgets = budgets; self.categories = categories; self.counterparties = counterparties
            self.budgetGroupNames = budgetGroupNames; self.budgetGroups = budgetGroups
            self.holdings = holdings; self.scheduled = scheduled; self.exchangeRates = exchangeRates
            self.rules = rules; self.tags = tags; self.displayCurrencyByLedger = displayCurrencyByLedger
            self.budgetOrderByLedger = budgetOrderByLedger
            self.trackedCurrencies = trackedCurrencies
            self.rateMap = Money.latestRateMap(exchangeRates)
            self.merchantStatsCache = nil   // recompute on next access
            self.runningBalanceCache = nil  // depends on txns + opening balances; recompute lazily
            self.dataError = nil
        } catch {
            self.dataError = "Couldn't load your data: \(error.localizedDescription)"
        }
    }

    func makeDBInfo() -> DatabaseInfo {
        guard let q = dbQueue else { return .empty }
        let size = (try? FileManager.default.attributesOfItem(atPath: liveDBURL.path)[.size] as? Int) ?? 0
        let counts = (try? Projection.rowCounts(dbQueue: q)) ?? [:]
        let meta: (schema: String, exportedAt: String?)? = try? q.read { db in
            let r = try Row.fetchOne(db, sql: "SELECT schema_version, exported_at FROM db_metadata WHERE id = 1")
            return (r?["schema_version"] ?? "—", r?["exported_at"])
        }
        let lastImported: Date? = meta?.exportedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        return DatabaseInfo(
            filename: liveDBURL.lastPathComponent, sizeBytes: size,
            schemaVersion: meta?.schema ?? Schema.version,
            lastImportedAt: lastImported, rowCounts: counts)
    }
}
