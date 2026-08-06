import XCTest
import GRDB
@testable import FinchCore

/// What the user typed, kept per cell.
///
/// A category leg is stored in the LEDGER BASE, so on a foreign-currency
/// purchase the stored figure is not the one that was entered. Keeping the typed
/// figure alongside it is what lets a grid reopen showing the numbers the user
/// actually wrote rather than back-converted ones — which drift by a cent on
/// awkward rates, and would be baked in as the new truth on the next save.
///
/// This is deliberately NOT part of the equivalence oracle: `addTransaction`
/// writes one auto-balanced category leg and has no per-cell concept, so there
/// is nothing to be equivalent to.
final class TypedAmountTests: XCTestCase {

    /// Base USD, one USD card, rate 1 EUR = 1.10 USD.
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
            try db.execute(sql: "INSERT INTO exchange_rates (date,currency,rate) VALUES ('2026-06-01','EUR',1.10)")
        }
        return q
    }

    private func write(_ q: DatabaseQueue, currency: String) throws {
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string("Market"),
            "date": .string("2026-06-01"), "kind": .string("expense"),
            "currency": .string(currency), "skipRules": .bool(true),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .string("c1"), "amount": .double(-70)]),
                .object(["accountId": .string("a1"), "categoryId": .string("c2"), "amount": .double(-30)]),
            ]),
        ]))
    }

    /// A €100 purchase split €70 / €30 across two categories, on a USD card.
    /// Each category leg must remember its own typed figure, not just the
    /// converted $77 / $33.
    func test_eachCellRemembersTheAmountAsTyped() throws {
        let q = try seed()
        try write(q, currency: "EUR")

        let byCategory = try q.read { db in
            try Row.fetchAll(db, sql: """
                SELECT category_id, ROUND(orig_amount,2) AS oa, orig_currency AS oc
                  FROM postings WHERE category_id IS NOT NULL ORDER BY category_id
                """).reduce(into: [String: (Double?, String?)]()) {
                    $0[$1["category_id"]] = ($1["oa"], $1["oc"])
                }
        }
        // Stored with the same negation the category leg's amount_base carries,
        // so the projection's existing flip restores both together.
        XCTAssertEqual(byCategory["c1"]?.0, 70, "the €70 the user typed")
        XCTAssertEqual(byCategory["c1"]?.1, "EUR")
        XCTAssertEqual(byCategory["c2"]?.0, 30, "the €30 the user typed")
        XCTAssertEqual(byCategory["c2"]?.1, "EUR")
    }

    /// And it survives the trip back out, sign-corrected like `amount` is.
    func test_theTypedAmountReachesTheProjectedSplits() throws {
        let q = try seed()
        try write(q, currency: "EUR")

        // `Projection.run` returns `[Tx]` directly — there is no wrapper type.
        let txns = try Projection.run(dbQueue: q, ledgerId: "l1")
        let tx = txns.first { $0.splits?.isEmpty == false }
        let splits = try XCTUnwrap(tx?.splits)
        let c1 = try XCTUnwrap(splits.first { $0.categoryId == "c1" })
        XCTAssertEqual(c1.origAmount ?? 0, -70, accuracy: 0.001, "signed like `amount`, and in euros")
        XCTAssertEqual(c1.origCurrency, "EUR")
        XCTAssertEqual(c1.amountBase, -77, accuracy: 0.001, "the base figure is unchanged by any of this")
    }

    /// A same-currency purchase records nothing: the pair would only duplicate
    /// what is already stored, and nil is what "not a foreign entry" means.
    func test_aSameCurrencyPurchaseRecordsNoTypedCopy() throws {
        let q = try seed()
        try write(q, currency: "USD")
        let anyOrig = try q.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE orig_amount IS NOT NULL") ?? -1
        }
        XCTAssertEqual(anyOrig, 0)
    }

    /// A transfer's two sides are each typed in their OWN card's currency, so
    /// there is no "as typed in another currency" figure to keep.
    func test_aTransferRecordsNoTypedCopy() throws {
        let q = try seed()
        try q.write { db in
            try db.execute(sql: """
                INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at)
                VALUES ('eur','l1','Euro','cash','EUR',0,2,1,1,datetime('now'),datetime('now'))
                """)
        }
        try Apply.apply(dbQueue: q, action: "saveTransaction", args: Args([
            "ledgerId": .string("l1"), "merchant": .string(""),
            "date": .string("2026-06-01"), "kind": .string("transfer"), "skipRules": .bool(true),
            "cells": .array([
                .object(["accountId": .string("a1"), "categoryId": .null, "amount": .double(-110)]),
                .object(["accountId": .string("eur"), "categoryId": .null, "amount": .double(100)]),
            ]),
        ]))
        let anyOrig = try q.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE orig_amount IS NOT NULL") ?? -1
        }
        XCTAssertEqual(anyOrig, 0)
    }
}
