# Rules editing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tap a rule to edit it in place (simple single-condition/action rules), with priority/run-on-edit/active; complex rules open read-only; each row shows a `N×` match count. Plus fix the `set_reviewed`→`mark_reviewed` action bug.

**Architecture:** No rules-engine change. (1) Surface condition/actions/runOnEdit on `RuleSummary`; (2) a pure `Selectors.ruleMatchCounts` + a pure `SimpleRule` parser (reusing `RuleCondition.parse`/`RuleAction.parse`); (3) generalize the create sheet into a create/edit `RuleSheet`, restructure the list (tap-to-route + `N×` + active toggle), and add a read-only `RuleDetailView`.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), FinchCore, XcodeGen, XCTest. FinchCore via `swift test`; FinchApp via `xcodebuild … -only-testing:FinchAppTests/…`.

## Global Constraints

- **No rules-engine change.** `updateRule` already patches `name/priority/condition/actions/isActive/runOnEdit`; the engine already evaluates `all/any/not` + all action types.
- **Edit only simple rules** (single `.leaf` on `merchant`/`amount` with a builder op, single `set_category`/`mark_reviewed` action). Complex rules → read-only (never flatten). The gate is `SimpleRule.parse(...) != nil`.
- **Match count** = txns in the active ledger whose `appliedRuleIds` contains the rule id (pending included). Computed once per render.
- **Bug fix:** the create/edit save emits action type `"mark_reviewed"` (was `"set_reviewed"`); `SimpleRule.parse` accepts **both** so legacy iOS rules stay editable.
- **Preserve existing op vocabulary** (merchant `contains`/`equals`; amount `gt`/`lt`/`equals`) verbatim — do NOT change condition op semantics (only the reviewed action string is fixed).
- **Must build iOS AND macOS (FinchMac).** Sim: `iPhone 17 Pro Max`. New files → `xcodegen generate`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit messages; **no `Co-Authored-By` trailer**.

---

## File Structure

**Modify (FinchCore):**
- `ios/FinchCore/Sources/FinchCore/Project/RuleSummary.swift` — add `conditionJSON`, `actionsJSON`, `runOnEdit`.
- `ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift` — `rules()` SELECTs + maps the new columns.
- `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift` — add `ruleMatchCounts`.

**Create (FinchCore):**
- `ios/FinchCore/Sources/FinchCore/Rules/SimpleRule.swift` — `SimpleRuleForm` + `SimpleRule.parse` + `SimpleRule.jsonValue`.

**Create (tests):**
- `ios/FinchCore/Tests/FinchCoreTests/RulesEditingTests.swift` — projection + `ruleMatchCounts` + `SimpleRule.parse`.

**Modify (FinchApp, full rewrite):**
- `ios/FinchApp/Sources/FinchApp/PowerTools/RulesManagerView.swift` — list (tap-route + `N×` + active toggle), `RuleSheet` (create/edit), `RuleDetailView`.

**Common run commands:**
```bash
cd /Users/blackmount8/_repository/finch/ios
swift test --filter <ClassName>                       # FinchCore
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:FinchAppTests/<ClassName>
```

---

### Task 1: Surface condition/actions/runOnEdit on `RuleSummary`

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Project/RuleSummary.swift`
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift` (the `rules(...)` func, ~lines 199-211)
- Test: `ios/FinchCore/Tests/FinchCoreTests/RulesEditingTests.swift` (create; add the projection test now, more in Task 2)

**Interfaces:**
- Produces: `RuleSummary` gains `conditionJSON: String`, `actionsJSON: String`, `runOnEdit: Bool` (init params defaulted so any other call sites compile). `Projection.rules` populates them.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchCore/Tests/FinchCoreTests/RulesEditingTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter RulesEditingTests`
Expected: FAIL to compile — `RuleSummary` has no `conditionJSON`/`actionsJSON`/`runOnEdit`.

- [ ] **Step 3: Extend `RuleSummary`**

Replace `RuleSummary.swift` lines 7-15 with:

```swift
public struct RuleSummary: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let priority: Int
    public let isActive: Bool
    public let conditionJSON: String
    public let actionsJSON: String
    public let runOnEdit: Bool
    public init(id: String, name: String, priority: Int, isActive: Bool,
                conditionJSON: String = "", actionsJSON: String = "[]", runOnEdit: Bool = false) {
        self.id = id; self.name = name; self.priority = priority; self.isActive = isActive
        self.conditionJSON = conditionJSON; self.actionsJSON = actionsJSON; self.runOnEdit = runOnEdit
    }
}
```

- [ ] **Step 4: Populate them in the projection**

In `Projections+State.swift`, replace the `rules(...)` body (the SELECT + map) with:

```swift
public static func rules(dbQueue: DatabaseQueue, ledgerId: String) throws -> [RuleSummary] {
    try dbQueue.read { db in
        try Row.fetchAll(db, sql: """
            SELECT id, name, priority, is_active, condition, actions, run_on_edit FROM rules
             WHERE ledger_id = ? ORDER BY priority, created_at
            """, arguments: [ledgerId]).map { r in
            RuleSummary(id: r["id"], name: (r["name"] as String?) ?? "Rule",
                        priority: (r["priority"] as Int?) ?? 100,
                        isActive: ((r["is_active"] as Int?) ?? 0) != 0,
                        conditionJSON: (r["condition"] as String?) ?? "",
                        actionsJSON: (r["actions"] as String?) ?? "[]",
                        runOnEdit: ((r["run_on_edit"] as Int?) ?? 0) != 0)
        }
    }
}
```

- [ ] **Step 5: Run tests**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter RulesEditingTests`
Expected: PASS (1 test).

