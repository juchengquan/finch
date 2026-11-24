import XCTest
import GRDB
@testable import FinchCore

/// Phase 8 — the CloudKit down-sync seed (`DownSync`). Verified WITHOUT any
/// CloudKit dependency: it's pure DB I/O, so the round-trip (build a live DB via
/// the chokepoint → extract row-mirror records → ingest into a fresh DB → audit)
/// is fully unit-testable. This is the "riskiest blind piece" the live loop
/// deferred, now landed with tests ahead of provisioning.
final class DownSyncTests: XCTestCase {

    private func freshDB() throws -> DatabaseQueue {
        let q = try DatabaseQueue()           // in-memory
        try Migrations.runAll(on: q)
        return q
    }

    /// Empty input leaves a fresh DB clean.
    func test_emptyTablesAuditsClean() throws {
        let db = try freshDB()
        let problems = try DownSync.ingest(into: db, tables: [:])
        XCTAssertTrue(problems.isEmpty)
    }

    /// A hand-built minimal ledger + account ingests and audits clean.
    func test_minimalLedgerIngests() throws {
        let db = try freshDB()
        let tables: [String: [[String: String]]] = [
            "ledgers": [[
                "id": "l1", "name": "Personal", "base_currency": "USD", "is_default": "1",
                "created_at": "2026-06-15T00:00:00Z", "updated_at": "2026-06-15T00:00:00Z",
            ]],
            "accounts": [[
                "id": "a1", "ledger_id": "l1", "name": "Cash", "type": "cash", "currency": "USD",
                "current_balance": "0", "sort_order": "0", "include_in_net_worth": "1", "is_active": "1",
                "created_at": "2026-06-15T00:00:00Z", "updated_at": "2026-06-15T00:00:00Z",
            ]],
        ]
        let problems = try DownSync.ingest(into: db, tables: tables)
        XCTAssertTrue(problems.isEmpty, "minimal ledger should audit clean")
        let n = try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM accounts WHERE id='a1'") }
        XCTAssertEqual(n, 1)
    }

