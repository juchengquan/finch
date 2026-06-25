# Feed: sort options

**Date:** 2026-06-25
**Status:** Design approved, pending implementation
**Scope:** A sort control on the transaction feed (date / amount, each direction). UI-only — view-level sort over the existing selector. No engine change.

## Problem

The feed is always date-descending (`selectTransactions` sorts newest-first). There's
no way to reorder — e.g. oldest-first, or biggest transactions first.

## Design

Sort the filtered result **in the view** (the feed is the only consumer that needs an
ordering choice; threading a `sort` field through `ListOptions` is avoided — it's
decoded by the parity fixtures and fiddly, per #314).

### 1. `TxSort` enum (in `ActivityTab.swift`)

```swift
enum TxSort: String, CaseIterable, Identifiable {
    case dateDesc, dateAsc, amountDesc, amountAsc
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dateDesc:   return "Newest first"
        case .dateAsc:    return "Oldest first"
        case .amountDesc: return "Largest amount"
        case .amountAsc:  return "Smallest amount"
        }
    }
    func sorted(_ txns: [Tx]) -> [Tx] {
        switch self {
        case .dateDesc:   return txns.sorted { $0.date != $1.date ? $0.date > $1.date : ($0.time ?? "") > ($1.time ?? "") }
        case .dateAsc:    return txns.sorted { $0.date != $1.date ? $0.date < $1.date : ($0.time ?? "") < ($1.time ?? "") }
        case .amountDesc: return txns.sorted { abs($0.amount) != abs($1.amount) ? abs($0.amount) > abs($1.amount) : $0.date > $1.date }
        case .amountAsc:  return txns.sorted { abs($0.amount) != abs($1.amount) ? abs($0.amount) < abs($1.amount) : $0.date > $1.date }
        }
    }
}
```
Amount sorts by **magnitude** (`abs`), so the largest transactions surface regardless
of income/expense sign; date-desc breaks ties. `dateDesc` matches today's behavior.

### 2. Feed state + apply

In `ActivityFeedView`:
- `@State private var sort: TxSort = .dateDesc` (separate from `TxFilter` — "Clear
  filters" must not reset the sort).
- `filteredTxns()` returns `sort.sorted(Selectors.selectTransactions(base, opts))`
  (sort the full filtered list before pagination).
- Recompute on change: add `.onChange(of: sort) { _, _ in recompute() }`.

### 3. Toolbar Sort menu

A `Menu` (icon `arrow.up.arrow.down`) next to the Filter button, holding an inline
`Picker` bound to `$sort` (so the current option shows a checkmark):

```swift
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(TxSort.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort")
            }
```

## Out of scope
- Persisting the sort across launches (session-only `@State`, like the filter).
- Sorting anywhere other than the feed; any engine/`ListOptions` change.
- A signed-amount sort (magnitude only).

## Testing

**App (build + manual sim — UI-only):**
- Feed → Sort menu lists the four options (current checkmarked); pick **Oldest first**
  → list reverses; **Largest amount** → biggest-magnitude transactions first.
- Sort survives a filter change / Clear; combines with an active filter.
- iOS + macOS build.

No engine test — view-level sort over the existing (tested) selector.

## Notes
- `Tx.amount` is a `Double` in the active-ledger base; `abs` is on the raw amount
  (ordering only — display still converts via `displayMoneyBase`).
- PR targets `feat/frontend`.
