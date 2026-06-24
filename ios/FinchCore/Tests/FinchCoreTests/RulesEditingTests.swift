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

    // MARK: SimpleRule.parse

    func test_simple_merchant_contains_set_category() {
        let cond = #"{"field":"merchant","op":"contains","value":"coffee"}"#
        let acts = #"[{"type":"set_category","categoryId":"cFood"}]"#
        let f = try? XCTUnwrap(SimpleRule.parse(conditionJSON: cond, actionsJSON: acts))
        XCTAssertEqual(f?.field, .merchant)
        XCTAssertEqual(f?.op, "contains")
        XCTAssertEqual(f?.value, "coffee")
        XCTAssertEqual(f?.action, .setCategory("cFood"))
    }

    func test_simple_amount_gt_mark_reviewed() {
        let cond = #"{"field":"amount","op":"gt","value":50}"#
        let acts = #"[{"type":"mark_reviewed"}]"#
        let f = SimpleRule.parse(conditionJSON: cond, actionsJSON: acts)
        XCTAssertEqual(f?.field, .amount); XCTAssertEqual(f?.op, "gt"); XCTAssertEqual(f?.value, "50")
        XCTAssertEqual(f?.action, .markReviewed)
    }

    func test_simple_large_amount_not_scientific() {
        // a large threshold must stay a plain number (regression: %g → "1.5e+06" was lossy/unparseable)
        let cond = #"{"field":"amount","op":"gt","value":1500000.0}"#
        let acts = #"[{"type":"set_category","categoryId":"c"}]"#
        XCTAssertEqual(SimpleRule.parse(conditionJSON: cond, actionsJSON: acts)?.value, "1500000")
    }

    func test_simple_accepts_legacy_set_reviewed() {
        let cond = #"{"field":"merchant","op":"is","value":"x"}"#
        let acts = #"[{"type":"set_reviewed"}]"#
        // op "is" is not a builder op (merchant builder = contains/equals) → nil
        XCTAssertNil(SimpleRule.parse(conditionJSON: cond, actionsJSON: acts))
        // but with a builder op, legacy set_reviewed parses to markReviewed
        let acts2 = #"[{"type":"set_reviewed"}]"#
        let f = SimpleRule.parse(conditionJSON: #"{"field":"merchant","op":"contains","value":"x"}"#, actionsJSON: acts2)
        XCTAssertEqual(f?.action, .markReviewed)
    }

    func test_complex_rules_return_nil() {
        // all/any wrapper
        XCTAssertNil(SimpleRule.parse(conditionJSON: #"{"all":[{"field":"merchant","op":"contains","value":"x"}]}"#,
                                      actionsJSON: #"[{"type":"set_category","categoryId":"c"}]"#))
        // unsupported field
        XCTAssertNil(SimpleRule.parse(conditionJSON: #"{"field":"tag_id","op":"has","value":"t"}"#,
                                      actionsJSON: #"[{"type":"set_category","categoryId":"c"}]"#))
        // multiple actions
        XCTAssertNil(SimpleRule.parse(conditionJSON: #"{"field":"merchant","op":"contains","value":"x"}"#,
                                      actionsJSON: #"[{"type":"set_category","categoryId":"c"},{"type":"mark_reviewed"}]"#))
        // unsupported action
        XCTAssertNil(SimpleRule.parse(conditionJSON: #"{"field":"merchant","op":"contains","value":"x"}"#,
                                      actionsJSON: #"[{"type":"add_tag","tagId":"t"}]"#))
    }
}
