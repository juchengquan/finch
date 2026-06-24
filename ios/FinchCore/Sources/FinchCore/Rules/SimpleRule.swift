import Foundation

/// The simple, single-condition/single-action rule form the iOS builder can edit.
public struct SimpleRuleForm: Equatable, Sendable {
    public enum Field: String, Sendable { case merchant, amount }
    public enum Action: Equatable, Sendable { case setCategory(String); case markReviewed }
    public let field: Field
    public let op: String
    public let value: String
    public let action: Action
}

/// Parse a stored rule's condition/actions JSON into the builder form — or nil
/// when the rule is too complex for the simple builder.
public enum SimpleRule {
    /// Decode a JSON string into a JSONValue (the stored condition/actions blob).
    public static func jsonValue(_ s: String) -> JSONValue? {
        guard let data = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    public static func parse(conditionJSON: String, actionsJSON: String) -> SimpleRuleForm? {
        // Condition must be a single leaf on merchant/amount with a builder op.
        guard let cv = jsonValue(conditionJSON), let cond = RuleCondition.parse(cv),
              case .leaf(let leaf) = cond, let field = SimpleRuleForm.Field(rawValue: leaf.field) else { return nil }
        let builderOps: Set<String> = field == .merchant ? ["contains", "equals"] : ["gt", "lt", "equals"]
        guard builderOps.contains(leaf.op) else { return nil }
        let valueStr: String
        switch leaf.value {
        case .string(let s)?: valueStr = s
        case .double(let d)?: valueStr = String(format: "%g", d)
        case .int(let i)?: valueStr = String(i)
        default: return nil
        }
        // Actions must be exactly one supported action.
        guard let av = jsonValue(actionsJSON), case .array(let arr) = av, arr.count == 1,
              let a = RuleAction.parse(arr[0]) else { return nil }
        let action: SimpleRuleForm.Action
        switch a.type {
        case "set_category":
            guard case .string(let cid)? = a.raw["categoryId"] else { return nil }
            action = .setCategory(cid)
        case "mark_reviewed", "set_reviewed":   // accept legacy iOS value
            action = .markReviewed
        default: return nil
        }
        return SimpleRuleForm(field: field, op: leaf.op, value: valueStr, action: action)
    }
}
