# Multi-condition rule builder — CP2a (iOS Power Tools)

**Date:** 2026-06-25
**Status:** Design approved, pending implementation
**Scope:** iOS `RulesManagerView`/`RuleSheet` + `RuleForm`/`RuleParse` (FinchCore). **No rules-engine change.** iPad/Mac share the view. CP2a of the multi-condition builder — the **single-value / no-value entity fields + the three entity actions**. CP2b (array / multi-select ops) is a separate later effort.

## Problem

CP1 lets the iOS builder create/edit rules over simple-valued fields (merchant/note/amount/kind-is) + simple actions. Rules that reference an **entity** (a category, account, counterparty, currency, tag) or **day-of-month**, or that use the **add tag / remove tag / set counterparty** actions, still open **read-only** (`RuleParse.parse` returns nil). CP2a adds the single-value/no-value subset of those so they become editable, reusing inline pickers — no new multi-select UI.

## Goal

Make these **editable** in the builder (create + edit), reusing the existing array `RuleSheet`:

**Condition fields (new):**
| field | ops | editor | value shape |
|---|---|---|---|
| category_id | is, is_null | category Picker (is) / none (is_null) | string id / — |
| account_id | is | account Picker | string id |
| counterparty_id | is, is_null | counterparty Picker (is) / none (is_null) | string id / — |
| currency | is | currency Picker | string |
| tag_id | has | tag Picker | string id |
| date_dom | eq, gte, lte | number field (1–31) | int |

**Actions (new):** `add_tag` (tag Picker), `remove_tag` (tag Picker), `set_counterparty` (counterparty Picker).

A rule using only CP1 + CP2a fields/actions becomes editable; CP2b ops (`in`, `has_any`, `has_all`, `date_dow`), nested groups, `not`, `split` stay **read-only** (never flattened).

## Non-goals (CP2b / later)

- Array / multi-value ops: `category_id in`, `account_id in`, `kind in`, `tag_id has_any`/`has_all`, `date_dow in` — and the `LeafForm.values: [String]` model + the multi-select / weekday picker they need.
- Searchable `SearchablePickerRow` for these fields (inline menu Pickers now; searchable is a possible later upgrade).
- Nested groups, `not`, `split`; no engine change; no web change.

## Key decisions (locked)

