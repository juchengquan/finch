import XCTest
import GRDB
@testable import FinchCore

final class BudgetsDomainTests: XCTestCase {
    private func ledgerDB() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
        }
        return q
    }

    func test_createAndPatch() throws {
        let q = try ledgerDB()
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args([
            "id": .string("b1"), "ledgerId": .string("l1"), "name": .string("Food"), "type": .string("expense"),
            "amount": .double(500), "categoryIds": .array([.string("food"), .string("dining")]),
        ]))
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount FROM budgets WHERE id='b1'") ?? 0, 500, accuracy: 0.001)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT kind FROM budgets WHERE id='b1'"), "expense")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT category_ids FROM budgets WHERE id='b1'"), "[\"food\",\"dining\"]")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT is_recurring FROM budgets WHERE id='b1'"), 1)   // expense default
        }
        // amount-only edit on a recurring budget stages it
        try Apply.apply(dbQueue: q, action: "updateBudget", args: Args(["id": .string("b1"), "patch": .object(["amount": .double(600)])]))
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT pending_amount FROM budgets WHERE id='b1'") ?? -1, 600, accuracy: 0.001)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount FROM budgets WHERE id='b1'") ?? 0, 500, accuracy: 0.001)  // unchanged
        }
        try Apply.apply(dbQueue: q, action: "clearPendingAmount", args: Args(["id": .string("b1")]))
        XCTAssertNil(try q.read { db in try Double.fetchOne(db, sql: "SELECT pending_amount FROM budgets WHERE id='b1'") ?? nil })
        // amount-must-be-positive guard
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "createBudget", args: Args(["name": .string("X"), "amount": .double(0)]))) {
            XCTAssertEqual(($0 as? I18nError)?.code, "error.budget.amountGt0")
        }
    }

    func test_contributeAndCycleAndRemove() throws {
        let q = try ledgerDB()
        try Apply.apply(dbQueue: q, action: "createBudget", args: Args(["id": .string("b1"), "ledgerId": .string("l1"), "name": .string("Save"), "type": .string("income"), "amount": .double(1000)]))
        try Apply.apply(dbQueue: q, action: "contributeBudget", args: Args(["id": .string("b1"), "amount": .double(250)]))
        try Apply.apply(dbQueue: q, action: "contributeBudget", args: Args(["id": .string("b1"), "amount": .double(-100)]))
        XCTAssertEqual(try q.read { db in try Double.fetchOne(db, sql: "SELECT saved FROM budgets WHERE id='b1'") ?? 0 }, 150, accuracy: 0.001)
        try Apply.apply(dbQueue: q, action: "updateBudgetCycle", args: Args(["id": .string("b1"), "patch": .object(["frequency": .string("weekly"), "startDate": .string("2026-01-01"), "amount": .double(1200)])]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT frequency FROM budgets WHERE id='b1'"), "weekly")
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount FROM budgets WHERE id='b1'") ?? 0, 1200, accuracy: 0.001)
        }
        try Apply.apply(dbQueue: q, action: "removeBudget", args: Args(["id": .string("b1")]))
        XCTAssertEqual(try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM budgets") }, 0)
    }
}
