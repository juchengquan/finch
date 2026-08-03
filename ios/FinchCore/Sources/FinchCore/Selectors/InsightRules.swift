import Foundation

/// A narrative insight card (advice). iOS is English-only, so title/body are
/// rendered strings (matching the web `en` copy); money is formatted by the
/// caller's `fmt` closure.
public struct Insight: Equatable, Sendable {
    public enum Tone: String, Sendable { case pos, warn, neut }
    public let tone: Tone
    public let icon: String      // semantic: arrowUp/arrowDown/doc/fork/check
    public let title: String
    public let body: String
    public init(tone: Tone, icon: String, title: String, body: String) {
        self.tone = tone; self.icon = icon; self.title = title; self.body = body
    }
}

/// Inputs for `generateInsights` (the app builds this from its store).
public struct InsightContext {
    public var txns: [Tx]
    public var accounts: [AccountRow]
    public var budgets: [BudgetRow]
    public var categories: [CategoryRow]
    public var ledgerId: String
    public var month: String   // "YYYY-MM"
    public var today: String
    public init(txns: [Tx], accounts: [AccountRow], budgets: [BudgetRow], categories: [CategoryRow],
                ledgerId: String, month: String, today: String) {
        self.txns = txns; self.accounts = accounts; self.budgets = budgets; self.categories = categories
        self.ledgerId = ledgerId; self.month = month; self.today = today
    }
}

extension Selectors {
    /// Up to `max` narrative insights in web priority order. `fmt` formats money.
    /// Pure; reuses categorySpend/prevMonth/budgetProgress/netWorthSeries.
    public static func generateInsights(_ c: InsightContext, fmt: (Double) -> String, max: Int = 6) -> [Insight] {
        var out: [Insight] = []
        func add(_ i: Insight?) { if let i, out.count < max { out.append(i) } }
        add(spendingTrendInsight(c, fmt))
        add(overBudgetInsight(c, fmt))
        add(pendingInsight(c, fmt))
        add(topCategoryInsight(c, fmt))
        // CP2 — the 5 day-of-week / day-of-month pattern surfacers (web PR #82
        // order: after the actionable rules, before the progress/trend coda).
        add(weekendVsWeekdayInsight(c, fmt))
        add(topCategoryByWeekdayInsight(c))
        add(endOfMonthBumpInsight(c))
        add(weekdaySkewInsight(c))
        add(quietestDayInsight(c))
        add(goalProgressInsight(c, fmt))
        add(netWorthTrendInsight(c, fmt))
        return out
    }

    private static func spendingTrendInsight(_ c: InsightContext, _ fmt: (Double) -> String) -> Insight? {
        let cur = categorySpend(c.txns, c.ledgerId, c.month).values.reduce(0, +)
        let prev = categorySpend(c.txns, c.ledgerId, prevMonth(c.month)).values.reduce(0, +)
        guard prev > 0 else { return nil }
        let pct = Int((abs(cur - prev) / prev * 100).rounded())
        guard pct != 0 else { return nil }
        let down = cur < prev
        return Insight(tone: down ? .pos : .warn, icon: down ? "arrowDown" : "arrowUp",
            title: "Spending \(down ? "down" : "up") \(pct)% vs last month",
            body: "\(fmt(cur)) this month vs \(fmt(prev)) last month.")
    }

    private static func overBudgetInsight(_ c: InsightContext, _ fmt: (Double) -> String) -> Insight? {
        let nodes = c.categories.map { CategoryNode(id: $0.id, parentId: $0.parentId) }
        var worst: (name: String, p: BudgetProgress)?
        for b in c.budgets where b.type == "expense" {
            let p = budgetProgress(b, c.txns, c.today, nodes)
            if p.over, worst == nil || (p.used - p.base) > (worst!.p.used - worst!.p.base) { worst = (b.name, p) }
        }
        guard let w = worst else { return nil }
        return Insight(tone: .warn, icon: "arrowUp",
            title: "\(w.name) over budget",
            body: "At \(fmt(w.p.used)) of \(fmt(w.p.base)) — \(fmt(w.p.used - w.p.base)) over.")
    }

    private static func pendingInsight(_ c: InsightContext, _ fmt: (Double) -> String) -> Insight? {
        // One row per PURCHASE: a pending purchase paid on two cards is one thing
        // to confirm, not two.
        let pend = byPurchase(c.txns.filter { ledgerOf($0) == c.ledgerId && ($0.pending ?? false) })
        guard !pend.isEmpty else { return nil }
        let total = pend.reduce(0.0) { $0 + abs($1.nativeAmount ?? $1.amount) }
        return Insight(tone: .neut, icon: "doc",
            title: "\(pend.count) pending to review",
            body: "\(fmt(total)) awaiting confirmation on the Pending screen.")
    }

