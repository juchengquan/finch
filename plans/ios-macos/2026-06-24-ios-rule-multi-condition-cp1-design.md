# Multi-condition rule builder — CP1 (iOS Power Tools)

**Date:** 2026-06-24
**Status:** Design approved, pending implementation
**Scope:** iOS `RulesManagerView`/`RuleSheet` + a new `RuleForm` model in FinchCore (superseding `SimpleRule`). **No rules-engine change.** iPad/Mac share the view. CP1 of the multi-condition builder; CP2 (entity-picker / multi-value fields) is a separate later effort.

## Problem

Rules editing (#282) only builds a **single condition + single action**. Rules with multiple conditions (`all`/`any`) or multiple actions — which the engine fully evaluates and the web builds — open **read-only** on iOS. CP1 adds a builder that creates/edits rules with **multiple conditions (all/any) and multiple actions**, for the simple-valued field/action set (no entity pickers yet).

Two pre-existing op bugs surface here and are fixed in scope:
- The single builder emits merchant/amount op `"equals"`, but the engine handles merchant `is` and amount `eq` (no `equals` case) — so `"equals"` rules **silently never match**.
- (`set_reviewed`→`mark_reviewed` was already fixed in #282.)

## Goal

- Build/edit rules with **`all`/`any` over multiple conditions** and **multiple actions**, for CP1 fields/actions.
- **CP1 condition fields:** `merchant` (is/contains/startsWith), `note` (contains), `amount` (gt/gte/lt/lte/eq/**between**), `kind` (is).
- **CP1 actions:** set category, set note, set merchant, set kind, mark reviewed.
- **Fix `equals`** → emit engine ops (`is` for merchant, `eq` for amount); the parser accepts legacy `equals` and **self-heals** it on save.
- A rule using only CP1 fields/actions (incl. multi-condition/action) becomes **editable**; anything else (CP2 fields, nested groups, `not`, `split`) stays **read-only** — never flattened.

## Non-goals (CP2 / later)

- Entity-picker / multi-value fields: `category_id` (as a condition), `account_id`, `counterparty_id`, `currency`, `tag_id`, `date_dow`, `date_dom`; the `in`/`has_any`/`has_all` array operators; `kind in`.
- Actions `add_tag`, `remove_tag`, `set_counterparty`.
- Nested condition groups, `not`, the `split` action — remain read-only.
- No rules-engine change; no web change.

## Key decisions (locked)

1. **Flat `all`/`any` only** (match the web builder) — no nested groups, no `not`.
2. **One unified builder** — `RuleForm` supersedes `SimpleRule`; `RuleSheet` grows condition/action arrays. A 1-condition rule round-trips to a bare leaf (output identical to today's single builder).
3. **Fix `equals`** → `is`/`eq` on save; parser accepts legacy `equals` (and `set_reviewed`) for backward-compat + self-heal.
4. **No engine change.**

## Detailed design

### `RuleForm` — FinchCore, pure (replaces `SimpleRule`)

```swift
public struct LeafForm: Equatable, Sendable {
    public enum Field: String, Sendable { case merchant, note, amount, kind }
    public var field: Field
    public var op: String        // engine ops per field (see table)
    public var value: String     // single value (text / number / kind raw)
    public var value2: String    // amount `between` upper bound; "" otherwise
}
public struct ActionForm: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case setCategory(String); case setNote(String); case setMerchant(String); case setKind(String); case markReviewed
    }
    public var kind: Kind
}
public struct RuleForm: Equatable, Sendable {
    public enum Combinator: String, Sendable { case all, any }
    public var combinator: Combinator
    public var conditions: [LeafForm]
    public var actions: [ActionForm]
}

public enum RuleParse {
    public static func jsonValue(_ s: String) -> JSONValue?
    /// nil when the rule uses a non-CP1 field/op/action, a `not`, or nested groups.
    public static func parse(conditionJSON: String, actionsJSON: String) -> RuleForm?
    /// (conditionJSON, actionsJSON). 1 condition → bare leaf; >1 → {all|any:[…]}.
    public static func build(_ form: RuleForm) -> (condition: JSONValue, actions: JSONValue)
}
```

**parse:**
- Condition: a single `.leaf`, or `.all([leaves])` / `.any([leaves])` where **every** child is a `.leaf` with a CP1 field + a CP1 op. Any `.not`, nested `.all`/`.any`, non-CP1 field, or unsupported op ⇒ nil. Combinator from the wrapper (single leaf ⇒ `.all`).
- Legacy op map on read: merchant `equals`→`is`, amount `equals`→`eq`.
- Leaf value: `merchant`/`note`/`kind` → string; `amount` non-between → number string; `amount between` → `value`=lo, `value2`=hi (from the 2-element array).
- Actions: each must be a CP1 action; `set_reviewed`/`mark_reviewed`→`.markReviewed`. Any non-CP1 action (add_tag, split, …) ⇒ nil.

**build:** inverse; emits engine ops (`is`/`eq`, never `equals`) and `mark_reviewed`. amount `between` → `value: [lo, hi]`. 1 condition → bare leaf object; >1 → `{all|any: [leaf, …]}`.

### Op vocabulary (CP1) — engine-correct

| field | ops | value editor |
|---|---|---|
| merchant | is, contains, startsWith | text |
| note | contains | text |
| amount | gt, gte, lt, lte, eq, between | number (between → two numbers) |
| kind | is | enum: expense/income/transfer/refund/adjustment |

Actions: set_category (category picker), set_note (text), set_merchant (text), set_kind (enum), mark_reviewed (none).

### `RuleSheet` — grows arrays

- **Combinator** Picker (`all`/`any`) — shown when >1 condition.
- **Conditions** — a `ForEach` of editable rows; each row: `Field` Picker → `op` Picker (ops depend on field) → value editor (field-specific). **"+ Add condition"**; swipe-to-delete (min 1).
- **Actions** — a `ForEach` of editable rows; each row: action-`Kind` Picker → value editor. **"+ Add action"**; swipe-to-delete (min 1).
- name, priority (Stepper), run-on-edit, active (edit only) — as today.
- Save: `RuleParse.build(form)` → `createRule`/`updateRule` (full patch: name/priority/condition/actions/isActive/runOnEdit).
- Validation: ≥1 condition, ≥1 action; amount values numeric (incl. both `between` bounds); kind/category chosen.

### Routing & read-only fallback

`RulesManagerView.open(rule)`: `RuleParse.parse(...) != nil` → `RuleSheet`; else `RuleDetailView` (read-only, unchanged). After CP1 the fallback only catches CP2-field rules + nested/`not`/`split`.

### Bug fixes (in scope)

- **`equals` → `is`/`eq`:** the builder no longer emits `equals`; `RuleParse.parse` maps legacy `equals` so old rules stay editable and a re-save rewrites them to the engine op. (`mark_reviewed` already fixed in #282; `RuleParse` keeps accepting legacy `set_reviewed`.)

## Facts (engine — no change)

- `evaluateLeaf` ops: merchant `is/contains/startsWith`; note `contains`; amount `gt/gte/lt/lte/eq/between`; kind `is/in` (CP1 uses `is`). No `equals` case (→ the bug). `RuleCondition.parse` handles `all/any/not/leaf`; `RuleAction.parse` → `{type, raw}`.
- `updateRule`/`createRule` patch: name/priority/condition/actions/isActive/runOnEdit (priority via `asDouble`). `RuleSummary` already carries `conditionJSON`/`actionsJSON`/`runOnEdit` (#282).

## Testing

- **FinchCore (`RuleParse`, pure — the crux):**
  - parse single leaf (merchant contains) → 1-condition form; build → bare leaf (no wrapper).
  - parse `all`/`any` of 2+ leaves → multi-condition form, right combinator; build → `{all|any:[…]}`.
  - amount `between` → value/value2; build → 2-element array.
  - kind `is`; note `contains`; merchant `is`/`startsWith`.
  - **legacy `equals`** (merchant) → parsed as `is`; build emits `is` (self-heal). amount `equals` → `eq`.
  - multi-action (set_category + mark_reviewed) parse/build.
  - **nil cases:** `not`, nested `all` inside `all`, a CP2 field (category_id/tag_id/…), a CP2 op (`in`/`has_any`), a CP2 action (add_tag/split).
  - round-trip: parse → build → parse equals (for the supported set), incl. large amounts (no scientific — reuse the safe formatting from #282).
- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests green.
- **Manual (sim):** build a 2-condition all/any rule with 2 actions; backfill matches; edit it; a legacy `equals`/single rule still edits (and its op is corrected on save); a CP2-field rule still opens read-only.

## Out of scope

CP2 fields/actions + their pickers/array editors; nested groups, `not`, `split`; web changes; a human-readable rule description.
