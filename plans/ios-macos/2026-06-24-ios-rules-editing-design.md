# Rules editing (iOS Power Tools)

**Date:** 2026-06-24
**Status:** Design approved, pending implementation
**Scope:** iOS `RulesManagerView` (Settings › Power Tools › Rules) + small FinchCore projection/selector additions. **No rules-engine change.** iPad/Mac share the view.

## Problem

iOS can list rules, toggle active, delete, backfill, and **add** a rule (single condition + single action) — but **cannot edit** one. Changing a rule means delete-and-recreate. The list also shows no usage info. (The engine already supports everything: `updateRule` patches name/priority/condition/actions/isActive/runOnEdit, and the engine evaluates all/any/not trees + 9 action types — the gap is purely the iOS UI.)

Scope decision: **edit-in-place + match counts** — not the full multi-condition builder (that's a future, larger effort).

## Goal

- **Tap a rule → edit it.** For a **simple** rule (single leaf condition on `merchant`/`amount` + a single supported action), open an editor prefilled with its name, condition, action, **priority**, **active**, and **run-on-edit**; Save → `updateRule`.
- For a **complex** rule (multi-condition/-action, or a field/action the simple builder can't express), open a **read-only detail** ("N conditions · M actions — edit on the web") — never silently flatten it.
- **Match count** `N×` on each list row (txns the rule has been applied to).
- **Create** gains the same priority + run-on-edit fields (shared editor).
- **Fix a pre-existing bug:** the builder writes the reviewed action as `"set_reviewed"`, but the engine handles `"mark_reviewed"` — so iOS-made "mark reviewed" rules silently no-op and diverge from the web. Emit `"mark_reviewed"` going forward; the parser also accepts legacy `"set_reviewed"` so editing such a rule re-saves it correctly.

## Non-goals

- No multi-condition (all/any/not) or multi-action builder (deferred — complex rules are read-only here).
- No full human-readable rule description (the complex-rule detail is a lightweight structural summary).
- No `lastAppliedAt` display; no live match preview.
- No data migration of already-stored legacy `"set_reviewed"` actions (only new saves/edits write `"mark_reviewed"`).
- No rules-engine change; no web change.

## Key decisions (locked)

1. **Edit-in-place** reusing the simple single-condition/single-action builder; **complex rules are read-only** (detected by a parser, never flattened).
2. **Match count** = all txns in the active ledger whose `appliedRuleIds` contains the rule id (pending included — `appliedRuleIds` means the rule fired).
3. **Complex-rule detail is lightweight** (counts + "edit on web"), not a full describe.
4. **Fix `set_reviewed` → `mark_reviewed`** (bug + parity); parser accepts both.

## Detailed design

### Projection — extend `RuleSummary`

`RuleSummary` (`Project/RuleSummary.swift`) gains `conditionJSON: String`, `actionsJSON: String`, `runOnEdit: Bool`. The rules projection (`Projections+State.swift`, currently `SELECT id, name, priority, is_active FROM rules`) adds `condition, actions, run_on_edit` and passes them to the init. (Stored as raw JSON strings — parsed only when editing.)

### Match counts — `Selectors.ruleMatchCounts`

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
Shown as `N×` (muted/monospaced, hidden when 0) on each list row; computed once per render.

### Simple-form parser — FinchCore, pure + testable

A helper that decides editability and extracts the builder fields:

```swift
public struct SimpleRuleForm: Equatable, Sendable {
    public enum Field: String { case merchant, amount }
    public enum Action: Equatable { case setCategory(String); case markReviewed }
    public var field: Field
    public var op: String          // builder ops: merchant {contains,is}; amount {gt,lt,eq…}
    public var value: String
    public var action: Action
}

/// Parse the rule's condition+actions JSON into the simple builder form, or nil
/// when the rule is too complex for the simple builder (multi-condition, all/any/
/// not wrapper, unsupported field/op, multiple actions, or an unsupported action).
public static func simpleRuleForm(conditionJSON: String, actionsJSON: String) -> SimpleRuleForm? { … }
```

Rules:
- **Condition** must be a single leaf with `field ∈ {merchant, amount}` and an op the builder supports; any `all`/`any`/`not` wrapper or other field ⇒ nil.
- **Actions** must be exactly one, of type `set_category` (→ `.setCategory(categoryId)`) or `mark_reviewed`/`set_reviewed` (→ `.markReviewed`); anything else ⇒ nil.

This reuses the engine's existing condition/action JSON decoding where possible.

### Editor — generalize `AddRuleSheet` → `RuleSheet`

One sheet for create + edit:
- `init(rule: RuleSummary?)` — nil = create; non-nil = edit (prefill from `simpleRuleForm(rule.conditionJSON, rule.actionsJSON)` + `rule.name`/`priority`/`isActive`/`runOnEdit`).
- Fields: name, condition (field/op/value), action (set category / mark reviewed), **priority** (stepper/number), **run-on-edit** (toggle), **active** (toggle, edit only).
- Save: create → `createRule` (now emitting `mark_reviewed`); edit → `updateRule` patch `{name, priority, condition, actions, isActive, runOnEdit}`.

### Read-only detail — `RuleDetailView` (complex rules)

Shows name, priority, active (read-only or a toggle), run-on-edit, match count, and a structural line: "Matches `all`/`any` of N conditions · M actions" + "Open on the web to edit." (Derived by counting the parsed condition leaves / actions; no full describe.)

### `RulesManagerView` wiring

- Row: existing name + priority + active toggle, **+ `N×`** match count; keep swipe delete + backfill.
- Tap a row → if `simpleRuleForm(...)` non-nil → `RuleSheet(rule:)`; else → `RuleDetailView(rule:)`.
- `+` toolbar → `RuleSheet(rule: nil)`.

### Bug fix

`RulesManagerView` create path: emit `"mark_reviewed"` (not `"set_reviewed"`). The `simpleRuleForm` parser accepts both so legacy iOS rules remain editable (and an edit rewrites them to `mark_reviewed`).

## Facts (from survey — no engine change)

- `updateRule` patch: `name/priority/condition/actions/isActive/runOnEdit` (parity with web).
- `RulesEngine` actions include `mark_reviewed` (not `set_reviewed`); conditions are `all/any/not/leaf`.
- `Tx.appliedRuleIds: [String]?` is projected; web computes match count the same way.
- `RuleSummary` currently `{id, name, priority, isActive}`; query `SELECT id, name, priority, is_active FROM rules`.

## Testing

- **FinchCore (pure):**
  - `ruleMatchCounts`: count by rule id across appliedRuleIds; multi-rule txn increments each; other-ledger excluded; never-fired absent.
  - `simpleRuleForm`: single merchant-contains + set_category → parsed; single amount-gt + mark_reviewed → parsed; legacy `set_reviewed` → `.markReviewed`; `all`/`any` wrapper → nil; multi-action → nil; unsupported field (e.g. tag_id) → nil; unsupported action (e.g. add_tag) → nil; round-trip (parse → rebuild condition/actions JSON → re-parse equal).
  - (If the create/edit save builds condition/actions, a small builder-roundtrip test.)
- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests green.
- **Manual (sim):** edit a simple rule (change keyword/category/priority/runOnEdit) → persists + re-fires on backfill; a complex (web-made/seeded multi-condition) rule opens read-only; match counts show; a newly-created "mark reviewed" rule actually marks matched txns reviewed (bug fix).

## Out of scope

Multi-condition/-action builder; full rule description; lastApplied; live preview; legacy `set_reviewed` data migration; priority drag-reorder.
