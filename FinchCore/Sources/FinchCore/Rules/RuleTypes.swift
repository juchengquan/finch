import Foundation

// The conditional rules engine's data model — port of lib/rules/types.ts. The
// condition tree + action list are parsed from the JSON blobs stored in the
// `rules` table (via JSONValue). Leaf/action values stay as JSONValue and are
// read positionally during evaluation, mirroring the web's per-field handling.

/// A leaf comparator over one transaction field.
public struct RuleLeaf: Sendable {
    public let field: String
    public let op: String
    public let value: JSONValue?
    public let caseInsensitive: Bool?
}

/// A condition: a leaf or a boolean combinator over sub-conditions.
public indirect enum RuleCondition: Sendable {
    case all([RuleCondition])
    case any([RuleCondition])
    case not(RuleCondition)
    case leaf(RuleLeaf)

    /// Parse from a JSONValue (the stored `condition` blob).
    public static func parse(_ v: JSONValue) -> RuleCondition? {
        guard case .object(let o) = v else { return nil }
        if case .array(let arr)? = o["all"] { return .all(arr.compactMap(parse)) }
        if case .array(let arr)? = o["any"] { return .any(arr.compactMap(parse)) }
        if let n = o["not"] { return parse(n).map { .not($0) } }
        guard case .string(let field)? = o["field"], case .string(let op)? = o["op"] else { return nil }
        let ci: Bool? = { if case .bool(let b)? = o["caseInsensitive"] { return b }; return nil }()
        return .leaf(RuleLeaf(field: field, op: op, value: o["value"], caseInsensitive: ci))
    }
}

/// One slice of a split action.
public struct SplitTemplate: Sendable, Equatable {
    public let fraction: Double
    public let categoryId: String?
    public let description: String?
}

/// A single action — `type` + the raw object for positional field access.
public struct RuleAction: Sendable {
    public let type: String
    public let raw: [String: JSONValue]
    public static func parse(_ v: JSONValue) -> RuleAction? {
        guard case .object(let o) = v, case .string(let type)? = o["type"] else { return nil }
        return RuleAction(type: type, raw: o)
    }
}

/// A rule projected from the `rules` table (condition/actions parsed from JSON).
public struct Rule: Sendable {
    public let id: String
    public let ledgerId: String
    public let priority: Int
    public let condition: RuleCondition
    public let actions: [RuleAction]
    public let isActive: Bool
    public let runOnEdit: Bool
}

/// The merged patch the engine produces. `categoryId`/`counterpartyId` use Field
/// so "set to null" is distinct from "not set" (matching the web's `!== undefined`).
public struct RulePatch: Sendable {
    public var appliedRuleIds: [String] = []
    public var categoryId: Entries.Field<String?> = .keep
    public var counterpartyId: Entries.Field<String?> = .keep
    public var merchant: String?
    public var note: String?
    public var kind: String?
    public var tagIdsAdd: [String]?
    public var tagIdsRemove: [String]?
    public var reviewed = false
    public var splits: [SplitTemplate]?
}
