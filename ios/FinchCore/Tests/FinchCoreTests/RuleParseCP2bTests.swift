import XCTest
@testable import FinchCore

final class RuleParseCP2bTests: XCTestCase {
    private let act = #"[{"type":"mark_reviewed"}]"#

    func test_category_in() {
        let f = RuleParse.parse(conditionJSON: #"{"field":"category_id","op":"in","value":["c1","c2"]}"#, actionsJSON: act)
        XCTAssertEqual(f?.conditions.first, LeafForm(field: .categoryId, op: "in", value: "", values: ["c1", "c2"]))
    }

    func test_account_in_kind_in() {
        XCTAssertEqual(RuleParse.parse(conditionJSON: #"{"field":"account_id","op":"in","value":["a1"]}"#, actionsJSON: act)?.conditions.first,
                       LeafForm(field: .accountId, op: "in", value: "", values: ["a1"]))
        XCTAssertEqual(RuleParse.parse(conditionJSON: #"{"field":"kind","op":"in","value":["expense","income"]}"#, actionsJSON: act)?.conditions.first,
                       LeafForm(field: .kind, op: "in", value: "", values: ["expense", "income"]))
    }

    func test_tag_has_any_has_all() {
        XCTAssertEqual(RuleParse.parse(conditionJSON: #"{"field":"tag_id","op":"has_any","value":["t1","t2"]}"#, actionsJSON: act)?.conditions.first,
                       LeafForm(field: .tagId, op: "has_any", value: "", values: ["t1", "t2"]))
        XCTAssertEqual(RuleParse.parse(conditionJSON: #"{"field":"tag_id","op":"has_all","value":["t1"]}"#, actionsJSON: act)?.conditions.first,
                       LeafForm(field: .tagId, op: "has_all", value: "", values: ["t1"]))
    }

    func test_date_dow_int_array_round_trip() {
        let f = RuleParse.parse(conditionJSON: #"{"field":"date_dow","op":"in","value":[0,6]}"#, actionsJSON: act)
        XCTAssertEqual(f?.conditions.first, LeafForm(field: .dateDow, op: "in", value: "", values: ["0", "6"]))
        let (cond, _) = RuleParse.build(RuleForm(combinator: .all,
            conditions: [LeafForm(field: .dateDow, op: "in", value: "", values: ["0", "6"])],
            actions: [ActionForm(kind: .markReviewed)]))
        XCTAssertEqual(cond, .object(["field": .string("date_dow"), "op": .string("in"), "value": .array([.int(0), .int(6)])]))
    }

    func test_category_in_builds_string_array() {
        let (cond, _) = RuleParse.build(RuleForm(combinator: .all,
            conditions: [LeafForm(field: .categoryId, op: "in", value: "", values: ["c1", "c2"])],
            actions: [ActionForm(kind: .markReviewed)]))
        XCTAssertEqual(cond, .object(["field": .string("category_id"), "op": .string("in"), "value": .array([.string("c1"), .string("c2")])]))
    }

    func test_mixed_cp1_cp2a_cp2b_round_trip() {
        let form = RuleForm(combinator: .all,
            conditions: [LeafForm(field: .merchant, op: "contains", value: "uber"),
                         LeafForm(field: .categoryId, op: "in", value: "", values: ["c1", "c2"]),
                         LeafForm(field: .dateDow, op: "in", value: "", values: ["0", "6"])],
            actions: [ActionForm(kind: .addTag("t1"))])
        let (cond, acts) = RuleParse.build(form)
        XCTAssertEqual(RuleParse.parse(conditionJSON: cond.jsonString, actionsJSON: acts.jsonString), form)
    }

    func test_empty_array_nested_not_still_nil() {
        XCTAssertNil(RuleParse.parse(conditionJSON: #"{"field":"category_id","op":"in","value":[]}"#, actionsJSON: act))
        XCTAssertNil(RuleParse.parse(conditionJSON: #"{"all":[{"all":[{"field":"merchant","op":"is","value":"x"}]}]}"#, actionsJSON: act))
        XCTAssertNil(RuleParse.parse(conditionJSON: #"{"not":{"field":"merchant","op":"is","value":"x"}}"#, actionsJSON: act))
    }
}
