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

    public static func selectTransactions(_ txns: [Tx], _ opts: ListOptions) -> [Tx] {
        var out = txns.filter { ledgerOf($0) == opts.ledgerId }
        if opts.direction == "in" { out = out.filter { $0.amount > 0 } }
        if opts.direction == "out" { out = out.filter { $0.amount < 0 } }
        if let q = opts.query?.lowercased() { out = out.filter { $0.merchant.lowercased().contains(q) } }
        if let a = opts.accountId { out = out.filter { $0.account == a } }
        if let c = opts.categoryId { out = out.filter { $0.category == c } }
        if let s = opts.status { out = out.filter { ($0.pending ?? false) == (s == "pending") } }
        if let f = opts.from { out = out.filter { $0.date >= f } }
        if let t = opts.to { out = out.filter { $0.date <= t } }
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
        for t in txns {
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
        for t in txns {
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
    /// newest-first, INCLUDES pending.
    public static func merchantTransactions(_ txns: [Tx], _ counterparties: [Counterparty],
                                            _ counterpartyId: String, _ ledgerId: String) -> [Tx] {
        let idSet = Set(counterparties.map(\.id))
        var byName: [String: String] = [:]
        for c in counterparties {
            let n = c.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !n.isEmpty, byName[n] == nil { byName[n] = c.id }
        }
        let matched = txns.filter { t in
            guard ledgerOf(t) == ledgerId else { return false }
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
        for t in txns {
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
        for t in txns {
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
    private static func advance(_ d: Date, _ frequency: String) -> Date {
        switch frequency {
        case "daily": return addDays(d, 1)
        case "weekly": return addDays(d, 7)
        case "biweekly": return addDays(d, 14)
        case "quarterly": return addMonths(d, 3)
        case "yearly": return addMonths(d, 12)
        default: return addMonths(d, 1)   // monthly
        }
    }

    public static func cycleWindow(_ frequency: String, _ startDate: String, _ today: String,
                                   _ endDate: String? = nil, _ isRecurring: Int = 1) -> CycleWindow {
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
        var s = start, e = advance(s, frequency), guardI = 0
        while e <= now && guardI < 5000 { s = e; e = advance(e, frequency); guardI += 1 }
        return CycleWindow(from: ymd(s), to: ymd(addDays(e, -1)))
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

    public static func budgetProgress(_ budget: BudgetRow, _ txns: [Tx], _ today: String,
                                      _ categories: [CategoryNode] = []) -> BudgetProgress {
        let win = cycleWindow(budget.frequency, budget.startDate, today, budget.endDate, budget.isRecurring)
        let accountSet = budget.accountIds.isEmpty ? nil : Set(budget.accountIds)
        let matchSet = categories.isEmpty ? Set(budget.categoryIds) : expandDescendants(budget.categoryIds, categories)

        var used = 0.0
        let oneShotIncome = budget.type == "income" && budget.isRecurring == 0
        if oneShotIncome {
            used = budget.saved
        } else {
            for t in txns {
                if ledgerOf(t) != budget.ledgerId { continue }
                if (t.pending ?? false) || kindOf(t) == "transfer" || kindOf(t) == "adjustment" { continue }
                if t.date < win.from || t.date > win.to { continue }
                if let accountSet, !accountSet.contains(t.account) { continue }
                let amt = matchedAmount(t, matchSet)
                if budget.type == "expense" { if amt < 0 { used += -amt } }
                else if amt > 0 { used += amt }
            }
        }
        let base = r2(budget.amount + (budget.type == "expense" ? budget.carryForward : 0))
        used = r2(used)
        let remaining = r2(base - used)
        let pct = base != 0 ? Int((used / base * 100).rounded()) : 0
        let over = budget.type == "expense" && used > base
        return BudgetProgress(from: win.from, to: win.to, base: base, used: used, remaining: remaining, pct: pct, over: over)
    }

    /// The transactions `budgetProgress` counts for the current cycle (same
    /// predicate), newest first — for the budget detail screen. Empty for a
    /// one-shot income goal (tracked via `saved`, not transactions).
    public static func budgetMatchedTransactions(_ budget: BudgetRow, _ txns: [Tx], _ today: String,
                                                 _ categories: [CategoryNode] = []) -> [Tx] {
        if budget.type == "income" && budget.isRecurring == 0 { return [] }
        let win = cycleWindow(budget.frequency, budget.startDate, today, budget.endDate, budget.isRecurring)
        let accountSet = budget.accountIds.isEmpty ? nil : Set(budget.accountIds)
        let matchSet = categories.isEmpty ? Set(budget.categoryIds) : expandDescendants(budget.categoryIds, categories)
        var out: [Tx] = []
        for t in txns {
            if ledgerOf(t) != budget.ledgerId { continue }
            if (t.pending ?? false) || kindOf(t) == "transfer" || kindOf(t) == "adjustment" { continue }
            if t.date < win.from || t.date > win.to { continue }
            if let accountSet, !accountSet.contains(t.account) { continue }
            let amt = matchedAmount(t, matchSet)
            if budget.type == "expense" ? (amt < 0) : (amt > 0) { out.append(t) }
        }
        return out.sorted { $0.date != $1.date ? $0.date > $1.date : ($0.time ?? "") > ($1.time ?? "") }
    }

    /// Per-rule applied count: txns in `ledgerId` whose appliedRuleIds contains the
    /// rule id. Keyed by rule id; absent for rules that never fired.
    public static func ruleMatchCounts(_ txns: [Tx], _ ledgerId: String) -> [String: Int] {
        var out: [String: Int] = [:]
        for t in txns where ledgerOf(t) == ledgerId {
            for id in (t.appliedRuleIds ?? []) { out[id, default: 0] += 1 }
        }
        return out
    }

    /// Detect repeating expense charges (subscriptions). Groups expenses by merchant,
    /// keeps those with a consistent cadence + stable amount that are still active.
    public static func detectRecurring(_ txns: [Tx], _ ledgerId: String, _ today: String,
                                       minOccurrences: Int = 3) -> [RecurringCharge] {
        var groups: [String: [Tx]] = [:]
        var names: [String: String] = [:]
        for t in txns {
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
            guard variance.squareRoot() / mean < 0.35 else { continue }   // amounts roughly equal

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
            guard sinceLast <= Int(1.6 * Double(med)) else { continue }    // still active

            let isScheduled = items.contains { ($0.sourceTemplateId?.isEmpty == false) }
            out.append(RecurringCharge(
                id: key, merchantName: names[key] ?? key, averageAmount: r2(mean), cadence: cadence,
                monthlyEstimate: r2(monthlyFor(mean, cadence)), occurrences: items.count,
                lastDate: lastDate, nextEstimatedDate: ymd(addDays(date(lastDate), med)), isScheduled: isScheduled))
        }
        return out.sorted { $0.monthlyEstimate > $1.monthlyEstimate }
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
