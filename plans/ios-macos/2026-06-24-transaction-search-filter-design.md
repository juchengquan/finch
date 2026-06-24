# Transaction search & filter (iOS)

**Date:** 2026-06-24
**Status:** Design approved, pending implementation
**Scope:** iOS transaction feed (`ActivityFeedView`) — a filter sheet over the existing search, routed through the existing `selectTransactions` selector, plus a small optional tag filter on the engine.

## Problem

`ActivityFeedView` (reused by the Activity tab, the Ledger home feed, and "All
Transactions") only filters by **merchant text** (`.searchable` → a naive
`merchant.contains`). The engine's `Selectors.selectTransactions(_, ListOptions)`
already supports **direction (in/out), query, account, category, status, date
range, amount range** — none of it surfaced. **Tags** are the one filter neither
the selector nor the web supports yet.

## Goal

A **filter sheet** on the feed (account · category · tag · status · type · date
range · amount range) layered on the existing search, applied via
`selectTransactions`. A toolbar button shows when filters are active. Appears on all
three feed surfaces (it's one shared view).

## Design

### 1. Engine — optional `tagId` filter (parity-safe)

- **`ListOptions`** (in `Models.swift`) gains `tagId: String?` (init param, default
  `nil`).
- **`selectTransactions`** adds one filter line (alongside the existing ones):
  ```swift
  if let tag = opts.tagId { out = out.filter { ($0.tags ?? []).contains(tag) } }
  ```
- Default `nil` ⇒ no-op ⇒ existing callers and the web-parity selector fixtures are
  unchanged ⇒ **`ParityTests` green**. (`tx.tags` holds tag ids.) Single-tag only.

### 2. Filter model + sheet — new `TransactionFilterSheet.swift`

A value type for the filter state:

```swift
struct TxFilter: Equatable {
    var direction: String? = nil       // nil = all, "in", "out"
    var accountId: String? = nil
    var categoryId: String? = nil
    var tagId: String? = nil
    var status: String? = nil          // nil = all, "pending", "confirmed"
    var from: Date? = nil
    var to: Date? = nil
    var minAmount: Double? = nil
    var maxAmount: Double? = nil
    var isActive: Bool {               // any field set?
        direction != nil || accountId != nil || categoryId != nil || tagId != nil
        || status != nil || from != nil || to != nil || minAmount != nil || maxAmount != nil
    }
}
```

`TransactionFilterSheet(filter: Binding<TxFilter>)` — a `Form` with:
- **Type** — segmented All / In / Out (→ `direction`).
- **Account** — `SearchablePickerRow` with an "Any" option (→ `accountId`).
- **Category** — picker with "Any" (→ `categoryId`).
- **Tag** — picker over `store.tags` with "Any" (→ `tagId`).
- **Status** — segmented All / Pending / Confirmed (→ `status`).
- **Date range** — two optional `DatePicker`s (toggled on; → `from`/`to`).
- **Amount range** — two decimal `TextField`s (min/max; → `minAmount`/`maxAmount`).
- A **"Clear all"** button (`filter = TxFilter()`), plus Done/Cancel.

### 3. Feed wiring — `ActivityFeedView`

- New `@State private var filter = TxFilter()` and `@State private var showingFilter = false`.
- A **Filter toolbar button** (`line.3.horizontal.decrease.circle`, filled when
  `filter.isActive`) → `.sheet { TransactionFilterSheet(filter: $filter) }`.
- Replace `filteredTxns()` to build a `ListOptions` from `filter` + `searchQuery`
  and return `Selectors.selectTransactions(store.txns, opts)`:
  ```swift
  private func filteredTxns() -> [Tx] {
      let opts = ListOptions(
          ledgerId: store.activeLedgerId,
          direction: filter.direction,
          query: searchQuery.isEmpty ? nil : searchQuery,
          accountId: filter.accountId, categoryId: filter.categoryId, status: filter.status,
          from: filter.from.map(Self.day), to: filter.to.map(Self.day),
          minAmount: filter.minAmount, maxAmount: filter.maxAmount,
          tagId: filter.tagId)
      return Selectors.selectTransactions(store.txns, opts)
  }
  ```
  (`Self.day` formats a `Date` → "yyyy-MM-dd"; the feed already has day helpers.)
- Add `.onChange(of: filter) { _, _ in recompute() }` (mirrors the existing
  `searchQuery`/`visibleCount` onChange). `recompute()`'s day-section grouping and
  `visibleCount` paging are unchanged.

The engine selector already applies the active-ledger scope and the stable
date-desc sort, so the feed's manual ledger scoping in `filteredTxns` is replaced by
the selector's.

## Out of scope
- Saved filter presets; multi-tag (AND/OR) filtering; custom sort order; a
  counterparty filter; FTS / fuzzy search (still substring on merchant, as today).
- The "All Transactions"-only gating (filter shows on all three surfaces — intended).

## Testing

**Engine (FinchCore):**
- `selectTransactions` with `tagId` set returns only txns whose `tags` contains it;
  with `tagId == nil` the result is identical to today (guards the default path).
- `ParityTests` green (`swift test`).

**App (build + manual sim):**
- Open the feed → **Filter** button → set Type=Out + a Category → list narrows;
  the button shows active; **Clear all** resets it.
- Tag filter shows only tagged txns; date range + amount range narrow correctly;
  combine with the search box.
- Verify on the Activity tab, the Ledger home feed, and "All Transactions".

## Notes
- Single-tag filter (`tagId`), matching the new engine field.
- PR targets `feat/frontend`.
