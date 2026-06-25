# Tag colors on transaction rows

**Date:** 2026-06-25
**Status:** Design approved, pending implementation
**Scope:** Show a transaction's tags as small colored chips on its feed row (`TxRow`). UI-only, no engine change.

## Problem

Tags gained per-tag colors (tag admin), and transactions carry tag ids
(`Tx.tags`) — but the feed's `TxRow` shows **no tags at all** (only the category
chip). So tags (and their colors) aren't visible while browsing.

## Design

In `TxRow` (in `ActivityTab.swift`), on the second line (currently just the category
capsule), render the transaction's tags as small colored chips on the same line.

- A computed map of the row's tags to their `TagRow` (for name + color):
  ```swift
  private var rowTags: [TagRow] {
      guard let ids = txn.tags, !ids.isEmpty else { return [] }
      return ids.compactMap { id in store.tags.first { $0.id == id } }
  }
  ```
- Wrap the existing category chip + the tag chips in one `HStack(spacing: 4)`:
  - Category chip unchanged (`.quaternary` capsule).
  - For each of the **first 3** `rowTags`, a capsule:
    ```swift
    Text(tag.name).font(.caption2)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background((Color(hex: tag.color ?? "") ?? .secondary).opacity(0.2), in: Capsule())
        .foregroundStyle(Color(hex: tag.color ?? "") ?? .secondary)
    ```
    (tinted background + colored name; `Color(hex:)` is `Common/Color+Hex.swift`,
    same palette as the tag admin; `.secondary` fallback when a tag has no color.)
  - If `rowTags.count > 3`, a `Text("+\(rowTags.count - 3)").font(.caption2).foregroundStyle(.secondary)` overflow chip.
- Appears wherever `TxRow` is used (Activity tab, Ledger home, "All Transactions").

## Out of scope
- Coloring the tag controls in the Add/Edit sheets or the transaction filter
  (separate follow-ups).
- Re-styling the category chip; any engine/data change (`Tx.tags`, `TagRow.color`
  already exist).

## Testing

**Build:** FinchApp (iOS) + FinchMac (macOS) — `TxRow` is shared.

**Manual (sim):** a transaction with one or more tags shows colored tag chips on its
row (names tinted by tag color; uncolored tags fall back to gray); >3 tags shows
"+N". Untagged rows are unchanged.

## Notes
- Pure-view change; `store.tags` is small, so the per-row `first { … }` lookups are
  fine.
- PR targets `feat/frontend`.
