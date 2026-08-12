import Foundation

/// The iOS port's mirror of the web's `lib/select.ts` — the read-side selectors,
/// pure functions over the projected `Tx[]`. Phase 1.0 ships the 7 selectors the
/// 4 tabs need; ported verbatim (same filters, same r2 rounding, same date math).
public enum Selectors {

    // MARK: shared helpers

    static func ledgerOf(_ t: Tx) -> String { t.ledgerId ?? "personal" }

    static func kindOf(_ t: Tx) -> String {
        if let k = t.kind { return k }
        if t.transferGroupId != nil { return "transfer" }
        return t.amount > 0 ? "income" : "expense"
    }

    static func isSpend(_ t: Tx) -> Bool { kindOf(t) == "expense" || kindOf(t) == "refund" }

    static func merchantKey(_ t: Tx) -> String? {
        if let cp = t.counterpartyId { return "cp:\(cp)" }
        let name = t.merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return name.isEmpty ? nil : "m:\(name)"
    }

    /// Math.round(n * 100) / 100 — 2-decimal rounding matching the web's `r2`.
    static func r2(_ n: Double) -> Double { (n * 100).rounded() / 100 }

    // MARK: accountBalance

    public static func accountBalance(_ accounts: [AccountRow], _ accountId: String) -> Double {
        accounts.first { $0.id == accountId }?.balance ?? 0
    }

    // MARK: selectTransactions

    /// Case-insensitive query match over what a feed row displays: the merchant
    /// text, the category title (incl. split categories), and tag names — the
    /// id→name lookups come from the caller. Mirror of the web's `txMatchesQuery`.
    public static func txMatchesQuery(_ t: Tx, _ query: String,
                                      categoryNames: [String: String] = [:],
                                      tagNames: [String: String] = [:]) -> Bool {
        let q = query.lowercased()
        func catHit(_ id: String?) -> Bool {
            guard let id else { return false }
            return (categoryNames[id] ?? "").lowercased().contains(q)
        }
        return t.merchant.lowercased().contains(q)
            || catHit(t.category)
            || (t.splits ?? []).contains { catHit($0.categoryId) }
            || (t.tags ?? []).contains { (tagNames[$0] ?? "").lowercased().contains(q) }
    }

    public static func selectTransactions(_ txns: [Tx], _ opts: ListOptions,
                                          categoryNames: [String: String] = [:],
                                          tagNames: [String: String] = [:]) -> [Tx] {
        var out = txns.filter { ledgerOf($0) == opts.ledgerId }
        if opts.direction == "in" { out = out.filter { $0.amount > 0 } }
        if opts.direction == "out" { out = out.filter { $0.amount < 0 } }
        if let q = opts.query {
            out = out.filter { txMatchesQuery($0, q, categoryNames: categoryNames, tagNames: tagNames) }
        }
        if let a = opts.accountId { out = out.filter { $0.account == a } }
        if let c = opts.categoryId { out = out.filter { $0.category == c } }
        if let s = opts.status { out = out.filter { ($0.pending ?? false) == (s == "pending") } }
        // A bare "yyyy-MM-dd" compares against the transaction's DATE, exactly as it
        // always has. A bound carrying a time compares MOMENTS instead — and stays
        // inclusive at both ends, because a filter range is what the user typed
        // ("from here to here"), not a cycle whose top belongs to the next window.
        if let f = opts.from {
            out = f.count > 10 ? out.filter { momentOf($0) >= f } : out.filter { $0.date >= f }
        }
        if let t = opts.to {
            out = t.count > 10 ? out.filter { momentOf($0) <= t } : out.filter { $0.date <= t }
        }
        if let lo = opts.minAmount { out = out.filter { abs($0.amount) >= lo } }
        if let hi = opts.maxAmount { out = out.filter { abs($0.amount) <= hi } }
        if let tags = opts.tagIds, !tags.isEmpty {
            let want = Set(tags)
            out = out.filter {
                let have = Set($0.tags ?? [])
                return opts.tagsMatchAll ? want.isSubset(of: have) : !want.isDisjoint(with: have)
            }
        }
        // Stable sort: equal (date,time) rows keep input order, matching the
        // web's stable Array.sort (its comparator returns 0 for ties).
        out = out.enumerated().sorted { a, b in
            if a.element.date != b.element.date { return a.element.date > b.element.date }  // date DESC
            let at = a.element.time ?? "", bt = b.element.time ?? ""
            if at != bt { return at > bt }                                                 // time DESC
            return a.offset < b.offset
        }.map { $0.element }
        if let limit = opts.limit {
            let off = opts.offset ?? 0
            out = Array(out.dropFirst(off).prefix(limit))
        }
        return out
    }

