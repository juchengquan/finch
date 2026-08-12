import XCTest
import GRDB
@testable import FinchCore

/// The `interledger` entry shape and its audit contract
/// (`plans/ios-macos/2026-08-12-cross-ledger-transfers-design.md`, D2 + D3).
///
/// A cross-ledger transfer is a PAIR of entries, one per ledger, each balanced in
/// its own base currency. Each half is `kind = 'interledger'` with exactly one
/// account leg and exactly one equity leg pointing at the ledger's
/// `system = 'interledger'` category. This file is the contract for one half —
/// the audit is per-entry, so a valid half is the unit under test.
///
/// Why the contract has to be ADDED rather than inherited: the kind-shape rule
/// only flags kinds it recognizes, so a brand-new kind sails past every clause.
/// Without these tests the shape would be unguarded — the seal trigger would
/// still force it to balance and hold an account leg, but nothing would catch a
/// second account leg or an equity leg pointing at the wrong system category.
final class InterledgerAuditTests: XCTestCase {

    /// A ledger with one account, the `interledger` + `adjustment` system
    /// categories, and one ordinary expense category.
    private func seed() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','Personal','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Checking','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a2','l1','Savings','savings','USD',0,1,1,1,datetime('now'),datetime('now'))")
            // The new 4th system category — this INSERT is what fails before the
            // CHECK constraint is widened.
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,system,created_at,updated_at) VALUES ('cat-inter','l1',NULL,'Between books','equity',9003,'interledger',datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,system,created_at,updated_at) VALUES ('cat-adj','l1',NULL,'Balance adjustment','equity',9001,'adjustment',datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('cat-food','l1',NULL,'Food','expense',0,datetime('now'),datetime('now'))")
        }
        return q
    }

    private func postings(_ db: Database, _ sql: String) throws {
        try db.execute(sql: "INSERT INTO entries (id,ledger_id,date,description,kind,status,sealed,created_at,updated_at) VALUES ('e1','l1','2026-08-12','Travel · Travel Card','interledger','confirmed',0,datetime('now'),datetime('now'))")
        try db.execute(sql: sql)
        try db.execute(sql: "UPDATE entries SET sealed = 1 WHERE id = 'e1'")
    }

    private func kindShape(_ q: DatabaseQueue) throws -> [Audit.AuditProblem] {
        try Audit.run(on: q).filter { $0.code == .kindShape }
    }

    // MARK: the well-formed half

    func test_wellFormedHalfPasses() throws {
        let q = try seed()
        try q.write { db in
            try postings(db, """
                INSERT INTO postings (id,entry_id,account_id,category_id,amount,currency,amount_base,exchange_rate,sort_order)
                VALUES ('p1','e1','a1',NULL,-5000,'USD',-5000,1,0),
                       ('p2','e1',NULL,'cat-inter',5000,'USD',5000,1,1)
                """)
        }
        let problems = try Audit.run(on: q)
        XCTAssertTrue(problems.isEmpty,
                      "a well-formed interledger half must raise no audit problems at all: \(problems)")
    }

    /// Rule 6 is about postings pointing OUTSIDE their entry's ledger. Our design
    /// deliberately keeps every posting inside its own ledger — the pairing lives
    /// in a link id, not in a posting — so rule 6 must stay silent.
    func test_crossLedgerRuleStaysSilent() throws {
        let q = try seed()
        try q.write { db in
            try postings(db, """
                INSERT INTO postings (id,entry_id,account_id,category_id,amount,currency,amount_base,exchange_rate,sort_order)
                VALUES ('p1','e1','a1',NULL,-5000,'USD',-5000,1,0),
                       ('p2','e1',NULL,'cat-inter',5000,'USD',5000,1,1)
                """)
        }
        XCTAssertTrue(try Audit.run(on: q).filter { $0.code == .crossLedger }.isEmpty,
                      "the pair links by id, never by a posting that reaches into another ledger")
    }

    // MARK: the shapes the new clause must CATCH

    func test_twoAccountLegsIsAKindShapeDefect() throws {
        let q = try seed()
        try q.write { db in
            // An ordinary same-ledger transfer wearing the interledger label.
            try postings(db, """
                INSERT INTO postings (id,entry_id,account_id,category_id,amount,currency,amount_base,exchange_rate,sort_order)
                VALUES ('p1','e1','a1',NULL,-5000,'USD',-5000,1,0),
                       ('p2','e1','a2',NULL,5000,'USD',5000,1,1)
                """)
        }
        XCTAssertFalse(try kindShape(q).isEmpty,
                       "two account legs is not an interledger transfer — it never left the books")
    }

    func test_wrongEquityCategoryIsAKindShapeDefect() throws {
        let q = try seed()
        try q.write { db in
            // Balances, but claims the money was a balance adjustment.
            try postings(db, """
                INSERT INTO postings (id,entry_id,account_id,category_id,amount,currency,amount_base,exchange_rate,sort_order)
                VALUES ('p1','e1','a1',NULL,-5000,'USD',-5000,1,0),
                       ('p2','e1',NULL,'cat-adj',5000,'USD',5000,1,1)
                """)
        }
        XCTAssertFalse(try kindShape(q).isEmpty,
                       "the equity leg must be the interledger category, not another system row")
    }

    func test_ordinaryCategoryLegIsAKindShapeDefect() throws {
        let q = try seed()
        try q.write { db in
            // Money leaving the books is not spending — a plain category leg here
            // would double-count it in every spend aggregation.
            try postings(db, """
                INSERT INTO postings (id,entry_id,account_id,category_id,amount,currency,amount_base,exchange_rate,sort_order)
                VALUES ('p1','e1','a1',NULL,-5000,'USD',-5000,1,0),
                       ('p2','e1',NULL,'cat-food',2000,'USD',2000,1,1),
                       ('p3','e1',NULL,'cat-inter',3000,'USD',3000,1,2)
                """)
        }
        XCTAssertFalse(try kindShape(q).isEmpty,
                       "an ordinary category leg has no business in an interledger entry")
    }

    // MARK: the seeding side (D2) — the 4th system category exists and is found by marker

    func test_ensureSystemCategoriesCreatesTheInterledgerRow() throws {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','Personal','USD',1,datetime('now'),datetime('now'))")
            // Ordinary seeding must NOT create it — it is native-only, and seeding
            // it alongside the other three made every write diverge from the web
            // oracle (the write-parity gate caught it).
            _ = try Entries.ensureSystemCategories(db, "l1")
            XCTAssertNil(try String.fetchOne(db, sql:
                "SELECT id FROM categories WHERE ledger_id = 'l1' AND system = 'interledger'"),
                "the ordinary seeder must leave the interledger category alone")

            let id = try Entries.ensureInterledgerCategory(db, "l1")
            XCTAssertFalse(id.isEmpty, "the lazy creator must mint it on first use")
            let kind = try String.fetchOne(db, sql: "SELECT kind FROM categories WHERE id = ?", arguments: [id])
            XCTAssertEqual(kind, "equity",
                           "equity is what keeps it out of pickers and spend aggregations")
            XCTAssertEqual(try Entries.ensureInterledgerCategory(db, "l1"), id, "must be idempotent")
        }
    }
}
