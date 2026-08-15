import XCTest
import FinchCore
@testable import FinchApp

/// `ScheduledTemplate.amount` is an unsigned magnitude with `type` carrying the
/// direction — unlike `Tx.amount`, which is already signed. `signedAmount` is what every
/// screen must render, and this pins the three cases it has to get right.
final class ScheduledAmountTests: XCTestCase {
    private func template(_ type: String, _ amount: Double?) -> ScheduledTemplate {
        ScheduledTemplate(id: "s1", name: "n", type: type, amount: amount,
                          frequency: "monthly", dayOfMonth: 1, accountId: "a1", nextRun: "2026-09-01")
    }

    func testAnExpenseReadsNegative() {
        XCTAssertEqual(template("expense", 1500).signedAmount, -1500)
    }

    func testIncomeStaysPositive() {
        XCTAssertEqual(template("income", 4200).signedAmount, 4200)
    }

    /// Money moving between your own accounts is neither spent nor received — the
    /// day-totals logic excludes transfers from both sides for the same reason.
    func testATransferIsUnsigned() {
        XCTAssertEqual(template("transfer", 200).signedAmount, 200)
    }

    /// A template already carrying a negative magnitude must not flip back to positive —
    /// `abs` first, so the type is the single source of direction.
    func testANegativeMagnitudeIsStillAnExpense() {
        XCTAssertEqual(template("expense", -1500).signedAmount, -1500)
    }

    /// A variable-amount template has nothing to sign.
    func testNilStaysNil() {
        XCTAssertNil(template("expense", nil).signedAmount)
    }
}