    // MARK: categorySpend

    public static func categorySpend(_ txns: [Tx], _ ledgerId: String, _ month: String? = nil) -> [String: Double] {
        var m: [String: Double] = [:]
        for t in txns {
            if ledgerOf(t) != ledgerId { continue }
            if let month, t.date.prefix(7) != month { continue }
            if (t.pending ?? false) || !isSpend(t) { continue }
            if let splits = t.splits, !splits.isEmpty {
                for s in splits where s.categoryId != nil { m[s.categoryId!, default: 0] += -s.amountBase }
            } else if let cat = t.category {
                m[cat, default: 0] += -t.amount
            }
        }
        return m
    }

    // MARK: merchantStats

    public static func merchantStats(_ txns: [Tx], _ ledgerId: String) -> [String: MerchantStats] {
        var sums: [String: (n: Int, sum: Double, sqSum: Double)] = [:]
                // One row per PURCHASE. Wrong twice over otherwise: the count is
        // inflated AND each leg's magnitude is a fraction of what was spent,
        // so the mean and deviation are distorted, not merely rescaled.
        for t in byPurchase(txns) {
            if ledgerOf(t) != ledgerId { continue }
            if (t.pending ?? false) { continue }
            if kindOf(t) != "expense" { continue }
            guard let key = merchantKey(t) else { continue }
            let mag = abs(t.nativeAmount ?? t.amount)
            var b = sums[key] ?? (0, 0, 0)
            b.n += 1; b.sum += mag; b.sqSum += mag * mag
            sums[key] = b
        }
        var out: [String: MerchantStats] = [:]
        for (key, b) in sums {
            let mean = b.sum / Double(b.n)
            let variance = b.n > 0 ? b.sqSum / Double(b.n) - mean * mean : 0
            let std = Swift.max(0, variance).squareRoot()
            out[key] = MerchantStats(count: b.n, mean: r2(mean), std: r2(std))
        }
        return out
    }

    // MARK: topMerchants

    /// Top merchants by net expense total (base currency, refunds netted like
    /// `categorySpend`), optionally scoped to a "YYYY-MM" month. Merchants are
    /// keyed like `merchantStats` (counterparty FK first, normalized name
    /// fallback); the display name is the first-seen row's merchant text.
    public static func topMerchants(_ txns: [Tx], _ ledgerId: String, _ month: String? = nil,
                                    limit: Int = 5) -> [MerchantSpend] {
        var totals: [String: (name: String, total: Double)] = [:]
        for t in txns {
            if ledgerOf(t) != ledgerId { continue }
            if let month, t.date.prefix(7) != month { continue }
            if (t.pending ?? false) || !isSpend(t) { continue }
            guard let key = merchantKey(t) else { continue }
            var b = totals[key] ?? (t.merchant.trimmingCharacters(in: .whitespacesAndNewlines), 0)
            b.total += -t.amount
            totals[key] = b
        }
        return totals.values
            .filter { $0.total > 0 }
            .map { MerchantSpend(name: $0.name, total: r2($0.total)) }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.name < $1.name }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: anomalyScore

    public static func anomalyScore(_ tx: Tx, _ stats: [String: MerchantStats],
                                    minCount: Int = 3, threshold: Double = 2.5) -> AnomalyScore? {
        if kindOf(tx) != "expense" || (tx.pending ?? false) { return nil }
        guard let key = merchantKey(tx), let s = stats[key], s.count >= 2, s.std != 0 else { return nil }
        let mag = abs(tx.nativeAmount ?? tx.amount)
        let z = abs(mag - s.mean) / s.std
        return AnomalyScore(zScore: r2(z), mean: s.mean, count: s.count,
                            isAnomaly: z >= threshold && s.count >= minCount)
    }

    // MARK: counterpartyTxCounts

    /// Is this row pending AND due — i.e. would it belong in "To confirm" today?
    ///
    /// The row-level companion to `pendingSplit`, for the screens that filter one list
    /// rather than building two buckets. Same rule, one definition: a screen that
    /// spelled `pending == true` inline would silently keep nagging about next month.
    public static func isPendingNow(_ t: Tx, today: String) -> Bool {
        t.pending == true && t.date <= today
    }

