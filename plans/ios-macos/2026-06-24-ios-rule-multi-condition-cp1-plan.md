# Multi-condition rule builder CP1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build/edit rules with `all`/`any` over multiple conditions and multiple actions (CP1 simple-valued fields: merchant/note/amount/kind; actions set category/note/merchant/kind/mark-reviewed), fixing the `equals`→`is`/`eq` op bug.

**Architecture:** No rules-engine change. (1) A pure `RuleForm`/`RuleParse` in FinchCore that parses a stored rule into an editable form (or nil for non-CP1 rules) and builds condition/actions JSON back — superseding `SimpleRule`. (2) `RuleSheet` rewritten as a dynamic array builder (combinator toggle + condition/action rows with per-field value editors); `open()`/`RuleDetailView` migrate to `RuleParse`; `SimpleRule` deleted.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), FinchCore, XcodeGen, XCTest.

## Global Constraints

- **No rules-engine change.** Engine already evaluates all/any/not + every field/action.
- **Flat all/any only** — no nested groups, no `not`. CP1 fields: merchant (is/contains/startsWith), note (contains), amount (gt/gte/lt/lte/eq/between), kind (is). CP1 actions: set_category, set_note, set_merchant, set_kind, mark_reviewed. Anything else → `RuleParse.parse` returns nil → read-only.
- **Bug fix:** never emit `equals`; emit engine ops (`is`/`eq`). `RuleParse.parse` maps legacy `equals`→`is`/`eq` and `set_reviewed`→mark_reviewed (self-heal on save).
- **Amounts:** the view validates/normalizes amount strings (via `DecimalInput.parse` → plain-decimal string) before calling `RuleParse.build`; `build` uses `Double(string)` (no locale). Avoid `%g` (use integral→Int else Double description).
- **1 condition → bare leaf JSON** (output identical to today's single rule); >1 → `{all|any:[…]}`.
- **Must build iOS AND macOS (FinchMac).** Sim `iPhone 17 Pro Max`. New files → `xcodegen generate`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit; **no `Co-Authored-By` trailer**.

---

## File Structure

**Create (FinchCore):** `ios/FinchCore/Sources/FinchCore/Rules/RuleForm.swift` (`LeafForm`, `ActionForm`, `RuleForm`, `RuleParse`).
**Delete (FinchCore):** `ios/FinchCore/Sources/FinchCore/Rules/SimpleRule.swift` (Task 2).
**Create (tests):** `ios/FinchCore/Tests/FinchCoreTests/RuleParseTests.swift`.
**Modify (tests):** `ios/FinchCore/Tests/FinchCoreTests/RulesEditingTests.swift` (Task 2 — remove the `SimpleRule.parse` tests; keep projection + ruleMatchCounts).
**Modify (FinchApp, full rewrite):** `ios/FinchApp/Sources/FinchApp/PowerTools/RulesManagerView.swift`.

---

### Task 1: `RuleForm` + `RuleParse` (pure, FinchCore)

**Files:**
- Create: `ios/FinchCore/Sources/FinchCore/Rules/RuleForm.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests/RuleParseTests.swift`

**Interfaces:**
- Produces: `LeafForm` (Field {merchant,note,amount,kind}; field/op/value/value2), `ActionForm` (Kind: setCategory(String)/setNote(String)/setMerchant(String)/setKind(String)/markReviewed), `RuleForm` (Combinator {all,any}; combinator/conditions/actions), and `enum RuleParse { jsonValue; parse(conditionJSON:actionsJSON:)->RuleForm?; build(_:)->(condition:JSONValue, actions:JSONValue) }`. `SimpleRule` is left intact this task (deleted in Task 2).

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchCore/Tests/FinchCoreTests/RuleParseTests.swift`:

```swift
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter RuleParseTests`
Expected: FAIL to compile — `RuleForm`/`LeafForm`/`ActionForm`/`RuleParse` undefined.

- [ ] **Step 3: Implement `RuleForm.swift`**

Create `ios/FinchCore/Sources/FinchCore/Rules/RuleForm.swift`:

```swift
import Foundation

/// A single condition row, editable in the builder. CP1 fields only.
public struct LeafForm: Equatable, Sendable {
    public enum Field: String, Sendable, CaseIterable { case merchant, note, amount, kind }
    public var field: Field
    public var op: String
    public var value: String     // text / number (plain decimal) / kind raw
    public var value2: String    // amount `between` upper bound; "" otherwise
    public init(field: Field, op: String, value: String, value2: String = "") {
        self.field = field; self.op = op; self.value = value; self.value2 = value2
    }
}

/// A single action row. CP1 actions only.
public struct ActionForm: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case setCategory(String), setNote(String), setMerchant(String), setKind(String), markReviewed
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
    static func numStr(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }

    static func opsAllowed(_ field: LeafForm.Field) -> Set<String> {
        switch field {
        case .merchant: return ["is", "contains", "startsWith"]
        case .note:     return ["contains"]
        case .amount:   return ["gt", "gte", "lt", "lte", "eq", "between"]
        case .kind:     return ["is"]
        }
    }

    static func leafForm(_ leaf: RuleLeaf) -> LeafForm? {
        guard let field = LeafForm.Field(rawValue: leaf.field) else { return nil }
        var op = leaf.op
        if op == "equals" { op = field == .amount ? "eq" : "is" }   // self-heal legacy
        guard opsAllowed(field).contains(op) else { return nil }
        if field == .amount && op == "between" {
            guard case .array(let arr)? = leaf.value, arr.count == 2,
                  let lo = arr[0].asDouble, let hi = arr[1].asDouble else { return nil }
            return LeafForm(field: field, op: op, value: numStr(lo), value2: numStr(hi))
        }
        if field == .amount {
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
        let value: JSONValue
        if f.field == .amount {
            value = f.op == "between"
                ? .array([.double(Double(f.value) ?? 0), .double(Double(f.value2) ?? 0)])
                : .double(Double(f.value) ?? 0)
        } else {
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
        }
    }

    /// Build condition + actions JSON. 1 condition → bare leaf; >1 → {all|any:[…]}.
    public static func build(_ form: RuleForm) -> (condition: JSONValue, actions: JSONValue) {
        let leaves = form.conditions.map(leafJSON)
        let condition: JSONValue = leaves.count == 1 ? leaves[0] : .object([form.combinator.rawValue: .array(leaves)])
        return (condition, .array(form.actions.map(actionJSON)))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter RuleParseTests`
Expected: PASS (13 tests).

- [ ] **Step 5: Full FinchCore suite (no regressions; SimpleRule still present)**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchCore/Sources/FinchCore/Rules/RuleForm.swift ios/FinchCore/Tests/FinchCoreTests/RuleParseTests.swift
git commit -m "feat(ios): RuleForm + RuleParse (multi-condition parse/build, equals self-heal)"
```

---

### Task 2: Array-based `RuleSheet` + migrate routing/detail + delete `SimpleRule`

**Files:**
- Modify (full rewrite): `ios/FinchApp/Sources/FinchApp/PowerTools/RulesManagerView.swift`
- Delete: `ios/FinchCore/Sources/FinchCore/Rules/SimpleRule.swift`
- Modify: `ios/FinchCore/Tests/FinchCoreTests/RulesEditingTests.swift` (remove the `SimpleRule.parse` tests; keep `test_rules_projection_*` + `test_ruleMatchCounts_*`)

**Interfaces:**
- Consumes: `RuleForm`/`RuleParse` (Task 1); existing `RuleSummary`, `Selectors.ruleMatchCounts`, `RuleCondition`/`RuleAction.parse`, `DecimalInput`, `store.pickableCategories`, `store.apply`.

- [ ] **Step 1: Remove obsolete SimpleRule tests**

In `ios/FinchCore/Tests/FinchCoreTests/RulesEditingTests.swift`, delete the `// MARK: SimpleRule.parse` section and every `test_simple_*`/`test_complex_rules_return_nil` method (they're superseded by `RuleParseTests`). Keep `test_rules_projection_carries_condition_actions_runOnEdit`, the `tx(...)` helper, and both `test_ruleMatchCounts_*`.

- [ ] **Step 2: Delete `SimpleRule.swift`**

```bash
rm /tmp/finch-mcrplan/ios/FinchCore/Sources/FinchCore/Rules/SimpleRule.swift
```
(Use the actual repo path in the worktree you're working in.)

- [ ] **Step 3: Rewrite `RulesManagerView.swift`**

Replace the entire file with:

```swift
import SwiftUI
import FinchCore

/// Phase 4 — rules manager: list (match counts + active toggle), create, edit
/// (multi-condition all/any + multi-action, CP1 fields), delete, backfill.
/// Rules using CP2 fields / nested groups / not / split open read-only.
struct RulesManagerView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var creating = false
    @State private var editing: RuleSummary?
    @State private var viewing: RuleSummary?
    @State private var errorMessage: String?

    var body: some View {
        let counts = Selectors.ruleMatchCounts(store.txns, store.activeLedgerId)
        return List {
            if store.rules.isEmpty {
                Text("No rules yet. Rules auto-apply to new income/expense entries.").foregroundStyle(.secondary)
            }
            ForEach(store.rules) { rule in
                HStack {
                    Button { open(rule) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name).foregroundStyle(.primary)
                            Text("priority \(rule.priority)").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if let n = counts[rule.id], n > 0 {
                        Text("\(n)×").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .accessibilityLabel("\(n) transactions")
                    }
                    Toggle("", isOn: Binding(get: { rule.isActive }, set: { setActive(rule, $0) }))
                        .labelsHidden().accessibilityLabel("Active")
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { delete(rule) } label: { Label("Delete", systemImage: "trash") }
                }
                .swipeActions(edge: .leading) {
                    Button { backfill(rule) } label: { Label("Backfill", systemImage: "arrow.triangle.2.circlepath") }.tint(.blue)
                }
            }
        }
        .navigationTitle("Rules")
        .errorAlert($errorMessage)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add rule")
            }
        }
        .sheet(isPresented: $creating) { RuleSheet(rule: nil) }
        .sheet(item: $editing) { RuleSheet(rule: $0) }
        .sheet(item: $viewing) { RuleDetailView(rule: $0) }
    }

    private func open(_ r: RuleSummary) {
        if RuleParse.parse(conditionJSON: r.conditionJSON, actionsJSON: r.actionsJSON) != nil { editing = r }
        else { viewing = r }
    }
    private func setActive(_ r: RuleSummary, _ on: Bool) {
        do { try store.apply(.updateRule, Args(["id": .string(r.id), "patch": .object(["isActive": .bool(on)])])) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func delete(_ r: RuleSummary) {
        do { try store.apply(.deleteRule, Args(["id": .string(r.id)])) } catch { errorMessage = i18nMessage(error) }
    }
    private func backfill(_ r: RuleSummary) {
        do { try store.apply(.backfillRule, Args(["id": .string(r.id)])) } catch { errorMessage = i18nMessage(error) }
    }
}

// CP1 kind values a user can target.
private let kindValues = ["expense", "income", "transfer", "refund", "adjustment"]

private func opsFor(_ f: LeafForm.Field) -> [String] {
    switch f {
    case .merchant: return ["is", "contains", "startsWith"]
    case .note:     return ["contains"]
    case .amount:   return ["gt", "gte", "lt", "lte", "eq", "between"]
    case .kind:     return ["is"]
    }
}
private func opLabel(_ o: String) -> String {
    switch o {
    case "is": return "is"; case "contains": return "contains"; case "startsWith": return "starts with"
    case "gt": return "greater than"; case "gte": return "≥"; case "lt": return "less than"; case "lte": return "≤"
    case "eq": return "equals"; case "between": return "between"; default: return o
    }
}

/// Create (rule == nil) or edit a multi-condition / multi-action rule.
struct RuleSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let rule: RuleSummary?

    // Editable rows (flattened mutable mirror of RuleForm).
    struct CondRow: Identifiable { let id = UUID(); var field: LeafForm.Field = .merchant; var op = "contains"; var value = ""; var value2 = "" }
    enum ActType: String, CaseIterable, Identifiable { case setCategory, setNote, setMerchant, setKind, markReviewed
        var id: String { rawValue }
        var label: String { switch self { case .setCategory: "Set category"; case .setNote: "Set note"; case .setMerchant: "Set merchant"; case .setKind: "Set kind"; case .markReviewed: "Mark reviewed" } } }
    struct ActRow: Identifiable { let id = UUID(); var type: ActType = .setCategory; var categoryId = ""; var text = ""; var kind = "expense" }

    @State private var name: String
    @State private var combinator: RuleForm.Combinator
    @State private var conditions: [CondRow]
    @State private var actions: [ActRow]
    @State private var priority: Int
    @State private var isActive: Bool
    @State private var runOnEdit: Bool
    @State private var errorMessage: String?

    init(rule: RuleSummary?) {
        self.rule = rule
        let form = rule.flatMap { RuleParse.parse(conditionJSON: $0.conditionJSON, actionsJSON: $0.actionsJSON) }
        _name = State(initialValue: rule?.name ?? "")
        _combinator = State(initialValue: form?.combinator ?? .all)
        _conditions = State(initialValue: form.map { $0.conditions.map { lf in
            CondRow(field: lf.field, op: lf.op, value: lf.value, value2: lf.value2)
        } } ?? [CondRow()])
        _actions = State(initialValue: form.map { $0.actions.map(Self.actRow(from:)) } ?? [ActRow()])
        _priority = State(initialValue: rule?.priority ?? 100)
        _isActive = State(initialValue: rule?.isActive ?? true)
        _runOnEdit = State(initialValue: rule?.runOnEdit ?? false)
    }

    private static func actRow(from a: ActionForm) -> ActRow {
        switch a.kind {
        case .setCategory(let id): return ActRow(type: .setCategory, categoryId: id)
        case .setNote(let s):      return ActRow(type: .setNote, text: s)
        case .setMerchant(let s):  return ActRow(type: .setMerchant, text: s)
        case .setKind(let k):      return ActRow(type: .setKind, kind: k)
        case .markReviewed:        return ActRow(type: .markReviewed)
        }
    }

    private var isEdit: Bool { rule != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rule") {
                    TextField("Name", text: $name)
                    Stepper("Priority \(priority)", value: $priority, in: 0...1000)
                }
                Section("When") {
                    if conditions.count > 1 {
                        Picker("Match", selection: $combinator) {
                            Text("all of").tag(RuleForm.Combinator.all); Text("any of").tag(RuleForm.Combinator.any)
                        }.pickerStyle(.segmented)
                    }
                    ForEach($conditions) { $c in condRow($c) }
                        .onDelete { conditions.remove(atOffsets: $0) }
                    Button { conditions.append(CondRow()) } label: { Label("Add condition", systemImage: "plus") }
                }
                Section("Then") {
                    ForEach($actions) { $a in actRow($a) }
                        .onDelete { actions.remove(atOffsets: $0) }
                    Button { actions.append(ActRow()) } label: { Label("Add action", systemImage: "plus") }
                }
                Section {
                    Toggle("Run on edit", isOn: $runOnEdit)
                    if isEdit { Toggle("Active", isOn: $isActive) }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle(isEdit ? "Edit Rule" : "New Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }.accessibilityLabel("Save").bold()
                }
            }
        }
    }

    @ViewBuilder private func condRow(_ c: Binding<CondRow>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Field", selection: c.field) {
                ForEach(LeafForm.Field.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .onChange(of: c.wrappedValue.field) { _, f in if !opsFor(f).contains(c.wrappedValue.op) { c.wrappedValue.op = opsFor(f)[0] } }
            Picker("Is", selection: c.op) { ForEach(opsFor(c.wrappedValue.field), id: \.self) { Text(opLabel($0)).tag($0) } }
            switch c.wrappedValue.field {
            case .merchant, .note:
                TextField("Text", text: c.value)
            case .amount:
                TextField("Amount", text: c.value).keyboardType(.decimalPad)
                if c.wrappedValue.op == "between" { TextField("and", text: c.value2).keyboardType(.decimalPad) }
            case .kind:
                Picker("Kind", selection: c.value) { ForEach(kindValues, id: \.self) { Text($0.capitalized).tag($0) } }
            }
        }
    }

    @ViewBuilder private func actRow(_ a: Binding<ActRow>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Action", selection: a.type) { ForEach(ActType.allCases) { Text($0.label).tag($0) } }
            switch a.wrappedValue.type {
            case .setCategory:
                Picker("Category", selection: a.categoryId) { ForEach(store.pickableCategories) { Text($0.name).tag($0.id) } }
            case .setNote:     TextField("Note", text: a.text)
            case .setMerchant: TextField("Merchant", text: a.text)
            case .setKind:     Picker("Kind", selection: a.kind) { ForEach(kindValues, id: \.self) { Text($0.capitalized).tag($0) } }
            case .markReviewed: EmptyView()
            }
        }
    }

    private func save() {
        errorMessage = nil
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter a name."; return }
        guard !conditions.isEmpty else { errorMessage = "Add at least one condition."; return }
        guard !actions.isEmpty else { errorMessage = "Add at least one action."; return }

        // Build condition forms, validating/normalizing amounts to plain decimal.
        var condForms: [LeafForm] = []
        for c in conditions {
            var value = c.value, value2 = c.value2
            switch c.field {
            case .merchant, .note:
                guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter a value for every condition."; return }
            case .kind:
                if value.isEmpty { value = kindValues[0] }
            case .amount:
                guard let d = DecimalInput.parse(value) else { errorMessage = "Enter a numeric amount."; return }
                value = RuleParse.numStr(d)
                if c.op == "between" {
                    guard let hi = DecimalInput.parse(value2) else { errorMessage = "Enter both amounts for 'between'."; return }
                    value2 = RuleParse.numStr(hi)
                }
            }
            condForms.append(LeafForm(field: c.field, op: c.op, value: value, value2: value2))
        }

        // Build action forms.
        var actForms: [ActionForm] = []
        for a in actions {
            switch a.type {
            case .setCategory:
                let cid = a.categoryId.isEmpty ? (store.pickableCategories.first?.id ?? "") : a.categoryId
                guard !cid.isEmpty else { errorMessage = "Pick a category."; return }
                actForms.append(ActionForm(kind: .setCategory(cid)))
            case .setNote:
                guard !a.text.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter the note text."; return }
                actForms.append(ActionForm(kind: .setNote(a.text)))
            case .setMerchant:
                guard !a.text.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter the merchant."; return }
                actForms.append(ActionForm(kind: .setMerchant(a.text)))
            case .setKind:
                actForms.append(ActionForm(kind: .setKind(a.kind.isEmpty ? kindValues[0] : a.kind)))
            case .markReviewed:
                actForms.append(ActionForm(kind: .markReviewed))
            }
        }

        let (condition, actionsJSON) = RuleParse.build(RuleForm(combinator: combinator, conditions: condForms, actions: actForms))
        do {
            if let rule {
                try store.apply(.updateRule, Args(["id": .string(rule.id), "patch": .object([
                    "name": .string(name), "priority": .int(priority),
                    "condition": condition, "actions": actionsJSON,
                    "isActive": .bool(isActive), "runOnEdit": .bool(runOnEdit),
                ])]))
            } else {
                try store.apply(.createRule, Args([
                    "ledgerId": .string(store.activeLedgerId), "name": .string(name),
                    "condition": condition, "actions": actionsJSON,
                    "priority": .int(priority), "runOnEdit": .bool(runOnEdit),
                ]))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}

/// Read-only detail for a rule the CP1 builder can't represent.
struct RuleDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let rule: RuleSummary

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Name", value: rule.name)
                    LabeledContent("Priority", value: "\(rule.priority)")
                    LabeledContent("Active", value: rule.isActive ? "Yes" : "No")
                    LabeledContent("Run on edit", value: rule.runOnEdit ? "Yes" : "No")
                }
                Section("Matches") { Text(conditionSummary) }
                Section("Actions") { Text(actionsSummary) }
                Section {
                    Text("This rule is too complex to edit on iOS. Open it on the web for full control.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var conditionSummary: String {
        guard let v = RuleParse.jsonValue(rule.conditionJSON), let cond = RuleCondition.parse(v) else { return "—" }
        switch cond {
        case .all(let cs): return "all of \(cs.count) conditions"
        case .any(let cs): return "any of \(cs.count) conditions"
        case .not: return "not (1 condition)"
        case .leaf(let l): return "\(l.field) \(l.op)"
        }
    }
    private var actionsSummary: String {
        guard let v = RuleParse.jsonValue(rule.actionsJSON), case .array(let arr) = v else { return "—" }
        let types = arr.compactMap { RuleAction.parse($0)?.type }
        return types.isEmpty ? "—" : "\(types.count) action(s): " + types.joined(separator: ", ")
    }
}
```

- [ ] **Step 4: Build iOS + run the full FinchApp suite**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`. If a SwiftUI binding/closure detail fails to compile, fix minimally and note it (the dynamic `ForEach($array)` + per-row `switch` is the likely spot).

- [ ] **Step 5: Full FinchCore suite (SimpleRule deleted; RuleParse covers it)**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test 2>&1 | grep -iE "error:|Test Suite 'All tests'"`
Expected: all pass (RulesEditingTests no longer references SimpleRule).

- [ ] **Step 6: Build macOS (FinchMac)**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Manual verification on the simulator**

Launch (Settings › Power Tools › Rules). Then:
- **Create a 2-condition rule:** "all of: merchant contains Uber, amount > 20" + 2 actions (set category, mark reviewed). Save → appears; backfill → matches only big Uber rides.
- **any of:** add a second condition and flip the all/any toggle.
- **between:** an amount `between` condition shows two number fields.
- **Edit** the rule (tap) → fields prefill; change + save persists.
- **Legacy/single rule** still edits; a single condition saves as a bare leaf; an `equals` rule's op shows as is/eq after save.
- **Complex rule** (CP2 field / nested) opens read-only.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch -initialTab settings
```

- [ ] **Step 8: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add -A ios/FinchApp/Sources/FinchApp/PowerTools/RulesManagerView.swift \
        ios/FinchCore/Sources/FinchCore/Rules/SimpleRule.swift \
        ios/FinchCore/Tests/FinchCoreTests/RulesEditingTests.swift
git commit -m "feat(ios): multi-condition rule builder (all/any, multi-action, CP1 fields)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-24-ios-rule-multi-condition-cp1-design.md`):
- `RuleForm`/`RuleParse` parse (all/any/single, CP1 fields/ops/actions, legacy `equals`/`set_reviewed`, nil for non-CP1) + build (bare leaf vs wrapper, between array) → Task 1. ✓
- Array `RuleSheet` (combinator toggle, +/- condition & action rows, per-field value editors), routing via `RuleParse.parse`, read-only fallback, create+edit, priority/runOnEdit/active → Task 2. ✓
- `equals`→is/eq fix (in `leafForm` + build never emits equals) → Task 1. ✓
- Amount validation/normalization via `DecimalInput` → Task 2 `save()`. ✓
- `SimpleRule` deleted, tests migrated → Task 2. ✓
- No engine change; build iOS+macOS; full tests green → Task 2 steps 4-6. ✓

**Placeholder scan:** No TBD/TODO; full code in every step; sim step concrete. ✓

**Type consistency:** `LeafForm.Field` raw values (merchant/note/amount/kind) used in `opsFor`, `condRow`, and parse; `RuleForm.Combinator` (.all/.any) in the Picker + build; `RuleParse.parse/build` signatures match call sites (`open`, `RuleSheet.init`, `save`); `RuleParse.numStr` reused in `save()`'s amount normalization; `ActType`↔`ActionForm.Kind` mapping is total. `kindValues` shared by kind-condition + set-kind editors. ✓

---

## Out of scope (CP2)

Entity-picker/multi-value fields (category-condition, account, counterparty, currency, tag, date_dow, date_dom, kind `in`); actions add_tag/remove_tag/set_counterparty; nested groups, `not`, `split`; web changes.
