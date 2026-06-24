# Tag & Category usage counts (iOS Power Tools)

**Date:** 2026-06-24
**Status:** Design approved, pending implementation
**Scope:** iOS `TagAdminView` + `CategoryAdminView` (Settings › Power Tools) + two new pure selectors in FinchCore. **No engine/schema/model/projection change.** iPad/Mac share the views. Extends the merchant `N×` pattern (#274) to tags and categories.

## Problem

Merchants now show a live `N×` usage count (#274); tags and categories don't. The web shows no transaction-usage count for either (the categories page shows a structural "N subcategories", not tx usage; tags show nothing). iOS can show a real, live count — useful for spotting unused tags/categories to clean up.

## Goal

- `TagAdminView` row: a live `N×` count = non-pending transactions tagged with that tag.
- `CategoryAdminView` row: a live `N×` count = non-pending transactions filed in that category (**direct** — no descendant rollup).
- Both muted/monospaced, **hidden when 0**, mirroring the merchant row.

## Non-goals

- No engine/schema/model/projection change — derived live from `store.txns`.
- **No descendant rollup for categories** (decision: direct count only). A pure grouper parent with no direct txns shows no count.
- No sorting by usage; no change to add/edit/delete/search/reorder/drag behavior.

## Key decisions (locked)

1. **Direct count for categories** (not descendant rollup).
2. **Count = all non-pending txns** attributed to the tag/category (consistent with merchants).
3. **Bundle tags + categories** in one spec/plan/PR (parallel, tiny).
4. **Splits:** a txn with split legs is attributed to its split legs' categories; a txn without splits to its `tx.category` (mirrors `categorySpend`). A txn counts once per distinct category it touches.

## Detailed design

### New selectors — `Selectors` (FinchCore `Selectors.swift`)

Mirror `counterpartyTxCounts` (added in #274), placed near it; reuse `ledgerOf`.

```swift
/// Per-tag usage count: non-pending txns in `ledgerId` tagged with the tag.
/// Keyed by tag id (tx.tags holds tag ids); absent for unused tags.
public static func tagTxCounts(_ txns: [Tx], _ ledgerId: String) -> [String: Int] {
    var out: [String: Int] = [:]
    for t in txns {
        if ledgerOf(t) != ledgerId { continue }
        if (t.pending ?? false) { continue }
        for tagId in (t.tags ?? []) { out[tagId, default: 0] += 1 }
    }
    return out
}

/// Per-category usage count (DIRECT, no descendant rollup): non-pending txns in
/// `ledgerId` whose category leg(s) reference the category. A split txn is
/// attributed to its split legs' categoryIds; otherwise to `tx.category`. Counts
/// each txn once per distinct category. Keyed by category id; absent for unused.
public static func categoryTxCounts(_ txns: [Tx], _ ledgerId: String) -> [String: Int] {
    var out: [String: Int] = [:]
    for t in txns {
        if ledgerOf(t) != ledgerId { continue }
        if (t.pending ?? false) { continue }
        var cats = Set<String>()
        if let splits = t.splits, !splits.isEmpty {
            for s in splits { if let c = s.categoryId { cats.insert(c) } }
        } else if let c = t.category {
            cats.insert(c)
        }
        for c in cats { out[c, default: 0] += 1 }
    }
    return out
}
```

### `TagAdminView` row

Compute `let counts = Selectors.tagTxCounts(store.txns, store.activeLedgerId)` once per render; in the row (which already shows a color dot + name), after the name:
```swift
if let n = counts[tag.id], n > 0 {
    Text("\(n)×").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        .accessibilityLabel("\(n) transactions")
}
```

### `CategoryAdminView` tree row

Compute `let counts = Selectors.categoryTxCounts(store.txns, store.activeLedgerId)` once per render (alongside the existing forest build); in the row, after the name (before the create-child `+`):
```swift
if let n = counts[c.id], n > 0 {
    Text("\(n)×").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        .accessibilityLabel("\(n) transactions")
}
```

## Facts (no change needed)

- `Tx.tags: [String]?` holds **tag ids** (`entry_tags(entry_id, tag_id)` → projected onto `Tx.tags`).
- `Tx.category: String?` holds the **category id** (what `categorySpend` groups by); `TxSplit.categoryId` for split legs.
- `Selectors.ledgerOf(_:)` + the `pending` guard already exist; `counterpartyTxCounts` (#274) is the direct precedent.

## Testing

- **FinchCore (pure selectors):**
  - `tagTxCounts`: count by tag id; a multi-tag txn increments each of its tags; pending excluded; other-ledger excluded; untagged/unused → absent.
  - `categoryTxCounts`: direct count by `tx.category`; **split legs counted** (a 2-leg txn across 2 categories increments both); splits **override** `tx.category` (a split txn's own `category` is not counted); a 2-leg-same-category txn counts once; pending excluded; other-ledger excluded; unused → absent; **no descendant rollup** (a parent with only child txns is absent/0).
- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests green.
- **Manual (sim):** with seeded data, a used tag/category shows `N×`; an unused one shows none; a grouper parent category shows no count while its leaves do.

## Out of scope

Descendant rollup; sort-by-usage; tag/category color or icon changes; any non-tag/category screen.