- [ ] **Step 6: Full FinchCore suite (no regressions)**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test`
Expected: all pass (defaulted init params keep other `RuleSummary(...)` call sites valid).

- [ ] **Step 7: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchCore/Sources/FinchCore/Project/RuleSummary.swift \
        ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift \
        ios/FinchCore/Tests/FinchCoreTests/RulesEditingTests.swift
git commit -m "feat(ios): surface condition/actions/runOnEdit on RuleSummary"
```

---

### Task 2: `ruleMatchCounts` selector + `SimpleRule` parser (pure)

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift` (append `ruleMatchCounts` before the enum's final `}`)
- Create: `ios/FinchCore/Sources/FinchCore/Rules/SimpleRule.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests/RulesEditingTests.swift` (append cases)

**Interfaces:**
- Produces:
  - `static func ruleMatchCounts(_ txns: [Tx], _ ledgerId: String) -> [String: Int]` (keyed by rule id).
  - `struct SimpleRuleForm: Equatable, Sendable` with `enum Field {merchant,amount}`, `enum Action {setCategory(String), markReviewed}`, `field/op/value/action`.
  - `enum SimpleRule { static func jsonValue(_ s: String) -> JSONValue?; static func parse(conditionJSON: String, actionsJSON: String) -> SimpleRuleForm? }`.

- [ ] **Step 1: Write the failing tests**

Append to `RulesEditingTests` (inside the class):

```swift
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
        XCTAssertEqual(f??.field, .merchant)
        XCTAssertEqual(f??.op, "contains")
        XCTAssertEqual(f??.value, "coffee")
        XCTAssertEqual(f??.action, .setCategory("cFood"))
    }

    func test_simple_amount_gt_mark_reviewed() {
        let cond = #"{"field":"amount","op":"gt","value":50}"#
        let acts = #"[{"type":"mark_reviewed"}]"#
        let f = SimpleRule.parse(conditionJSON: cond, actionsJSON: acts)
        XCTAssertEqual(f?.field, .amount); XCTAssertEqual(f?.op, "gt"); XCTAssertEqual(f?.value, "50")
        XCTAssertEqual(f?.action, .markReviewed)
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter RulesEditingTests`
Expected: FAIL to compile — `ruleMatchCounts`/`SimpleRule` undefined.

- [ ] **Step 3: Add `ruleMatchCounts`**

In `Selectors.swift`, just before the final closing `}` of the `Selectors` enum (after `budgetMatchedTransactions`), add (4-space indent):

```swift
    /// Per-rule applied count: txns in `ledgerId` whose appliedRuleIds contains the
    /// rule id. Keyed by rule id; absent for rules that never fired.
    public static func ruleMatchCounts(_ txns: [Tx], _ ledgerId: String) -> [String: Int] {
        var out: [String: Int] = [:]
        for t in txns where ledgerOf(t) == ledgerId {
            for id in (t.appliedRuleIds ?? []) { out[id, default: 0] += 1 }
        }
        return out
    }
```

- [ ] **Step 4: Add `SimpleRule`**

Create `ios/FinchCore/Sources/FinchCore/Rules/SimpleRule.swift`:

```swift
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
```

- [ ] **Step 5: Run tests**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter RulesEditingTests`
Expected: PASS (projection + 2 match-count + 4 SimpleRule cases).

- [ ] **Step 6: Full FinchCore suite**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift \
        ios/FinchCore/Sources/FinchCore/Rules/SimpleRule.swift \
        ios/FinchCore/Tests/FinchCoreTests/RulesEditingTests.swift
