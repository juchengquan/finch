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

    /// The DATA-anchored "today" = the max tx date (falls back to the wall
    /// clock only when there are no transactions). The web anchors the Insights
    /// forecast/digest on the data (demo determinism, no hydration mismatch) — use
    /// this ONLY for those surfaces. BUDGET CYCLES no longer use it: they take
    /// `budgetToday`, because a cycle that stops advancing when you stop spending
    /// showed last month's budget on the 1st. See `budgetToday`.
    /// Anything that means the literal current day (calendar Today ring,
    /// Today/Yesterday labels, scheduled next-runs, posting dates) must use
    /// `wallToday` — this value lags behind the real date whenever the newest
    /// transaction isn't from today.
    public var today: String { txns.map(\.date).max() ?? Self.isoDay(Date()) }

    /// The real current day (wall clock), for surfaces that mean literal today.
    public var wallToday: String { Self.isoDay(Date()) }

    /// The day BUDGET CYCLES are measured from — the wall clock, deliberately NOT
    /// `today`.
    ///
    /// Budget windows used to be anchored on the data, matching the web, whose two
    /// stated reasons are demo determinism and avoiding a React hydration mismatch
    /// (`no Date() → no hydration mismatch`). Neither applies to a native app: there
    /// is no server render here, and a real ledger is not a fixture.
    ///
    /// What it cost: with the newest transaction on 31 July, opening the app on
    /// 1 August showed JULY's cycle — last month's spend, "0 days left" on every
    /// budget — because the ledger's "today" had not moved. Any quiet spell froze
    /// the cycle at the last thing you recorded.
    ///
    /// Named rather than spelled `wallToday` at each call site so this decision lives
    /// in one place if it is ever revisited.
    public var budgetToday: String { wallToday }

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

    /// Confirm several pending transactions as ONE write.
    ///
    /// The multi-select toolbars used to loop `apply` per row, and every `apply`
    /// fires a full round of post-write work — a whole-ledger reprojection, a widget
    /// rebuild, a Spotlight re-index. Ten selected rows meant ten rounds, all on the
    /// main actor, while ten rows were trying to animate out of the pending section.
    ///
    /// Returns how many ops did NOT throw — which is not the same as rows changed:
    /// the engine treats an unresolvable id as a silent no-op, exactly as the old
    /// per-row loop did. The count exists because `applyBatch` skips a genuinely
    /// rejected op rather than abandoning the rest, so the caller can say what it
    /// could not apply instead of failing silently — see the `bulkConfirm` sites.
    @discardableResult
    public func confirmTransactions(_ ids: [String]) -> Int {
        applyBatch(ids.map { (action: ActionName.confirmTransaction, args: Args(["id": .string($0)])) })
    }

    /// Delete several transactions as one write, unlinking their receipts after.
    /// Attachment paths are read BEFORE the delete, while the rows still exist.
    @discardableResult
    public func deleteTransactions(_ ids: [String]) -> Int {
        let files = ids.flatMap { attachments(for: $0).map { $0.relPath } }
        let applied = applyBatch(ids.map { (action: ActionName.deleteTransaction, args: Args(["id": .string($0)])) })
        unlink(relPaths: files)
        return applied
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

    /// ledger base → display. Returns the privacy mask when privacy mode is on
    /// (masking here propagates to displayMoney(_:from:)/subtotalDisplay/netWorthDisplay).
    public func displayMoneyBase(_ baseAmount: Double) -> String {
        if privacyMode { return FinchStore.moneyMask }
        let v = Money.convert(baseAmount, from: baseCurrency, to: displayCurrency, rates: rateMap) ?? baseAmount
        return Money.format(v, currency: displayCurrency)
    }
    /// account currency → base → display. Inherits privacy masking via
    /// `displayMoneyBase`.
    public func displayMoney(_ amount: Double, from currency: String?) -> String {
        displayMoneyBase(toBase(amount, from: currency))
    }
    /// ledger base → display value, exact (no symbol; the cell adds sign and
    /// color) — the calendar cells' formatter. Cents show only when non-zero
    /// ("19.99", "1,850"), so the cell figure always corroborates the amounts
    /// in the occurrence rows and the List view instead of rounding 19.99 into
    /// a contradictory 20. Nil in privacy mode: the cells drop their amount
    /// lines entirely rather than render a grid of masks.
    public func displayExactBase(_ baseAmount: Double) -> String? {
        if privacyMode { return nil }
        let v = Money.convert(baseAmount, from: baseCurrency, to: displayCurrency, rates: rateMap) ?? baseAmount
        let cents = (abs(v) * 100).rounded() / 100
        let f = cents == cents.rounded() ? Self.wholeAmountFormatter : Self.centsAmountFormatter
        return f.string(from: cents as NSNumber)
    }
    private static let wholeAmountFormatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f
    }()
    private static let centsAmountFormatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
        return f
    }()

    /// Format an amount already denominated in its own currency — no conversion,
    /// just format-or-mask. The privacy-aware replacement for calling
    /// Money.format directly in a view (web's `native` formatter).
    public func displayNative(_ amount: Double, currency: String) -> String {
        privacyMode ? FinchStore.moneyMask : Money.format(amount, currency: currency)
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
    ///
    /// **Pending transactions are skipped, and get no figure of their own (nil).**
    ///
    /// The walk used to add every transaction regardless of status, while the
    /// account's stored balance counts only confirmed ones — two rules for the same
    /// quantity. Setting a $4,200 salary to pending therefore moved the account
    /// balance and left every row's running balance exactly where it was, because by
    /// the walk's rule nothing HAD changed: same row, same amount, only its status.
    /// The top row then claimed a balance $4,200 above the one printed over it.
    ///
    /// A pending row returns nil rather than the preceding confirmed balance: this
    /// column means "the balance after this cleared", and a pending row has not.
    /// Printing the previous row's figure would be a number that is not true of the
    /// row it sits on.
    public func runningBalanceBase(for tx: Tx) -> Double? {
        if runningBalanceCache == nil {
            var running = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.openingBalanceBase ?? 0) })
            var result: [String: Double] = [:]
            for t in txns.reversed() {
                guard t.pending != true else { continue }
                running[t.account, default: 0] += t.amount
                result[t.id] = running[t.account]
            }
            runningBalanceCache = result
        }
        return runningBalanceCache?[tx.id]
    }

    // MARK: - Scheduled

    /// How many split rows a scheduled template has. Non-zero on an income
    /// template means the posting fans out across several ACCOUNTS — see
    /// `ScheduledPostRouting`, which keeps those on the silent engine path.
    public func scheduledSplitCount(templateId: String) -> Int {
        guard let q = dbQueue else { return 0 }
        return (try? Projection.scheduledSplitCount(dbQueue: q, templateId: templateId)) ?? 0
    }

    /// A draft `Tx` seeding the Add sheet from ONE occurrence of a scheduled
    /// template — the same posting `postScheduled` would make, but presented for
    /// confirmation instead of written silently.
    ///
    /// `date` and `occurrenceDate` are BOTH the occurrence: the date is what the
    /// user sees and may still move, the occurrence is the calendar cell being
    /// fulfilled, and keeping them separate is what lets the badge flip even when
    /// the user re-dates the transaction (`Selectors.scheduledPostedMap`).
    ///
    /// A variable-amount template (`amount == nil`) yields 0, which the sheet
    /// renders as an EMPTY amount field — that case used to be refused outright
    /// by the engine (`error.scheduled.variableAmount`).
    public func txPrefill(for template: ScheduledTemplate, occurrence: String) -> Tx {
        let magnitude = template.amount.map(abs) ?? 0
        let isInflow = template.type == "income" || template.type == "refund"
        let description = template.description ?? template.name
        return Tx(id: "", merchant: description, category: template.categoryId,
                  amount: isInflow ? magnitude : -magnitude,
                  account: template.accountId, date: occurrence,
                  kind: template.type,
                  // A transfer has no merchant field in the sheet, so its
                  // description rides along as the note instead.
                  note: template.type == "transfer" ? description : nil,
                  sourceTemplateId: template.id, occurrenceDate: occurrence)
    }

    // MARK: - Accounts grouping

    /// Group names in `account_groups.sort_order` (store.accountGroups is projected
    /// ORDER BY sort_order, name). Includes EMPTY groups — a freshly added group
    /// shows immediately (mirrors budgetGroupsOrdered).
    public var accountGroupsOrdered: [String] {
        accountGroups.map(\.name)
    }
    /// Accounts with no group — rendered bare at the top of the list (no "Ungrouped" header).
    public var ungroupedAccounts: [AccountRow] { accounts.filter { $0.groupName == nil } }
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

    /// Group names in `budget_groups.sort_order` (store.budgetGroups is projected
    /// ORDER BY sort_order, name). Includes EMPTY groups — a freshly added group
    /// shows immediately (user direction; the old hide-empty rule read as a bug).
    public var budgetGroupsOrdered: [String] {
        budgetGroups.map(\.name)
    }
    /// Budgets with no (resolvable) group — rendered bare at the top.
    public var ungroupedBudgets: [BudgetRow] {
        applyBudgetOrder(budgets.filter { $0.groupId.flatMap { budgetGroupNames[$0] } == nil })
    }
    public func budgets(in group: String) -> [BudgetRow] {
        applyBudgetOrder(budgets.filter { (($0.groupId.flatMap { budgetGroupNames[$0] }) ?? "Ungrouped") == group })
    }
    /// Apply the user's manual order (app_state budgetOrderByLedger); unknown ids
    /// (e.g. newly created budgets) keep their relative created_at order, after
    /// the ordered ones.
    private func applyBudgetOrder(_ list: [BudgetRow]) -> [BudgetRow] {
        guard let order = budgetOrderByLedger[activeLedgerId], !order.isEmpty else { return list }
        let pos = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return list.enumerated().sorted {
            (pos[$0.element.id] ?? order.count + $0.offset) < (pos[$1.element.id] ?? order.count + $1.offset)
        }.map(\.element)
    }
    /// The group's total budget (sum of each member's cycle base) in display
    /// currency — the Budgets-page analogue of Accounts' `subtotalDisplay`.
    public func budgetSubtotalDisplay(for group: String) -> String {
        displayMoneyBase(budgets(in: group).reduce(0.0) {
            $0 + Selectors.budgetProgress($1, txns, budgetToday, categoryNodes).base
        })
    }
    /// Ledger-wide budget health for the Budgets summary card — spend totals with
    /// savings goals split out (see BudgetSummary). Raw base-currency doubles; the
    /// card formats via the privacy-aware displayMoneyBase.
    var budgetSummary: BudgetSummary {
        BudgetSummary.compute(budgets) { b in
            let p = Selectors.budgetProgress(b, txns, budgetToday, categoryNodes)
            return (p.used, p.base, p.over)
        }
    }

    /// Whole days from the WALL CLOCK to `ymd` INCLUSIVE (device timezone), floored at 0.
    ///
    /// Two things this gets right that the previous version did not, both reported
    /// from a device on the 1st of a month:
    ///
    /// Dates here are in the DEVICE's timezone, not UTC: `AppDate` sets a locale but
    /// no `timeZone`, so its formatters use the current one. (An older comment on this
    /// method claimed UTC. Harmless while the unit was whole days; it would be an
    /// hours-sized error now that `remaining(until:)` exists.)
    ///
    /// **The anchor.** It measured from `today` — the newest transaction's date —
    /// while the cycle it is describing comes from `budgetToday` (the wall clock).
    /// Mixing the two overstated the count by however long since you last recorded
    /// something: `Aug 31 - Jul 30 = 32 days left` in an August that has 31.
    ///
    /// **Today counts.** Counting only the days AFTER today made a cycle's final day
    /// read "0 days left" while it was still running and still spendable. Today is a
    /// day you can still use, so it is included: the 1st of a 31-day month reads
    /// "31 days left", the last day reads "1 day left", and it rolls over the morning
    /// after.
    ///
    /// Deliberately different from `MonthForecast.daysRemaining`, which stays
    /// exclusive — that one is a term in the run-rate maths ("days of spending still
    /// to come"), not a label.
    public func daysLeft(until ymd: String) -> Int {
        guard let to = Self.parseDay(ymd), let now = Self.parseDay(budgetToday) else { return 0 }
        let daysAfterToday = Int((to.timeIntervalSince(now) / 86_400).rounded(.up))
        return max(0, daysAfterToday + 1)
    }

    /// How much of a cycle is left, at the granularity worth showing.
    ///
    /// A budget cycle ends at a MOMENT, and where that moment falls depends on
    /// whether the budget carries a turnover time:
    ///
    ///  - Without one, `cycle.to` is the last day and the cycle runs until that day
    ///    ENDS — local midnight, derived rather than stored.
    ///  - With one, `cycle.to` is the day the cycle stops ON and `toTime` is the
    ///    moment inside it. Counting to the end of that day instead would overstate
    ///    the remainder by up to a day — the same class of error as the "32 days
    ///    left" in a 31-day month this helper was written to fix.
    ///
    /// Hours appear only on the FINAL day, where they are the useful unit — "7 hours
    /// left" beats "1 day left" when you are deciding whether to buy something now.
    /// Above that it stays in days, matching `daysLeft`.
    public enum CycleRemaining: Equatable, Sendable {
        case days(Int)          // 24h or more, inclusive of today
        case hours(Int)         // the final day, 1...23
        case lessThanAnHour     // the last stretch; minutes would go stale unrendered
        case ended
    }

    /// - Note: computed at render time, so it does not tick on its own. Fine at hour
    ///   granularity; it is the reason this stops short of minutes.
    /// - Parameter now: the moment to measure from. Defaults to the wall clock;
    ///   injectable so the boundary cases can be asserted exactly instead of
    ///   depending on what time of day the suite happens to run.
    public func remaining(until ymd: String, toTime: String? = nil, now: Date = Date()) -> CycleRemaining {
        guard let lastDay = Self.parseDay(ymd) else { return .ended }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let cycleEnd: Date
        if let t = toTime, !t.isEmpty, t != "00:00" {
            // A turnover time: the cycle stops at that moment ON `ymd`.
            let parts = t.split(separator: ":")
            let h = Int(parts.first ?? "0") ?? 0, m = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
            guard let end = cal.date(byAdding: DateComponents(hour: h, minute: m),
                                     to: cal.startOfDay(for: lastDay)) else { return .ended }
            cycleEnd = end
        } else {
            // The cycle ends when its last day ends: the start of the NEXT day. Built with
            // Calendar rather than +86400 so a DST boundary cannot shift it by an hour.
            guard let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: lastDay)) else {
                return .ended
            }
            cycleEnd = end
        }
        let seconds = cycleEnd.timeIntervalSince(now)
        if seconds <= 0 { return .ended }
        if seconds >= 86_400 { return .days(Int((seconds / 86_400).rounded(.up))) }
        if seconds >= 3_600 { return .hours(Int(seconds / 3_600)) }
        return .lessThanAnHour
    }

    // MARK: - Per-ledger reads (two-layer Ledger tab: detail works for ANY ledger)

    /// Summary figures for the ledger detail page; money fields are in the
    /// ledger's own base currency. Computed for the active ledger from the live
    /// published state, and for any other ledger from a fresh projection read.
    public struct LedgerSummary: Equatable, Sendable {
        public let netWorth: Double
        public let monthIncome: Double
        public let monthExpense: Double
        public let accounts: [AccountRow]
    }

    /// A ledger's base currency (falls back to the active base if unknown).
    func baseCurrency(forLedger ledgerId: String) -> String {
        ledgers.first { $0.id == ledgerId }?.base ?? baseCurrency
    }
    /// Display currency chosen for a ledger (defaults to its base).
    public func displayCurrency(forLedger ledgerId: String) -> String {
        displayCurrencyByLedger[ledgerId] ?? baseCurrency(forLedger: ledgerId)
    }
    /// Display-currency options for a ledger: its base + every FX rate currency.
    public func availableDisplayCurrencies(forLedger ledgerId: String) -> [String] {
        let base = baseCurrency(forLedger: ledgerId)
        return [base] + Set(exchangeRates.map(\.currency)).subtracting([base]).sorted()
    }
    /// account-currency → a specific ledger's base.
    func toBase(_ amount: Double, from currency: String?, ledgerBase: String) -> Double {
        Money.convert(amount, from: currency ?? ledgerBase, to: ledgerBase, rates: rateMap) ?? amount
    }
    /// Format a ledger-base amount into that ledger's display currency (privacy-masked).
    public func displayMoney(_ baseAmount: Double, forLedger ledgerId: String) -> String {
        if privacyMode { return FinchStore.moneyMask }
        let base = baseCurrency(forLedger: ledgerId)
        let disp = displayCurrency(forLedger: ledgerId)
        let v = Money.convert(baseAmount, from: base, to: disp, rates: rateMap) ?? baseAmount
        return Money.format(v, currency: disp)
    }
    /// Accounts for a ledger: live state when active, else a fresh read.
    func accounts(forLedger ledgerId: String) -> [AccountRow] {
        if ledgerId == activeLedgerId { return accounts }
        guard let q = dbQueue else { return [] }
        return (try? Projection.accounts(dbQueue: q, ledgerId: ledgerId)) ?? []
    }
    /// Transactions for a ledger: live state when active, else a fresh read.
    func txns(forLedger ledgerId: String) -> [Tx] {
        if ledgerId == activeLedgerId { return txns }
        guard let q = dbQueue else { return [] }
        return (try? Projection.run(dbQueue: q, ledgerId: ledgerId)) ?? []
    }
    /// Net worth (ledger base) for any ledger — used by the list rows.
    public func netWorth(forLedger ledgerId: String) -> Double {
        let base = baseCurrency(forLedger: ledgerId)
        return Selectors.ledgerNetWorth(accounts(forLedger: ledgerId), ledgerId) { amt, ccy in
            self.toBase(amt, from: ccy, ledgerBase: base)
        }
    }
    /// Full per-ledger summary for the detail page. "This month" is anchored to
    /// the ledger's own latest transaction date (wall clock if empty), mirroring
    /// how the app anchors `today` to the max tx date.
    public func ledgerSummary(_ ledgerId: String) -> LedgerSummary {
        let base = baseCurrency(forLedger: ledgerId)
        let accts = accounts(forLedger: ledgerId)
        let tx = txns(forLedger: ledgerId)
        let nw = Selectors.ledgerNetWorth(accts, ledgerId) { amt, ccy in
            self.toBase(amt, from: ccy, ledgerBase: base)
        }
        let anchor = tx.map(\.date).max() ?? Self.isoDay(Date())
        let p = Selectors.monthlyCashflow(tx, ledgerId, String(anchor.prefix(7)), 1).first
        return LedgerSummary(netWorth: nw, monthIncome: p?.inc ?? 0,
                             monthExpense: p?.exp ?? 0, accounts: accts)
    }
    /// Set display currency for a specific (possibly non-active) ledger.
    public func setDisplayCurrency(_ currency: String, ledgerId: String) {
        try? apply(.setDisplayCurrency, Args(["ledgerId": .string(ledgerId), "currency": .string(currency)]))
    }

    // MARK: - Day helpers
    // These delegate to `AppDate.isoDay` rather than owning a second formatter. They
    // used to keep their own, pinned to UTC, which made this the app's *other*
    // yyyy-MM-dd converter — disagreeing with `AppDate` by up to a day. That is what
    // put `wallToday` (below) a day behind between 00:00 and 08:00 at UTC+8, so
    // "today" comparisons and the Scheduled "missed" badge were wrong every morning.
    static func isoDay(_ d: Date) -> String { AppDate.isoDay.string(from: d) }
    static func parseDay(_ s: String) -> Date? { AppDate.isoDay.date(from: String(s.prefix(10))) }
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
