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
    @Published public internal(set) var txnsReady = true      // false while the launch-deferred txns projection is in flight (see reprojectActiveLedger / awaitTxnsReady)
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
    var categories: [CategoryRow] = [] {
        // Kept in step here rather than at the assignment site: `categories` is written
        // from reprojection AND from tests, and a map rebuilt in only one of those goes
        // stale silently. Every transaction row resolves its icon and colour through
        // this, so a linear scan per row would be paid once per visible row per frame
        // while the feed scrolls.
        didSet {
            categoriesById = Dictionary(categories.map { ($0.id, $0) },
                                        uniquingKeysWith: { first, _ in first })
        }
    }
    /// `categories` keyed by id. `uniquingKeysWith` rather than `uniqueKeysWithValues`:
    /// the latter traps on a duplicate id, and a malformed import must not crash a list.
    private(set) var categoriesById: [String: CategoryRow] = [:]
    var counterparties: [Counterparty] = []
    var budgetGroupNames: [String: String] = [:]
    var rateMap: [String: Double] = [:]
    var displayCurrencyByLedger: [String: String] = [:]
    var budgetOrderByLedger: [String: [String]] = [:]   // per-ledger manual budget order (app_state)
    var trackedCurrencies: [String]?                    // global FX auto-update fetch list (app_state); nil = seeded default
    var merchantStatsCache: [String: MerchantStats]?   // lazily built; invalidated each reproject
    /// purchaseKeys of purchases flagged as anomalies. Cached because `isAnomaly`
    /// runs per row per render and collapsing the ledger there would be O(n) per
    /// row. Invalidated alongside `merchantStatsCache`.
    var anomalyKeysCache: Set<String>?
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
            #if DEBUG
            // `-stressSeed N`: append N synthetic transactions for scale profiling.
            let stressCount = UserDefaults.standard.integer(forKey: "stressSeed")
            if stressCount > 0 { try? StressSeed.seed(live, count: stressCount) }
            #endif
        }
        #if DEBUG
        LaunchTiming.mark("db open + migrate + seed")
        #endif
        // NOTE: the integrity Audit used to run HERE (a full ledger sweep, every
        // launch) and blocked the launch spinner. It only feeds the Settings
        // "N problems" indicator, so it's now deferred off the critical path —
        // see `runAuditInBackground()`, called after first paint.
        self.ledgers = (try? Projection.ledgers(dbQueue: live)) ?? []
        let first = ledgers.first?.id ?? ""
        // Restore the last-active ledger if it still exists; else the default (first).
        let saved = UserDefaults.standard.string(forKey: Self.activeLedgerKey)
        let target = (saved.map { s in ledgers.contains { $0.id == s } } ?? false) ? saved! : first
        if activeLedgerId == target { reprojectActiveLedger() } else { activeLedgerId = target }
        // dbInfo (file size + row counts) only feeds the Settings "database info"
        // screen. Computing it here would block ~600ms behind the deferred txns
        // projection on the serialized queue, so defer it off the first-paint path too.
        // (`bootstrap` runs once — guarded by `dbQueue == nil` — so this is always the
        // launch path; import recomputes dbInfo synchronously via `makeDBInfo()`.)
        if let q = dbQueue {
            let url = liveDBURL
            Task.detached(priority: .utility) { [q, url] in
                let info = FinchStore.computeDBInfo(dbQueue: q, url: url)
                await MainActor.run { self.dbInfo = info }
            }
        }
        #if DEBUG
        LaunchTiming.mark("bootstrap done (projection ready)")
        #endif
    }

    /// Run the integrity Audit off the main thread and publish `auditProblems`.
    /// The audit sweeps every ledger entry, so it must NOT sit on the launch
    /// critical path — it only feeds the Settings "N problems" indicator. Call
    /// once after first paint. `DatabaseQueue` serializes access, so reading it
    /// off-main concurrently with the projection is safe.
    func runAuditInBackground() {
        guard let q = dbQueue else { return }
        Task.detached(priority: .utility) {
            let problems = (try? Audit.run(on: q)) ?? []
            await MainActor.run { self.auditProblems = problems }
            #if DEBUG
            LaunchTiming.mark("audit done")
            #endif
        }
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
        fireWriteSideEffects(q, mutations: [(action, args)])
        return result
    }

    /// Apply several actions as ONE write: each runs through the FinchCore
    /// chokepoint in order, then the side-effect train fires once for the whole
    /// batch instead of once per action. Exists because the daily FX refresh
    /// applied each fetched rate individually — N currencies × (16 projections +
    /// full Spotlight re-index + widget/notification replans) stacked on the
    /// MainActor and jammed the UI for seconds right after foregrounding
    /// (audit 2026-07-22). A failing op is skipped (matching the FX path's old
    /// per-row `try?`), so one bad row can't sink the rest; returns how many
    /// applied. No ops applied → no side effects at all.
    @discardableResult
    public func applyBatch(_ ops: [(action: ActionName, args: Args)]) -> Int {
        guard let q = dbQueue, !ops.isEmpty else { return 0 }
        var applied: [(ActionName, Args)] = []
        for op in ops {
            do {
                _ = try Apply.applyReturningId(dbQueue: q, action: op.action.rawValue, args: op.args)
                applied.append((op.action, op.args))
            } catch { continue }   // skip the bad row, keep the rest
        }
        if !applied.isEmpty { fireWriteSideEffects(q, mutations: applied) }
        return applied.count
    }

    /// Every post-write side effect, fired exactly once per user-visible write
    /// (single action or a whole batch). `mutations` lists what was applied —
    /// the CloudKit outbox logs each one individually.
    ///
    /// **Split by whether a pixel is waiting for it.** Everything here used to run
    /// inline, on the main actor, between the tap and the next frame — which is
    /// exactly the window a row-move animation needs. Confirming a pending
    /// transaction therefore animated against a main thread busy rebuilding the
    /// widget snapshot, the Spotlight index and the DB-info probe, none of which is
    /// on screen while the row slides. See `scheduleAmbientSideEffects`.
    private func fireWriteSideEffects(_ q: DatabaseQueue, mutations: [(ActionName, Args)]) {
        WriteTiming.begin()
        // The projection IS the animation: the row cannot move until the new state
        // is published, so this stays synchronous.
        self.ledgers = (try? Projection.ledgers(dbQueue: q)) ?? ledgers
        WriteTiming.mark("ledgers")
        reprojectActiveLedger()
        WriteTiming.mark("reproject")
        // Phase 8: publish each write to the CloudKit mutation log (no-op when
        // sync is off or while replaying a remote mutation — the echo guard).
        // Stays inline: a mutation that never reaches the outbox is a lost edit,
        // which is worse than a frame.
        for (action, args) in mutations {
            CloudKitSyncCoordinator.shared.noteLocalMutation(action: action, args: args, ledgerId: activeLedgerId)
        }
        WriteTiming.mark("cloudkit")
        scheduleAmbientSideEffects()
    }

    // MARK: - Ambient side effects

    /// The pending debounced round, cancelled and replaced by each new write.
    private var ambientTask: Task<Void, Never>?

    /// How long after the LAST write the ambient round fires. Long enough to clear a
    /// row-move animation (~0.35s) and to swallow a burst — a multi-select confirm,
    /// an import, a sync replay — into one round instead of N.
    static let ambientDebounce = Duration.milliseconds(400)

    /// Counts completed ambient rounds. The seam the tests assert on: "one write did
    /// not run this inline" and "a burst of ten ran it once" are both statements
    /// about this number.
    private(set) var ambientRunCount = 0

    /// Queue the work no on-screen pixel is waiting for: the widget + Watch
    /// snapshot, the Spotlight index, scheduled notifications, the DB-info probe and
    /// the auto-backup timer.
    ///
    /// `WidgetSnapshotWriter.write` walks every transaction once per budget, encodes
    /// JSON and writes it to the App Group synchronously; `makeDBInfo` runs COUNT(*)
    /// across every table — which the launch path already refuses to do on the main
    /// actor, for this same reason (see `computeDBInfo`). Neither is visible while a
    /// row is moving, so neither belongs in that window.
    private func scheduleAmbientSideEffects() {
        ambientTask?.cancel()
        ambientTask = Task { [weak self] in
            try? await Task.sleep(for: FinchStore.ambientDebounce)
            guard !Task.isCancelled else { return }
            await self?.runAmbientSideEffects()
        }
    }

    /// Run the pending ambient round NOW, cancelling the debounce.
    ///
    /// Called when the app backgrounds: a stale widget is never more visible than on
    /// the home screen the user just went back to, and the debounce would otherwise
    /// drop the update on the floor until the next write.
    public func flushAmbientSideEffects() {
        guard ambientTask != nil else { return }
        ambientTask?.cancel()
        ambientTask = nil
        Task { await runAmbientSideEffects() }
    }

    private func runAmbientSideEffects() async {
        ambientTask = nil
        WriteTiming.beginAmbient()
        self.dbInfo = makeDBInfo()
        WriteTiming.markAmbient("dbInfo")
        // Tier 2/3: refresh the home-screen + Watch widget (was only on backup, so
        // the widget could show stale figures for up to an hour).
        WidgetSnapshotWriter.write(from: self)
        WidgetCenter.shared.reloadAllTimelines()
        WriteTiming.markAmbient("widget")
        // Phase 5: debounce an auto-backup pack.
        AutoBackupManager.shared.schedule()
        ambientRunCount += 1
        // Phase 6.1: keep Spotlight in sync (idempotent full re-index; the
        // in-memory store is the UI's source of truth regardless). Its own item
        // building already runs off the main actor.
        Task { await SpotlightIndexer.shared.indexAll(store: self) }
        // Phase 6.2: re-plan notifications from the new state.
        Task { await NotificationService.shared.refresh() }
        WriteTiming.markAmbient("done")
    }

    // MARK: - Projection

    /// Rebuild the published state for the active ledger. Transactions are scoped
    /// to the active ledger (a mutation only ever touches the active ledger);
    /// `Projection.run(ledgerId:)` keeps it from rebuilding every ledger's txns.
    func reprojectActiveLedger() {
        guard let q = dbQueue else { return }
        // `pending_kind` caches a date rule, so it is refreshed here — the one funnel
        // every write and the launch bootstrap already pass through. Idempotent and
        // indexed, so the common case writes no rows. It deliberately does NOT go
        // through `apply`: the calendar moving is not a user edit, and routing it there
        // would queue a sync mutation and re-plan notifications for every row, daily.
        try? q.write { db in try Entries.refreshPendingKind(db, today: wallToday) }
        // Launch defers the heavy txns projection off the first-paint path (see the
        // txns block below); every OTHER reproject — a mutation, a ledger switch —
        // projects synchronously so the change shows immediately. `isHydrating` is true
        // only during `bootstrap()`'s launch reproject.
        let deferTxns = isHydrating
        // All-or-nothing: compute every slice first, then publish a consistent
        // snapshot. On any query failure, keep the last-good state and surface
        // the error rather than silently publishing stale-or-empty data.
        do {
            let id = activeLedgerId
            // Cheap slices — each its own SQL query (~1ms even at scale). The Accounts
            // landing (the launch tab) reads only these, never the txns list.
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

            self.accounts = accounts; self.accountGroups = accountGroups
            self.budgets = budgets; self.categories = categories; self.counterparties = counterparties
            self.budgetGroupNames = budgetGroupNames; self.budgetGroups = budgetGroups
            self.holdings = holdings; self.scheduled = scheduled; self.exchangeRates = exchangeRates
            self.rules = rules; self.tags = tags; self.displayCurrencyByLedger = displayCurrencyByLedger
            self.budgetOrderByLedger = budgetOrderByLedger
            self.trackedCurrencies = trackedCurrencies
            self.rateMap = Money.latestRateMap(exchangeRates)
            self.merchantStatsCache = nil   // recompute on next access
            self.anomalyKeysCache = nil
            self.dataError = nil

            // The txns list (`Projection.run`, per-account-leg grain) is the one slice
            // that scales O(transactions): it materializes every leg with its splits /
            // tags / transfer & refund resolution (~600ms at 20k legs). On LAUNCH we
            // publish the cheap slices above for an instant first paint and project
            // txns from a background task; `txnsReady` lets the txn feeds show a brief
            // spinner until it lands (Accounts never reads txns, so it's unaffected).
            if deferTxns {
                self.txns = []
                self.runningBalanceCache = nil
                self.txnsReady = false
                Task.detached(priority: .userInitiated) { [q, id] in
                    let txns = (try? Projection.run(dbQueue: q, ledgerId: id)) ?? []
                    await MainActor.run {
                        // A newer reproject (e.g. a ledger switch) may have superseded
                        // this one — only publish if we're still on the same ledger.
                        guard self.activeLedgerId == id else { return }
                        self.txns = txns
                        self.runningBalanceCache = nil
                        self.markTxnsReady()
                        #if DEBUG
                        LaunchTiming.mark("txns projected (\(txns.count) legs)")
                        #endif
                    }
                }
            } else {
                self.txns = try Projection.run(dbQueue: q, ledgerId: id)
                self.runningBalanceCache = nil
                self.markTxnsReady()
            }
        } catch {
            self.dataError = "Couldn't load your data: \(error.localizedDescription)"
        }
    }

    /// Continuations parked by `awaitTxnsReady()` while the launch txns projection
    /// is in flight; resumed by `markTxnsReady()`. MainActor-only.
    private var txnsReadyWaiters: [CheckedContinuation<Void, Never>] = []

    /// Suspends until the active ledger's txns projection has been published. On
    /// launch that projection is deferred off the first-paint path (see
    /// `reprojectActiveLedger`), so background consumers that snapshot the FULL
    /// txns list — Spotlight indexing, notification planning — must await this or
    /// they'd capture an empty list and leave transactions unsearchable / budget
    /// alerts mis-planned until the next write. Returns immediately when txns are
    /// already ready (every non-launch reproject projects synchronously). Always
    /// completes: `markTxnsReady()` fires even when the projection itself failed.
    func awaitTxnsReady() async {
        if txnsReady { return }
        await withCheckedContinuation { txnsReadyWaiters.append($0) }
    }

    /// Publish `txnsReady = true` and wake anyone parked in `awaitTxnsReady()`.
    private func markTxnsReady() {
        txnsReady = true
        let waiters = txnsReadyWaiters
        txnsReadyWaiters = []
        for w in waiters { w.resume() }
    }

    func makeDBInfo() -> DatabaseInfo {
        guard let q = dbQueue else { return .empty }
        return Self.computeDBInfo(dbQueue: q, url: liveDBURL)
    }

    /// The DB-info probe (file size + row counts + schema / import metadata), factored
    /// out of `makeDBInfo()` so the launch path can run it OFF the main actor — it
    /// otherwise blocks ~600ms behind the deferred txns projection on the serialized
    /// queue (see `bootstrap`). Pure DB reads through that queue — safe on any thread.
    nonisolated static func computeDBInfo(dbQueue q: DatabaseQueue, url: URL) -> DatabaseInfo {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let counts = (try? Projection.rowCounts(dbQueue: q)) ?? [:]
        let meta: (schema: String, exportedAt: String?)? = try? q.read { db in
            let r = try Row.fetchOne(db, sql: "SELECT schema_version, exported_at FROM db_metadata WHERE id = 1")
            return (r?["schema_version"] ?? "—", r?["exported_at"])
        }
        let lastImported: Date? = meta?.exportedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        return DatabaseInfo(
            filename: url.lastPathComponent, sizeBytes: size,
            schemaVersion: meta?.schema ?? Schema.version,
            lastImportedAt: lastImported, rowCounts: counts)
    }
}
