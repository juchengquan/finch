import XCTest
@testable import FinchApp

/// The FAB's page-context preference: a pushed detail page's (non-empty)
/// context must win over the empty default the rest of the tab publishes,
/// and popping back must restore the empty default.
final class AddTxContextTests: XCTestCase {

    func test_empty_by_default() {
        XCTAssertTrue(AddTxContextKey.defaultValue.isEmpty)
        XCTAssertTrue(AddTxContext().isEmpty)
        XCTAssertFalse(AddTxContext(accountId: "a1").isEmpty)
        XCTAssertFalse(AddTxContext(categoryId: "c1").isEmpty)
    }

    func test_reduce_nonEmpty_next_wins() {
        var value = AddTxContext()
        AddTxContextKey.reduce(value: &value, nextValue: { AddTxContext(accountId: "a1") })
        XCTAssertEqual(value.accountId, "a1")

        // A later non-empty sibling (innermost publisher) replaces the earlier one.
        AddTxContextKey.reduce(value: &value, nextValue: { AddTxContext(accountId: "a2", categoryId: "c2") })
        XCTAssertEqual(value.accountId, "a2")
        XCTAssertEqual(value.categoryId, "c2")
    }

    func test_reduce_empty_next_keeps_value() {
        var value = AddTxContext(accountId: "a1")
        AddTxContextKey.reduce(value: &value, nextValue: { AddTxContext() })
        XCTAssertEqual(value.accountId, "a1")
    }
}
