# Transaction feed: result count + no-results empty state + bulk confirm/delete

**Date:** 2026-06-25
**Status:** Design approved, pending implementation
**Scope:** `ActivityFeedView` only. UI-only — no engine/DB/parity changes.

## Problem

Three small gaps on the transaction feed (which gained search + filtering in #286):
1. **No result count** — you can't tell how many transactions match the current
   search/filter.
2. **No "no results" state** — when a search/filter excludes everything (but the
   ledger *has* transactions), the list is just a header + blank space. The existing
   `EmptyState` only covers an empty *ledger*.
3. **Bulk actions are thin** — Select mode's bottom bar only offers **Recategorize**.
   There's no bulk **delete** or **confirm**.

The engine already has single `deleteTransaction` / `confirmTransaction` (and
`confirmAllPending`); bulk-of-selected is a UI-side loop over those — no engine
change.

## Design

All changes are in `ActivityFeedView`.

### 1. Result count

- `recompute()` already computes `let f = filteredTxns()`. Store its count:
  `@State private var filteredCount = 0` (set `filteredCount = f.count`).
- Show a subtle caption at the **top of the list** (e.g. a `Section` or a plain row
  above the day sections), always visible:
  `Text("\(filteredCount) transaction\(filteredCount == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)`.
  Because `filteredTxns()` applies the active search + filter, this reads as the
  filtered count whenever a filter/search is active.

### 2. No-results empty state

- A computed `hasActiveQuery: Bool` = `!searchQuery.isEmpty || filter.isActive`.
- When `!store.txns.isEmpty && sections.isEmpty` (ledger has transactions, but the
  current query matches none), render a no-results view **in place of** the day
  sections (keeping the `headerSection` for the Ledger home):
  ```swift
  ContentUnavailableView {
      Label("No matching transactions", systemImage: "line.3.horizontal.decrease.circle")
  } description: {
      Text("Try adjusting your search or filters.")
  } actions: {
      if hasActiveQuery { Button("Clear filters & search") { searchQuery = ""; filter = TxFilter() } }
  }
  ```
  (Embedded as a `Section`/row inside the `List` so the header stays; the count
  caption shows "0 transactions".)

### 3. Bulk Confirm + Delete

Select mode currently shows one bottom-bar item (`Recategorize \(selected.count)`).
Add two more, gated on a non-empty selection:

- **Confirm \(selected.count)** — `run { for id in selected { try store.apply(.confirmTransaction, Args(["id": .string(id)])) } }`, then exit selection (`isSelecting = false; selected.removeAll()`). No-op on already-confirmed rows is harmless.
- **Delete \(selected.count)** — destructive; opens a `confirmationDialog` ("Delete N transactions?"); on confirm, `run { for id in selected { try store.deleteTransaction(id) } }` (also unlinks each receipt's files), then exit selection.

Layout: three bottom-bar buttons — **Confirm · Recategorize · Delete** (Delete styled
`.destructive`/red). Each existing per-row helper (`confirm`, `delete`) already wraps
`run { … }`; the bulk variants loop the same calls.

Trade-off: each `store.apply` / `deleteTransaction` re-projects, so a large selection
does N reprojections. Acceptable for typical selections; a batched-apply (one write +
one reprojection) is a clean future optimization, out of scope here.

## Out of scope
- Bulk **tag** / **account** edits; a true batched engine action (`bulkDelete`/`bulkConfirm`).
- Per-item failure handling beyond the existing `run { }` error alert (the loop stops
  on the first error and surfaces it — acceptable; deletes/confirms rarely fail).
- The "all-empty-ledger" `EmptyState` (unchanged).

## Testing

**App (build + manual sim — UI-only):**
- Apply a filter that matches some rows → the top caption shows the **count**; matches
  none → **"No matching transactions"** + **Clear** resets search + filter.
- Select mode → pick a few rows → **Confirm N** clears their pending state; **Delete N**
  → confirm dialog → rows (and any receipts) are removed; **Recategorize N** unchanged.
- Count caption updates as the selection/filter changes.

No engine tests (no engine change). Existing suite stays green.

## Notes
- `ContentUnavailableView` is iOS 17+ (our floor) — fine.
- PR targets `feat/frontend`.
