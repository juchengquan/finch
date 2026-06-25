# Multi-condition rule builder CP2a — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the single-value/no-value entity condition fields (category/account/counterparty/currency/tag-has/day-of-month) and the three entity actions (add_tag/remove_tag/set_counterparty) editable in the rule builder.

**Architecture:** No rules-engine change. (1) Extend `RuleForm`/`RuleParse` (FinchCore) with the new `LeafForm.Field` cases + `ActionForm.Kind` cases, `is_null` (no value) handling, and `date_dom` as a JSON int. (2) Extend `RuleSheet` (FinchApp) with value editors (inline menu Pickers + a number field), reusing a small first-value-fallback picker helper.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), FinchCore, XcodeGen, XCTest.

## Global Constraints

- **No rules-engine change.** Engine already evaluates these fields/ops/actions.
- CP2a fields/ops: category_id (is/is_null), account_id (is), counterparty_id (is/is_null), currency (is), tag_id (has), date_dom (eq/gte/lte). Actions: add_tag, remove_tag, set_counterparty.
- **`is_null` carries no value** — `build` emits `{field, op}` with no `value` key; `leafForm` returns empty value.
- **`date_dom` → JSON int**; validated **1–31** in `save()`.
- Field raw values must equal engine strings: `category_id`, `account_id`, `counterparty_id`, `currency`, `tag_id`, `date_dom`.
- **CP2b stays read-only** — `in`/`has_any`/`has_all`/`date_dow` must still make `RuleParse.parse` return nil.
- Entity Pickers use the **first-value-fallback** binding (no blank state). Inline menu Pickers (consistent with the existing set-category picker).
- **Must build iOS AND macOS (FinchMac).** Sim `iPhone 17 Pro Max`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit; **no `Co-Authored-By` trailer**.

---

## File Structure

**Modify (FinchCore):** `ios/FinchCore/Sources/FinchCore/Rules/RuleForm.swift`.
**Create (tests):** `ios/FinchCore/Tests/FinchCoreTests/RuleParseCP2aTests.swift`.
**Modify (FinchApp):** `ios/FinchApp/Sources/FinchApp/PowerTools/RulesManagerView.swift`.

---

### Task 1: `RuleForm`/`RuleParse` — CP2a fields + actions

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Rules/RuleForm.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests/RuleParseCP2aTests.swift`

**Interfaces:**
- Produces: `LeafForm.Field` gains `categoryId/accountId/counterpartyId/currency/tagId/dateDom`; `ActionForm.Kind` gains `addTag(String)/removeTag(String)/setCounterparty(String)`. `RuleParse.parse`/`build` handle them. CP2b ops still → nil.

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchCore/Tests/FinchCoreTests/RuleParseCP2aTests.swift`:

```swift
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter RuleParseCP2aTests`
Expected: FAIL to compile — new `LeafForm.Field`/`ActionForm.Kind` cases don't exist.

- [ ] **Step 3: Extend `RuleForm.swift`**

Make these edits to `ios/FinchCore/Sources/FinchCore/Rules/RuleForm.swift`:

**(a)** Replace the `LeafForm.Field` enum (line 5):
```swift
    public enum Field: String, Sendable, CaseIterable {
        case merchant, note, amount, kind
        case categoryId = "category_id", accountId = "account_id", counterpartyId = "counterparty_id"
        case currency, tagId = "tag_id", dateDom = "date_dom"
    }
```

**(b)** Replace the `ActionForm.Kind` enum (lines 17-19):
```swift
    public enum Kind: Equatable, Sendable {
        case setCategory(String), setNote(String), setMerchant(String), setKind(String), markReviewed
        case addTag(String), removeTag(String), setCounterparty(String)
    }
```

**(c)** Replace `opsAllowed` (lines 47-54):
```swift
    static func opsAllowed(_ field: LeafForm.Field) -> Set<String> {
        switch field {
        case .merchant:       return ["is", "contains", "startsWith"]
        case .note:           return ["contains"]
        case .amount:         return ["gt", "gte", "lt", "lte", "eq", "between"]
        case .kind:           return ["is"]
        case .categoryId:     return ["is", "is_null"]
        case .accountId:      return ["is"]
        case .counterpartyId: return ["is", "is_null"]
        case .currency:       return ["is"]
        case .tagId:          return ["has"]
        case .dateDom:        return ["eq", "gte", "lte"]
        }
    }
```