    /// Split pending transactions into the ones worth confirming NOW and the ones that
    /// have not happened yet.
    ///
    /// `pending` carries two readings in this app. The engine treats it as "has not
    /// counted yet" — pending rows are excluded from spend, budgets and the running
    /// balance. The UI treated it as "needs your attention", pinning EVERY pending row
    /// into a "To confirm (N)" bucket on ten screens. Those agreed only because nothing
    /// was ever pending and future-dated at once. Once a future-dated transaction starts
    /// pending, they come apart: next month's rent is correctly not-counted, and
    /// incorrectly nagging.
    ///
    /// `today` is a PARAMETER, not a read of the clock: this stays pure so its tests can
    /// fix the date. Callers pass `store.wallToday` — the literal current day — never
    /// `store.today`, which is anchored on the data rather than the calendar.
    ///
    /// Day strings compare lexicographically because they are zero-padded ISO
    /// (`2026-08-12`), so no date parsing is needed. The boundary is `>`, NOT `>=`:
    /// something dated today is confirmable today, and that is the app's most common
    /// case.
    ///
    /// Order within each bucket is the input's; callers sort afterwards.
    public static func pendingSplit(_ txns: [Tx], today: String) -> (dueNow: [Tx], upcoming: [Tx]) {
        var dueNow: [Tx] = []
        var upcoming: [Tx] = []
        for t in txns where t.pending == true {
            if t.date > today { upcoming.append(t) } else { dueNow.append(t) }
        }
        return (dueNow, upcoming)
    }

    /// Per-counterparty usage count: non-pending txns in `ledgerId` attributed to a
    /// counterparty by `counterpartyId` (when set & known) else by normalized name.
    /// Keyed by counterparty id; absent for unused merchants. Counts all kinds.
    public static func counterpartyTxCounts(_ txns: [Tx], _ counterparties: [Counterparty], _ ledgerId: String) -> [String: Int] {
        let idSet = Set(counterparties.map(\.id))
        var byName: [String: String] = [:]   // normalized name → counterparty id (first wins)
        for c in counterparties {
            let n = c.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !n.isEmpty, byName[n] == nil { byName[n] = c.id }
        }
        var out: [String: Int] = [:]
                // One row per PURCHASE: a purchase paid from several accounts is
        // several rows, and counting rows counts it more than once.
        for t in byPurchase(txns) {
            if ledgerOf(t) != ledgerId { continue }
            if (t.pending ?? false) { continue }
            let cpId: String?
            if let cid = t.counterpartyId, idSet.contains(cid) {
                cpId = cid
            } else {
                let n = t.merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                cpId = n.isEmpty ? nil : byName[n]
            }
            if let id = cpId { out[id, default: 0] += 1 }
        }
        return out
    }

    /// A merchant's transactions: linked by counterpartyId, or matched by normalized
    /// merchant name (mirrors `counterpartyTxCounts`' resolution). Active-ledger,
    /// newest-first. Excludes pending by default, matching `counterpartyTxCounts`
    /// (the Merchants page pill) — these used to disagree, so the detail list and
    /// its Total counted pending while the pill did not. Callers that genuinely
    /// want pending (feed filtering, merge impact) opt in.
    public static func merchantTransactions(_ txns: [Tx], _ counterparties: [Counterparty],
                                            _ counterpartyId: String, _ ledgerId: String,
                                            includePending: Bool = false) -> [Tx] {
        let idSet = Set(counterparties.map(\.id))
        var byName: [String: String] = [:]
        for c in counterparties {
            let n = c.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !n.isEmpty, byName[n] == nil { byName[n] = c.id }
        }
        let matched = txns.filter { t in
            guard ledgerOf(t) == ledgerId else { return false }
            if !includePending, (t.pending ?? false) { return false }
            let resolved: String?
            if let cid = t.counterpartyId, idSet.contains(cid) {
                resolved = cid
            } else {
                let n = t.merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                resolved = n.isEmpty ? nil : byName[n]
            }
            return resolved == counterpartyId
        }
        return matched.sorted { $0.date != $1.date ? $0.date > $1.date : ($0.time ?? "") > ($1.time ?? "") }
    }

    /// Per-tag usage count: non-pending txns in `ledgerId` tagged with the tag.
    /// Keyed by tag id (`tx.tags` holds tag ids); absent for unused tags.
    public static func tagTxCounts(_ txns: [Tx], _ ledgerId: String) -> [String: Int] {
        var out: [String: Int] = [:]
                // One row per PURCHASE: a purchase paid from several accounts is
        // several rows, and counting rows counts it more than once.
        for t in byPurchase(txns) {
            if ledgerOf(t) != ledgerId { continue }
            if (t.pending ?? false) { continue }
            for tagId in (t.tags ?? []) { out[tagId, default: 0] += 1 }
        }
        return out
    }

