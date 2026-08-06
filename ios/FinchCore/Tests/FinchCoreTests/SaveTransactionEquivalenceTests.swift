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
    /// `comparingTypedAmounts: false` drops `orig_*` from the comparison, for the
    /// one shape where the two doors are handed DIFFERENT information and so
    /// cannot be expected to record the same thing. See the mixed-currency split.
    private func canonical(_ q: DatabaseQueue, comparingTypedAmounts: Bool = true) throws -> String {
        try q.read { db in
            var out: [String] = []
            for e in try Row.fetchAll(db, sql: """
                SELECT id, date, time, description, kind, status, group_id
                  FROM entries WHERE kind != 'opening' ORDER BY date, description
                """) {
                let eid: String = e["id"]
                let legs = try Row.fetchAll(db, sql: """
                    SELECT account_id, category_id, ROUND(amount,2) AS a, currency,
                           ROUND(amount_base,2) AS ab, memo,
                           ROUND(orig_amount,2) AS oa, orig_currency AS oc
                      FROM postings WHERE entry_id = ?
                     ORDER BY COALESCE(account_id,''), COALESCE(category_id,''), ab
                    """, arguments: [eid])
                    .map { r -> String in
                        let acct = r["account_id"] as String? ?? ""
                        // orig_amount/orig_currency — what the user TYPED, and the pair
                        // `Projection.swift:81` displays from. Compared on the ACCOUNT leg
                        // only: that is the one the old actions also fill, so it is the one
                        // where a difference means a real disagreement.
                        //
                        // Category legs carry a per-cell copy that `addTransaction` has no
                        // concept of — it writes one auto-balanced category leg, and a grid
                        // has no old-action equivalent at all. Comparing it here would
                        // assert a difference that is by design. `TypedAmountTests` covers
                        // that side instead.
                        let orig = (acct.isEmpty || !comparingTypedAmounts)
                            ? "" : "\(r["oa"] as Double? ?? 0)|\(r["oc"] as String? ?? "")"
                        return "\(acct)|\(r["category_id"] as String? ?? "")|\(r["a"] as Double)"
                             + "|\(r["currency"] as String? ?? "")|\(r["ab"] as Double)"
                             + "|\(r["memo"] as String? ?? "")|\(orig)"
                    }
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

    /// The case where a currency mistake would hide: one purchase, two cards
    /// holding DIFFERENT currencies, amounts given in the purchase's.
    ///
    /// `addTransaction` and `saveTransaction` are two doors into one core, so
    /// disagreement here means one of them is lying about currency — and the lie
    /// would be invisible, because either reading produces a balanced entry.
    ///
    /// **The two doors take different units, on purpose.** `addTransaction`'s
    /// shares are each in their OWN account's currency; `saveTransaction`'s cells
    /// are all in the PURCHASE's, so a grid's columns add up when the cards hold
    /// different currencies (Decision 16). The same purchase therefore reaches
    /// them as different numbers — 36.36 EUR to one, the 40 USD it cost to the
    /// other — and must land as the same ledger. Handing either one the other's
    /// units is caught rather than absorbed: fed cells in the purchase currency,
    /// `addTransaction` refuses, because the shares then sum to 104 against a
    /// stated 100.
    func test_matchesAddTransaction_forAMixedCurrencySplit() throws {
        let old = try seed(), new = try seed()
        for q in [old, new] {
            try q.write { db in
                try db.execute(sql: """
                    INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                    VALUES ('eur','l1','Euro','cash','EUR',0,2,1,1,datetime('now'),datetime('now'))
                    """)
                try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-06-01','EUR',1.10)")
            }
        }

        try Apply.apply(dbQueue: old, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "amount": .double(-100), "currency": .string("USD"),
            "merchant": .string("Market"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"), "time": .string("12:00"), "skipRules": .bool(true),
            "accounts": .array([
                .object(["accountId": .string("a1"), "amount": .double(-60)]),
                // In the EUR account's own currency: the 40 USD share is
                // 36.36 EUR, the rate being 1 EUR = 1.10 USD.
                .object(["accountId": .string("eur"), "amount": .double(-36.36)]),
            ]),
        ]))
        try Apply.apply(dbQueue: new, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "time": .string("12:00"),
            "kind": .string("expense"), "currency": .string("USD"), "skipRules": .bool(true),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-60)]),
                .object(["accountId": .string("eur"), "categoryId": .string("c1"), "amount": .double(-40)]),
            ]),
        ]))
        // The MONEY must match exactly. The typed record is deliberately excluded:
        // `addTransaction`'s shares arrive already converted into each account's
        // own currency, so it was never told what the user typed and records
        // nothing. `saveTransaction`'s cells arrive in the purchase currency, so it
        // knows the EUR card's share was typed as $40 and keeps it.
        //
        // That is a difference in FIDELITY, not in the ledger: one door was handed
        // information the other never receives. Asserted below rather than left
        // implicit, so a future change that drops it fails here.
        XCTAssertEqual(try canonical(new, comparingTypedAmounts: false),
                       try canonical(old, comparingTypedAmounts: false))

        let typed = try new.read { db in
            try Row.fetchOne(db, sql: """
                SELECT ROUND(orig_amount,2) AS oa, orig_currency AS oc
                  FROM postings WHERE account_id = 'eur'
                """)
        }
        XCTAssertEqual(typed?["oa"] as Double?, -40, "the share as typed, in the purchase's currency")
        XCTAssertEqual(typed?["oc"] as String?, "USD")

        let untyped = try old.read { db in
            try Double.fetchOne(db, sql: "SELECT orig_amount FROM postings WHERE account_id = 'eur'")
        }
        XCTAssertNil(untyped, "addTransaction was handed €36.36 and has nothing to remember")
    }

    /// A foreign-currency purchase: €100 paid with a USD card, ledger base USD.
    ///
    /// The figure the app DISPLAYS is `orig_amount ?? amount`
    /// (`Projection.swift:81`), so an action that does not record the pair shows
    /// the converted $110 where the user typed €100 — and the €100 is gone, not
    /// recoverable from anything else in the row.
    func test_matchesAddTransaction_forAForeignCurrencyPurchase() throws {
        let old = try seed(), new = try seed()
        for q in [old, new] {
            try q.write { db in
                try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-06-01','EUR',1.10)")
            }
        }

        try Apply.apply(dbQueue: old, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-100),
            "currency": .string("EUR"), "merchant": .string("Market"), "categoryId": .string("c1"),
            "date": .string("2026-06-01"), "time": .string("12:00"), "skipRules": .bool(true),
        ]))
        try Apply.apply(dbQueue: new, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "time": .string("12:00"),
            "kind": .string("expense"), "currency": .string("EUR"), "skipRules": .bool(true),
            "cells": .array([.object([
                "accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-100),
            ])]),
        ]))
        XCTAssertEqual(try canonical(new), try canonical(old))
    }

    /// A same-currency transfer. The engine authors the description and both leg
    /// memos, so a sheet that sends only the two amounts still produces the feed
    /// text `createTransfer` produced.
    func test_matchesCreateTransfer_forASameCurrencyTransfer() throws {
        let old = try seed(), new = try seed()

        try Apply.apply(dbQueue: old, action: "createTransfer", args: Args([
            "fromAccountId": .string("a1"), "toAccountId": .string("a2"),
            "fromAmount": .double(100),
            "date": .string("2026-06-01"), "time": .string("12:00"),
        ]))
        try Apply.apply(dbQueue: new, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string(""),
            "date": .string("2026-06-01"), "time": .string("12:00"),
            "kind": .string("transfer"), "currency": .string("USD"), "skipRules": .bool(true),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .null, "amount": .double(-100)]),
                .object(["accountId": .string("a2"), "categoryId": .null, "amount": .double(100)]),
            ]),
        ]))
        XCTAssertEqual(try canonical(new), try canonical(old))
    }

    /// A cross-currency transfer: 110 USD out, 100 EUR in. Both numbers are typed
    /// by the user, so both must survive verbatim — this is the case where
    /// treating cells as purchase-currency would silently store a different
    /// transfer.
    func test_matchesCreateTransfer_forACrossCurrencyTransfer() throws {
        let old = try seed(), new = try seed()
        for q in [old, new] {
            try q.write { db in
                try db.execute(sql: """
                    INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                    VALUES ('eur','l1','Euro','cash','EUR',0,2,1,1,datetime('now'),datetime('now'))
                    """)
                try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-06-01','EUR',1.10)")
            }
        }

        try Apply.apply(dbQueue: old, action: "createTransfer", args: Args([
            "fromAccountId": .string("a1"), "toAccountId": .string("eur"),
            "fromAmount": .double(110), "toAmount": .double(100),
            "date": .string("2026-06-01"), "time": .string("12:00"),
        ]))
        try Apply.apply(dbQueue: new, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string(""),
            "date": .string("2026-06-01"), "time": .string("12:00"),
            "kind": .string("transfer"), "skipRules": .bool(true),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .null, "amount": .double(-110)]),
                .object(["accountId": .string("eur"), "categoryId": .null, "amount": .double(100)]),
            ]),
        ]))
        XCTAssertEqual(try canonical(new), try canonical(old))
    }
}