    private static func topCategoryInsight(_ c: InsightContext, _ fmt: (Double) -> String) -> Insight? {
        let spend = categorySpend(c.txns, c.ledgerId, c.month)
        let total = spend.values.reduce(0, +)
        guard total > 0, let top = spend.max(by: { $0.value < $1.value }), top.value > 0 else { return nil }
        let pct = Int((top.value / total * 100).rounded())
        let name = c.categories.first { $0.id == top.key }?.name ?? "Uncategorized"
        return Insight(tone: .neut, icon: "fork",
            title: "\(name) leads your spending",
            body: "\(fmt(top.value)) — \(pct)% of expenses this period.")
    }

    private static func goalProgressInsight(_ c: InsightContext, _ fmt: (Double) -> String) -> Insight? {
        let goals = c.budgets.filter { $0.type == "income" && $0.amount > 0 && $0.saved < $0.amount }
        guard let g = goals.max(by: { ($0.saved / $0.amount) < ($1.saved / $1.amount) }) else { return nil }
        let pct = Int((g.saved / g.amount * 100).rounded())
        return Insight(tone: .pos, icon: "check",
            title: "\(g.name) is \(pct)% funded",
            body: "\(fmt(g.saved)) of \(fmt(g.amount)) saved.")
    }

    // MARK: CP2 pattern rules (day-of-week / day-of-month)

    /// Confirmed expense rows in the ledger — the shared filter every pattern
    /// rule uses (web: `ledgerOf(t) !== ledgerId || t.pending || kindOf(t) !== 'expense'`;
    /// note: plain expenses only, refunds excluded, matching the web rules).
    /// One row per PURCHASE — five insights read this, and `quietestDayInsight`
    /// counts rows (its "at least 25 expense rows" gate tripped early on a ledger
    /// full of split purchases). The other four only sum amounts, which collapsing
    /// leaves untouched since a purchase's legs add back to its total.
    private static func patternExpenses(_ c: InsightContext) -> [Tx] {
        byPurchase(c.txns.filter { ledgerOf($0) == c.ledgerId && !($0.pending ?? false) && kindOf($0) == "expense" })
    }

