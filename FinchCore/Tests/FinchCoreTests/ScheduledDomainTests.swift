import XCTest
import GRDB
@testable import FinchCore

final class ScheduledDomainTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            for acc in ["a1", "a2"] {
                try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES (?,'l1','A','cash','USD',0,0,1,1,datetime('now'),datetime('now'))", arguments: [acc])
            }
        }
        return q
    }

    func test_scheduledCrud() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createScheduled", args: Args([
            "id": .string("s1"), "ledgerId": .string("l1"), "name": .string("Rent"), "type": .string("expense"),
            "amount": .double(1200), "frequency": .string("monthly"), "dayOfMonth": .int(1), "accountId": .string("a1"),
        ]))
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT kind FROM scheduled_templates WHERE id='s1'"), "expense")
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT amount FROM scheduled_templates WHERE id='s1'") ?? 0, 1200, accuracy: 0.001)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT is_active FROM scheduled_templates WHERE id='s1'"), 1)
        }
        try Apply.apply(dbQueue: q, action: "updateScheduled", args: Args(["id": .string("s1"), "patch": .object(["amount": .double(1300)])]))
        XCTAssertEqual(try q.read { db in try Double.fetchOne(db, sql: "SELECT amount FROM scheduled_templates WHERE id='s1'") ?? 0 }, 1300, accuracy: 0.001)
        // unknown type rejected
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "createScheduled", args: Args(["name": .string("X"), "type": .string("bogus"), "accountId": .string("a1")]))) {
            XCTAssertEqual(($0 as? I18nError)?.code, "error.account.splitTypeUnknown")
        }
    }

    /// postScheduled posts one confirmed transaction NOW from the template,
    /// linked via source_template_id, moving the account balance.
    func test_postScheduledExpense() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('c1','l1',NULL,'Rent','expense',0,datetime('now'),datetime('now'))")
        }
        try Apply.apply(dbQueue: q, action: "createScheduled", args: Args([
            "id": .string("s1"), "ledgerId": .string("l1"), "name": .string("Rent"), "type": .string("expense"),
            "amount": .double(1500), "frequency": .string("monthly"), "dayOfMonth": .int(1), "accountId": .string("a1"), "category": .string("c1"),
        ]))
        try Apply.apply(dbQueue: q, action: "postScheduled", args: Args(["templateId": .string("s1")]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE source_template_id='s1' AND kind='expense' AND status='confirmed'"), 1)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a1'") ?? 0, -1500, accuracy: 0.001)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT category_id FROM postings WHERE category_id='c1'"), "c1")
        }
    }

    func test_scheduledSplits() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createScheduled", args: Args(["id": .string("s1"), "ledgerId": .string("l1"), "name": .string("Paycheck"), "type": .string("income"), "amount": .double(5000), "accountId": .string("a1")]))
        try Apply.apply(dbQueue: q, action: "addScheduledSplit", args: Args(["templateId": .string("s1"), "accountId": .string("a1"), "pct": .double(70)]))
        try Apply.apply(dbQueue: q, action: "addScheduledSplit", args: Args(["templateId": .string("s1"), "accountId": .string("a2"), "pct": .double(30)]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scheduled_splits WHERE template_id='s1'"), 2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT splits_enabled FROM scheduled_templates WHERE id='s1'"), 1)
        }
        // update split at index 1 (the a2 / 30% one) to 25
        try Apply.apply(dbQueue: q, action: "updateScheduledSplit", args: Args(["templateId": .string("s1"), "index": .int(1), "pct": .double(25)]))
        XCTAssertEqual(try q.read { db in try Double.fetchOne(db, sql: "SELECT amount_pct FROM scheduled_splits WHERE account_id='a2'") ?? 0 }, 25, accuracy: 0.001)
        // remove both → splits_enabled flips back to 0
        try Apply.apply(dbQueue: q, action: "removeScheduledSplit", args: Args(["templateId": .string("s1"), "index": .int(0)]))
        try Apply.apply(dbQueue: q, action: "removeScheduledSplit", args: Args(["templateId": .string("s1"), "index": .int(0)]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scheduled_splits WHERE template_id='s1'"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT splits_enabled FROM scheduled_templates WHERE id='s1'"), 0)
        }
    }
}