    /// Per-category usage count (DIRECT, no descendant rollup): non-pending txns in
    /// `ledgerId` whose category leg(s) reference the category. A split txn is
    /// attributed to its split legs' categoryIds; otherwise to `tx.category`. Each
    /// txn counts once per distinct category. Keyed by category id; absent for unused.
    public static func categoryTxCounts(_ txns: [Tx], _ ledgerId: String) -> [String: Int] {
        var out: [String: Int] = [:]
                // One row per PURCHASE: a purchase paid from several accounts is
        // several rows, and counting rows counts it more than once.
        for t in byPurchase(txns) {
            if ledgerOf(t) != ledgerId { continue }
            if (t.pending ?? false) { continue }
            var cats = Set<String>()
            if let splits = t.splits, !splits.isEmpty {
                for s in splits { if let c = s.categoryId { cats.insert(c) } }
            } else if let c = t.category {
                cats.insert(c)
            }
            for c in cats { out[c, default: 0] += 1 }
        }
        return out
    }

    /// Transactions in `ledgerId` that reference `categoryId`, matched the SAME
    /// way as `categoryTxCounts` — a split txn by its split legs' categoryIds,
    /// otherwise by `tx.category` — and excluding pending, so this list agrees
    /// with the count badge. Date-desc sorted (time-desc tiebreak).
    public static func categoryTransactions(_ txns: [Tx], _ categoryId: String, _ ledgerId: String,
                                            includePending: Bool = false) -> [Tx] {
        let matched = txns.filter { t in
            guard ledgerOf(t) == ledgerId else { return false }
            if !includePending, (t.pending ?? false) { return false }
            if let splits = t.splits, !splits.isEmpty {
                return splits.contains { $0.categoryId == categoryId }
            }
            return t.category == categoryId
        }
        return matched.sorted { $0.date != $1.date ? $0.date > $1.date : ($0.time ?? "") > ($1.time ?? "") }
    }

    /// `categoryTransactions`, with each row's amount narrowed to what THIS
    /// category took.
    ///
    /// **Why this is not just `categoryTransactions`.** A row's `amount` is the
    /// whole purchase. On a merchant or tag screen that is the right number — the
    /// question is what the shop cost. On a category screen it is not: a 100 shop
    /// split 70 groceries / 30 household reported 100 under BOTH, so the two
    /// screens together claimed 200 of spend for 100 spent. `spendByCategory` and
    /// budget matching have always summed the per-split `amountBase`; the detail
    /// screen was the outlier.
    ///
    /// A grid group widens the same error rather than creating it: its rows are
    /// separate entries that both carry both categories, so they collapse into one
    /// row holding the whole group.
    ///
    /// **The amount is narrowed, the identity is not.** `id` still names the real
    /// posting, so a screen showing these must resolve the row back to the store
    /// before handing it to an editor — otherwise the sheet opens on a share.
    public static func categoryShares(_ txns: [Tx], _ categoryId: String, _ ledgerId: String,
                                      includePending: Bool = false) -> [Tx] {
        categoryTransactions(txns, categoryId, ledgerId, includePending: includePending)
            .map { t in
                guard let splits = t.splits, !splits.isEmpty else { return t }
                var out = t
                out.amount = r2(splits.filter { $0.categoryId == categoryId }
                                      .reduce(0) { $0 + $1.amount })
                // Splits carry base amounts only, so a share has no native figure
                // to show. Cleared rather than left stale — the same rule
                // `byPurchase` follows when it can no longer trust one.
                out.nativeAmount = nil
                out.currency = nil
                return out
            }
    }

    /// One row per PURCHASE, each carrying only this category's share — what a
    /// category screen's list, count, total and average are all built from.
    public static func categoryPurchases(_ txns: [Tx], _ categoryId: String, _ ledgerId: String,
                                         includePending: Bool = false) -> [Tx] {
        byPurchase(categoryShares(txns, categoryId, ledgerId, includePending: includePending))
    }

    /// Transactions in `ledgerId` tagged with `tagId`, matched the SAME way as
    /// `tagTxCounts` (non-pending; `tx.tags` holds tag ids), so this list agrees
    /// with the count badge. Date-desc sorted (time-desc tiebreak).
    public static func tagTransactions(_ txns: [Tx], _ tagId: String, _ ledgerId: String,
                                       includePending: Bool = false) -> [Tx] {
        let matched = txns.filter { t in
            guard ledgerOf(t) == ledgerId else { return false }
            if !includePending, (t.pending ?? false) { return false }
            return (t.tags ?? []).contains(tagId)
        }
        return matched.sorted { $0.date != $1.date ? $0.date > $1.date : ($0.time ?? "") > ($1.time ?? "") }
    }

    // MARK: cycleWindow + date helpers

