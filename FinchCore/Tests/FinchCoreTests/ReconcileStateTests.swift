import XCTest
import GRDB
@testable import FinchCore

final class ReconcileStateTests: XCTestCase {
    func test_reconcile_state_cleared_vs_target() throws {
        let q = try TestSeed.base()   // l1 / c1 (USD base)
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("ra"), "ledgerId": .string("l1"), "name": .string("Checking"),
            "type": .string("cash"), "currency": .string("USD"), "openingBalance": .double(100)]))
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("ra"), "amount": .double(-30),
            "merchant": .string("Shop"), "categoryId": .string("c1"), "date": .string("2026-06-10"), "skipRules": .bool(true)]))
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("ra"), "amount": .double(50),
            "merchant": .string("Pay"), "categoryId": .string("c1"), "date": .string("2026-06-11"), "skipRules": .bool(true)]))

        // clear the +50 by its projected id
        let pre = try Projection.run(dbQueue: q, ledgerId: "l1")
        let pay = try XCTUnwrap(pre.first { $0.merchant == "Pay" && $0.account == "ra" })
        try Apply.apply(dbQueue: q, action: "setCleared", args: Args(["id": .string(pay.id), "cleared": .bool(true)]))

        let a = try XCTUnwrap(try Projection.accounts(dbQueue: q, ledgerId: "l1").first { $0.id == "ra" })
        let txns = try Projection.run(dbQueue: q, ledgerId: "l1")

        // balance = 100 − 30 + 50 = 120; clearedBalance = 120 − (−30) = 150 (= opening 100 + cleared 50)
        let s = Selectors.reconcileState(a, txns, 150)
        XCTAssertEqual(s.clearedBalance, 150, accuracy: 0.001)
        XCTAssertEqual(s.difference, 0, accuracy: 0.001)
        XCTAssertTrue(s.balanced)
        XCTAssertEqual(s.clearedCount, 1)     // the +50 (opening leg excluded from projected txns)
        XCTAssertEqual(s.unclearedCount, 1)   // the −30

        let s2 = Selectors.reconcileState(a, txns, 120)
        XCTAssertEqual(s2.difference, -30, accuracy: 0.001)   // 120 − 150
        XCTAssertFalse(s2.balanced)
    }
}
