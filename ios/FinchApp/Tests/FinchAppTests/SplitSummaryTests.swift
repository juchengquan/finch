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

    // The rule REVERSED when page 2 took over dividing.
    //
    // It used to be: the summary reads `payload` (funded rows), because `save()`
    // gated on `payload.count >= 2` and a two-name summary describing a
    // transaction that saved as single-account would be a lie.
    //
    // The pickers now collect no amounts at all — they select, page 2 divides —
    // so `payload` is empty until page 2 has been through. Reading it made a
    // two-account row display ONE name, which is what a user reported as
    // "it only shows one for each". The summary describes the SELECTION, and
    // page 2 is where a selection becomes amounts.
    func test_namesFor_readsTheSelection_notJustFundedRows() {
        var alloc = SplitAllocation(total: 0)   // straight off the picker: no amounts
        alloc.tick("a1"); alloc.tick("a2")
        let options = [PickerOption(id: "a1", name: "Checking"), PickerOption(id: "a2", name: "Savings")]

        XCTAssertTrue(alloc.payload.isEmpty, "nothing is funded until page 2")
        XCTAssertEqual(SearchablePickerRow<Text>.namesFor(payload: alloc.payload, options: options), [],
                       "reading payload is the bug: the row would name nothing, and fall back to one")
        XCTAssertEqual(SearchablePickerRow<Text>.namesFor(payload: alloc.selection, options: options),
                       ["Checking", "Savings"],
                       "the selection is what the row describes")
    }

    /// And a selection still reads correctly once page 2 HAS given it amounts —
    /// a reopened split arrives that way.
    func test_namesFor_stillReadsASelectionThatCarriesAmounts() {
        let alloc = SplitAllocation.merging([(id: Optional("a1"), amount: 60),
                                             (id: Optional("a2"), amount: 40)], total: 100)
        let options = [PickerOption(id: "a1", name: "Checking"), PickerOption(id: "a2", name: "Savings")]
        XCTAssertEqual(SearchablePickerRow<Text>.namesFor(payload: alloc.selection, options: options),
                       ["Checking", "Savings"])
    }
}
