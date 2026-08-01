import XCTest
import SwiftUI
@testable import FinchApp

final class SplitSummaryTests: XCTestCase {
    func test_single_or_zero_is_nil() {
        XCTAssertNil(splitSummaryText(names: []))
        XCTAssertNil(splitSummaryText(names: ["Food"]))
    }
    func test_two_or_more_joins_names() {
        XCTAssertEqual(splitSummaryText(names: ["Groceries", "Household"]), "Groceries, Household")
        XCTAssertEqual(splitSummaryText(names: ["A", "B", "C"]), "A, B, C")
    }
    // The account picker's row summary reuses this same helper — proving it's
    // genuinely axis-agnostic rather than secretly category-shaped.
    func test_two_or_more_joins_account_names() {
        XCTAssertEqual(splitSummaryText(names: ["Checking", "Savings"]), "Checking, Savings")
    }

    // I4 (fix round 1): a ticked-but-UNFUNDED row (its whole share pinned away
    // to another row) must not count toward the row's summary — `save()` gates
    // on `payload` (funded rows only), so a two-name summary describing a
    // transaction that actually saves as single-account would be a lie.
    // `SearchablePickerRow.namesFor` is what the row's live summary calls, fed
    // `payload`; feeding it `rows` instead (the bug) is shown here to contrast
    // with the correct `payload` behaviour on the exact same allocation.
    func test_namesFor_readsFundedRowsOnly_soAPinnedAwayRowIsExcluded() {
        var alloc = SplitAllocation(total: 100)
        alloc.tick("a1"); alloc.tick("a2")
        alloc.setAmount("a1", 100)   // pins a1 to the whole total; a2 floats to 0
        let options = [PickerOption(id: "a1", name: "Checking"), PickerOption(id: "a2", name: "Savings")]

        // Correct: `payload` (funded only) yields ONE name — not a split.
        let fromPayload = SearchablePickerRow<Text>.namesFor(payload: alloc.payload, options: options)
        XCTAssertEqual(fromPayload, ["Checking"])

        // The bug this fixes: `rows` (every ticked row, funded or not) would
        // have shown BOTH names even though only one row is actually funded.
        let fromRows = SearchablePickerRow<Text>.namesFor(
            payload: alloc.rows.map { (id: $0.id, amount: $0.amount) }, options: options)
        XCTAssertEqual(fromRows, ["Checking", "Savings"])
    }
}
