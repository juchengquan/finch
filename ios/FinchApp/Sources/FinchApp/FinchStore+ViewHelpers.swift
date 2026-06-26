import Foundation
import FinchCore

/// The read / format surface the views call: money formatting (all via Money +
/// the rate map), the active-ledger display-currency, account & budget grouping,
/// attachments, the anomaly check, and UTC day math. Split out of
/// FinchStore.swift; no published state here — these read the core's projected
/// slices. One definition each.
extension FinchStore {

    public var baseCurrency: String {
        ledgers.first { $0.id == activeLedgerId }?.base ?? Money.hubCurrency
    }
    /// Per-ledger display currency (DB-backed via app_state.displayCurrencyByLedger);
    /// defaults to the active ledger's base until the user picks one.
    public var displayCurrency: String { displayCurrencyByLedger[activeLedgerId] ?? baseCurrency }

    /// Currencies offerable as a display currency: the ledger base + any currency
    /// with an exchange rate (so the conversion actually resolves).
    public var availableDisplayCurrencies: [String] {
        [baseCurrency] + Set(exchangeRates.map(\.currency)).subtracting([baseCurrency]).sorted()
    }

    /// Set the active ledger's display currency (per-ledger).
    public func setDisplayCurrency(_ currency: String) {
        try? apply(.setDisplayCurrency, Args(["ledgerId": .string(activeLedgerId), "currency": .string(currency)]))
    }

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

    public func toBase(_ amount: Double, from currency: String?) -> Double {
        Money.convert(amount, from: currency ?? baseCurrency, to: baseCurrency, rates: rateMap) ?? amount
    }
    /// account-currency → ledger base (public, for the Phase 7 widget snapshot).
    public func baseAmount(_ amount: Double, from currency: String?) -> Double { toBase(amount, from: currency) }

    // MARK: - Attachments (engine is filesystem-agnostic; file cleanup is app-side)

    /// Attachments for a transaction (in-app receipt display).
    public func attachments(for txId: String) -> [AttachmentRow] {
        guard let q = dbQueue else { return [] }
        return (try? Projection.attachments(dbQueue: q, txId: txId)) ?? []
    }
    /// The live attachments directory (next to the DB); the pack reads from here.
    public var attachmentsRoot: URL {
        liveDBURL.deletingLastPathComponent().appendingPathComponent("attachments", isDirectory: true)
    }
    /// Absolute on-disk URL for an attachment (`relPath` already includes "attachments/…").
    public func attachmentURL(for att: AttachmentRow) -> URL {
        attachmentsRoot.deletingLastPathComponent().appendingPathComponent(att.relPath)
    }
    private func unlink(relPaths: [String]) {
        let root = attachmentsRoot.deletingLastPathComponent()   // Application Support (relPath includes 'attachments/…')
        for rel in relPaths { try? FileManager.default.removeItem(at: root.appendingPathComponent(rel)) }
    }
    /// Remove an attachment row AND unlink its on-disk file.
    public func removeAttachment(id: String, relPath: String) throws {
        try apply(.removeAttachment, Args(["id": .string(id)]))
        unlink(relPaths: [relPath])
    }
    /// Delete a transaction AND unlink its receipts' files (captured before the
    /// cascade delete drops the rows).
    public func deleteTransaction(_ txId: String) throws {
        let files = attachments(for: txId).map { $0.relPath }
        try apply(.deleteTransaction, Args(["id": .string(txId)]))
        unlink(relPaths: files)
    }
    /// Human-readable transactions CSV for the active ledger, optionally scoped
    /// to one `YYYY-MM` month (Insights → Breakdown export). Mirrors the web's
    /// `/api/export/transactions?ledger=…&month=…`.
    public func transactionsCsv(month: String?) throws -> String {
        guard let q = dbQueue else { return "" }
        let lid = activeLedgerId
        return try q.read { db in try TxExport.csv(db, ledgerId: lid, month: month) }
    }

    // MARK: - Money formatting