**(d)** Replace `leafForm` (lines 56-72):
```swift
    static func leafForm(_ leaf: RuleLeaf) -> LeafForm? {
        guard let field = LeafForm.Field(rawValue: leaf.field) else { return nil }
        var op = leaf.op
        if op == "equals" { op = field == .amount ? "eq" : "is" }   // self-heal legacy
        guard opsAllowed(field).contains(op) else { return nil }
        if op == "is_null" { return LeafForm(field: field, op: op, value: "") }
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

**(e)** Replace `actionForm` (lines 74-83):
```swift
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
```

**(f)** Replace `leafJSON` (lines 109-119):
```swift
    static func leafJSON(_ f: LeafForm) -> JSONValue {
        if f.op == "is_null" {
            return .object(["field": .string(f.field.rawValue), "op": .string("is_null")])
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

**(g)** Replace `actionJSON` (lines 121-129):
```swift
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
```

(`parse`/`build` bodies and the doc comment are unchanged.)

- [ ] **Step 4: Run tests**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter RuleParseCP2aTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Full FinchCore suite (no regressions; CP1 RuleParseTests still pass)**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchCore/Sources/FinchCore/Rules/RuleForm.swift ios/FinchCore/Tests/FinchCoreTests/RuleParseCP2aTests.swift
git commit -m "feat(ios): RuleForm CP2a — entity fields + add/remove tag + set counterparty"
```

---

### Task 2: `RuleSheet` — CP2a value editors

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/RulesManagerView.swift`

**Interfaces:**
- Consumes: `LeafForm.Field`/`ActionForm.Kind` CP2a cases (Task 1); `store.pickableCategories`, `store.accounts`, `store.counterparties`, `store.tags`, `store.availableDisplayCurrencies`.

- [ ] **Step 1: Extend `opsFor` (lines 77-84)**

Replace the function with:
```swift
private func opsFor(_ f: LeafForm.Field) -> [String] {
    switch f {
    case .merchant:       return ["is", "contains", "startsWith"]
    case .note:           return ["contains"]
    case .amount:         return ["gt", "gte", "lt", "lte", "eq", "between"]
    case .kind:           return ["is"]
    case .categoryId:     return ["is", "is_null"]
    case .accountId:      return ["is"]
    case .counterpartyId: return ["is", "is_null"]
    case .currency:       return ["is"]
    case .tagId:          return ["has"]
    case .dateDom:        return ["eq", "gte", "lte"]
    }
}
```

- [ ] **Step 2: Extend `opLabel` + add `fieldLabel` + `PickItem` (lines 85-91)**

Replace `opLabel` and append the two helpers + the struct:
```swift
private func opLabel(_ o: String) -> String {
    switch o {
    case "is": return "is"; case "contains": return "contains"; case "startsWith": return "starts with"
    case "gt": return "greater than"; case "gte": return "≥"; case "lt": return "less than"; case "lte": return "≤"
    case "eq": return "equals"; case "between": return "between"
    case "is_null": return "is not set"; case "has": return "has tag"; default: return o
    }
}
private func fieldLabel(_ f: LeafForm.Field) -> String {
    switch f {
    case .merchant: return "Merchant"; case .note: return "Note"; case .amount: return "Amount"; case .kind: return "Kind"
    case .categoryId: return "Category"; case .accountId: return "Account"; case .counterpartyId: return "Counterparty"
    case .currency: return "Currency"; case .tagId: return "Tag"; case .dateDom: return "Day of month"
    }
}
private struct PickItem: Identifiable { let id: String; let name: String }
```

- [ ] **Step 3: Extend `ActType` + `ActRow` (lines 101-104)**

Replace the `ActType` enum and `ActRow` struct:
```swift
    enum ActType: String, CaseIterable, Identifiable {
        case setCategory, setNote, setMerchant, setKind, markReviewed, addTag, removeTag, setCounterparty
        var id: String { rawValue }
        var label: String { switch self {
            case .setCategory: "Set category"; case .setNote: "Set note"; case .setMerchant: "Set merchant"
            case .setKind: "Set kind"; case .markReviewed: "Mark reviewed"
            case .addTag: "Add tag"; case .removeTag: "Remove tag"; case .setCounterparty: "Set counterparty" } } }
    struct ActRow: Identifiable { let id = UUID(); var type: ActType = .setCategory; var categoryId = ""; var text = ""; var kind = "expense"; var tagId = ""; var counterpartyId = "" }
```

- [ ] **Step 4: Extend `actRow(from:)` (lines 129-137)**

Replace the function:
```swift
    private static func actRow(from a: ActionForm) -> ActRow {
        switch a.kind {
        case .setCategory(let id): return ActRow(type: .setCategory, categoryId: id)
        case .setNote(let s):      return ActRow(type: .setNote, text: s)
        case .setMerchant(let s):  return ActRow(type: .setMerchant, text: s)
        case .setKind(let k):      return ActRow(type: .setKind, kind: k)
        case .markReviewed:        return ActRow(type: .markReviewed)
        case .addTag(let id):      return ActRow(type: .addTag, tagId: id)
        case .removeTag(let id):   return ActRow(type: .removeTag, tagId: id)
        case .setCounterparty(let id): return ActRow(type: .setCounterparty, counterpartyId: id)
        }
    }
```

- [ ] **Step 5: Add the `entityPicker` helper + rewrite `condRow` (lines 182-199)**

Replace `condRow` with the version below, and add the `entityPicker` helper right after it:
```swift
    @ViewBuilder private func condRow(_ c: Binding<CondRow>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Field", selection: c.field) {
                ForEach(LeafForm.Field.allCases, id: \.self) { Text(fieldLabel($0)).tag($0) }
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
            case .categoryId:
                if c.wrappedValue.op != "is_null" { entityPicker("Category", c.value, store.pickableCategories.map { PickItem(id: $0.id, name: $0.name) }) }
            case .accountId:
                entityPicker("Account", c.value, store.accounts.map { PickItem(id: $0.id, name: $0.name ?? $0.id) })
            case .counterpartyId:
                if c.wrappedValue.op != "is_null" { entityPicker("Counterparty", c.value, store.counterparties.map { PickItem(id: $0.id, name: $0.name) }) }
            case .currency:
                entityPicker("Currency", c.value, store.availableDisplayCurrencies.map { PickItem(id: $0, name: $0) })
            case .tagId:
                entityPicker("Tag", c.value, store.tags.map { PickItem(id: $0.id, name: $0.name) })
            case .dateDom:
                TextField("Day (1–31)", text: c.value).keyboardType(.numberPad)
            }
        }
    }

    /// Inline menu Picker that displays the first item when nothing is chosen yet
    /// (a fresh row starts empty), so the Picker never shows a blank selection.
    /// `save()` applies the same first-item fallback, so the two stay in sync.
    @ViewBuilder private func entityPicker(_ title: String, _ sel: Binding<String>, _ items: [PickItem]) -> some View {
        Picker(title, selection: Binding(
            get: { sel.wrappedValue.isEmpty ? (items.first?.id ?? "") : sel.wrappedValue },
            set: { sel.wrappedValue = $0 })) {
            ForEach(items) { Text($0.name).tag($0.id) }
        }
    }
```

- [ ] **Step 6: Rewrite `actRow` (lines 201-220)**

Replace `actRow` (reusing `entityPicker`):
```swift
    @ViewBuilder private func actRow(_ a: Binding<ActRow>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Action", selection: a.type) { ForEach(ActType.allCases) { Text($0.label).tag($0) } }
            switch a.wrappedValue.type {
            case .setCategory:
                entityPicker("Category", a.categoryId, store.pickableCategories.map { PickItem(id: $0.id, name: $0.name) })
            case .setNote:     TextField("Note", text: a.text)
            case .setMerchant: TextField("Merchant", text: a.text)
            case .setKind:     Picker("Kind", selection: a.kind) { ForEach(kindValues, id: \.self) { Text($0.capitalized).tag($0) } }
            case .markReviewed: EmptyView()
            case .addTag, .removeTag:
                entityPicker("Tag", a.tagId, store.tags.map { PickItem(id: $0.id, name: $0.name) })
            case .setCounterparty:
                entityPicker("Counterparty", a.counterpartyId, store.counterparties.map { PickItem(id: $0.id, name: $0.name) })
            }
        }
    }
```

- [ ] **Step 7: Add `firstId` helper + extend `save()`'s condition loop (lines 230-246)**

Replace the `for c in conditions { … }` loop with:
```swift
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
            }
            condForms.append(LeafForm(field: c.field, op: c.op, value: value, value2: value2))
        }
```

Then add this helper method inside `RuleSheet` (e.g. right after `save()`):
```swift
    private func firstId(for field: LeafForm.Field) -> String {
        switch field {
        case .categoryId:     return store.pickableCategories.first?.id ?? ""
        case .accountId:      return store.accounts.first?.id ?? ""
        case .counterpartyId: return store.counterparties.first?.id ?? ""
        case .currency:       return store.availableDisplayCurrencies.first ?? ""
        case .tagId:          return store.tags.first?.id ?? ""
        default:              return ""
        }
    }
```

- [ ] **Step 8: Extend `save()`'s action loop (lines 250-267)**

Replace the `for a in actions { … }` loop with:
```swift
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
            case .addTag, .removeTag:
                let tid = a.tagId.isEmpty ? (store.tags.first?.id ?? "") : a.tagId
                guard !tid.isEmpty else { errorMessage = "Pick a tag."; return }
                actForms.append(ActionForm(kind: a.type == .addTag ? .addTag(tid) : .removeTag(tid)))
            case .setCounterparty:
                let cid = a.counterpartyId.isEmpty ? (store.counterparties.first?.id ?? "") : a.counterpartyId
                guard !cid.isEmpty else { errorMessage = "Pick a counterparty."; return }
                actForms.append(ActionForm(kind: .setCounterparty(cid)))
            }
        }
```

- [ ] **Step 9: Build iOS + full FinchApp suite**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`. (No new .swift files → `xcodegen` is a no-op but harmless.)

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
- New rule: "**Category is** <pick> AND **Day of month ≤** 5 → **Add tag** <pick>". Save → appears; backfill applies.
- A "**Category is not set**" (is_null) condition shows **no value editor**; saves + matches uncategorized txns.
- **Currency is**, **Account is**, **Counterparty is/is not set**, **Tag has**, **Set counterparty**, **Remove tag** all selectable; pickers never blank.
- Edit the rule → fields prefill from the stored rule.
- A CP2b rule (e.g. `tag_id has_any`, made on web) still opens **read-only**.

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
git commit -m "feat(ios): rule builder CP2a editors (entity fields + tag/counterparty actions)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-25-ios-rule-multi-condition-cp2a-design.md`):
- New fields category_id(is/is_null)/account_id(is)/counterparty_id(is/is_null)/currency(is)/tag_id(has)/date_dom(eq/gte/lte) → Task 1 (model) + Task 2 (editors). ✓
- Actions add_tag/remove_tag/set_counterparty → Task 1 + Task 2. ✓
- is_null no value key; date_dom int → Task 1 (d),(f); validated 1–31 → Task 2 step 7. ✓
- CP2b ops still nil → Task 1 test `test_cp2b_ops_still_nil` (opsAllowed excludes in/has_any/has_all/date_dow). ✓
- First-value-fallback pickers → Task 2 `entityPicker` + `firstId`. ✓
- No engine change; build iOS+macOS; full tests → Task 2 steps 9-10. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code; sim step concrete. ✓

**Type consistency:** `LeafForm.Field` raw values (`category_id`…`date_dom`) used in `opsFor`/`fieldLabel`/`condRow`/`firstId` match the enum; `ActType` new cases match `actRow`/`actRow(from:)`/`save`; `ActionForm.Kind` new cases (addTag/removeTag/setCounterparty) match Task 1's actionForm/actionJSON; `entityPicker(_:_:_:)` takes `(String, Binding<String>, [PickItem])` — call sites pass `c.value`/`a.categoryId`/`a.tagId`/`a.counterpartyId` (all `Binding<String>`) + `[PickItem]`; `firstId(for:)` covers the entity fields used in save. `numStr` (public, CP1) reused. ✓

---

## Out of scope (CP2b)

`in`/`has_any`/`has_all`/`date_dow` array ops + `values:[String]` model + multi-select/weekday pickers; searchable pickers; nested groups, `not`, `split`.
