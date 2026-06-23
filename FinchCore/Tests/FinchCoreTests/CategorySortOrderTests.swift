import XCTest
@testable import FinchCore

final class CategorySortOrderTests: XCTestCase {
    func test_updateCategory_sets_sort_order_changing_projection_order() throws {
        let q = try TestSeed.base()   // seeds category c1 "Food" sort_order 0
        try Apply.apply(dbQueue: q, action: "createCategory", args: Args([
            "id": .string("cx"), "ledgerId": .string("l1"), "name": .string("Coffee"), "type": .string("expense"),
        ]))   // cx gets sort_order MAX+1 = 1
        XCTAssertEqual(try Projection.categories(dbQueue: q, ledgerId: "l1").map(\.id), ["c1", "cx"])

        // Move cx ahead of c1 by giving it a lower sort_order.
        try Apply.apply(dbQueue: q, action: "updateCategory", args: Args([
            "id": .string("cx"), "patch": .object(["sortOrder": .int(-1)]),
        ]))
        XCTAssertEqual(try Projection.categories(dbQueue: q, ledgerId: "l1").map(\.id), ["cx", "c1"])
    }
}