git commit -m "feat(ios): ruleMatchCounts selector + SimpleRule parser"
```

---

### Task 3: Edit/create `RuleSheet`, list wiring, read-only detail

**Files:**
- Modify (full rewrite): `ios/FinchApp/Sources/FinchApp/PowerTools/RulesManagerView.swift`

**Interfaces:**
- Consumes: `RuleSummary.conditionJSON/actionsJSON/runOnEdit` (Task 1); `Selectors.ruleMatchCounts`, `SimpleRule.parse`, `SimpleRule.jsonValue`, `RuleCondition.parse`, `RuleAction.parse` (Task 2 + existing); `updateRule`/`createRule`/`deleteRule`/`backfillRule`.

- [ ] **Step 1: Replace the file**

Replace the entire contents of `ios/FinchApp/Sources/FinchApp/PowerTools/RulesManagerView.swift` with:

```swift
import SwiftUI
import FinchCore

/// Phase 4 — rules manager: list (with match counts + active toggle), create,
/// edit (simple single-condition/action rules), delete, backfill. Complex rules
/// open read-only. create/update/delete/backfillRule through the chokepoint.
struct RulesManagerView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var creating = false
    @State private var editing: RuleSummary?    // simple rule → editor
    @State private var viewing: RuleSummary?    // complex rule → read-only detail
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
        if SimpleRule.parse(conditionJSON: r.conditionJSON, actionsJSON: r.actionsJSON) != nil { editing = r }
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

