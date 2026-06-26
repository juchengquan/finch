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
            do { try seedSimulatorDemo(live) } catch { try? seedMinimalStarter(live) }
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

    #if targetEnvironment(simulator)
    /// Simulator-only demo seed: a Personal/USD ledger with several accounts
    /// (incl. opening balances), a richer category set, a few monthly budgets,
    /// and ~3 months of transactions — so a fresh simulator launch shows populated
    /// tabs without hand-entering data. Routed through the chokepoint so all
    /// invariants (system categories, balances, budget cache) stay correct.
    private func seedSimulatorDemo(_ q: DatabaseQueue) throws {
        func apply(_ action: String, _ args: [String: JSONValue]) throws {
            try Apply.apply(dbQueue: q, action: action, args: Args(args))
        }
        let cal = Calendar.current
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = cal.timeZone
        let now = Date()
        func ymd(_ daysAgo: Int) -> String {
            df.string(from: cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now)
        }
        // First day of the month `monthsAgo` before now — a budget start that
        // predates every seeded transaction (oldest is 68 days ≈ 2.3 months back),
        // so the current monthly window captures real month-to-date spend instead
        // of starting "today" and counting nothing. See cycleWindow/budgetProgress.
        func monthStart(_ monthsAgo: Int) -> String {
            let base = cal.date(byAdding: .month, value: -monthsAgo, to: now) ?? now
            let comps = cal.dateComponents([.year, .month], from: base)
            return df.string(from: cal.date(from: comps) ?? base)
        }

        try apply("createLedger", ["id": .string("personal"), "name": .string("Personal"), "base": .string("USD")])
        try apply("setDefaultLedger", ["id": .string("personal")])

        // Accounts (with opening balances). Types limited to the valid set.
        let accounts: [(id: String, name: String, type: String, opening: Double)] = [
            ("cash", "Cash", "cash", 180),
            ("everyday", "Everyday", "savings", 3_200),
            ("savings", "Savings", "savings", 15_400),
            ("brokerage", "Brokerage", "investment", 8_600),
            ("credit", "Credit Card", "credit_card", 0),
        ]
        for a in accounts {
            try apply("createAccount", [
                "id": .string(a.id), "ledgerId": .string("personal"), "name": .string(a.name),
                "type": .string(a.type), "currency": .string("USD"), "openingBalance": .double(a.opening)])
        }

        // Categories (explicit ids so transactions/budgets can reference them).
        let categories: [(id: String, name: String, kind: String)] = [
            ("cat-groceries", "Groceries", "expense"),
            ("cat-dining", "Dining", "expense"),
            ("cat-transport", "Transport", "expense"),
            ("cat-shopping", "Shopping", "expense"),
            ("cat-entertainment", "Entertainment", "expense"),
            ("cat-utilities", "Utilities", "expense"),
            ("cat-rent", "Rent", "expense"),
            ("cat-health", "Health", "expense"),
            ("cat-salary", "Salary", "income"),
        ]
        for c in categories {
            try apply("createCategory", [
                "id": .string(c.id), "ledgerId": .string("personal"),
                "name": .string(c.name), "type": .string(c.kind)])
        }

        // Monthly budgets over a few categories.
        let budgets: [(name: String, amount: Double, cat: String)] = [
            ("Groceries", 600, "cat-groceries"), ("Dining", 300, "cat-dining"),
            ("Shopping", 400, "cat-shopping"), ("Transport", 200, "cat-transport"),
        ]
        for b in budgets {
            try apply("createBudget", [
                "ledgerId": .string("personal"), "name": .string(b.name), "type": .string("expense"),
                "amount": .double(b.amount), "frequency": .string("monthly"),
                "startDate": .string(monthStart(3)),
                "categoryIds": .array([.string(b.cat)])])
        }

        // ~3 months of transactions. Expenses negative, income positive.
        let txns: [(d: Int, acct: String, amt: Double, merchant: String, cat: String)] = [
            (2, "credit", -42.18, "Whole Foods", "cat-groceries"),
            (3, "credit", -16.40, "Blue Bottle Coffee", "cat-dining"),
            (4, "everyday", -1_850, "Apartment Rent", "cat-rent"),
            (5, "everyday", 4_200, "Acme Corp Payroll", "cat-salary"),
            (6, "credit", -28.75, "Shell Gas", "cat-transport"),
            (7, "cash", -12.00, "Food Truck", "cat-dining"),
            (8, "credit", -64.99, "Uniqlo", "cat-shopping"),
            (9, "credit", -9.99, "Netflix", "cat-entertainment"),
            (10, "everyday", -88.30, "PG&E Utilities", "cat-utilities"),
            (12, "credit", -53.20, "Trader Joe's", "cat-groceries"),
            (13, "credit", -22.50, "Chipotle", "cat-dining"),
            (14, "credit", -31.00, "Uber", "cat-transport"),
            (16, "credit", -120.00, "Nordstrom", "cat-shopping"),
            (17, "cash", -18.00, "Farmers Market", "cat-groceries"),
            (19, "credit", -45.60, "CVS Pharmacy", "cat-health"),
            (20, "everyday", 4_200, "Acme Corp Payroll", "cat-salary"),
            (21, "credit", -38.40, "Safeway", "cat-groceries"),
            (23, "credit", -14.25, "Starbucks", "cat-dining"),
            (25, "credit", -19.99, "Spotify", "cat-entertainment"),
            (27, "credit", -27.80, "Lyft", "cat-transport"),
            (30, "credit", -58.10, "Whole Foods", "cat-groceries"),
            (33, "credit", -72.00, "AMC Theatres", "cat-entertainment"),
            (35, "everyday", 4_200, "Acme Corp Payroll", "cat-salary"),
            (38, "credit", -41.30, "Trader Joe's", "cat-groceries"),
            (42, "credit", -33.50, "Olive Garden", "cat-dining"),
            (46, "credit", -95.00, "Best Buy", "cat-shopping"),
            (50, "everyday", -1_850, "Apartment Rent", "cat-rent"),
            (55, "credit", -49.90, "Costco", "cat-groceries"),
            (60, "credit", -24.00, "Shell Gas", "cat-transport"),
            (68, "credit", -61.40, "REI", "cat-shopping"),
        ]
        for t in txns {
            try apply("addTransaction", [
                "ledgerId": .string("personal"), "accountId": .string(t.acct),
                "amount": .double(t.amt), "merchant": .string(t.merchant),
                "categoryId": .string(t.cat), "date": .string(ymd(t.d)), "time": .string("12:00")])
        }
    }
    #endif

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
        guard let q = dbQueue else { throw I18nError("error.noDatabase", [:], "No database is open") }
        let newId = try Apply.applyReturningId(dbQueue: q, action: action.rawValue, args: args)
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
        return newId
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
            let counterparties = try Projection.counterparties(dbQueue: q, ledgerId: id)
            let budgetGroupNames = try Projection.budgetGroupNames(dbQueue: q, ledgerId: id)
            let budgetGroups = try Projection.budgetGroups(dbQueue: q, ledgerId: id)
            let holdings = try Projection.holdings(dbQueue: q, ledgerId: id)
            let scheduled = try Projection.scheduledTemplates(dbQueue: q, ledgerId: id)
            let exchangeRates = try Projection.exchangeRates(dbQueue: q)
            let rules = try Projection.rules(dbQueue: q, ledgerId: id)
            let tags = try Projection.tags(dbQueue: q, ledgerId: id)
            let displayCurrencyByLedger = try Projection.displayCurrencyByLedger(dbQueue: q)

            self.txns = txns; self.accounts = accounts; self.accountGroups = accountGroups
            self.budgets = budgets; self.categories = categories; self.counterparties = counterparties
            self.budgetGroupNames = budgetGroupNames; self.budgetGroups = budgetGroups
            self.holdings = holdings; self.scheduled = scheduled; self.exchangeRates = exchangeRates
            self.rules = rules; self.tags = tags; self.displayCurrencyByLedger = displayCurrencyByLedger
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
