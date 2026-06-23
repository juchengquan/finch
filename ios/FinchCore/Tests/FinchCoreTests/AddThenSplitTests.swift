import XCTest
import GRDB
@testable import FinchCore

final class AddThenSplitTests: XCTestCase {
    func test_addTransaction_thenSetTransactionSplits_buildsTwoCategoryLegs() throws {
        let q = try TestSeed.base()   // l1 / a1 / c1
        try Apply.apply(dbQueue: q, action: "createCategory",
                        args: Args(["id": .string("c2"), "ledgerId": .string("l1"), "name": .string("Household"), "kind": .string("expense")]))
        let eid = try Apply.applyReturningId(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-30),
            "merchant": .string("Market"), "categoryId": .string("c1"), "date": .string("2026-06-01")]))
        try Apply.apply(dbQueue: q, action: "setTransactionSplits", args: Args([
            "id": .string(eid!),
            "splits": .array([
                .object(["categoryId": .string("c1"), "amount": .double(20)]),
                .object(["categoryId": .string("c2"), "amount": .double(10)]),
            ])]))
        let catLegs = try q.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE entry_id = ? AND category_id IS NOT NULL", arguments: [eid!])
        }
        XCTAssertEqual(catLegs, 2)
    }
}
