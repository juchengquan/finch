# Multi-condition rule builder — CP2b (iOS Power Tools)

**Date:** 2026-06-25
**Status:** Design approved, pending implementation
**Scope:** iOS `RulesManagerView`/`RuleSheet` + `RuleForm`/`RuleParse` (FinchCore). **No rules-engine change.** iPad/Mac share the view. CP2b — the **array / multi-value condition ops**. This is the final rules-parity checkpoint.

## Problem

CP1 + CP2a made flat all/any rules over single-valued fields + entity actions editable. The remaining gap is the **array-valued condition ops**: `category_id in`, `account_id in`, `kind in`, `tag_id has_any` / `has_all`, and `date_dow in`. Rules using these still open **read-only** (`RuleParse.parse` returns nil). CP2b adds them with a reusable multi-select editor. No new actions (the three entity actions landed in CP2a).

## Goal

Make these **editable** (create + edit) in the existing array `RuleSheet`:

| field | op(s) | editor | JSON value shape |
|---|---|---|---|
| category_id | in | multi-select (categories) | string[] |
| account_id | in | multi-select (accounts) | string[] |
| kind | in | multi-select (kinds) | string[] |
| tag_id | has_any, has_all | multi-select (tags) | string[] |
| date_dow | in | weekday chips (S–S) | int[] (0=Sun … 6=Sat) |

After CP2b the read-only fallback only remains for **nested groups / `not` / `split`** — every flat rule the web builds becomes editable on iOS.

## Non-goals

- Nested condition groups, `not`, the `split` action — remain read-only.
- No new actions; no engine change; no web change.
- No change to CP1/CP2a single-value behavior.

## Key decisions (locked)

1. **`LeafForm.values: [String]`** carries the array payload (default `[]`); single-value ops keep using `value`. `date_dow` weekday indices are stored as strings in `values` and built as a JSON **int** array.
2. **Multi-select UX:** a reusable **pushed sub-screen** (a row "Label: N selected" → a searchable checkmark list) for category/account/kind/tag; **inline weekday chips** for `date_dow`.
3. **Weekday convention:** engine `dayOfWeek` = `Calendar(.weekday, UTC) - 1` → **0 = Sunday … 6 = Saturday**; chips labelled `S M T W T F S`.
4. **`has_any` and `has_all`** share the same tag multi-select; the op picker distinguishes them.
5. **No engine change.**

## Detailed design

### `RuleForm.swift` (FinchCore)

- `LeafForm`: add `public var values: [String]` (init default `[]`). `LeafForm.Field`: add `case dateDow = "date_dow"`.
- `opsAllowed`: `category_id → ["is","is_null","in"]`, `account_id → ["is","in"]`, `kind → ["is","in"]`, `tag_id → ["has","has_any","has_all"]`, `dateDow → ["in"]`. (CP1/CP2a entries otherwise unchanged.)
- `leafForm`: after the `is_null` early return, handle the array ops **before** the scalar paths:
  - if `op ∈ {"in","has_any","has_all"}`: require `case .array(let arr)? = leaf.value`; for `dateDow` → `values = arr.compactMap { $0.asDouble.map { numStr($0) } }` (ints as strings); else → `values = arr.compactMap { $0.asString }`. Require non-empty (else nil). Return `LeafForm(field, op, value: "", values: values)`.
  - (scalar/between/entity paths unchanged.)
- `leafJSON`: after the `is_null` no-value branch, handle array ops:
  - if `op ∈ {"in","has_any","has_all"}`: `value = field == .dateDow ? .array(values.map { .int(Int($0) ?? 0) }) : .array(values.map { .string($0) })`.
  - (amount/dateDom/default unchanged.)
- `parse`/`build` bodies unchanged; `actionForm`/`actionJSON` unchanged (no new actions).

### `RuleSheet` (FinchApp)

- `CondRow` gains `var values: [String] = []`; `init` prefill maps `lf.values`; `save()` passes it into `LeafForm`.
- `opsFor`: mirror `opsAllowed` (add `in`/`has_any`/`has_all` to the relevant fields; add `dateDow → ["in"]`). `opLabel`: add `in`→"in", `has_any`→"has any of", `has_all`→"has all of". `fieldLabel`: add `dateDow`→"Day of week".
- **`MultiSelectField`** (new, reusable): a row showing `title` + "N selected" (or "None"), as a `NavigationLink` pushing **`MultiSelectList`** — a `searchable` `List` of `[PickItem]` with a checkmark per selected id, toggling a `Binding<[String]>`. Cross-platform (`NavigationLink` + `.searchable`).
- **Weekday chips** (new): an inline `HStack` of 7 tappable cells (labels `["S","M","T","W","T","F","S"]`, index = weekday 0–6) toggling membership of the index string in `Binding<[String]>`; selected cells use the accent color.
- `condRow` branches by op:
  - `.kind`: `op == "in"` → `MultiSelectField` over kind items; else single kind Picker.
  - `.categoryId`: `is_null` → no editor; `in` → `MultiSelectField`(categories); else `entityPicker`.
  - `.accountId`: `in` → `MultiSelectField`(accounts); else `entityPicker`.
  - `.tagId`: `has` → `entityPicker`; else (`has_any`/`has_all`) → `MultiSelectField`(tags).
  - `.dateDow`: weekday chips.
  - `.counterpartyId`/`.currency` unchanged (CP2a).

### `save()` validation

- For an array op, `guard !c.values.isEmpty else { errorMessage = "Select at least one value."; return }`; append `LeafForm(field: c.field, op: c.op, value: value, value2: value2, values: c.values)`.
- date_dow chips only produce valid 0–6 indices; no extra validation.

### Routing

`open()` unchanged. CP2b widens `RuleParse.parse` acceptance → these rules become editable; only nested/`not`/`split` still → nil → `RuleDetailView`.

## Facts (engine — no change; verified)

- `evaluateLeaf` value shapes: category_id/account_id/kind `in` → string[] (`asStringArray`); tag_id `has_any`/`has_all` → string[]; `date_dow in` → int[] read via `asDouble` (`utcCal.component(.weekday) - 1`, 0=Sun). `applyAction` unchanged.
- Store collections (CP2a): `store.pickableCategories`, `store.accounts` (name `String?`), `store.counterparties`, `store.tags`, `store.availableDisplayCurrencies`; `kindValues` (expense/income/transfer/refund/adjustment). `PickItem`/`entityPicker`/`firstId`/`fieldLabel` exist.

## Testing

- **FinchCore (`RuleParse`):**
  - parse+build: category_id `in` (string array), account_id `in`, kind `in`, tag_id `has_any` + `has_all`, `date_dow in` (**int** array: `[0,6]` round-trips through `values:["0","6"]`).
  - a mixed rule (e.g. all of: merchant contains + category_id in + date_dow in) with a CP2a action — round-trip equality.
  - still-nil: nested all-in-all, `not` (CP2b doesn't change that).
- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests green.
- **Manual (sim):** build "all of: **Category in** {A,B} AND **Day of week in** {Sat,Sun} → add tag"; the multi-select pushes a searchable checkmark list; weekday chips toggle; backfill matches; edit prefills the selections; tag `has any`/`has all` selectable; a nested/`not` rule still opens read-only.

## Out of scope

Nested groups, `not`, `split`; new actions; engine/web changes.