    /// Days since 1970-01-01 for a "YYYY-MM-DD" string (Howard Hinnant's civil
    /// algorithm — no timezone involved, matching the web's UTC date parsing).
    private static func serialDay(_ date: String) -> Int? {
        let parts = date.prefix(10).split(separator: "-")
        guard parts.count == 3, let y0 = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        let y = y0 - (m <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// Day of week for a "YYYY-MM-DD" string, 0 = Sunday … 6 = Saturday
    /// (the web's `getUTCDay` convention). 1970-01-01 was a Thursday (4).
    private static func dowOf(_ date: String) -> Int? {
        guard let s = serialDay(date) else { return nil }
        return ((s + 4) % 7 + 7) % 7
    }

    private static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static func weekdayName(_ dow: Int) -> String { weekdayNames[((dow % 7) + 7) % 7] }

    /// Weekend per-calendar-day spend ≥ 1.5× weekday per-day spend.
    private static func weekendVsWeekdayInsight(_ c: InsightContext, _ fmt: (Double) -> String) -> Insight? {
        var weekendSum = 0.0, weekdaySum = 0.0
        var earliest = "", latest = ""
        for t in patternExpenses(c) {
            if earliest.isEmpty || t.date < earliest { earliest = t.date }
            if latest.isEmpty || t.date > latest { latest = t.date }
            guard let dow = dowOf(t.date) else { continue }
            if dow == 0 || dow == 6 { weekendSum += -t.amount } else { weekdaySum += -t.amount }
        }
        // Count weekend vs weekday CALENDAR days in the data range so the per-day
        // means are like-for-like (distinct active dates would under-count
        // no-spend days and skew toward whichever segment is busier).
        guard let start = serialDay(earliest), let end = serialDay(latest) else { return nil }
        var weekendDays = 0, weekdayDays = 0
        var s = start
        while s <= end {
            let dow = ((s + 4) % 7 + 7) % 7
            if dow == 0 || dow == 6 { weekendDays += 1 } else { weekdayDays += 1 }
            s += 1
        }
        guard weekendDays >= 6, weekdayDays >= 15 else { return nil }
        let weekendPerDay = weekendSum / Double(weekendDays)
        let weekdayPerDay = weekdaySum / Double(weekdayDays)
        guard weekdayPerDay > 0 else { return nil }
        let ratio = weekendPerDay / weekdayPerDay
        guard ratio >= 1.5 else { return nil }
        return Insight(tone: .neut, icon: "calendar",
            title: "Weekends cost more than weekdays",
            body: "Weekend days run \(String(format: "%.1f", ratio))× weekday spend (\(fmt(weekendPerDay)) vs \(fmt(weekdayPerDay)) per day).")
    }

    /// One weekday dominated by one category (share ≥ 40% of a ≥ $100 day).
    private static func topCategoryByWeekdayInsight(_ c: InsightContext) -> Insight? {
        guard !c.categories.isEmpty else { return nil }
        var byDay = Array(repeating: [String: Double](), count: 7)
        for t in patternExpenses(c) {
            guard let cat = t.category, let dow = dowOf(t.date) else { continue }
            byDay[dow][cat, default: 0] += -t.amount
        }
        var best: (dow: Int, categoryId: String, share: Double)?
        for d in 0..<7 {
            let entries = byDay[d]
            guard entries.count >= 2 else { continue }
            let total = entries.values.reduce(0, +)
            guard total >= 100 else { continue }
            guard let top = entries.max(by: { $0.value < $1.value }) else { continue }
            let share = top.value / total
            guard share >= 0.4 else { continue }
            if best == nil || share > best!.share { best = (d, top.key, share) }
        }
        guard let b = best else { return nil }
        let name = c.categories.first { $0.id == b.categoryId }?.name ?? b.categoryId
        let day = weekdayName(b.dow)
        return Insight(tone: .neut, icon: "tag",
            title: "\(day)s are mostly \(name)",
            body: "\(Int((b.share * 100).rounded()))% of your \(day) spending goes to \(name).")
    }

    /// Days 23–31 average ≥ 1.3× the per-day spend of days 1–22 (≥ 3 months of data).
    private static func endOfMonthBumpInsight(_ c: InsightContext) -> Insight? {
        var lastWeekSum = 0.0, restSum = 0.0
        var months = Set<String>()
        for t in patternExpenses(c) {
            months.insert(String(t.date.prefix(7)))
            let day = Int(t.date.dropFirst(8).prefix(2)) ?? 0
            if day >= 23 { lastWeekSum += -t.amount } else { restSum += -t.amount }
        }
        // Approx: every month has ~8 "last week" days (23-30/31) and ~22 earlier
        // days; scale by observed-month count to get a per-day mean.
        guard months.count >= 3 else { return nil }
        let lastWeekPerDay = lastWeekSum / (Double(months.count) * 8)
        let restPerDay = restSum / (Double(months.count) * 22)
        guard restPerDay > 0 else { return nil }
        let ratio = lastWeekPerDay / restPerDay
        guard ratio >= 1.3 else { return nil }
        return Insight(tone: .neut, icon: "calendar",
            title: "End-of-month runs hotter",
            body: "Days 23-31 average \(String(format: "%.1f", ratio))× your earlier-month spend per day.")
    }

    /// One day-of-week ≥ 1.5× the mean daily total.
    private static func weekdaySkewInsight(_ c: InsightContext) -> Insight? {
        var totals = Array(repeating: 0.0, count: 7)
        var any = false
        for t in patternExpenses(c) {
            guard let dow = dowOf(t.date) else { continue }
            totals[dow] += -t.amount
            any = true
        }
        guard any else { return nil }
        let mean = totals.reduce(0, +) / 7
        guard mean > 0 else { return nil }
        var maxDay = 0
        for i in 1..<7 where totals[i] > totals[maxDay] { maxDay = i }
        let ratio = totals[maxDay] / mean
        guard ratio >= 1.5 else { return nil }
        let day = weekdayName(maxDay)
        return Insight(tone: .neut, icon: "sparkle",
            title: "\(day)s are your spendy days",
            body: "You spend \(String(format: "%.1f", ratio))× the daily average on \(day)s.")
    }

    /// Counterpart to weekdaySkew — the quietest day-of-week (≤ 0.5× the mean;
    /// needs ≥ 25 expense rows so a sparse ledger doesn't fire it).
    private static func quietestDayInsight(_ c: InsightContext) -> Insight? {
        var totals = Array(repeating: 0.0, count: 7)
        var counts = Array(repeating: 0, count: 7)
        for t in patternExpenses(c) {
            guard let dow = dowOf(t.date) else { continue }
            totals[dow] += -t.amount
            counts[dow] += 1
        }
        guard counts.reduce(0, +) >= 25 else { return nil }
        let mean = totals.reduce(0, +) / 7
        guard mean > 0 else { return nil }
        var minDay = 0
        for i in 1..<7 where totals[i] < totals[minDay] { minDay = i }
        let ratio = totals[minDay] / mean
        guard ratio <= 0.5 else { return nil }
        let day = weekdayName(minDay)
        return Insight(tone: .pos, icon: "check",
            title: "\(day)s are your quietest",
            body: "You spend \(Int(((1 - ratio) * 100).rounded()))% less on \(day)s than the daily average.")
    }

    private static func netWorthTrendInsight(_ c: InsightContext, _ fmt: (Double) -> String) -> Insight? {
        let series = netWorthSeries(c.txns, c.accounts, c.ledgerId)
        guard series.count >= 2, let first = series.first, let last = series.last else { return nil }
        let delta = last - first
        guard abs(delta) >= 1 else { return nil }
        let up = delta > 0
        return Insight(tone: up ? .pos : .warn, icon: up ? "arrowUp" : "arrowDown",
            title: up ? "Net worth is trending up" : "Net worth dipped",
            body: "\(delta >= 0 ? "+" : "−")\(fmt(abs(delta))) across this period's activity.")
    }
}
