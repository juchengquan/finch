import XCTest
import GRDB
@testable import FinchCore

final class ReconcileStatusTests: XCTestCase {
    func test_reconcileStatus_never_fresh_stale_boundary() {
        XCTAssertEqual(Selectors.reconcileStatus(nil, "2026-06-26"), .never)
        XCTAssertEqual(Selectors.reconcileStatus("", "2026-06-26"), .never)
        XCTAssertEqual(Selectors.reconcileStatus("2026-06-26", "2026-06-26"), .fresh(days: 0))
        XCTAssertEqual(Selectors.reconcileStatus("2026-05-22", "2026-06-26"), .fresh(days: 35))   // exactly 35 → fresh
        XCTAssertEqual(Selectors.reconcileStatus("2026-05-21", "2026-06-26"), .stale(days: 36))   // 36 → stale
        XCTAssertEqual(Selectors.reconcileStatus("2026-07-01", "2026-06-26"), .fresh(days: 0))    // future → clamp 0
    }

    func test_accounts_projection_carries_last_reconciled() throws {
        let q = try TestSeed.base()   // l1 / a1 / c1
        try Apply.apply(dbQueue: q, action: "reconcileAccount", args: Args([
            "accountId": .string("a1"), "statementBalance": .double(1200), "statementDate": .string("2026-05-01")]))
        let a = try XCTUnwrap(Projection.accounts(dbQueue: q, ledgerId: "l1").first { $0.id == "a1" })
        XCTAssertEqual(a.lastReconciledAt, "2026-05-01")
        XCTAssertEqual(a.lastReconciledBalance, 1200)
        // a never-reconciled account projects nil (seed a 2nd account)
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("a2"), "ledgerId": .string("l1"), "name": .string("Savings"), "type": .string("savings"), "currency": .string("USD")]))
        let a2 = try XCTUnwrap(Projection.accounts(dbQueue: q, ledgerId: "l1").first { $0.id == "a2" })
        XCTAssertNil(a2.lastReconciledAt)
        XCTAssertNil(a2.lastReconciledBalance)
    }
}