    // internal (not private) so the TimeSeries.swift extension can share them.
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    static func date(_ ymd: String) -> Date {
        let p = ymd.prefix(10).split(separator: "-").map { Int($0) ?? 0 }
        var dc = DateComponents()
        dc.year = p.count > 0 ? p[0] : 0; dc.month = p.count > 1 ? p[1] : 1; dc.day = p.count > 2 ? p[2] : 1
        return cal.date(from: dc)!
    }
    static func ymd(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func addDays(_ d: Date, _ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: d)! }
    // Foundation's month-add clamps the day to the target month (Jan 31 +1mo → Feb 28), matching JS addMonths.
    private static func addMonths(_ d: Date, _ n: Int) -> Date { cal.date(byAdding: .month, value: n, to: d)! }
    static func advance(_ d: Date, _ frequency: String) -> Date {
        switch frequency {
        case "daily": return addDays(d, 1)
        case "weekly": return addDays(d, 7)
        case "biweekly": return addDays(d, 14)
        case "quarterly": return addMonths(d, 3)
        case "yearly": return addMonths(d, 12)
        default: return addMonths(d, 1)   // monthly
        }
    }

    /// - Parameter startTime: the moment in the day the cycle turns over, "HH:mm".
    ///   Nil — every budget until one is set — keeps the whole-day window this has
    ///   always produced, byte-for-byte.
    ///
    /// With a time, the boundary moves within the day: a monthly budget starting
    /// 1 Aug 09:30 runs until 1 Sep 09:30, so `to` is 1 Sep and `toTime` is 09:30,
    /// exclusive. `today` may carry a time ("yyyy-MM-dd HH:mm") so the caller can say
    /// which side of the turnover it is on; a bare date reads as midnight.
    public static func cycleWindow(_ frequency: String, _ startDate: String, _ today: String,
                                   _ endDate: String? = nil, _ isRecurring: Int = 1,
                                   _ startTime: String? = nil) -> CycleWindow {
        let start = date(startDate), now = date(today)
        if isRecurring == 0 {
            let to: String
            if let e = endDate { to = String(e.prefix(10)) }
            else { to = now < start ? ymd(start) : String(today.prefix(10)) }
            return CycleWindow(from: ymd(start), to: to)
        }
        if now < start {
            return CycleWindow(from: ymd(start), to: ymd(addDays(advance(start, frequency), -1)))
        }
        // "00:00" IS the untimed behaviour — a cycle running midnight-to-midnight.
        // Treating it as timed would take the branch below and change what `to`
        // means for every budget the sheet saves without touching the time, which is
        // most of them. Normalised here rather than at the write path so no route
        // into the database can bypass it.
        guard let turnover = startTime, !turnover.isEmpty, turnover != "00:00" else {
            var s = start, e = advance(s, frequency), guardI = 0
            while e <= now && guardI < 5000 { s = e; e = advance(e, frequency); guardI += 1 }
            return CycleWindow(from: ymd(s), to: ymd(addDays(e, -1)))
        }
        // Timed: the turnover is a moment inside the day, so the comparison has to be
        // one too. `today` carries the current time when the caller knows it; without
        // one it reads as midnight, which puts a same-day "now" BEFORE the turnover —
        // the correct reading, since the cycle has not rolled yet.
        let nowStamp = today.count > 10 ? today : "\(today) 00:00"
        var s = start, e = advance(s, frequency), guardI = 0
        while "\(ymd(e)) \(turnover)" <= nowStamp && guardI < 5000 {
            s = e; e = advance(e, frequency); guardI += 1
        }
        // `to` is the day the cycle STOPS on — the same day the next one starts —
        // and `toTime` is the moment it stops, exclusive.
        return CycleWindow(from: ymd(s), to: ymd(e), fromTime: turnover, toTime: turnover)
    }

    // MARK: budgetProgress

    static func expandDescendants(_ ids: [String], _ categories: [CategoryNode]) -> Set<String> {
        var out = Set(ids)
        var childrenOf: [String: [String]] = [:]
        for c in categories where c.parentId != nil { childrenOf[c.parentId!, default: []].append(c.id) }
        var stack = Array(out)
        while let cur = stack.popLast() {
            for child in childrenOf[cur] ?? [] where out.insert(child).inserted { stack.append(child) }
        }
        return out
    }

    private static func matchedAmount(_ t: Tx, _ matchSet: Set<String>) -> Double {
        if matchSet.isEmpty { return t.amount }
        if let splits = t.splits, !splits.isEmpty {
            var sum = 0.0
            for s in splits { if let cid = s.categoryId, matchSet.contains(cid) { sum += s.amountBase } }
            return sum
        }
        if let cat = t.category, matchSet.contains(cat) { return t.amount }
        return 0
    }

    /// Sum of budget-matched activity in [from, to] — the accumulation shared by
    /// budgetProgress (current cycle) and budgetCycleHistory (each past cycle).
    /// A transaction as a single comparable moment, "yyyy-MM-dd HH:mm". One with no
    /// time of its own reads as midnight — the assumption every date-only comparison
    /// in the engine already makes.
    static func momentOf(_ t: Tx) -> String { "\(t.date) \(t.time ?? "00:00")" }

