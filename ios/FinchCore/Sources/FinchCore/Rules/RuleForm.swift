import Foundation

/// A single condition row, editable in the builder. CP1 + CP2 fields (nested
/// groups / `not` / `split` are not representable here — those stay read-only).
public struct LeafForm: Equatable, Sendable {
    public enum Field: String, Sendable, CaseIterable {
        case merchant, note, amount, kind
        case categoryId = "category_id", accountId = "account_id", counterpartyId = "counterparty_id"
        case currency, tagId = "tag_id", dateDom = "date_dom", dateDow = "date_dow"
    }
    public var field: Field
    public var op: String
    public var value: String     // text / number (plain decimal) / kind raw
    public var value2: String    // amount `between` upper bound; "" otherwise
    public var values: [String]  // array ops (in/has_any/has_all); weekday indices for date_dow
    public init(field: Field, op: String, value: String, value2: String = "", values: [String] = []) {
        self.field = field; self.op = op; self.value = value; self.value2 = value2; self.values = values
    }
}

/// A single action row. CP1 + CP2a actions.
public struct ActionForm: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case setCategory(String), setNote(String), setMerchant(String), setKind(String), markReviewed
        case addTag(String), removeTag(String), setCounterparty(String)
    }
    public var kind: Kind
    public init(kind: Kind) { self.kind = kind }
}

/// The editable form of a (CP1-representable) rule: a flat all/any of leaves + actions.
public struct RuleForm: Equatable, Sendable {
    public enum Combinator: String, Sendable { case all, any }
    public var combinator: Combinator
    public var conditions: [LeafForm]
    public var actions: [ActionForm]
    public init(combinator: Combinator, conditions: [LeafForm], actions: [ActionForm]) {
        self.combinator = combinator; self.conditions = conditions; self.actions = actions
    }
}

