import Foundation
import GRDB
@testable import FinchCore

/// Shared test seed — a migrated DB with USD ledger `l1`, cash account `a1`, and
/// expense category `c1` (Food). The base INSERTs were copy-pasted across many
/// test files; centralize them here. Tests that need more (extra accounts /
/// categories) seed `base()` then add their own rows.
enum TestSeed {
    static func seedBase(into db: Database) throws {
        try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
        try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','Cash','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
        try db.execute(sql: "INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at) VALUES ('c1','l1',NULL,'Food','expense',0,datetime('now'),datetime('now'))")
    }

    static func base() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { try seedBase(into: $0) }
        return q
    }
}