    /// Is `t` inside the cycle window `[from fromTime, to toTime)`?
    ///
    /// With both times nil this is the inclusive date comparison it has always been.
    /// With them, it compares MOMENTS — a transaction carrying no time of its own
    /// reads as midnight, which is the same assumption the untimed path makes.
    static func inWindow(_ t: Tx, from: String, to: String, fromTime: String?, toTime: String?) -> Bool {
        if fromTime == nil && toTime == nil { return t.date >= from && t.date <= to }
        let stamp = momentOf(t)
        if stamp < "\(from) \(fromTime ?? "00:00")" { return false }
        if let hi = toTime { return stamp < "\(to) \(hi)" }
        return t.date <= to
    }

    static func usedInWindow(_ budget: BudgetRow, _ txns: [Tx], _ matchSet: Set<String>,
                             _ accountSet: Set<String>?, from: String, to: String,
                             fromTime: String? = nil, toTime: String? = nil) -> Double {
        // Extra match dimensions (AND across, OR within, empty = unconstrained —
        // same rule as account/category).
        let tagSet = budget.tagIds.isEmpty ? nil : Set(budget.tagIds)
        let cpSet = budget.counterpartyIds.isEmpty ? nil : Set(budget.counterpartyIds)
        var used = 0.0
        for t in txns {
            if ledgerOf(t) != budget.ledgerId { continue }
            if (t.pending ?? false) || kindOf(t) == "adjustment" { continue }
            // Transfers are excluded for expense budgets only; income goals count
            // incoming transfer legs (positive amount) landing in a matched account.
            if budget.type == "expense" && kindOf(t) == "transfer" { continue }
            if !inWindow(t, from: from, to: to, fromTime: fromTime, toTime: toTime) { continue }
            if let accountSet, !accountSet.contains(t.account) { continue }
            if let tagSet, !(t.tags ?? []).contains(where: { tagSet.contains($0) }) { continue }
            if let cpSet, t.counterpartyId == nil || !cpSet.contains(t.counterpartyId!) { continue }
            let amt = matchedAmount(t, matchSet)
            if budget.type == "expense" { if amt < 0 { used += -amt } }
            else if amt > 0 { used += amt }
        }
        return used
    }

    public static func budgetProgress(_ budget: BudgetRow, _ txns: [Tx], _ today: String,
                                      _ categories: [CategoryNode] = []) -> BudgetProgress {
        let win = cycleWindow(budget.frequency, budget.startDate, today, budget.endDate, budget.isRecurring, budget.startTime)
        let accountSet = budget.accountIds.isEmpty ? nil : Set(budget.accountIds)
        let matchSet = categories.isEmpty ? Set(budget.categoryIds) : expandDescendants(budget.categoryIds, categories)

        // One-shot income goals seed `used` with the pre-tracking `saved` offset
        // and then accumulate real matched inflows on top. Recurring income and
        // expense budgets start at 0 and sum matched flows only.
        let oneShotIncome = budget.type == "income" && budget.isRecurring == 0
        let seed = oneShotIncome ? budget.saved : 0.0
        // A one-shot goal with NO scope matches nothing — progress is the saved
        // offset alone (else an unconstrained goal counts all income; new goals
        // must set ≥1 dimension). Scoped goals + expense/recurring run the sum.
        let incomeUnscoped = oneShotIncome && accountSet == nil && matchSet.isEmpty
            && budget.tagIds.isEmpty && budget.counterpartyIds.isEmpty
        var used = incomeUnscoped ? seed : seed + usedInWindow(budget, txns, matchSet, accountSet,
                                                               from: win.from, to: win.to,
                                                               fromTime: win.fromTime, toTime: win.toTime)
        let base = r2(budget.amount + (budget.type == "expense" ? budget.carryForward : 0))
        used = r2(used)
        let remaining = r2(base - used)
        let pct = base != 0 ? Int((used / base * 100).rounded()) : 0
        let over = budget.type == "expense" && used > base
        return BudgetProgress(from: win.from, to: win.to, base: base, used: used, remaining: remaining, pct: pct, over: over)
    }

    /// The transactions `budgetProgress` counts for the current cycle (same
    /// predicate), newest first — for the budget detail screen. One-shot income
    /// goals now surface their matched inflows too (the `saved` offset is added
    /// separately by `budgetProgress`, not represented here).
    public static func budgetMatchedTransactions(_ budget: BudgetRow, _ txns: [Tx], _ today: String,
                                                 _ categories: [CategoryNode] = []) -> [Tx] {
        let win = cycleWindow(budget.frequency, budget.startDate, today, budget.endDate, budget.isRecurring, budget.startTime)
        return budgetMatchedTransactions(budget, txns, from: win.from, to: win.to,
                                         fromTime: win.fromTime, toTime: win.toTime, categories)
    }

