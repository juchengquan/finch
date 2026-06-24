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

    // MARK: ruleMatchCounts

    private func tx(_ id: String, applied: [String]? = nil, ledger: String = "l1") -> Tx {
        Tx(id: id, merchant: "m", amount: -5, account: "a1", date: "2026-05-01",
           ledgerId: ledger, appliedRuleIds: applied)
    }

    func test_ruleMatchCounts_by_rule_id() {
        let r = Selectors.ruleMatchCounts([tx("t1", applied: ["r1"]), tx("t2", applied: ["r1", "r2"])], "l1")
        XCTAssertEqual(r, ["r1": 2, "r2": 1])
    }

    func test_ruleMatchCounts_excludes_other_ledger_and_unapplied() {
        let r = Selectors.ruleMatchCounts([tx("t1", applied: ["r1"]), tx("t2", applied: ["r1"], ledger: "l2"), tx("t3")], "l1")
        XCTAssertEqual(r, ["r1": 1])
    }

}
