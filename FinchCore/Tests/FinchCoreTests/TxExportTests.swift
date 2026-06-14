import XCTest
import GRDB
@testable import FinchCore

/// Port-parity for the human-readable transactions CSV (web export.ts + csv.ts):
/// column order, RFC-4180 escaping, leg-per-row, newest-first, month scoping.
final class TxExportTests: XCTestCase {
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','Personal','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Cash','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('c1','l1',NULL,'Food','expense',0,datetime('now'),datetime('now'))")
        }
        return q
    }

    func test_csv_headerOrderAndRow() throws {
        let q = try seeded()
        // A merchant with a comma exercises RFC-4180 quoting.
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-12),
            "merchant": .string("Joe's, Diner"), "categoryId": .string("c1"),
            "date": .string("2026-05-10"), "time": .string("09:00"), "skipRules": .bool(true),
        ]))
        let csv = try q.read { db in try TxExport.csv(db, ledgerId: "l1", month: nil) }
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.first, "Date,Time,Ledger,Account,Merchant,Category,Amount,Currency,Amount (base),Status,Type,Note,Tags")
        let row = lines[1]
        XCTAssertTrue(row.hasPrefix("2026-05-10,09:00,l1,Cash,\"Joe's, Diner\",Food,-12,USD,-12,"), row)
        // Integral amounts stringify without a trailing ".0".
        XCTAssertFalse(row.contains("-12.0"), row)
        XCTAssertTrue(csv.hasSuffix("\r\n"))
    }

    func test_monthScope_filtersRows() throws {
        let q = try seeded()
        for (d, t) in [("2026-04-02", "08:00"), ("2026-05-03", "08:00")] {
            try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
                "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-5),
                "merchant": .string("Coffee"), "categoryId": .string("c1"),
                "date": .string(d), "time": .string(t), "skipRules": .bool(true),
            ]))
        }
        let may = try q.read { db in try TxExport.rows(db, ledgerId: "l1", month: "2026-05") }
        XCTAssertEqual(may.count, 1)
        XCTAssertEqual(may.first?.first, "2026-05-03")
        let all = try q.read { db in try TxExport.rows(db, ledgerId: "l1", month: nil) }
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first?.first, "2026-05-03") // newest first
    }
}