    /// The real test: a live DB built through the chokepoint (transactions, a
    /// transfer, a split, a budget) round-trips through extract → ingest with an
    /// identical row count, rebuilt balances, and a clean audit.
    func test_roundTrip_liveExtractIngestAuditsClean() throws {
        let live = try TestSeed.base()   // l1 / a1 (Cash, USD) / c1 (Food)
        try live.write { db in
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a2','l1','Savings','savings','USD',0,1,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('pay','l1',NULL,'Salary','income',1,datetime('now'),datetime('now'))")
        }
        try Apply.apply(dbQueue: live, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-25),
            "merchant": .string("Coffee"), "categoryId": .string("c1"), "date": .string("2026-05-01"), "skipRules": .bool(true)]))
        try Apply.apply(dbQueue: live, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(2000),
            "merchant": .string("Pay"), "categoryId": .string("pay"), "date": .string("2026-05-02"), "kind": .string("income"), "skipRules": .bool(true)]))
        try Apply.apply(dbQueue: live, action: "createTransfer", args: Args([
            "fromAccountId": .string("a1"), "toAccountId": .string("a2"), "fromAmount": .double(500), "date": .string("2026-05-03")]))
        // a pending entry (excluded from cached balance — exercises that path)
        try Apply.apply(dbQueue: live, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-7),
            "merchant": .string("Pending"), "categoryId": .string("c1"), "date": .string("2026-05-04"), "status": .string("pending"), "skipRules": .bool(true)]))

        // Extract → fresh ingest.
        let tables = try DownSync.extract(from: live)
        let fresh = try freshDB()
        let problems = try DownSync.ingest(into: fresh, tables: tables)

        XCTAssertEqual(problems.map(\.code.rawValue), [], "down-synced DB should audit clean")
        XCTAssertEqual(try Projection.rowCounts(dbQueue: fresh),
                       try Projection.rowCounts(dbQueue: live),
                       "row counts should match the source")
        // Balances were rebuilt by the triggers, not copied — must match the source.
        for acct in ["a1", "a2"] {
            let liveBal = try live.read { try Double.fetchOne($0, sql: "SELECT current_balance FROM accounts WHERE id=?", arguments: [acct]) } ?? 0
            let freshBal = try fresh.read { try Double.fetchOne($0, sql: "SELECT current_balance FROM accounts WHERE id=?", arguments: [acct]) } ?? 0
            XCTAssertEqual(freshBal, liveBal, accuracy: 0.0001, "balance for \(acct) should match")
        }
        // Every entry came back sealed (phase-2 re-seal ran).
        let unsealed = try fresh.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM entries WHERE sealed = 0") }
        XCTAssertEqual(unsealed, 0, "all entries should be re-sealed")
    }

    /// A row referencing a missing parent is rejected (FK), rolling the seed back.
    func test_rejectsOrphanedRow() throws {
        let db = try freshDB()
        let tables: [String: [[String: String]]] = [
            "accounts": [[
                "id": "a1", "ledger_id": "missing", "name": "Cash", "type": "cash", "currency": "USD",
                "current_balance": "0", "sort_order": "0", "include_in_net_worth": "1", "is_active": "1",
                "created_at": "2026-06-15T00:00:00Z", "updated_at": "2026-06-15T00:00:00Z",
            ]],
        ]
        XCTAssertThrowsError(try DownSync.ingest(into: db, tables: tables))
        let n = try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM accounts") }
        XCTAssertEqual(n, 0, "failed ingest rolls back")
    }

    // MARK: peer schema skew

    /// A peer on a different schema sends a column this build dropped
    /// (`counterparties.ledger_id`, removed in schema 2026-07-20). It must be
    /// ignored, not abort the seed — ingest is ONE transaction, so an unfiltered
    /// unknown column would roll back everything and leave the device un-seedable.
    func test_unknownColumnIsIgnored_notFatal() throws {
        let db = try freshDB()
        let tables: [String: [[String: String]]] = [
            "counterparties": [[
                "id": "cp1", "name": "Whole Foods", "is_verified": "1",
                "ledger_id": "l1",                       // <- dropped in 2026-07-20
                "created_at": "2026-06-15T00:00:00Z", "updated_at": "2026-06-15T00:00:00Z",
            ]],
        ]
        let problems = try DownSync.ingest(into: db, tables: tables)
        XCTAssertTrue(problems.isEmpty)
        // The row landed, minus the unknown column.
        let name = try db.read { try String.fetchOne($0, sql: "SELECT name FROM counterparties WHERE id='cp1'") }
        XCTAssertEqual(name, "Whole Foods")
        let verified = try db.read { try Int.fetchOne($0, sql: "SELECT is_verified FROM counterparties WHERE id='cp1'") }
        XCTAssertEqual(verified, 1, "known columns still bind correctly alongside a dropped one")
    }

    /// Skew must not silently drop a row: one unknown column among known ones
    /// keeps the row, but a row of ONLY unknown columns inserts nothing rather
    /// than issuing an empty INSERT.
    func test_rowOfOnlyUnknownColumnsIsSkipped() throws {
        let db = try freshDB()
        let tables: [String: [[String: String]]] = [
            "counterparties": [["not_a_column": "x", "also_bogus": "y"]],
        ]
        let problems = try DownSync.ingest(into: db, tables: tables)
        XCTAssertTrue(problems.isEmpty)
        let n = try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM counterparties") }
        XCTAssertEqual(n, 0)
    }

    /// A budget in a group, a rule and a holding come across too. The group was not
    /// synced, so the grouped budget failed its foreign key and the whole seed rolled
    /// back; rules and holdings were silently left behind.
    func test_groupedBudgetsRulesAndHoldingsRoundTrip() throws {
        let live = try TestSeed.base()   // l1 / a1 / c1
        try live.write { db in
            try db.execute(sql: "INSERT INTO budget_groups (id,ledger_id,name,sort_order,created_at,updated_at) VALUES ('bg1','l1','Home',0,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO budgets (id,ledger_id,group_id,kind,amount,frequency,start_date,created_at,updated_at) VALUES ('b1','l1','bg1','expense',100,'monthly','2026-01-01',datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('inv','l1','Brokerage','investment','USD',0,1,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO holdings (id,ledger_id,account_id,symbol,shares,cost_basis,currency,created_at,updated_at) VALUES ('h1','l1','inv','VTI',10,2000,'USD',datetime('now'),datetime('now'))")
        }
        try Apply.apply(dbQueue: live, action: "createRule", args: Args([
            "id": .string("r1"), "ledgerId": .string("l1"), "name": .string("Coffee"),
            "condition": .object(["field": .string("merchant"), "op": .string("contains"), "value": .string("coffee")]),
            "actions": .array([.object(["type": .string("set_category"), "categoryId": .string("c1")])])]))

        let fresh = try freshDB()
        let problems = try DownSync.ingest(into: fresh, tables: try DownSync.extract(from: live))
        XCTAssertEqual(problems.map(\.code.rawValue), [])
        for (table, id) in [("budget_groups", "bg1"), ("budgets", "b1"), ("rules", "r1"), ("holdings", "h1")] {
            XCTAssertEqual(try fresh.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table) WHERE id = ?", arguments: [id]) }, 1, table)
        }
    }
}