    /// Same predicate over an explicit [from, to] window — the budget detail's
    /// past-cycle drill-in (windows come from `budgetCycleHistory`).
    public static func budgetMatchedTransactions(_ budget: BudgetRow, _ txns: [Tx],
                                                 from: String, to: String,
                                                 fromTime: String? = nil, toTime: String? = nil,
                                                 _ categories: [CategoryNode] = []) -> [Tx] {
        let accountSet = budget.accountIds.isEmpty ? nil : Set(budget.accountIds)
        let matchSet = categories.isEmpty ? Set(budget.categoryIds) : expandDescendants(budget.categoryIds, categories)
        let tagSet = budget.tagIds.isEmpty ? nil : Set(budget.tagIds)
        let cpSet = budget.counterpartyIds.isEmpty ? nil : Set(budget.counterpartyIds)
        // Unscoped one-shot goal matches nothing (mirrors budgetProgress).
        if budget.type == "income" && budget.isRecurring == 0
            && accountSet == nil && matchSet.isEmpty && tagSet == nil && cpSet == nil { return [] }
        var out: [Tx] = []
        for t in txns {
            if ledgerOf(t) != budget.ledgerId { continue }
            if (t.pending ?? false) || kindOf(t) == "adjustment" { continue }
            if budget.type == "expense" && kindOf(t) == "transfer" { continue }
            if !inWindow(t, from: from, to: to, fromTime: fromTime, toTime: toTime) { continue }
            if let accountSet, !accountSet.contains(t.account) { continue }
            if let tagSet, !(t.tags ?? []).contains(where: { tagSet.contains($0) }) { continue }
            if let cpSet, t.counterpartyId == nil || !cpSet.contains(t.counterpartyId!) { continue }
            let amt = matchedAmount(t, matchSet)
            if budget.type == "expense" ? (amt < 0) : (amt > 0) { out.append(t) }
        }
        return out.sorted { $0.date != $1.date ? $0.date > $1.date : ($0.time ?? "") > ($1.time ?? "") }
    }

    /// Per-rule applied count: txns in `ledgerId` whose appliedRuleIds contains the
    /// rule id. Keyed by rule id; absent for rules that never fired.
    public static func ruleMatchCounts(_ txns: [Tx], _ ledgerId: String) -> [String: Int] {
        var out: [String: Int] = [:]
                // One row per PURCHASE: a purchase paid from several accounts is
        // several rows, and counting rows counts it more than once.
        for t in byPurchase(txns) where ledgerOf(t) == ledgerId {
            for id in (t.appliedRuleIds ?? []) { out[id, default: 0] += 1 }
        }
        return out
    }

    /// Detect repeating expense charges (subscriptions). Groups expenses by merchant,
    /// keeps those with a consistent cadence + stable amount that are still active.
    public static func detectRecurring(_ txns: [Tx], _ ledgerId: String, _ today: String,
                                       _ scheduled: [ScheduledTemplate] = [],
                                       minOccurrences: Int = 3) -> [RecurringCharge] {
        let scheduledNames = Set(scheduled.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var groups: [String: [Tx]] = [:]
        var names: [String: String] = [:]
                // One row per PURCHASE. Wrong twice over otherwise: the count is
        // inflated AND each leg's magnitude is a fraction of what was spent,
        // so the mean and deviation are distorted, not merely rescaled.
        for t in byPurchase(txns) {
            if ledgerOf(t) != ledgerId { continue }
            if (t.pending ?? false) { continue }
            if kindOf(t) != "expense" { continue }
            guard let key = merchantKey(t) else { continue }
            groups[key, default: []].append(t)
            names[key] = t.merchant
        }
        let todayDate = date(today)
        var out: [RecurringCharge] = []
        for (key, raw) in groups {
            let items = raw.sorted { ($0.date, $0.time ?? "") < ($1.date, $1.time ?? "") }
            guard items.count >= minOccurrences else { continue }

            let mags = items.map { abs($0.nativeAmount ?? $0.amount) }
            let mean = mags.reduce(0, +) / Double(mags.count)
            guard mean > 0 else { continue }
            let variance = mags.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(mags.count)
            guard variance.squareRoot() / mean < 0.35 else { continue }

            var gaps: [Int] = []
            for i in 1..<items.count {
                let g = cal.dateComponents([.day], from: date(items[i-1].date), to: date(items[i].date)).day ?? 0
                if g > 0 { gaps.append(g) }
            }
            guard !gaps.isEmpty else { continue }
            let med = medianInt(gaps)
            guard let cadence = cadenceForGap(med) else { continue }
            guard gaps.allSatisfy({ abs(Double($0) - Double(med)) <= 0.4 * Double(med) }) else { continue }

            let lastDate = items.last!.date
            let sinceLast = cal.dateComponents([.day], from: date(lastDate), to: todayDate).day ?? 0
            guard sinceLast <= Int(1.6 * Double(med)) else { continue }

            let mname = (names[key] ?? key).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isScheduled = items.contains { ($0.sourceTemplateId?.isEmpty == false) } || scheduledNames.contains(mname)
            out.append(RecurringCharge(
                id: key, merchantName: names[key] ?? key, averageAmount: r2(mean), cadence: cadence,
                monthlyEstimate: r2(monthlyFor(mean, cadence)), occurrences: items.count,
                lastDate: lastDate, nextEstimatedDate: ymd(addDays(date(lastDate), med)), isScheduled: isScheduled,
                accountId: mode(items.map { $0.account }), categoryId: mode(items.compactMap { $0.category })))
        }
        return out.sorted { $0.monthlyEstimate > $1.monthlyEstimate }
    }

    private static func mode(_ xs: [String]) -> String? {
        guard !xs.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for x in xs { counts[x, default: 0] += 1 }
        return counts.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }?.key
    }

