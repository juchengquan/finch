import XCTest
@testable import FinchCore

final class CategoryProjectionTests: XCTestCase {
    func test_projection_carries_icon_and_color() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "createCategory", args: Args([
            "id": .string("cx"), "ledgerId": .string("l1"), "name": .string("Coffee"),
            "type": .string("expense"), "icon": .string("fork"), "color": .string("#00a0c5"),
        ]))
        let cats = try Projection.categories(dbQueue: q, ledgerId: "l1")
        let c = try XCTUnwrap(cats.first { $0.id == "cx" })
        XCTAssertEqual(c.icon, "fork")
        XCTAssertEqual(c.color, "#00a0c5")
    }

    func test_projection_nil_icon_color_when_absent() throws {
        let q = try TestSeed.base()   // seeds category 'c1' (Food) with no icon/color
        let cats = try Projection.categories(dbQueue: q, ledgerId: "l1")
        let c = try XCTUnwrap(cats.first { $0.id == "c1" })
        XCTAssertNil(c.icon)
        XCTAssertNil(c.color)
    }
}
