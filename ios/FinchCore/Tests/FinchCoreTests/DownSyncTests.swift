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
}
