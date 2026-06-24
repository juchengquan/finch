import XCTest
@testable import FinchCore

final class RulesEditingTests: XCTestCase {
    func test_rules_projection_carries_condition_actions_runOnEdit() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "createRule", args: Args([
            "id": .string("r1"), "ledgerId": .string("l1"), "name": .string("Coffee"),
            "condition": .object(["field": .string("merchant"), "op": .string("contains"), "value": .string("coffee")]),
            "actions": .array([.object(["type": .string("set_category"), "categoryId": .string("c1")])]),
            "runOnEdit": .bool(true),
        ]))
        let rules = try Projection.rules(dbQueue: q, ledgerId: "l1")
        let r = try XCTUnwrap(rules.first { $0.id == "r1" })
        XCTAssertTrue(r.conditionJSON.contains("\"merchant\""))
        XCTAssertTrue(r.actionsJSON.contains("set_category"))
        XCTAssertTrue(r.runOnEdit)
    }
}
