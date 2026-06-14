import XCTest
import GRDB
@testable import FinchCore

/// Behavioral coverage for actions the review flagged as untested:
/// markAllReviewed, deleteTransfer, deleteCategory, unarchiveAccount,
/// deleteBudgetGroup, unverifyCounterparty, setBackupFrequency.
final class ActionCoverageTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            for a in ["a1", "a2"] {
                try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES (?,'l1',?,'cash','USD',0,0,1,1,datetime('now'),datetime('now'))", arguments: [a, a])
            }
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('c1','l1',NULL,'Food','expense',0,datetime('now'),datetime('now'))")
        }
        return q
    }

    func test_markAllReviewed_stampsLedgerThenAccount() throws {
        let q = try seeded()
        // Two confirmed expenses on different accounts.
        for (acc, d) in [("a1", "2026-05-01"), ("a2", "2026-05-02")] {
            try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
                "ledgerId": .string("l1"), "accountId": .string(acc), "amount": .double(-5),
                "merchant": .string("x"), "categoryId": .string("c1"), "date": .string(d), "skipRules": .bool(true)]))
        }
        // Scope to one account first.
        try Apply.apply(dbQueue: q, action: "markAllReviewed", args: Args(["ledgerId": .string("l1"), "accountId": .string("a1")]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE reviewed_at IS NOT NULL"), 1)
        }
        // Whole ledger sweeps the rest.
        try Apply.apply(dbQueue: q, action: "markAllReviewed", args: Args(["ledgerId": .string("l1")]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE kind != 'opening' AND reviewed_at IS NULL"), 0)
        }
    }

    func test_deleteTransfer_removesEntryAndRestoresBalances() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createTransfer", args: Args([
            "fromAccountId": .string("a1"), "toAccountId": .string("a2"),
            "fromAmount": .double(100), "date": .string("2026-05-01")]))
        let id = try q.read { db in try String.fetchOne(db, sql: "SELECT id FROM postings WHERE account_id='a1'") }!
        try q.read { db in
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a2'") ?? 0, 100, accuracy: 0.001)
        }
        try Apply.apply(dbQueue: q, action: "deleteTransfer", args: Args(["id": .string(id)]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE kind='transfer'"), 0)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a2'") ?? -1, 0, accuracy: 0.001)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT current_balance FROM accounts WHERE id='a1'") ?? -1, 0, accuracy: 0.001)
        }
    }

    func test_deleteCategory_removesRow() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "deleteCategory", args: Args(["id": .string("c1")]))
        try q.read { db in
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT id FROM categories WHERE id='c1'"))
        }
    }

    func test_unarchiveAccount_roundTrip() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "archiveAccount", args: Args(["id": .string("a1")]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT is_active FROM accounts WHERE id='a1'"), 0)
        }
        try Apply.apply(dbQueue: q, action: "unarchiveAccount", args: Args(["id": .string("a1")]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT is_active FROM accounts WHERE id='a1'"), 1)
        }
    }

    func test_deleteBudgetGroup_removesGroup() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createBudgetGroup", args: Args(["id": .string("g1"), "ledgerId": .string("l1"), "name": .string("Essentials")]))
        try Apply.apply(dbQueue: q, action: "deleteBudgetGroup", args: Args(["id": .string("g1")]))
        try q.read { db in
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT id FROM budget_groups WHERE id='g1'"))
        }
    }

    func test_unverifyCounterparty_roundTrip() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "createCounterparty", args: Args(["id": .string("cp1"), "ledgerId": .string("l1"), "name": .string("Acme")]))
        try Apply.apply(dbQueue: q, action: "verifyCounterparty", args: Args(["id": .string("cp1")]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT is_verified FROM counterparties WHERE id='cp1'"), 1)
        }
        try Apply.apply(dbQueue: q, action: "unverifyCounterparty", args: Args(["id": .string("cp1")]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT is_verified FROM counterparties WHERE id='cp1'"), 0)
        }
    }

    func test_setBackupFrequency_persistsToBackupConfig() throws {
        let q = try seeded()
        try Apply.apply(dbQueue: q, action: "setBackupFrequency", args: Args(["frequencyMs": .double(86_400_000)]))  // 1 day
        let v = try q.read { db in try String.fetchOne(db, sql: "SELECT value FROM app_state WHERE key='backupConfig'") }
        XCTAssertNotNil(v)
        XCTAssertTrue(v?.contains("86400000") ?? false, v ?? "nil")
    }
}
