import XCTest
@testable import FinchCore

final class RuleParseTests: XCTestCase {
    // parse

    func test_parse_single_leaf_is_one_condition_all() {
        let f = RuleParse.parse(conditionJSON: #"{"field":"merchant","op":"contains","value":"coffee"}"#,
                                actionsJSON: #"[{"type":"set_category","categoryId":"c1"}]"#)
        XCTAssertEqual(f?.combinator, .all)
        XCTAssertEqual(f?.conditions, [LeafForm(field: .merchant, op: "contains", value: "coffee")])
        XCTAssertEqual(f?.actions, [ActionForm(kind: .setCategory("c1"))])
    }

    func test_parse_all_of_two_leaves() {
        let cond = #"{"all":[{"field":"merchant","op":"contains","value":"uber"},{"field":"amount","op":"gt","value":20}]}"#
        let f = RuleParse.parse(conditionJSON: cond, actionsJSON: #"[{"type":"mark_reviewed"}]"#)
        XCTAssertEqual(f?.combinator, .all)
        XCTAssertEqual(f?.conditions, [LeafForm(field: .merchant, op: "contains", value: "uber"),
                                       LeafForm(field: .amount, op: "gt", value: "20")])
    }

    func test_parse_any_combinator() {
        let cond = #"{"any":[{"field":"merchant","op":"is","value":"a"},{"field":"merchant","op":"is","value":"b"}]}"#
        XCTAssertEqual(RuleParse.parse(conditionJSON: cond, actionsJSON: #"[{"type":"mark_reviewed"}]"#)?.combinator, .any)
    }

    func test_parse_amount_between() {
        let cond = #"{"field":"amount","op":"between","value":[10,50]}"#
        let f = RuleParse.parse(conditionJSON: cond, actionsJSON: #"[{"type":"mark_reviewed"}]"#)
        XCTAssertEqual(f?.conditions.first, LeafForm(field: .amount, op: "between", value: "10", value2: "50"))
    }

    func test_parse_kind_note() {
        let f = RuleParse.parse(conditionJSON: #"{"all":[{"field":"kind","op":"is","value":"expense"},{"field":"note","op":"contains","value":"x"}]}"#,
                                actionsJSON: #"[{"type":"mark_reviewed"}]"#)
        XCTAssertEqual(f?.conditions, [LeafForm(field: .kind, op: "is", value: "expense"),
                                       LeafForm(field: .note, op: "contains", value: "x")])
    }

    func test_parse_legacy_equals_self_heals() {
        // merchant equals → is ; amount equals → eq
        let f1 = RuleParse.parse(conditionJSON: #"{"field":"merchant","op":"equals","value":"x"}"#, actionsJSON: #"[{"type":"mark_reviewed"}]"#)
        XCTAssertEqual(f1?.conditions.first?.op, "is")
        let f2 = RuleParse.parse(conditionJSON: #"{"field":"amount","op":"equals","value":5}"#, actionsJSON: #"[{"type":"mark_reviewed"}]"#)
        XCTAssertEqual(f2?.conditions.first?.op, "eq")
    }

    func test_parse_multi_action() {
        let acts = #"[{"type":"set_category","categoryId":"c"},{"type":"mark_reviewed"},{"type":"set_note","note":"n"}]"#
        let f = RuleParse.parse(conditionJSON: #"{"field":"merchant","op":"is","value":"x"}"#, actionsJSON: acts)
        XCTAssertEqual(f?.actions, [ActionForm(kind: .setCategory("c")), ActionForm(kind: .markReviewed), ActionForm(kind: .setNote("n"))])
    }

    func test_parse_nil_for_non_cp1() {
        let act = #"[{"type":"mark_reviewed"}]"#
        XCTAssertNil(RuleParse.parse(conditionJSON: #"{"not":{"field":"merchant","op":"is","value":"x"}}"#, actionsJSON: act)) // not
        XCTAssertNil(RuleParse.parse(conditionJSON: #"{"all":[{"all":[{"field":"merchant","op":"is","value":"x"}]}]}"#, actionsJSON: act)) // nested
        XCTAssertNil(RuleParse.parse(conditionJSON: #"{"field":"tag_id","op":"has","value":"t"}"#, actionsJSON: act)) // CP2 field
        XCTAssertNil(RuleParse.parse(conditionJSON: #"{"field":"kind","op":"in","value":["expense"]}"#, actionsJSON: act)) // CP2 op
        XCTAssertNil(RuleParse.parse(conditionJSON: #"{"field":"merchant","op":"is","value":"x"}"#, actionsJSON: #"[{"type":"add_tag","tagId":"t"}]"#)) // CP2 action
        XCTAssertNil(RuleParse.parse(conditionJSON: #"{"field":"merchant","op":"is","value":"x"}"#, actionsJSON: "[]")) // no actions
    }

    // build

    func test_build_single_condition_is_bare_leaf() {
        let (cond, acts) = RuleParse.build(RuleForm(combinator: .all,
            conditions: [LeafForm(field: .merchant, op: "is", value: "x")],
            actions: [ActionForm(kind: .markReviewed)]))
        XCTAssertEqual(cond, .object(["field": .string("merchant"), "op": .string("is"), "value": .string("x")]))
        XCTAssertEqual(acts, .array([.object(["type": .string("mark_reviewed")])]))
    }

    func test_build_multi_wraps_in_combinator() {
        let (cond, _) = RuleParse.build(RuleForm(combinator: .any,
            conditions: [LeafForm(field: .merchant, op: "is", value: "a"), LeafForm(field: .merchant, op: "is", value: "b")],
            actions: [ActionForm(kind: .markReviewed)]))
        guard case .object(let o) = cond, case .array(let arr)? = o["any"] else { return XCTFail("expected any wrapper") }
        XCTAssertEqual(arr.count, 2)
    }

    func test_build_amount_between_array_and_eq() {
        let (cond, _) = RuleParse.build(RuleForm(combinator: .all,
            conditions: [LeafForm(field: .amount, op: "between", value: "10", value2: "50")],
            actions: [ActionForm(kind: .markReviewed)]))
        XCTAssertEqual(cond, .object(["field": .string("amount"), "op": .string("between"), "value": .array([.double(10), .double(50)])]))
    }

    func test_build_actions() {
        let (_, acts) = RuleParse.build(RuleForm(combinator: .all,
            conditions: [LeafForm(field: .merchant, op: "is", value: "x")],
            actions: [ActionForm(kind: .setCategory("c")), ActionForm(kind: .setNote("n")), ActionForm(kind: .setMerchant("m")), ActionForm(kind: .setKind("income"))]))
        XCTAssertEqual(acts, .array([
            .object(["type": .string("set_category"), "categoryId": .string("c")]),
            .object(["type": .string("set_note"), "note": .string("n")]),
            .object(["type": .string("set_merchant"), "merchant": .string("m")]),
            .object(["type": .string("set_kind"), "kind": .string("income")]),
        ]))
    }

    func test_round_trip() {
        let form = RuleForm(combinator: .any,
            conditions: [LeafForm(field: .merchant, op: "contains", value: "uber"), LeafForm(field: .amount, op: "between", value: "10", value2: "1500000")],
            actions: [ActionForm(kind: .setCategory("c")), ActionForm(kind: .markReviewed)])
        let (cond, acts) = RuleParse.build(form)
        XCTAssertEqual(RuleParse.parse(conditionJSON: cond.jsonString, actionsJSON: acts.jsonString), form)
    }
}