    /// ledger base → display.
    public func displayMoneyBase(_ baseAmount: Double) -> String {
        let v = Money.convert(baseAmount, from: baseCurrency, to: displayCurrency, rates: rateMap) ?? baseAmount
        return Money.format(v, currency: displayCurrency)
    }
    /// account currency → base → display.
    public func displayMoney(_ amount: Double, from currency: String?) -> String {
        displayMoneyBase(toBase(amount, from: currency))
    }

    /// Whether a transaction is an unusual-spend anomaly (per-merchant z-score).
    /// merchantStats is computed once per projection and cached.
    public func isAnomaly(_ tx: Tx) -> Bool {
        if merchantStatsCache == nil { merchantStatsCache = Selectors.merchantStats(txns, activeLedgerId) }
        return Selectors.anomalyScore(tx, merchantStatsCache ?? [:])?.isAnomaly ?? false
    }

    /// The running balance (ledger base) of a transaction's account immediately
    /// after that transaction — the statement-style figure shown on each row.
    /// Built once per projection: opening balance (base) + cumulative base amounts
    /// oldest→newest, per account. `txns` is newest-first (projection order), so we
    /// walk it reversed. Opening entries are excluded from the feed (Projection), so
    /// seeding from `openingBalanceBase` doesn't double-count.
    public func runningBalanceBase(for tx: Tx) -> Double {
        if runningBalanceCache == nil {
            var running = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.openingBalanceBase ?? 0) })
            var result: [String: Double] = [:]
            for t in txns.reversed() {
                running[t.account, default: 0] += t.amount
                result[t.id] = running[t.account]
            }
            runningBalanceCache = result
        }
        return runningBalanceCache?[tx.id] ?? 0
    }

    // MARK: - Accounts grouping

    public var accountGroupsOrdered: [String] {
        var seen = Set<String>(); var out: [String] = []
        for a in accounts { let g = a.groupName ?? "Ungrouped"; if seen.insert(g).inserted { out.append(g) } }
        return out
    }
    public func accounts(in group: String) -> [AccountRow] {
        accounts.filter { ($0.groupName ?? "Ungrouped") == group }
    }
    /// Archived (is_active = 0) accounts for the active ledger — the unarchive view.
    public func archivedAccounts() -> [AccountRow] {
        guard let q = dbQueue else { return [] }
        return (try? Projection.archivedAccounts(dbQueue: q, ledgerId: activeLedgerId)) ?? []
    }
    /// This account's transactions (active ledger), newest first.
    public func transactions(for accountId: String) -> [Tx] {
        Selectors.selectTransactions(txns, ListOptions(ledgerId: activeLedgerId, accountId: accountId))
    }
    public func subtotalDisplay(for group: String) -> String {
        displayMoneyBase(accounts(in: group).reduce(0.0) { $0 + toBase($1.balance, from: $1.currency) })
    }
    public var netWorthDisplay: String {
        displayMoneyBase(accounts.filter { ($0.includeInNetWorth ?? 1) == 1 }
            .reduce(0.0) { $0 + toBase($1.balance, from: $1.currency) })
    }
    /// Total liabilities (active ledger): the sum of negative balances among
    /// net-worth accounts, in display currency (a negative figure). Assets +
    /// liabilities = net worth.
    public var liabilitiesDisplay: String {
        displayMoneyBase(accounts.filter { ($0.includeInNetWorth ?? 1) == 1 }
            .reduce(0.0) { sum, a in
                let b = toBase(a.balance, from: a.currency)
                return b < 0 ? sum + b : sum
            })
    }

    // MARK: - Budgets grouping

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
    static func isoDay(_ d: Date) -> String { dayFormatter.string(from: d) }
    static func parseDay(_ s: String) -> Date? { dayFormatter.date(from: String(s.prefix(10))) }
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
        return d.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppDate.h24Locale))
    }
    public var rowCountsOrdered: [(String, Int)] {
        rowCounts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}