/// Parse a stored rule's condition/actions JSON into an editable `RuleForm`, or
/// nil when it uses anything outside CP1 (nested groups, `not`, a CP2 field/op/
/// action). Builds the JSON back. Pure; reuses `RuleCondition`/`RuleAction.parse`.
public enum RuleParse {
    public static func jsonValue(_ s: String) -> JSONValue? {
        guard let data = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Numeric → display string without %g scientific/lossy output.
    public static func numStr(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }

    static func opsAllowed(_ field: LeafForm.Field) -> Set<String> {
        switch field {
        case .merchant:       return ["is", "contains", "startsWith"]
        case .note:           return ["contains"]
        case .amount:         return ["gt", "gte", "lt", "lte", "eq", "between"]
        case .kind:           return ["is", "in"]
        case .categoryId:     return ["is", "is_null", "in"]
        case .accountId:      return ["is", "in"]
        case .counterpartyId: return ["is", "is_null"]
        case .currency:       return ["is"]
        case .tagId:          return ["has", "has_any", "has_all"]
        case .dateDom:        return ["eq", "gte", "lte"]
        case .dateDow:        return ["in"]
        }
    }

    static func leafForm(_ leaf: RuleLeaf) -> LeafForm? {
        guard let field = LeafForm.Field(rawValue: leaf.field) else { return nil }
        var op = leaf.op
        if op == "equals" { op = field == .amount ? "eq" : "is" }   // self-heal legacy
        guard opsAllowed(field).contains(op) else { return nil }
        if op == "is_null" { return LeafForm(field: field, op: op, value: "") }
        if op == "in" || op == "has_any" || op == "has_all" {
            guard case .array(let arr)? = leaf.value, !arr.isEmpty else { return nil }
            let values: [String] = field == .dateDow
                ? arr.compactMap { $0.asDouble.map { numStr($0) } }
                : arr.compactMap { $0.asString }
            guard values.count == arr.count else { return nil }   // every element parsed
            return LeafForm(field: field, op: op, value: "", values: values)
        }
        if field == .amount && op == "between" {
            guard case .array(let arr)? = leaf.value, arr.count == 2,
                  let lo = arr[0].asDouble, let hi = arr[1].asDouble else { return nil }
            return LeafForm(field: field, op: op, value: numStr(lo), value2: numStr(hi))
        }
        if field == .amount || field == .dateDom {
            guard let d = leaf.value?.asDouble else { return nil }
            return LeafForm(field: field, op: op, value: numStr(d))
        }
        guard let s = leaf.value?.asString else { return nil }
        return LeafForm(field: field, op: op, value: s)
    }

    static func actionForm(_ a: RuleAction) -> ActionForm? {
        switch a.type {
        case "set_category": guard case .string(let id)? = a.raw["categoryId"] else { return nil }; return ActionForm(kind: .setCategory(id))
        case "set_note":     guard case .string(let s)? = a.raw["note"] else { return nil }; return ActionForm(kind: .setNote(s))
        case "set_merchant": guard case .string(let s)? = a.raw["merchant"] else { return nil }; return ActionForm(kind: .setMerchant(s))
        case "set_kind":     guard case .string(let s)? = a.raw["kind"] else { return nil }; return ActionForm(kind: .setKind(s))
        case "mark_reviewed", "set_reviewed": return ActionForm(kind: .markReviewed)
        case "add_tag":      guard case .string(let id)? = a.raw["tagId"] else { return nil }; return ActionForm(kind: .addTag(id))
        case "remove_tag":   guard case .string(let id)? = a.raw["tagId"] else { return nil }; return ActionForm(kind: .removeTag(id))
        case "set_counterparty": guard case .string(let id)? = a.raw["counterpartyId"] else { return nil }; return ActionForm(kind: .setCounterparty(id))
        default: return nil
        }
    }

    public static func parse(conditionJSON: String, actionsJSON: String) -> RuleForm? {
        guard let cv = jsonValue(conditionJSON), let cond = RuleCondition.parse(cv) else { return nil }
        let combinator: RuleForm.Combinator
        let rawLeaves: [RuleLeaf]
        switch cond {
        case .leaf(let l): combinator = .all; rawLeaves = [l]
        case .all(let cs), .any(let cs):
            if case .all = cond { combinator = .all } else { combinator = .any }
            var ls: [RuleLeaf] = []
            for c in cs { guard case .leaf(let l) = c else { return nil } ; ls.append(l) }   // no nesting
            rawLeaves = ls
        case .not: return nil
        }
        guard !rawLeaves.isEmpty else { return nil }
        var conditions: [LeafForm] = []
        for l in rawLeaves { guard let lf = leafForm(l) else { return nil }; conditions.append(lf) }

        guard let av = jsonValue(actionsJSON), case .array(let arr) = av, !arr.isEmpty else { return nil }
        var actions: [ActionForm] = []
        for a in arr { guard let ra = RuleAction.parse(a), let af = actionForm(ra) else { return nil }; actions.append(af) }

        return RuleForm(combinator: combinator, conditions: conditions, actions: actions)
    }

    static func leafJSON(_ f: LeafForm) -> JSONValue {
        if f.op == "is_null" {
            return .object(["field": .string(f.field.rawValue), "op": .string("is_null")])
        }
        if f.op == "in" || f.op == "has_any" || f.op == "has_all" {
            let arr: [JSONValue] = f.field == .dateDow
                ? f.values.map { .int(Int($0) ?? 0) }
                : f.values.map { .string($0) }
            return .object(["field": .string(f.field.rawValue), "op": .string(f.op), "value": .array(arr)])
        }
        let value: JSONValue
        switch f.field {
        case .amount:
            value = f.op == "between"
                ? .array([.double(Double(f.value) ?? 0), .double(Double(f.value2) ?? 0)])
                : .double(Double(f.value) ?? 0)
        case .dateDom:
            value = .int(Int(f.value) ?? 0)
        default:
            value = .string(f.value)
        }
        return .object(["field": .string(f.field.rawValue), "op": .string(f.op), "value": value])
    }

    static func actionJSON(_ a: ActionForm) -> JSONValue {
        switch a.kind {
        case .setCategory(let id): return .object(["type": .string("set_category"), "categoryId": .string(id)])
        case .setNote(let s):      return .object(["type": .string("set_note"), "note": .string(s)])
        case .setMerchant(let s):  return .object(["type": .string("set_merchant"), "merchant": .string(s)])
        case .setKind(let s):      return .object(["type": .string("set_kind"), "kind": .string(s)])
        case .markReviewed:        return .object(["type": .string("mark_reviewed")])
        case .addTag(let id):          return .object(["type": .string("add_tag"), "tagId": .string(id)])
        case .removeTag(let id):       return .object(["type": .string("remove_tag"), "tagId": .string(id)])
        case .setCounterparty(let id): return .object(["type": .string("set_counterparty"), "counterpartyId": .string(id)])
        }
    }

    /// Build condition + actions JSON. 1 condition → bare leaf; >1 → {all|any:[…]}.
    public static func build(_ form: RuleForm) -> (condition: JSONValue, actions: JSONValue) {
        let leaves = form.conditions.map(leafJSON)
        let condition: JSONValue = leaves.count == 1 ? leaves[0] : .object([form.combinator.rawValue: .array(leaves)])
        return (condition, .array(form.actions.map(actionJSON)))
    }
}
