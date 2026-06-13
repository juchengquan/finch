import Foundation

/// Pure rules engine — evaluation + application over a Tx and a list of rules.
/// Port of lib/rules/engine.ts. No DB, no I/O.
public enum RulesEngine {

    // MARK: Tx field readers

    private static func nativeAmount(_ t: Tx) -> Double { abs(t.nativeAmount ?? t.amount) }
    private static func kindOf(_ t: Tx) -> String {
        if let k = t.kind { return k }
        if t.transferGroupId != nil { return "transfer" }
        return t.amount > 0 ? "income" : "expense"
    }
    private static let utcCal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private static func dayOfWeek(_ date: String) -> Int {
        let p = date.prefix(10).split(separator: "-").map { Int($0) ?? 0 }
        var dc = DateComponents(); dc.year = p.count > 0 ? p[0] : 0; dc.month = p.count > 1 ? p[1] : 1; dc.day = p.count > 2 ? p[2] : 1
        guard let d = utcCal.date(from: dc) else { return 0 }
        return utcCal.component(.weekday, from: d) - 1   // .weekday 1=Sun → 0=Sun
    }
    private static func dayOfMonth(_ date: String) -> Int { Int(date.dropFirst(8).prefix(2)) ?? 0 }

    // MARK: leaf evaluation

    private static func evaluateLeaf(_ t: Tx, _ leaf: RuleLeaf) -> Bool {
        let v = leaf.value
        switch leaf.field {
        case "merchant", "note":
            let raw = leaf.field == "merchant" ? t.merchant : (t.note ?? "")
            let ci = leaf.caseInsensitive != false
            let a = ci ? raw.lowercased() : raw
            guard let valStr = v?.asString else { return false }
            let b = ci ? valStr.lowercased() : valStr
            if leaf.field == "note" { return leaf.op == "contains" && a.contains(b) }
            switch leaf.op { case "is": return a == b; case "contains": return a.contains(b); case "startsWith": return a.hasPrefix(b); default: return false }
        case "amount":
            let x = nativeAmount(t)
            if leaf.op == "between" {
                guard case .array(let arr)? = v, arr.count == 2, let lo = arr[0].asDouble, let hi = arr[1].asDouble else { return false }
                return x >= lo && x <= hi
            }
            guard let n = v?.asDouble else { return false }
            switch leaf.op { case "gt": return x > n; case "gte": return x >= n; case "lt": return x < n; case "lte": return x <= n; case "eq": return abs(x - n) < 0.005; default: return false }
        case "account_id":
            if leaf.op == "is" { return t.account == v?.asString }
            if leaf.op == "in" { return v?.asStringArray.contains(t.account) ?? false }
            return false
        case "category_id":
            if leaf.op == "is_null" { return t.category == nil }
            let c = t.category ?? ""
            if leaf.op == "is" { return c == v?.asString }
            if leaf.op == "in" { return !c.isEmpty && (v?.asStringArray.contains(c) ?? false) }
            return false
        case "counterparty_id":
            if leaf.op == "is_null" { return t.counterpartyId == nil }
            return leaf.op == "is" && t.counterpartyId == v?.asString
        case "currency":
            return leaf.op == "is" && (t.currency ?? "") == v?.asString
        case "date_dow":
            guard leaf.op == "in", case .array(let arr)? = v else { return false }
            return arr.compactMap { $0.asDouble.map(Int.init) }.contains(dayOfWeek(t.date))
        case "date_dom":
            let d = dayOfMonth(t.date)
            guard let n = v?.asDouble.map(Int.init) else { return false }
            switch leaf.op { case "eq": return d == n; case "gte": return d >= n; case "lte": return d <= n; default: return false }
        case "kind":
            let k = kindOf(t)
            if leaf.op == "is" { return k == v?.asString }
            if leaf.op == "in" { return v?.asStringArray.contains(k) ?? false }
            return false
        case "tag_id":
            let tags = t.tags ?? []
            if leaf.op == "has" { return v?.asString.map { tags.contains($0) } ?? false }
            let ids = v?.asStringArray ?? []
            if leaf.op == "has_any" { return ids.contains { tags.contains($0) } }
            if leaf.op == "has_all" { return ids.allSatisfy { tags.contains($0) } }
            return false
        default:
            return false
        }
    }

    /// Evaluate a (possibly nested) condition against a transaction.
    public static func evaluateCondition(_ t: Tx, _ cond: RuleCondition) -> Bool {
        switch cond {
        case .all(let cs): return cs.allSatisfy { evaluateCondition(t, $0) }
        case .any(let cs): return cs.contains { evaluateCondition(t, $0) }
        case .not(let c): return !evaluateCondition(t, c)
        case .leaf(let l): return evaluateLeaf(t, l)
        }
    }

    // MARK: action application

    private static func applyAction(_ patch: inout RulePatch, _ a: RuleAction) {
        let o = a.raw
        switch a.type {
        case "set_category": patch.categoryId = .set(o["categoryId"]?.asString)
        case "set_counterparty": patch.counterpartyId = .set(o["counterpartyId"]?.asString)
        case "set_merchant": patch.merchant = o["merchant"]?.asString
        case "set_note": patch.note = o["note"]?.asString
        case "set_kind": patch.kind = o["kind"]?.asString
        case "add_tag":
            if let t = o["tagId"]?.asString { var arr = patch.tagIdsAdd ?? []; if !arr.contains(t) { arr.append(t) }; patch.tagIdsAdd = arr }
        case "remove_tag":
            if let t = o["tagId"]?.asString { var arr = patch.tagIdsRemove ?? []; if !arr.contains(t) { arr.append(t) }; patch.tagIdsRemove = arr }
        case "mark_reviewed": patch.reviewed = true
        case "split":
            if patch.splits == nil, case .array(let arr)? = o["splits"] {
                patch.splits = arr.compactMap { s -> SplitTemplate? in
                    guard case .object(let so) = s, let f = so["fraction"]?.asDouble else { return nil }
                    return SplitTemplate(fraction: f, categoryId: so["categoryId"]?.asString, description: so["description"]?.asString)
                }
            }
        default: break
        }
    }

    /// Run the (priority-ordered) active rules against `t`; return the merged
    /// patch. `appliedRuleIds` lists every rule that matched, in fire order.
    public static func applyRules(_ t: Tx, _ rules: [Rule], skipIfRuleApplied: Bool = false, onEditOnly: Bool = false) -> RulePatch {
        var patch = RulePatch()
        if skipIfRuleApplied && (t.appliedRuleIds?.count ?? 0) > 0 { return patch }
        for rule in rules {
            if !rule.isActive { continue }
            if onEditOnly && !rule.runOnEdit { continue }
            if !evaluateCondition(t, rule.condition) { continue }
            patch.appliedRuleIds.append(rule.id)
            for action in rule.actions { applyAction(&patch, action) }
        }
        return patch
    }
}