    private static func medianInt(_ xs: [Int]) -> Int {
        let s = xs.sorted(); let n = s.count
        return n % 2 == 1 ? s[n/2] : (s[n/2 - 1] + s[n/2]) / 2
    }
    private static func cadenceForGap(_ g: Int) -> String? {
        switch g {
        case 6...8: return "weekly"
        case 12...16: return "biweekly"
        case 26...35: return "monthly"
        case 80...100: return "quarterly"
        case 350...380: return "yearly"
        default: return nil
        }
    }
    private static func monthlyFor(_ amount: Double, _ cadence: String) -> Double {
        switch cadence {
        case "weekly": return amount * 30.0 / 7.0
        case "biweekly": return amount * 30.0 / 14.0
        case "quarterly": return amount / 3.0
        case "yearly": return amount / 12.0
        default: return amount   // monthly
        }
    }
}

public extension Selectors {
    /// One row per purchase: the payment legs of a split-tender purchase summed
    /// into a single row carrying the true total.
    ///
    /// Use this wherever a statistic or a ranking needs what was actually spent —
    /// a mean, a variance, a z-score, a "biggest". For counting alone,
    /// `Tx.purchaseKey` is enough and cheaper.
    ///
    /// **`nativeAmount` and `currency` are dropped when the legs disagree.** Split
    /// tender is explicitly multi-currency, and every consumer reads
    /// `abs(nativeAmount ?? amount)`; summing raw natives across currencies would
    /// hand them a number that is not money in any unit, which is worse than the
    /// ledger-base amount they otherwise fall back to. The engine refuses to sum
    /// them for the same reason.
    ///
    /// **Identity fields are the FIRST leg's** — `id`, `account`, `clearedAt`,
    /// `pending`. Do not use this where a specific leg's account or reconcile mark
    /// matters; an account-scoped view should not collapse at all.
    ///
    /// **`splits` needs no special handling.** They belong to the entry, and the
    /// first leg's copy is already the whole set. Collapsing only ever happens for
    /// an entry with several *account* legs, which may hold at most one category
    /// leg, so a row being merged in never carries splits of its own.
    ///
    /// **A grid group breaks that.** Its rows are separate entries, each with its
    /// own category legs, collapsed here by `group_id` — so the merged-in row's
    /// splits ARE dropped and the survivor's are only its own. That is why a
    /// category screen must narrow amounts BEFORE collapsing
    /// (`categoryShares`); reading `splits` off a collapsed grid row is wrong.
    ///
    /// On a transfer the legs cancel to `amount == 0`. Every current caller filters
    /// by `kind` first; a new one must.
    static func byPurchase(_ txns: [Tx]) -> [Tx] {
        var order: [String] = []
        var acc: [String: Tx] = [:]
        for t in txns {
            let key = t.purchaseKey
            guard var seen = acc[key] else {
                order.append(key)
                acc[key] = t
                continue
            }
            seen.amount = r2(seen.amount + t.amount)
            if seen.currency == t.currency, let a = seen.nativeAmount, let b = t.nativeAmount {
                seen.nativeAmount = r2(a + b)
            } else {
                seen.currency = nil
                seen.nativeAmount = nil
            }
            acc[key] = seen
        }
        return order.compactMap { acc[$0] }
    }
}
