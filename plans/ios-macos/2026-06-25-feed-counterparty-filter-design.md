# Feed: filter by merchant (counterparty)

**Date:** 2026-06-25
**Status:** Design approved, pending implementation
**Scope:** Add a "Merchant" filter to the transaction feed's filter sheet. UI-only — composes existing selectors. No engine change.

## Problem

The feed's filter sheet (#286) filters by type/account/category/tag/status/date/
amount + text search, but not by **merchant (counterparty)**. The merchant detail
screen (#306) already defines "a merchant's transactions" via id-or-name matching
(`Selectors.merchantTransactions`); the feed should offer the same as a filter.

## Design

UI-only — reuse `merchantTransactions` (id-or-name, #306) + `selectTransactions`
(#286) by composing them.

### 1. `TxFilter` gains `counterpartyId`

In `TransactionFilterSheet.swift`:

```swift
    var counterpartyId: String? = nil
```
and add it to `isActive`:

```swift
    var isActive: Bool {
        direction != nil || accountId != nil || categoryId != nil || tagId != nil
            || counterpartyId != nil
            || status != nil || from != nil || to != nil || minAmount != nil || maxAmount != nil
    }
```

### 2. Filter sheet — a "Merchant" picker

In the sheet's picker section (next to Account/Category/Tag), when
`!store.merchants.isEmpty`:

```swift
                    if !store.merchants.isEmpty {
                        Picker("Merchant", selection: $draft.counterpartyId) {
                            Text("Any").tag(String?.none)
                            ForEach(store.merchants) { Text($0.name).tag(String?.some($0.id)) }
                        }
                    }
```

### 3. Feed — compose in `filteredTxns()`

In `ActivityFeedView.filteredTxns()`, narrow the base list to the selected
merchant's transactions (id-or-name) before applying the rest:

```swift
    private func filteredTxns() -> [Tx] {
        let base = filter.counterpartyId.map {
            Selectors.merchantTransactions(store.txns, store.merchants, $0, store.activeLedgerId)
        } ?? store.txns
        let opts = ListOptions(
            ledgerId: store.activeLedgerId,
            direction: filter.direction,
            query: searchQuery.isEmpty ? nil : searchQuery,
            accountId: filter.accountId, categoryId: filter.categoryId, status: filter.status,
            from: filter.fromYMD, to: filter.toYMD,
            minAmount: filter.minAmount, maxAmount: filter.maxAmount, tagId: filter.tagId)
        return Selectors.selectTransactions(base, opts)
    }
```

`merchantTransactions` already active-ledger-scopes and date-sorts; `selectTransactions`
re-applies the (same) ledger scope + sort harmlessly, plus the other filters. The
existing **count caption** and **no-results state** (from the feed-polish work) reflect
the merchant filter automatically (they read `filteredTxns()`/`sections`), and **Clear
filters & search** resets it (`filter = TxFilter()`).

## Out of scope
- A deep-link from the merchant detail (#306) into the pre-filtered feed (separate
  follow-on).
- Any engine / `ListOptions` change — both selectors already exist.

## Testing

**App (build + manual sim — UI-only):**
- Feed → Filter → **Merchant** picker lists merchants; pick one → the feed shows only
  that merchant's transactions (matching the merchant detail's list); the Filter icon
  shows active; **Clear** resets.
- Combine with another filter (e.g. Type = Out) → both apply.
- iOS + macOS build.

No engine test — `merchantTransactions` is already covered (#306).

## Notes
- `store.merchants` = the active-ledger counterparty list; `Counterparty.name` is the label.
- PR targets `feat/frontend`.
