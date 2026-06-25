# Multi-condition rule builder CP2b — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the array/multi-select condition ops editable: `category_id in`, `account_id in`, `kind in`, `tag_id has_any`/`has_all`, `date_dow in` — the final rules-parity checkpoint.

**Architecture:** No rules-engine change. (1) `LeafForm` gains `values: [String]`; `RuleParse` parses/builds the array ops (`date_dow` as a JSON int array, others string arrays). (2) `RuleSheet` gains a reusable pushed searchable multi-select (`MultiSelectList`) + inline weekday chips, branching `condRow` by op.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), FinchCore, XcodeGen, XCTest.

## Global Constraints

- **No rules-engine change.**
- CP2b ops: category_id `in`, account_id `in`, kind `in`, tag_id `has_any`/`has_all`, date_dow `in`. No new actions.
- **`values: [String]`** carries array payloads (single-value ops keep `value`). `date_dow` weekday indices stored as strings, built as a JSON **int** array; the others build as string arrays.
- **Weekday convention (verified):** engine `dayOfWeek = Calendar(.weekday, UTC) - 1` → **0 = Sunday … 6 = Saturday**; chip labels `["S","M","T","W","T","F","S"]`.
- `has_any`/`has_all` share the tag multi-select; op picker distinguishes.
- **Empty array → parse nil** (an `in`/`has_any`/`has_all` with `[]` is invalid). Nested groups / `not` still → nil (read-only).
- **Must build iOS AND macOS (FinchMac).** Sim `iPhone 17 Pro Max`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit; **no `Co-Authored-By` trailer**.

---

## File Structure

**Modify (FinchCore):** `ios/FinchCore/Sources/FinchCore/Rules/RuleForm.swift`.
**Create (tests):** `ios/FinchCore/Tests/FinchCoreTests/RuleParseCP2bTests.swift`.
**Modify (FinchApp):** `ios/FinchApp/Sources/FinchApp/PowerTools/RulesManagerView.swift`.

---

### Task 1: `RuleForm`/`RuleParse` — array ops + `values`

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Rules/RuleForm.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests/RuleParseCP2bTests.swift`

**Interfaces:**
- Produces: `LeafForm` gains `values: [String]` (init default `[]`) + `Field.dateDow = "date_dow"`. `RuleParse.parse`/`build` handle `in`/`has_any`/`has_all`. Nested/`not`/empty-array still → nil.

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchCore/Tests/FinchCoreTests/RuleParseCP2bTests.swift`:

```swift
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter RuleParseCP2bTests`
Expected: FAIL to compile — `LeafForm` has no `values`; no `dateDow` case.

- [ ] **Step 3: Edit `RuleForm.swift`**

**(a)** Replace the `LeafForm` struct + doc comment (lines 3-18):
```swift
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
```

**(b)** Replace `opsAllowed` (lines 53-66):
```swift
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
```

**(c)** Replace `leafForm` (lines 68-85) — add the array-op branch after `is_null`:
```swift
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
```

**(d)** Replace `leafJSON` (lines 125-141) — add the array-op branch after `is_null`:
```swift
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
```

(`parse`/`build`/`actionForm`/`actionJSON` unchanged. The synthesized `Equatable` now includes `values`.)

- [ ] **Step 4: Run tests**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter RuleParseCP2bTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Full FinchCore suite (no regressions; CP1/CP2a RuleParse tests still pass)**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test`
Expected: all pass. (The `values: [String] = []` default keeps every existing `LeafForm(...)` call site valid.)

- [ ] **Step 6: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchCore/Sources/FinchCore/Rules/RuleForm.swift ios/FinchCore/Tests/FinchCoreTests/RuleParseCP2bTests.swift
git commit -m "feat(ios): RuleForm CP2b — array ops (in/has_any/has_all, date_dow)"
```

---

