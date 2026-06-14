import XCTest
import GRDB
@testable import FinchCore

/// Coverage for the budget actions the iOS UI now exposes (edit / contribute /
/// cycle / clear-pending / groups) + the budget-detail transactions selector.
final class BudgetCrudTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue {
        let q = try TestSeed.base()   // l1 / a1 / c1 (Food)
        try q.write { db in
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('c2','l1',NULL,'Fun','expense',1,datetime('now'),datetime('now'))")
        }
        return q
    }

    private func mkExpenseBudget(_ q: DatabaseQueue, cats: [String] = ["c1"]) throws {
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
            "id": .string("b1"), "ledgerId": .string("l1"), "name": .string("Food"),
            "type": .string("expense"), "amount": .double(300), "frequency": .string("monthly"),
            "startDate": .string("2026-05-01"), "categoryIds": .array(cats.map { .string($0) }),
        ]))
    }

    func test_updateBudget_multiFieldPatch() throws {
        let q = try seeded()
        try mkExpenseBudget(q)
        try Apply.apply(dbQueue: q, action: "updateBudget", args: Args(["id": .string("b1"), "patch": .object([
            "name": .string("Groceries"), "amount": .double(250),
        ])]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT name FROM budgets WHERE id='b1'"), "Groceries")
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount FROM budgets WHERE id='b1'") ?? 0, 250, accuracy: 0.001)
        }
    }

    func test_amountOnlyEdit_stagesPending_thenClear() throws {
        let q = try seeded()
        try mkExpenseBudget(q)   // expense → recurring
        try Apply.apply(dbQueue: q, action: "updateBudget", args: Args(["id": .string("b1"), "patch": .object(["amount": .double(500)])]))
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT pending_amount FROM budgets WHERE id='b1'") ?? -1, 500, accuracy: 0.001)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount FROM budgets WHERE id='b1'") ?? 0, 300, accuracy: 0.001) // unchanged until cycle
        }
        try Apply.apply(dbQueue: q, action: "clearPendingAmount", args: Args(["id": .string("b1")]))
        try q.read { db in XCTAssertNil(try Double.fetchOne(db, sql: "SELECT pending_amount FROM budgets WHERE id='b1'")) }
    }

    func test_updateBudgetCycle() throws {
        let q = try seeded()
        try mkExpenseBudget(q)
        try Apply.apply(dbQueue: q, action: "updateBudgetCycle", args: Args(["id": .string("b1"), "patch": .object([
            "frequency": .string("weekly"), "startDate": .string("2026-06-01"), "amount": .double(80),
        ])]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT frequency FROM budgets WHERE id='b1'"), "weekly")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT start_date FROM budgets WHERE id='b1'"), "2026-06-01")
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount FROM budgets WHERE id='b1'") ?? 0, 80, accuracy: 0.001)
        }
    }

    func test_contributeBudget_clampsAtZero() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
            "id": .string("g1"), "ledgerId": .string("l1"), "name": .string("Vacation"),
            "type": .string("income"), "amount": .double(2000), "frequency": .string("monthly"), "startDate": .string("2026-01-01"),
        ]))
        try Apply.apply(dbQueue: q, action: "contributeBudget", args: Args(["id": .string("g1"), "amount": .double(500)]))
        try Apply.apply(dbQueue: q, action: "contributeBudget", args: Args(["id": .string("g1"), "amount": .double(-100)]))
        try q.read { db in XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT saved FROM budgets WHERE id='g1'") ?? 0, 400, accuracy: 0.001) }
        try Apply.apply(dbQueue: q, action: "contributeBudget", args: Args(["id": .string("g1"), "amount": .double(-9999)]))
        try q.read { db in XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT saved FROM budgets WHERE id='g1'") ?? -1, 0, accuracy: 0.001) }
    }

    func test_budgetGroup_crud_and_projection() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createBudgetGroup", args: Args(["id": .string("bg1"), "ledgerId": .string("l1"), "name": .string("Essentials")]))
        XCTAssertEqual(try Projection.budgetGroups(dbQueue: q, ledgerId: "l1").map(\.name), ["Essentials"])
        try Apply.apply(dbQueue: q, action: "updateBudgetGroup", args: Args(["id": .string("bg1"), "patch": .object(["name": .string("Core")])]))
        XCTAssertEqual(try Projection.budgetGroups(dbQueue: q, ledgerId: "l1").first?.name, "Core")
        try Apply.apply(dbQueue: q, action: "deleteBudgetGroup", args: Args(["id": .string("bg1")]))
        XCTAssertTrue(try Projection.budgetGroups(dbQueue: q, ledgerId: "l1").isEmpty)
    }

    func test_budgetMatchedTransactions_matchesProgressPredicate() throws {
        let q = try seeded()
        try mkExpenseBudget(q, cats: ["c1"])   // monthly from 2026-05-01, tracks c1
        // in-cycle c1 (counts), prev-month c1 (out of cycle), in-cycle c2 (other category)
        for (cat, amt, date) in [("c1", -10.0, "2026-05-10"), ("c1", -20.0, "2026-04-10"), ("c2", -5.0, "2026-05-11")] {
            try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
                "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(amt),
                "merchant": .string("x"), "categoryId": .string(cat), "date": .string(date), "skipRules": .bool(true)]))
        }
        let budget = try Projection.budgets(dbQueue: q, ledgerId: "l1").first { $0.id == "b1" }!
        let allTxns = try Projection.run(dbQueue: q)
        let txns = Selectors.budgetMatchedTransactions(budget, allTxns, "2026-05-15", [])
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns.first?.date, "2026-05-10")
        // Mirrors budgetProgress.used (10).
        let p = Selectors.budgetProgress(budget, allTxns, "2026-05-15", [])
        XCTAssertEqual(p.used, 10, accuracy: 0.001)
    }
}
