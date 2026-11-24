import XCTest
import GRDB
@testable import FinchCore

/// A base change re-locks each leg at the new base on its own, and the cents that
/// disagree go on an fx rounding leg in the ledger's system fx category. That leg
/// is a residue, not a category: counted as one, a plain purchase read as a split,
/// and re-categorising it (the sheet or the bulk action) silently did nothing.
final class FxResidueRecategorizeTests: XCTestCase {
    /// A USD ledger, a euro card, a €9.99 grocery purchase — then the base moves to yen.
    private func seeded() throws -> (DatabaseQueue, posting: String) {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try Apply.apply(dbQueue: q, action: "createLedger", args: Args([
            "id": .string("l1"), "name": .string("L"), "base": .string("USD")]))
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "ledgerId": .string("l1"), "id": .string("a1"), "name": .string("Card"), "type": .string("cash"),
            "currency": .string("EUR")]))
        try q.write { db in
            for c in ["food", "fun"] {
                try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES (?,'l1',NULL,?,'expense',0,datetime('now'),datetime('now'))", arguments: [c, c])
            }
            try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-05-01','EUR',1.0837)")
            try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-05-01','JPY',0.0067)")
        }
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-9.99),
            "merchant": .string("Market"), "categoryId": .string("food"), "date": .string("2026-05-01"),
            "skipRules": .bool(true)]))
        try Apply.apply(dbQueue: q, action: "changeLedgerBase", args: Args(["ledgerId": .string("l1"), "newBase": .string("JPY")]))
        let posting = try q.read { try String.fetchOne($0, sql: "SELECT id FROM postings WHERE account_id = 'a1' AND entry_id IN (SELECT id FROM entries WHERE kind = 'expense')") }
        return (q, try XCTUnwrap(posting))
    }

    private func categories(_ q: DatabaseQueue) throws -> [String] {
        try q.read { db in
            try String.fetchAll(db, sql: """
                SELECT c.id FROM postings p JOIN categories c ON c.id = p.category_id JOIN entries e ON e.id = p.entry_id
                 WHERE e.kind = 'expense' AND c.kind != 'equity' ORDER BY c.id
                """)
        }
    }

    func test_theBaseChangeLeftAnFxLeg() throws {
        let (q, _) = try seeded()
        let fxLegs = try q.read { try Int.fetchOne($0, sql: """
            SELECT COUNT(*) FROM postings p JOIN categories c ON c.id = p.category_id
             WHERE c.system = 'fx' AND p.entry_id IN (SELECT id FROM entries WHERE kind = 'expense')
            """) }
        XCTAssertEqual(fxLegs, 1, "the premise of the two tests below")
    }

    func test_editingTheCategoryChangesIt() throws {
        let (q, posting) = try seeded()
        try Apply.apply(dbQueue: q, action: "updateTransaction", args: Args([
            "id": .string(posting), "patch": .object(["category": .string("fun")])]))
        XCTAssertEqual(try categories(q), ["fun"])
    }

    func test_bulkRecategorizeChangesIt() throws {
        let (q, posting) = try seeded()
        try Apply.apply(dbQueue: q, action: "bulkRecategorize", args: Args([
            "ids": .array([.string(posting)]), "categoryId": .string("fun")]))
        XCTAssertEqual(try categories(q), ["fun"])
    }
}
