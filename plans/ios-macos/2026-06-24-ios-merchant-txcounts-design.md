# Merchant transaction counts (iOS Power Tools)

**Date:** 2026-06-24
**Status:** Design approved, pending implementation
**Scope:** iOS `CounterpartyAdminView` (Settings › Power Tools › Merchants) + one new pure selector in FinchCore. **No engine/schema/model/projection change.** iPad/Mac share the view.

## Problem

The Merchants list shows name + verified state but not **how often each merchant is used**. The web shows a `N×` count, but that number is **decorative static seed data** (`MOCK_BY_ID[...].txCount`), not a live count — so there's no meaningful parity to match. iOS can show a **real** count computed from the user's transactions, which is more useful (e.g. spotting unused merchants to clean up).

## Goal

- Show a live **`N×` usage count** next to each merchant in `CounterpartyAdminView` (muted, monospaced, like the web), hidden when 0.
- Count **all non-pending transactions** attributed to the merchant (money out *and* in) — decision **(A)**, the honest "used N times" number — not the expense-only `merchantStats`.

## Non-goals

- No engine/schema/model/projection change — the count is derived from existing `store.txns` + `store.merchants`.
- No new stored field; nothing persisted.
- No change to add/rename/verify/delete/search behavior.

## Key decisions (locked)

1. **Count all non-pending txns** attributed to the merchant (decision A), regardless of kind — not the expense-only `merchantStats` count.
2. **Attribution** mirrors `merchantKey`: a txn belongs to a counterparty by **`counterpartyId`** when set and known, else by **normalized name** (`merchant.trimmed.lowercased == counterparty.name.trimmed.lowercased`). A txn matching neither is uncounted.
3. **Live, view-computed** (no caching needed for a short list) via a new pure selector.

## Detailed design

### New selector — `Selectors.counterpartyTxCounts`

`ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift`:

```swift
/// Per-counterparty usage count: non-pending txns in `ledgerId` attributed to a
/// counterparty by counterpartyId (when set & known) else by normalized name.
/// Keyed by counterparty id; absent/zero for unused merchants.
public static func counterpartyTxCounts(_ txns: [Tx], _ counterparties: [Counterparty], _ ledgerId: String) -> [String: Int] {
    let idSet = Set(counterparties.map(\.id))
    // normalized name → counterparty id (first wins on duplicate names)
    var byName: [String: String] = [:]
    for c in counterparties {
        let n = c.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !n.isEmpty, byName[n] == nil { byName[n] = c.id }
    }
    var out: [String: Int] = [:]
    for t in txns {
        if ledgerOf(t) != ledgerId { continue }
        if (t.pending ?? false) { continue }
        let cpId: String?
        if let cid = t.counterpartyId, idSet.contains(cid) { cpId = cid }
        else {
            let n = t.merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            cpId = n.isEmpty ? nil : byName[n]
        }
        if let id = cpId { out[id, default: 0] += 1 }
    }
    return out
}
```

(Note: unlike `merchantStats`, this counts **all kinds** — no `expense`-only filter — per decision A. `ledgerOf` and the `pending` guard already exist in this file.)

### `CounterpartyAdminView` row

Compute the dict once per render and index per row:
```swift
private var txCounts: [String: Int] {
    Selectors.counterpartyTxCounts(store.txns, store.merchants, store.activeLedgerId)
}
```
In the row, after the name (before/near the verified badge), when `count > 0`:
```swift
if let n = txCounts[cp.id], n > 0 {
    Text("\(n)×").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
}
```
(Exact placement follows the current row's `HStack`; keep the existing name, verified badge, and trailing actions.)

## Facts (no change needed)

- `Counterparty`: `id, ledgerId, name, isVerified`. `store.merchants` = active-ledger counterparties.
- `Tx`: `merchant: String`, `counterpartyId: String?`, `pending`. `merchantKey` = `"cp:<id>"` if `counterpartyId` set else `"m:<lowercased name>"`.
- `Selectors.ledgerOf(_:)` exists; `merchantStats` is expense-only (unchanged, still used for anomaly detection).

## Testing

- **FinchCore (pure selector):**
  - id-linked txns counted to the right counterparty;
  - name-fallback (no `counterpartyId`, merchant name matches) counted;
  - **pending excluded**; **other-ledger excluded**;
  - unused merchant → absent/0;
  - case/whitespace-insensitive name match;
  - a txn whose `counterpartyId` is unknown but whose name matches → counted by name.
- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests green.
- **Manual (sim):** seed a couple merchants with transactions → `N×` shows; an unused merchant shows none.

## Out of scope

Merchant color/badge; merge; sorting by usage; any non-merchant screen.
