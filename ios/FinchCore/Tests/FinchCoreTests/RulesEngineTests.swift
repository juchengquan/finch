import XCTest
@testable import FinchCore

final class RulesEngineTests: XCTestCase {
    private func tx(_ json: String) -> Tx { try! JSONDecoder().decode(Tx.self, from: Data(json.utf8)) }
    private func rule(_ id: String, _ priority: Int, _ condition: JSONValue, _ actions: [JSONValue], isActive: Bool = true) -> Rule {
        Rule(id: id, ledgerId: "l1", priority: priority, condition: RuleCondition.parse(condition)!,
             actions: actions.compactMap(RuleAction.parse), isActive: isActive, runOnEdit: false)
    }

    func test_leafAndCombinators() throws {
        let t = tx(#"{"id":"t1","merchant":"Blue Coffee Co","amount":-25,"account":"a1","date":"2026-05-01"}"#)
        // merchant contains (case-insensitive default)
        let cMerchant: JSONValue = .object(["field": .string("merchant"), "op": .string("contains"), "value": .string("coffee")])
        XCTAssertTrue(RulesEngine.evaluateCondition(t, RuleCondition.parse(cMerchant)!))
        // amount between [10,50] AND kind is expense
        let cAll: JSONValue = .object(["all": .array([
            .object(["field": .string("amount"), "op": .string("between"), "value": .array([.int(10), .int(50)])]),
            .object(["field": .string("kind"), "op": .string("is"), "value": .string("expense")]),
        ])])
        XCTAssertTrue(RulesEngine.evaluateCondition(t, RuleCondition.parse(cAll)!))
        // not(merchant is "gas")
        let cNot: JSONValue = .object(["not": .object(["field": .string("merchant"), "op": .string("is"), "value": .string("gas")])])
        XCTAssertTrue(RulesEngine.evaluateCondition(t, RuleCondition.parse(cNot)!))
        // amount > 100 → false
        let cGt: JSONValue = .object(["field": .string("amount"), "op": .string("gt"), "value": .int(100)])
        XCTAssertFalse(RulesEngine.evaluateCondition(t, RuleCondition.parse(cGt)!))
    }

    func test_applyAndPriorityOrder() throws {
        let t = tx(#"{"id":"t1","merchant":"Blue Coffee Co","amount":-25,"account":"a1","date":"2026-05-01"}"#)
        let cMerchant: JSONValue = .object(["field": .string("merchant"), "op": .string("contains"), "value": .string("coffee")])
        // r1 (runs first) sets food + reviewed + a tag; r2 (runs later) overrides category to dining.
        let r1 = rule("r1", 10, cMerchant, [
            .object(["type": .string("set_category"), "categoryId": .string("food")]),
            .object(["type": .string("mark_reviewed")]),
            .object(["type": .string("add_tag"), "tagId": .string("tg1")]),
        ])
        let r2 = rule("r2", 20, cMerchant, [.object(["type": .string("set_category"), "categoryId": .string("dining")])])
        let patch = RulesEngine.applyRules(t, [r1, r2])   // priority order
        XCTAssertEqual(patch.appliedRuleIds, ["r1", "r2"])
        if case .set(let cat) = patch.categoryId { XCTAssertEqual(cat, "dining") } else { XCTFail("category not set") }   // last writer wins
        XCTAssertTrue(patch.reviewed)
        XCTAssertEqual(patch.tagIdsAdd, ["tg1"])
    }

    func test_noMatchAndInactive() throws {
        let t = tx(#"{"id":"t1","merchant":"Gas Station","amount":-40,"account":"a1","date":"2026-05-01"}"#)
        let cMerchant: JSONValue = .object(["field": .string("merchant"), "op": .string("contains"), "value": .string("coffee")])
        XCTAssertTrue(RulesEngine.applyRules(t, [rule("r1", 10, cMerchant, [])]).appliedRuleIds.isEmpty)   // no match
        // an inactive rule never fires even if its condition matches
        let always: JSONValue = .object(["field": .string("account_id"), "op": .string("is"), "value": .string("a1")])
        XCTAssertTrue(RulesEngine.applyRules(t, [rule("r1", 10, always, [], isActive: false)]).appliedRuleIds.isEmpty)
    }
}
