import XCTest
import GRDB
@testable import FinchCore

/// `saveTransaction` must produce the same ledger the old multi-write sequence
/// did.
///
/// This is how the cross-stack guarantee transfers. The oracle replays
/// `addTransaction` + `setTransactionSplits` and compares both stacks' database
/// state; it cannot replay `saveTransaction`, because that would need a web
/// implementation this plan is not scoped for. Proving the new command equals the
/// old sequence means the oracle still covers the semantics, one step removed.
///
/// **The honest limit:** this proves equivalence only for shapes the old actions
/// can express. A grid has no old-action equivalent and is covered by iOS tests
/// alone until the web catches up.
final class SaveTransactionEquivalenceTests: XCTestCase {

    private func seed() throws -> DatabaseQueue {
        let q = try TestSeed.base()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('a2','l1','Card','credit_card','USD',0,1,1,1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO categories (id,ledger_id,parent_id,name,kind,sort_order,created_at,updated_at)
                VALUES ('c2','l1',NULL,'Household','expense',1,datetime('now'),datetime('now'))
                """)
            try db.execute(sql: """
                INSERT INTO tags (id,ledger_id,name,created_at,updated_at)
                VALUES ('t1','l1','Trip',datetime('now'),datetime('now'))
                """)
        }
        return q
    }

    /// The ledger's shape, ignoring anything that cannot match between two runs
    /// (ids and timestamps). Deliberately mirrors what the write-parity oracle
    /// compares: entry header fields plus every posting's money and identity.
    private func canonical(_ q: DatabaseQueue) throws -> String {
        try q.read { db in
            var out: [String] = []
            for e in try Row.fetchAll(db, sql: """
                SELECT id, date, time, description, kind, status, group_id
                  FROM entries WHERE kind != 'opening' ORDER BY date, description
                """) {
                let eid: String = e["id"]
                let legs = try Row.fetchAll(db, sql: """
                    SELECT account_id, category_id, ROUND(amount,2) AS a, currency, ROUND(amount_base,2) AS ab, memo
                      FROM postings WHERE entry_id = ?
                     ORDER BY COALESCE(account_id,''), COALESCE(category_id,''), ab
                    """, arguments: [eid])
                    .map { "\($0["account_id"] as String? ?? "")|\($0["category_id"] as String? ?? "")|\($0["a"] as Double)|\($0["currency"] as String? ?? "")|\($0["ab"] as Double)|\($0["memo"] as String? ?? "")" }
                let tags = try String.fetchAll(db, sql: "SELECT tag_id FROM entry_tags WHERE entry_id = ? ORDER BY tag_id", arguments: [eid])
                out.append("""
                    \(e["date"] as String)|\(e["time"] as String? ?? "")|\(e["description"] as String? ?? "")\
                    |\(e["kind"] as String)|\(e["status"] as String)|\(e["group_id"] as String? ?? "")\
                    |legs:\(legs.joined(separator: ","))|tags:\(tags.joined(separator: ","))
                    """)
            }
            return out.joined(separator: "\n")
        }
    }

    /// An ordinary single-card purchase with tags.
    func test_matchesAddTransaction_forAPlainPurchase() throws {
        let old = try seed(), new = try seed()

        try Apply.apply(dbQueue: old, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-100),
            "merchant": .string("Market"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"), "time": .string("12:00"),
            "tagIds": .array([.string("t1")]), "skipRules": .bool(true),
        ]))
        try Apply.apply(dbQueue: new, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "time": .string("12:00"),
            "kind": .string("expense"), "currency": .string("USD"),
            "cells": .array([.object([
                "accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-100),
            ])]),
            "tagIds": .array([.string("t1")]), "skipRules": .bool(true),
        ]))
        XCTAssertEqual(try canonical(new), try canonical(old))
    }

    /// Split tender: one purchase, two cards, one category.
    func test_matchesAddTransaction_forSplitTender() throws {
        let old = try seed(), new = try seed()

        try Apply.apply(dbQueue: old, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "amount": .double(-100), "currency": .string("USD"),
            "merchant": .string("Market"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"), "time": .string("12:00"), "skipRules": .bool(true),
            "accounts": .array([
                .object(["accountId": .string("a1"), "amount": .double(-60)]),
                .object(["accountId": .string("a2"), "amount": .double(-40)]),
            ]),
        ]))
        try Apply.apply(dbQueue: new, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "time": .string("12:00"),
            "kind": .string("expense"), "currency": .string("USD"), "skipRules": .bool(true),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-60)]),
                .object(["accountId": .string("a2"), "categoryId": .string("c1"), "amount": .double(-40)]),
            ]),
        ]))
        XCTAssertEqual(try canonical(new), try canonical(old))
    }

    /// A category split — the sequence the Add sheet used to fire as TWO writes,
    /// which is the case where a part-way failure was visible.
    func test_matchesAddThenSetSplits_forACategorySplit() throws {
        let old = try seed(), new = try seed()

        let eid = try Apply.applyReturningId(dbQueue: old, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-100),
            "merchant": .string("Market"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"), "time": .string("12:00"), "skipRules": .bool(true),
        ]))!
        try Apply.apply(dbQueue: old, action: "setTransactionSplits", args: Args([
            "id": .string(eid), "splits": .array([
                .object(["categoryId": .string("c1"), "amount": .double(-70)]),
                .object(["categoryId": .string("c2"), "amount": .double(-30)]),
            ]),
        ]))
        try Apply.apply(dbQueue: new, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "time": .string("12:00"),
            "kind": .string("expense"), "currency": .string("USD"), "skipRules": .bool(true),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-70)]),
                .object(["accountId": .string("a1"), "categoryId": .string("c2"), "amount": .double(-30)]),
            ]),
        ]))
        XCTAssertEqual(try canonical(new), try canonical(old))
    }
}
