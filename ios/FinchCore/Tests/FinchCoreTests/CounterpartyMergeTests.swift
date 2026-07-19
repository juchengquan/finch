import XCTest
import GRDB
@testable import FinchCore

final class CounterpartyMergeTests: XCTestCase {
    /// Ledger, one account, two counterparties: cpSource (absorbed) and cpTarget (survivor).
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','a1','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
            for c in ["cpSource", "cpTarget"] {
                try db.execute(sql: "INSERT INTO counterparties (id,ledger_id,name,is_verified,created_at,updated_at) VALUES (?,'l1',?,0,datetime('now'),datetime('now'))", arguments: [c, c])
            }
        }
        return q
    }

    /// Add an expense (merchant → entries.description) then link its entry to `cp`.
    private func addLinkedTx(_ q: DatabaseQueue, merchant: String, cp: String) throws {
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-5),
            "merchant": .string(merchant), "date": .string("2026-05-01"), "skipRules": .bool(true)]))
        try q.write { db in
            try db.execute(sql: "UPDATE entries SET counterparty_id = ? WHERE description = ?", arguments: [cp, merchant])
        }
    }

    private func merge(_ q: DatabaseQueue, _ source: String, _ target: String) throws {
        try Apply.apply(dbQueue: q, action: "mergeCounterparty", args: Args(["sourceId": .string(source), "targetId": .string(target)]))
    }

    func test_entries_repoint_and_source_deleted() throws {
        let q = try seeded()
        try addLinkedTx(q, merchant: "x", cp: "cpSource")
        try addLinkedTx(q, merchant: "z", cp: "cpTarget")
        try merge(q, "cpSource", "cpTarget")
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE counterparty_id = 'cpSource'"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE counterparty_id = 'cpTarget'"), 2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM counterparties WHERE id = 'cpSource'"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM counterparties WHERE id = 'cpTarget'"), 1)
        }
    }

    func test_merge_many_folds_all_sources() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO counterparties (id,ledger_id,name,is_verified,created_at,updated_at) VALUES ('cpSource2','l1','cpSource2',0,datetime('now'),datetime('now'))")
        }
        try addLinkedTx(q, merchant: "x", cp: "cpSource")
        try addLinkedTx(q, merchant: "y", cp: "cpSource2")
        try Apply.apply(dbQueue: q, action: "mergeCounterparties", args: Args([
            "sourceIds": .array([.string("cpSource"), .string("cpSource2")]),
            "targetId": .string("cpTarget")]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE counterparty_id = 'cpTarget'"), 2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM counterparties WHERE id IN ('cpSource','cpSource2')"), 0)
        }
    }

    func test_merge_into_self_rejected() throws {
        let q = try seeded()
        XCTAssertThrowsError(try merge(q, "cpSource", "cpSource"))
    }

    func test_missing_source_or_target_rejected() throws {
        let q = try seeded()
        XCTAssertThrowsError(try merge(q, "nope", "cpTarget"))
        XCTAssertThrowsError(try merge(q, "cpSource", "nope"))
    }

    func test_cross_ledger_merge_rejected() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l2','L2','USD',0,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO counterparties (id,ledger_id,name,is_verified,created_at,updated_at) VALUES ('cpOther','l2','cpOther',0,datetime('now'),datetime('now'))")
        }
        XCTAssertThrowsError(try merge(q, "cpSource", "cpOther"))
    }
}