/// Create (rule == nil) or edit a simple single-condition/single-action rule.
struct RuleSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let rule: RuleSummary?

    enum Field: String, CaseIterable, Identifiable { case merchant, amount; var id: String { rawValue } }
    enum ActionKind: String, CaseIterable, Identifiable { case setCategory, markReviewed; var id: String { rawValue }
        var label: String { self == .setCategory ? "Set category" : "Mark reviewed" } }

    @State private var name: String
    @State private var field: Field
    @State private var op: String
    @State private var value: String
    @State private var action: ActionKind
    @State private var categoryId: String
    @State private var priority: Int
    @State private var isActive: Bool
    @State private var runOnEdit: Bool
    @State private var errorMessage: String?

    init(rule: RuleSummary?) {
        self.rule = rule
        let form = rule.flatMap { SimpleRule.parse(conditionJSON: $0.conditionJSON, actionsJSON: $0.actionsJSON) }
        _name = State(initialValue: rule?.name ?? "")
        _field = State(initialValue: form.flatMap { Field(rawValue: $0.field.rawValue) } ?? .merchant)
        _op = State(initialValue: form?.op ?? "contains")
        _value = State(initialValue: form?.value ?? "")
        switch form?.action {
        case .setCategory(let cid): _action = State(initialValue: .setCategory); _categoryId = State(initialValue: cid)
        case .markReviewed: _action = State(initialValue: .markReviewed); _categoryId = State(initialValue: "")
        case nil: _action = State(initialValue: .setCategory); _categoryId = State(initialValue: "")
        }
        _priority = State(initialValue: rule?.priority ?? 100)
        _isActive = State(initialValue: rule?.isActive ?? true)
        _runOnEdit = State(initialValue: rule?.runOnEdit ?? false)
    }

    private var ops: [String] { field == .merchant ? ["contains", "equals"] : ["gt", "lt", "equals"] }
    private var isEdit: Bool { rule != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rule") {
                    TextField("Name", text: $name)
                    Stepper("Priority \(priority)", value: $priority, in: 0...1000)
                }
                Section("When") {
                    Picker("Field", selection: $field) { ForEach(Field.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                        .onChange(of: field) { _, _ in if !ops.contains(op) { op = ops[0] } }
                    Picker("Is", selection: $op) { ForEach(ops, id: \.self) { Text(opLabel($0)).tag($0) } }
                    TextField(field == .merchant ? "Text" : "Amount", text: $value)
                        .keyboardType(field == .merchant ? .default : .decimalPad)
                }
                Section("Then") {
                    Picker("Action", selection: $action) { ForEach(ActionKind.allCases) { Text($0.label).tag($0) } }
                    if action == .setCategory {
                        Picker("Category", selection: $categoryId) {
                            ForEach(store.pickableCategories) { Text($0.name).tag($0.id) }
                        }
                    }
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
            .onAppear { if categoryId.isEmpty { categoryId = store.pickableCategories.first?.id ?? "" } }
        }
    }

    private func opLabel(_ o: String) -> String {
        switch o { case "contains": return "contains"; case "equals": return "equals"
        case "gt": return "greater than"; case "lt": return "less than"; default: return o }
    }

    private func save() {
        errorMessage = nil
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter a name."; return }
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter a value."; return }
        let condValue: JSONValue
        if field == .amount {
            guard let parsed = DecimalInput.parse(value) else { errorMessage = "Enter a numeric amount."; return }
            condValue = .double(parsed)
        } else {
            condValue = .string(value)
        }
        let condition: JSONValue = .object(["field": .string(field.rawValue), "op": .string(op), "value": condValue])
        let actions: JSONValue
        switch action {
        case .setCategory:
            guard !categoryId.isEmpty else { errorMessage = "Pick a category."; return }
            actions = .array([.object(["type": .string("set_category"), "categoryId": .string(categoryId)])])
        case .markReviewed:
            actions = .array([.object(["type": .string("mark_reviewed")])])   // fix: engine expects mark_reviewed
        }
        do {
            if let rule {
                try store.apply(.updateRule, Args(["id": .string(rule.id), "patch": .object([
                    "name": .string(name), "priority": .int(priority),
                    "condition": condition, "actions": actions,
                    "isActive": .bool(isActive), "runOnEdit": .bool(runOnEdit),
                ])]))
            } else {
                try store.apply(.createRule, Args([
                    "ledgerId": .string(store.activeLedgerId), "name": .string(name),
                    "condition": condition, "actions": actions,
                    "priority": .int(priority), "runOnEdit": .bool(runOnEdit),
                ]))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}

/// Read-only detail for a complex rule the simple builder can't represent.
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
        guard let v = SimpleRule.jsonValue(rule.conditionJSON), let cond = RuleCondition.parse(v) else { return "—" }
        switch cond {
        case .all(let cs): return "all of \(cs.count) conditions"
        case .any(let cs): return "any of \(cs.count) conditions"
        case .not: return "not (1 condition)"
        case .leaf(let l): return "\(l.field) \(l.op)"
        }
    }
    private var actionsSummary: String {
        guard let v = SimpleRule.jsonValue(rule.actionsJSON), case .array(let arr) = v else { return "—" }
        let types = arr.compactMap { RuleAction.parse($0)?.type }
        return types.isEmpty ? "—" : "\(types.count) action(s): " + types.joined(separator: ", ")
    }
}
```

- [ ] **Step 2: Build iOS + run the full FinchApp suite**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Build macOS (FinchMac) — CI gate**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verification on the simulator**

Launch (Settings › Power Tools › Rules). Then:
- **Create** a simple rule (merchant contains "coffee" → set category) with a priority + run-on-edit; it appears, active toggle works.
- **Edit** it (tap the name) → change keyword/category/priority → persists; backfill applies it.
- **Mark-reviewed fix:** create a "mark reviewed" rule, backfill → matched txns become reviewed (previously a no-op).
- **Match count:** a rule that's fired shows `N×`.
- **Complex rule:** if a multi-condition rule exists (web-made/seed), tapping it opens the read-only detail ("all of N conditions"); it is NOT flattened.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch -initialTab settings
```

- [ ] **Step 5: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/PowerTools/RulesManagerView.swift
git commit -m "feat(ios): edit rules in place (+ match counts, runOnEdit, mark_reviewed fix)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-24-ios-rules-editing-design.md`):
- RuleSummary + projection condition/actions/runOnEdit → Task 1. ✓
- `ruleMatchCounts` + `simpleRuleForm` parser (legacy set_reviewed accepted) → Task 2. ✓
- Tap-to-edit simple rules; complex → read-only; `N×` count; priority/runOnEdit/active; create gains priority/runOnEdit; `mark_reviewed` fix → Task 3. ✓
- No engine change; build iOS+macOS; full tests green → Task 3 steps 2-3. ✓

**Placeholder scan:** No TBD/TODO; full code in every step; sim step has concrete checks. ✓

**Type consistency:** `SimpleRule.parse(conditionJSON:actionsJSON:) -> SimpleRuleForm?` used in `RuleSheet.init` + list `open(_:)`; `SimpleRuleForm.Field` rawValues (`merchant`/`amount`) map to `RuleSheet.Field`; `.setCategory(String)`/`.markReviewed` match the `switch form?.action`. `priority` sent as `.int` (createRule/updateRule read via `asDouble`, which handles `.int`). `RuleSummary(... conditionJSON:actionsJSON:runOnEdit:)` defaulted init keeps other call sites valid. `RuleCondition.parse`/`RuleAction.parse`/`SimpleRule.jsonValue` used by `RuleDetailView`. ✓

---

## Out of scope

Multi-condition/-action builder; full human-readable rule description; lastApplied display; live match preview; legacy `set_reviewed` data migration; the merchant/amount `equals` op semantics (preserved as-is).
