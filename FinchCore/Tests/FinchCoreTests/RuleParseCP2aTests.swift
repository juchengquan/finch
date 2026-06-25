import XCTest
@testable import FinchCore

final class RuleParseCP2aTests: XCTestCase {
    private let act = #"[{"type":"mark_reviewed"}]"#

    func test_category_is() {
        let f = RuleParse.parse(conditionJSON: #"{"field":"category_id","op":"is","value":"c1"}"#, actionsJSON: act)
        XCTAssertEqual(f?.conditions.first, LeafForm(field: .categoryId, op: "is", value: "c1"))
    }

    func test_category_is_null_build_has_no_value_key() {
        let f = RuleParse.parse(conditionJSON: #"{"field":"category_id","op":"is_null"}"#, actionsJSON: act)
        XCTAssertEqual(f?.conditions.first, LeafForm(field: .categoryId, op: "is_null", value: ""))
        let (cond, _) = RuleParse.build(RuleForm(combinator: .all,
            conditions: [LeafForm(field: .categoryId, op: "is_null", value: "")],
            actions: [ActionForm(kind: .markReviewed)]))
        XCTAssertEqual(cond, .object(["field": .string("category_id"), "op": .string("is_null")]))
    }

    func test_account_currency_counterparty_tag_is() {
        XCTAssertEqual(RuleParse.parse(conditionJSON: #"{"field":"account_id","op":"is","value":"a1"}"#, actionsJSON: act)?.conditions.first,
                       LeafForm(field: .accountId, op: "is", value: "a1"))
        XCTAssertEqual(RuleParse.parse(conditionJSON: #"{"field":"currency","op":"is","value":"EUR"}"#, actionsJSON: act)?.conditions.first,
                       LeafForm(field: .currency, op: "is", value: "EUR"))
        XCTAssertEqual(RuleParse.parse(conditionJSON: #"{"field":"counterparty_id","op":"is_null"}"#, actionsJSON: act)?.conditions.first,
                       LeafForm(field: .counterpartyId, op: "is_null", value: ""))
        XCTAssertEqual(RuleParse.parse(conditionJSON: #"{"field":"tag_id","op":"has","value":"t1"}"#, actionsJSON: act)?.conditions.first,
                       LeafForm(field: .tagId, op: "has", value: "t1"))
    }

    func test_date_dom_int_round_trip() {
        let f = RuleParse.parse(conditionJSON: #"{"field":"date_dom","op":"lte","value":5}"#, actionsJSON: act)
        XCTAssertEqual(f?.conditions.first, LeafForm(field: .dateDom, op: "lte", value: "5"))
        let (cond, _) = RuleParse.build(RuleForm(combinator: .all,
            conditions: [LeafForm(field: .dateDom, op: "lte", value: "5")],
            actions: [ActionForm(kind: .markReviewed)]))
        XCTAssertEqual(cond, .object(["field": .string("date_dom"), "op": .string("lte"), "value": .int(5)]))
    }

    func test_new_actions_parse_and_build() {
        let acts = #"[{"type":"add_tag","tagId":"t1"},{"type":"remove_tag","tagId":"t2"},{"type":"set_counterparty","counterpartyId":"cp1"}]"#
        let f = RuleParse.parse(conditionJSON: #"{"field":"merchant","op":"is","value":"x"}"#, actionsJSON: acts)
        XCTAssertEqual(f?.actions, [ActionForm(kind: .addTag("t1")), ActionForm(kind: .removeTag("t2")), ActionForm(kind: .setCounterparty("cp1"))])
        let (_, built) = RuleParse.build(RuleForm(combinator: .all,
            conditions: [LeafForm(field: .merchant, op: "is", value: "x")],
            actions: [ActionForm(kind: .addTag("t1")), ActionForm(kind: .setCounterparty("cp1"))]))
        XCTAssertEqual(built, .array([
            .object(["type": .string("add_tag"), "tagId": .string("t1")]),
            .object(["type": .string("set_counterparty"), "counterpartyId": .string("cp1")]),
        ]))
    }

    func test_mixed_cp1_cp2a_round_trip() {
        let form = RuleForm(combinator: .all,
            conditions: [LeafForm(field: .categoryId, op: "is", value: "c1"), LeafForm(field: .dateDom, op: "gte", value: "10")],
            actions: [ActionForm(kind: .addTag("t1")), ActionForm(kind: .markReviewed)])
        let (cond, acts2) = RuleParse.build(form)
        XCTAssertEqual(RuleParse.parse(conditionJSON: cond.jsonString, actionsJSON: acts2.jsonString), form)
    }

    func test_cp2b_ops_still_nil() {
        XCTAssertNil(RuleParse.parse(conditionJSON: #"{"field":"category_id","op":"in","value":["c1","c2"]}"#, actionsJSON: act))
        XCTAssertNil(RuleParse.parse(conditionJSON: #"{"field":"tag_id","op":"has_any","value":["t1"]}"#, actionsJSON: act))
        XCTAssertNil(RuleParse.parse(conditionJSON: #"{"field":"date_dow","op":"in","value":[0,6]}"#, actionsJSON: act))
        XCTAssertNil(RuleParse.parse(conditionJSON: #"{"field":"kind","op":"in","value":["expense"]}"#, actionsJSON: act))
    }
}