1. **Single-value / no-value only** — no array model this checkpoint. The existing `LeafForm.value: String` carries the picked id or day number; `is_null` carries none.
2. **`is_null` emits no `value` key** (engine ignores value for is_null).
3. **`date_dom` → JSON int**; validated to **1–31** in `save()`.
4. **Inline menu `Picker`s** with the first-value-fallback binding (no blank state, per #288). `SearchablePickerRow` deferred.
5. **No engine change.**

## Detailed design

### `RuleForm.swift` (FinchCore)

- `LeafForm.Field` gains cases with engine-string raw values:
  `case categoryId = "category_id"`, `accountId = "account_id"`, `counterpartyId = "counterparty_id"`, `currency = "currency"`, `tagId = "tag_id"`, `dateDom = "date_dom"`.
- `opsAllowed(_:)`: category_id → `["is","is_null"]`; account_id → `["is"]`; counterparty_id → `["is","is_null"]`; currency → `["is"]`; tag_id → `["has"]`; date_dom → `["eq","gte","lte"]`. (CP1 fields unchanged.)
- `leafForm(_:)`:
  - `is_null` → `LeafForm(field, op: "is_null", value: "")` (no value read).
  - `date_dom` → `value = numStr(leaf.value?.asDouble ?? …)`; nil if no numeric value.
  - the entity fields (category_id/account_id/counterparty_id/currency/tag_id with is/has) → `value = leaf.value?.asString`; nil if missing.
- `leafJSON(_:)`:
  - `is_null` → `.object(["field": …, "op": .string("is_null")])` (**no `value` key**).
  - `date_dom` → `value: .int(Int(value) ?? 0)`.
  - entity fields → `value: .string(value)`.
  - (CP1 merchant/note → string; amount scalar → double; amount between → 2-elem array — unchanged.)
- `ActionForm.Kind` gains `addTag(String)`, `removeTag(String)`, `setCounterparty(String)`.
- `actionForm(_:)`: `add_tag`/`remove_tag` → read `raw["tagId"].asString`; `set_counterparty` → read `raw["counterpartyId"].asString`. (nil if missing.)
- `actionJSON(_:)`: `add_tag` → `{type:"add_tag", tagId}`; `remove_tag` → `{type:"remove_tag", tagId}`; `set_counterparty` → `{type:"set_counterparty", counterpartyId}`.

### `RuleSheet` (FinchApp)

- **`fieldLabel(_ Field) -> String`** (new) for the field Picker: merchant→"Merchant", note→"Note", amount→"Amount", kind→"Kind", category_id→"Category", account_id→"Account", counterparty_id→"Counterparty", currency→"Currency", tag_id→"Tag", date_dom→"Day of month". (Replaces `rawValue.capitalized`.)
- `opsFor(_:)`: add the new fields' ops (mirroring `opsAllowed`). `opLabel(_:)`: add `is_null`→"is not set", `has`→"has tag" (eq/gte/lte already present).
- `condRow` value-editor switch — new branches:
  - `.categoryId`: if op == `is_null` → no editor; else inline `Picker` over `store.pickableCategories` (first-fallback binding into `c.value`).
  - `.accountId`: inline `Picker` over `store.accounts` (name ?? id).
  - `.counterpartyId`: if `is_null` → none; else `Picker` over `store.counterparties`.
  - `.currency`: `Picker` over `store.availableDisplayCurrencies` (value = currency string).
  - `.tagId`: `Picker` over `store.tags`.
  - `.dateDom`: `TextField` (numberPad), binds `c.value`.
- `ActType` gains `addTag`, `removeTag`, `setCounterparty` (+ labels "Add tag"/"Remove tag"/"Set counterparty"); `ActRow` gains `tagId = ""`, `counterpartyId = ""`.
- `actRow` value-editor switch — new branches: `addTag`/`removeTag` → tag `Picker` (first-fallback into `tagId`); `setCounterparty` → counterparty `Picker` (first-fallback into `counterpartyId`).
- **First-value-fallback binding** (the #288 pattern) for every new entity Picker, so a fresh row shows a real selection.

### `save()` validation

- entity-`is`/`has` fields: value is the picked id; primed to first so non-empty (guard anyway → "Pick a …").
- `is_null`: no value; skip the value guard for that condition.
- `date_dom`: `guard let n = Int(value), (1...31).contains(n)` else "Enter a day 1–31."
- actions: `addTag`/`removeTag` need `tagId` (primed to first; guard → "Pick a tag."); `setCounterparty` needs `counterpartyId` (guard → "Pick a counterparty.").
- Build via `RuleParse.build`; create/update unchanged.

### Routing

`open()` already routes via `RuleParse.parse(...) != nil`. CP2a widens what parses → more rules editable; CP2b ops still nil → read-only `RuleDetailView`. Unchanged code.

## Facts (engine — no change; from survey)

- `evaluateLeaf` value shapes: category_id is→string / is_null→absent; account_id is→string; counterparty_id is→string / is_null→absent; currency is→string; tag_id has→string; date_dom eq/gte/lte→int (`asDouble`). `applyAction`: add_tag/remove_tag read `tagId`; set_counterparty reads `counterpartyId`.
- Store collections: `store.pickableCategories: [CategoryRow]` (id,name), `store.accounts: [AccountRow]` (id, name?), `store.counterparties: [Counterparty]` (id,name), `store.tags: [TagRow]` (id,name), `store.availableDisplayCurrencies: [String]`.
- `RuleForm.numStr` (public, from CP1) reused for date_dom formatting.

## Testing

- **FinchCore (`RuleParse`):**
  - parse+build each new field/op: category_id is (string), category_id is_null (build emits **no value key**), account_id is, counterparty_id is + is_null, currency is, tag_id has, date_dom eq/gte/lte (int round-trip).
  - parse+build the 3 actions (add_tag/remove_tag/set_counterparty); a multi-action mixing CP1+CP2a (e.g. set_category + add_tag).
  - **still-nil:** CP2b ops (`category_id in`, `tag_id has_any`, `date_dow in`) → nil (read-only until CP2b).
  - round-trip equality for a rule combining a CP2a condition + a CP2a action.
- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests green.
- **Manual (sim):** build "category is Groceries AND day-of-month ≤ 5 → add tag 'bills'"; backfill matches; edit it; a `category is_null` rule (no value editor) saves + matches uncategorized; a `tag_id has_any` (CP2b) rule still opens read-only.

## Out of scope (CP2b)

`in`/`has_any`/`has_all`/`date_dow` array ops + `values:[String]` model + multi-select/weekday pickers; searchable pickers; nested groups, `not`, `split`.
