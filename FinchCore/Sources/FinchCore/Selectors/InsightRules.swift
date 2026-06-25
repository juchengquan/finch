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
        let pend = c.txns.filter { ledgerOf($0) == c.ledgerId && ($0.pending ?? false) }
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
