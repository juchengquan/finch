import XCTest
import GRDB
@testable import FinchCore

/// Every leg-rebuild path must carry the account leg's reconcile mark
/// (cleared_at) + foreign-entry display fields (orig_*) across the rebuild —
/// the bug class from #167 where only updateTransaction forwarded them.
final class LegMetadataTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Cash','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
            for c in ["c1", "c2"] {
                try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES (?,'l1',NULL,?,'expense',0,datetime('now'),datetime('now'))", arguments: [c, c])
            }
        }
        return q
    }

    /// Add an expense, mark its account posting cleared, return the posting id.
    private func addClearedExpense(_ q: DatabaseQueue, amount: Double = -50, date: String = "2026-05-01") throws -> String {
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(amount),
            "merchant": .string("Shop"), "categoryId": .string("c1"), "date": .string(date),
            "time": .string("10:00"), "skipRules": .bool(true),
        ]))
        let pid = try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM postings WHERE account_id = 'a1'") }!
        try Apply.apply(dbQueue: q, action: "setCleared", args: Args(["id": .string(pid), "cleared": .bool(true)]))
        return pid
    }

    private func clearedAt(_ q: DatabaseQueue, _ pid: String) throws -> String? {
        try q.read { db in try String.fetchOne(db, sql: "SELECT cleared_at FROM postings WHERE id = ?", arguments: [pid]) }
    }

    func test_bulkRecategorize_preservesClearedAt() throws {
        let q = try seeded()
        let pid = try addClearedExpense(q)
        XCTAssertNotNil(try clearedAt(q, pid))
        try Apply.apply(dbQueue: q, action: "bulkRecategorize", args: Args(["ids": .array([.string(pid)]), "categoryId": .string("c2")]))
        // category moved c1 → c2, and the account leg stays cleared.
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT category_id FROM postings WHERE category_id IS NOT NULL"), "c2")
        }
        XCTAssertNotNil(try clearedAt(q, pid), "bulkRecategorize must not un-clear the account leg")
    }

    func test_dateOnlyEdit_preservesClearedAt() throws {
        let q = try seeded()
        let pid = try addClearedExpense(q)
        try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args(["id": .string(pid), "patch": .object(["date": .string("2026-06-15")])]))
        XCTAssertNotNil(try clearedAt(q, pid), "a date-only edit must not un-clear the account leg")
    }

    func test_setTransactionSplits_preservesClearedAt() throws {
        let q = try seeded()
        let pid = try addClearedExpense(q, amount: -100)
        let splits: JSONValue = .array([
            .object(["categoryId": .string("c1"), "amount": .double(60)]),
            .object(["categoryId": .string("c2"), "amount": .double(40)]),
        ])
        try Apply.apply(dbQueue: q, action: "setTransactionSplits", args: Args(["id": .string(pid), "splits": splits]))
        XCTAssertNotNil(try clearedAt(q, pid), "splitting must not un-clear the account leg")
    }

    func test_changeLedgerBase_preservesClearedAt() throws {
        let q = try seeded()
        let pid = try addClearedExpense(q)
        try Apply.apply(dbQueue: q, action: "changeLedgerBase", args: Args(["ledgerId": .string("l1"), "newBase": .string("EUR")]))
        XCTAssertNotNil(try clearedAt(q, pid), "changing the ledger base must not un-reconcile every leg")
    }
}