### Task 2: `RuleSheet` — multi-select + weekday editors

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/RulesManagerView.swift`

**Interfaces:**
- Consumes: `LeafForm.values`, `Field.dateDow`, the new array ops (Task 1); existing `store.pickableCategories`/`accounts`/`tags`, `kindValues`, `PickItem`, `entityPicker`, `firstId`.

- [ ] **Step 1: Extend `opsFor` (lines 77-90)**

Replace with:
```swift
private func opsFor(_ f: LeafForm.Field) -> [String] {
    switch f {
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
```

- [ ] **Step 2: Extend `opLabel` + `fieldLabel` + add `weekdayLabels` (lines 91-105)**

Replace `opLabel` and `fieldLabel`, then add `weekdayLabels` after `fieldLabel`:
```swift
private func opLabel(_ o: String) -> String {
    switch o {
    case "is": return "is"; case "contains": return "contains"; case "startsWith": return "starts with"
    case "gt": return "greater than"; case "gte": return "≥"; case "lt": return "less than"; case "lte": return "≤"
    case "eq": return "equals"; case "between": return "between"
    case "is_null": return "is not set"; case "has": return "has tag"
    case "in": return "in"; case "has_any": return "has any of"; case "has_all": return "has all of"; default: return o
    }
}
private func fieldLabel(_ f: LeafForm.Field) -> String {
    switch f {
    case .merchant: return "Merchant"; case .note: return "Note"; case .amount: return "Amount"; case .kind: return "Kind"
    case .categoryId: return "Category"; case .accountId: return "Account"; case .counterpartyId: return "Counterparty"
    case .currency: return "Currency"; case .tagId: return "Tag"; case .dateDom: return "Day of month"; case .dateDow: return "Day of week"
    }
}
// date_dow weekday indices: 0=Sun … 6=Sat (engine dayOfWeek = Calendar(.weekday, UTC) - 1).
private let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]
```

- [ ] **Step 3: Add `MultiSelectList` (after the `PickItem` struct, line 106)**

Add at file scope, right after `private struct PickItem … `:
```swift
/// A searchable checkmark list that toggles ids in a `[String]` selection.
private struct MultiSelectList: View {
    let title: String
    @Binding var selected: [String]
    let items: [PickItem]
    @State private var query = ""

    var body: some View {
        List {
            ForEach(filtered) { item in
                Button {
                    if let i = selected.firstIndex(of: item.id) { selected.remove(at: i) } else { selected.append(item.id) }
                } label: {
                    HStack {
                        Text(item.name).foregroundStyle(.primary)
                        Spacer()
                        if selected.contains(item.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $query)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
    private var filtered: [PickItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
}
```

- [ ] **Step 4: Add `values` to `CondRow` (line 115)**

Replace the `CondRow` struct:
```swift
    struct CondRow: Identifiable { let id = UUID(); var field: LeafForm.Field = .merchant; var op = "contains"; var value = ""; var value2 = ""; var values: [String] = [] }
```

- [ ] **Step 5: Prefill `values` in `init` (lines 139-141)**

Replace the `_conditions` initializer:
```swift
        _conditions = State(initialValue: form.map { $0.conditions.map { lf in
            CondRow(field: lf.field, op: lf.op, value: lf.value, value2: lf.value2, values: lf.values)
        } } ?? [CondRow()])
```

- [ ] **Step 6: Rewrite the `condRow` field switch + add `multiSelect`/`weekdayChips` (lines 211-233)**

Replace the `switch c.wrappedValue.field { … }` block inside `condRow`:
```swift
            switch c.wrappedValue.field {
            case .merchant, .note:
                TextField("Text", text: c.value)
            case .amount:
                TextField("Amount", text: c.value).keyboardType(.decimalPad)
                if c.wrappedValue.op == "between" { TextField("and", text: c.value2).keyboardType(.decimalPad) }
            case .kind:
                if c.wrappedValue.op == "in" { multiSelect("Kinds", c.values, kindValues.map { PickItem(id: $0, name: $0.capitalized) }) }
                else { Picker("Kind", selection: c.value) { ForEach(kindValues, id: \.self) { Text($0.capitalized).tag($0) } } }
            case .categoryId:
                if c.wrappedValue.op == "is_null" { EmptyView() }
                else if c.wrappedValue.op == "in" { multiSelect("Categories", c.values, store.pickableCategories.map { PickItem(id: $0.id, name: $0.name) }) }
                else { entityPicker("Category", c.value, store.pickableCategories.map { PickItem(id: $0.id, name: $0.name) }) }
            case .accountId:
                if c.wrappedValue.op == "in" { multiSelect("Accounts", c.values, store.accounts.map { PickItem(id: $0.id, name: $0.name ?? $0.id) }) }
                else { entityPicker("Account", c.value, store.accounts.map { PickItem(id: $0.id, name: $0.name ?? $0.id) }) }
            case .counterpartyId:
                if c.wrappedValue.op != "is_null" { entityPicker("Counterparty", c.value, store.counterparties.map { PickItem(id: $0.id, name: $0.name) }) }
            case .currency:
                entityPicker("Currency", c.value, store.availableDisplayCurrencies.map { PickItem(id: $0, name: $0) })
            case .tagId:
                if c.wrappedValue.op == "has" { entityPicker("Tag", c.value, store.tags.map { PickItem(id: $0.id, name: $0.name) }) }
                else { multiSelect("Tags", c.values, store.tags.map { PickItem(id: $0.id, name: $0.name) }) }
            case .dateDom:
                TextField("Day (1–31)", text: c.value).keyboardType(.numberPad)
            case .dateDow:
                weekdayChips(c.values)
            }
```

Then add these two helpers right after the `entityPicker` helper (after its closing brace, ~line 244):
```swift
    /// A pushed, searchable multi-select that summarizes the count inline.
    @ViewBuilder private func multiSelect(_ title: String, _ sel: Binding<[String]>, _ items: [PickItem]) -> some View {
        NavigationLink {
            MultiSelectList(title: title, selected: sel, items: items)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(sel.wrappedValue.isEmpty ? "None" : "\(sel.wrappedValue.count) selected").foregroundStyle(.secondary)
            }
        }
    }

    /// Inline Sun–Sat chips toggling weekday indices (0–6) in the selection.
    @ViewBuilder private func weekdayChips(_ sel: Binding<[String]>) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                let key = String(i)
                let on = sel.wrappedValue.contains(key)
                Text(weekdayLabels[i])
                    .font(.caption).frame(maxWidth: .infinity, minHeight: 32)
                    .background(on ? Color.accentColor : Color.secondary.opacity(0.15))
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let idx = sel.wrappedValue.firstIndex(of: key) { sel.wrappedValue.remove(at: idx) }
                        else { sel.wrappedValue.append(key) }
                    }
            }
        }
    }
```

- [ ] **Step 7: Handle array ops in `save()`'s condition loop (lines 272-300)**

Replace the `for c in conditions { … }` loop:
```swift
        for c in conditions {
            var value = c.value, value2 = c.value2
            // Array-valued ops (CP2b): require a non-empty selection; value/value2 unused.
            if c.op == "in" || c.op == "has_any" || c.op == "has_all" {
                guard !c.values.isEmpty else { errorMessage = "Select at least one value for every condition."; return }
                condForms.append(LeafForm(field: c.field, op: c.op, value: "", values: c.values))
                continue
            }
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
            case .dateDom:
                guard let n = Int(value), (1...31).contains(n) else { errorMessage = "Enter a day 1–31."; return }
                value = String(n)
            case .categoryId, .counterpartyId:
                if c.op == "is_null" { value = "" }
                else {
                    if value.isEmpty { value = firstId(for: c.field) }
                    guard !value.isEmpty else { errorMessage = "Pick a value for every condition."; return }
                }
            case .accountId, .currency, .tagId:
                if value.isEmpty { value = firstId(for: c.field) }
                guard !value.isEmpty else { errorMessage = "Pick a value for every condition."; return }
            case .dateDow:
                break   // date_dow's only op is `in`, handled by the array-op branch above
            }
            condForms.append(LeafForm(field: c.field, op: c.op, value: value, value2: value2))
        }
```

(The action loop, `firstId`, and the create/update calls are unchanged.)

- [ ] **Step 8: Build iOS + full FinchApp suite**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`. (Likely compile spot: the `condRow` switch must stay exhaustive — `.dateDow` is present; the `if/else if/else` arms each return a View.)

- [ ] **Step 9: Full FinchCore suite**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test 2>&1 | grep -iE "error:|Test Suite 'All tests'"`
Expected: all pass.

- [ ] **Step 10: Build macOS (FinchMac)**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 11: Manual verification on the simulator**

Launch (Settings › Power Tools › Rules). Then:
- New rule, "all of": **Category in** → row shows "Categories: N selected", taps into a searchable checkmark list; **Day of week in** → S–S chips toggle. Add an **add tag** action. Save → appears; backfill matches only the selected categories on Sat/Sun.
- **Kind in**, **Account in**, **Tag has any / has all** all use the multi-select.
- Edit the rule → the multi-selects and chips show the saved selections.
- A nested / `not` rule (web-made) still opens **read-only**.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch -initialTab settings
```

- [ ] **Step 12: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/PowerTools/RulesManagerView.swift
git commit -m "feat(ios): rule builder CP2b editors (multi-select + weekday chips)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-25-ios-rule-multi-condition-cp2b-design.md`):
- Array ops category/account/kind `in`, tag `has_any`/`has_all`, date_dow `in` → Task 1 (model) + Task 2 (editors). ✓
- `values: [String]`; date_dow int array / others string array → Task 1 (a),(c),(d). ✓
- Multi-select pushed searchable list + weekday chips (0=Sun…6=Sat) → Task 2 steps 3,6. ✓
- Empty array / nested / not → nil → Task 1 test `test_empty_array_nested_not_still_nil`. ✓
- save() requires non-empty selection → Task 2 step 7. ✓
- No engine change; build iOS+macOS; full tests → Task 2 steps 8-10. ✓

**Placeholder scan:** No TBD/TODO; full code in every step; sim step concrete. ✓

**Type consistency:** `LeafForm.values` (default `[]`) keeps existing `LeafForm(...)` call sites valid; `Field.dateDow` used in `opsFor`/`fieldLabel`/`condRow`/leafForm/leafJSON; array ops `in`/`has_any`/`has_all` gated consistently in `opsAllowed`/`opsFor`/`leafForm`/`leafJSON`/`condRow`/`save`; `multiSelect(_:_:_:)` takes `(String, Binding<[String]>, [PickItem])` — call sites pass `c.values` (`Binding<[String]>`) + `[PickItem]`; `MultiSelectList` binds `selected: sel`; `weekdayChips` takes `Binding<[String]>`; `weekdayLabels` has 7 entries indexed 0–6. ✓

---

## Out of scope

Nested groups, `not`, `split`; new actions; engine/web changes.
