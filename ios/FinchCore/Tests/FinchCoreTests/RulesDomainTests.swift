import XCTest
import GRDB
@testable import FinchCore

final class RulesDomainTests: XCTestCase {
    private func ledgerDB() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
        }
        return q
    }

    func test_ruleCrud() throws {
        let q = try ledgerDB()
        let condition: JSONValue = .object(["field": .string("merchant"), "op": .string("contains"), "value": .string("coffee")])
        let actions: JSONValue = .array([.object(["type": .string("setCategory"), "categoryId": .string("food")])])
        try Apply.apply(dbQueue: q, action: "createRule", args: Args([
            "id": .string("r1"), "ledgerId": .string("l1"), "name": .string("Coffee→Food"),
            "condition": condition, "actions": actions, "priority": .int(50),
        ]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT name FROM rules WHERE id='r1'"), "Coffee→Food")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT priority FROM rules WHERE id='r1'"), 50)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT is_active FROM rules WHERE id='r1'"), 1)   // default
            // condition stored as JSON
            let cond = try String.fetchOne(db, sql: "SELECT condition FROM rules WHERE id='r1'") ?? ""
            XCTAssertTrue(cond.contains("\"value\":\"coffee\""), cond)
        }
        // condition required
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "createRule", args: Args(["name": .string("X")]))) {
            XCTAssertEqual(($0 as? I18nError)?.code, "error.required.ruleCondition")
        }
        try Apply.apply(dbQueue: q, action: "updateRule", args: Args(["id": .string("r1"), "patch": .object(["priority": .int(10), "isActive": .bool(false)])]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT priority FROM rules WHERE id='r1'"), 10)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT is_active FROM rules WHERE id='r1'"), 0)
        }
        try Apply.apply(dbQueue: q, action: "deleteRule", args: Args(["id": .string("r1")]))
        XCTAssertEqual(try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM rules") }, 0)
    }
}
