import XCTest
import GRDB
@testable import FinchCore

final class InsightsRulesTests: XCTestCase {
    private let fmt: (Double) -> String = { String(format: "$%.0f", $0) }

    private func ctx(_ q: DatabaseQueue, month: String = "2026-05", today: String = "2026-05-31") throws -> InsightContext {
        InsightContext(
            txns: try Projection.run(dbQueue: q, ledgerId: "l1"),
            accounts: try Projection.accounts(dbQueue: q, ledgerId: "l1"),
            budgets: try Projection.budgets(dbQueue: q, ledgerId: "l1"),
            categories: try Projection.categories(dbQueue: q, ledgerId: "l1"),
            ledgerId: "l1", month: month, today: today)
    }
    private func add(_ q: DatabaseQueue, _ amount: Double, _ date: String, pending: Bool = false, cat: String = "c1") throws {
        var a: [String: JSONValue] = ["ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(amount),
            "merchant": .string("M"), "categoryId": .string(cat), "date": .string(date), "skipRules": .bool(true)]
        if pending { a["status"] = .string("pending") }
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args(a))
    }
    private func titles(_ ins: [Insight]) -> [String] { ins.map(\.title) }

    func test_empty_ledger_no_insights() throws {
        let q = try TestSeed.base()
        XCTAssertTrue(Selectors.generateInsights(try ctx(q), fmt: fmt).isEmpty)
    }

    func test_pending_insight() throws {
        let q = try TestSeed.base()
        try add(q, -40, "2026-05-10", pending: true)
        let ins = Selectors.generateInsights(try ctx(q), fmt: fmt)
        XCTAssertTrue(ins.contains { $0.title.contains("pending to review") && $0.tone == .neut })
    }

    func test_top_category_insight() throws {
        let q = try TestSeed.base()
        try add(q, -60, "2026-05-10")
        let ins = Selectors.generateInsights(try ctx(q), fmt: fmt)
        XCTAssertTrue(ins.contains { $0.title.contains("leads your spending") && $0.title.contains("Food") })
    }

    func test_over_budget_insight() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
            "id": .string("b1"), "ledgerId": .string("l1"), "name": .string("Groceries"),
            "type": .string("expense"), "amount": .double(100), "categoryIds": .array([.string("c1")]),
            "startDate": .string("2026-05-01")]))
        try add(q, -150, "2026-05-15")
        let ins = Selectors.generateInsights(try ctx(q), fmt: fmt)
        XCTAssertTrue(ins.contains { $0.title == "Groceries over budget" && $0.tone == .warn })
    }

    func test_spending_trend_up() throws {
        let q = try TestSeed.base()
        try add(q, -100, "2026-04-10")   // prev month
        try add(q, -150, "2026-05-10")   // current month (up 50%)
        let ins = Selectors.generateInsights(try ctx(q), fmt: fmt)
        XCTAssertTrue(ins.contains { $0.title == "Spending up 50% vs last month" && $0.tone == .warn })
    }

    func test_goal_progress_insight() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
            "id": .string("g1"), "ledgerId": .string("l1"), "name": .string("Savings"),
            "type": .string("income"), "amount": .double(1000)]))
        try Apply.apply(dbQueue: q, action: "contributeBudget", args: Args(["id": .string("g1"), "amount": .double(250)]))
        let ins = Selectors.generateInsights(try ctx(q), fmt: fmt)
        XCTAssertTrue(ins.contains { $0.title == "Savings is 25% funded" && $0.tone == .pos })
    }

    func test_net_worth_trend_present() throws {
        let q = try TestSeed.base()
        try add(q, 500, "2026-05-10")   // income → net worth up
        let ins = Selectors.generateInsights(try ctx(q), fmt: fmt)
        XCTAssertTrue(ins.contains { $0.title.contains("Net worth") })
    }

    func test_max_six_and_priority_order() throws {
        let q = try TestSeed.base()
        try add(q, -100, "2026-04-10"); try add(q, -150, "2026-05-10")     // spendingTrend + topCategory
        try add(q, -40, "2026-05-11", pending: true)                       // pending
        let ins = Selectors.generateInsights(try ctx(q), fmt: fmt)
        XCTAssertLessThanOrEqual(ins.count, 6)
        // spendingTrend (if firing) precedes pending precedes topCategory
        let t = titles(ins)
        if let iSpend = t.firstIndex(where: { $0.contains("vs last month") }),
           let iPend = t.firstIndex(where: { $0.contains("pending to review") }) {
            XCTAssertLessThan(iSpend, iPend)
        }
    }
}
