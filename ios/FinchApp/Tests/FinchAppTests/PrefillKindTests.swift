import XCTest
import FinchCore
@testable import FinchApp

/// Duplicate used to be offered on expense/income ONLY — not because other kinds
/// couldn't be duplicated, but because the prefill collapsed every non-income
/// kind to `.expense`, so duplicating a transfer would silently have produced an
/// expense. These pin the mapping that removed that guard.
@MainActor
final class PrefillKindTests: XCTestCase {

    private func tx(kind: String?) -> Tx {
        Tx(id: "t1", merchant: "M", category: nil, amount: -10, account: "a1",
           date: "2026-07-20", kind: kind)
    }

    func test_everyEngineKindMapsToItsOwnSegment() {
        XCTAssertEqual(AddTransactionSheet.prefillKind(tx(kind: "expense")),    .expense)
        XCTAssertEqual(AddTransactionSheet.prefillKind(tx(kind: "income")),     .income)
        XCTAssertEqual(AddTransactionSheet.prefillKind(tx(kind: "transfer")),   .transfer)
        XCTAssertEqual(AddTransactionSheet.prefillKind(tx(kind: "refund")),     .refund)
        XCTAssertEqual(AddTransactionSheet.prefillKind(tx(kind: "adjustment")), .adjust)
    }

    /// The old behaviour, kept only for genuinely unknown kinds.
    func test_unknownOrMissingKindFallsBackToExpense() {
        XCTAssertEqual(AddTransactionSheet.prefillKind(tx(kind: nil)), .expense)
        XCTAssertEqual(AddTransactionSheet.prefillKind(tx(kind: "something-new")), .expense)
    }

    /// The regression that motivated this: a transfer must NOT become an expense.
    func test_transferIsNotSilentlyAnExpense() {
        XCTAssertNotEqual(AddTransactionSheet.prefillKind(tx(kind: "transfer")), .expense)
    }
}
