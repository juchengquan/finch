# Merchant (counterparty) detail screen

**Date:** 2026-06-25
**Status:** Design approved, pending implementation
**Scope:** A detail screen for a merchant — aggregate stats + its transactions — reached from the Merchants admin. One additive engine selector; the rest is UI.

## Problem

The Merchants admin (`CounterpartyAdminView`) lists merchants with usage counts
(`counterpartyTxCounts`) but you **can't drill into a merchant** to see its
transactions or totals. The matching that defines "a merchant's transactions"
already exists inside `counterpartyTxCounts` — by `counterpartyId` **or** normalized
merchant **name** — but isn't exposed as a transaction list.

## Design

### 1. Engine — `merchantTransactions` selector (additive)

```swift
/// A merchant's transactions: linked by counterpartyId, or matched by normalized
/// merchant name (mirrors counterpartyTxCounts' matching). Newest first; includes pending.
public static func merchantTransactions(_ txns: [Tx], _ cp: Counterparty, _ ledgerId: String) -> [Tx]
```

- Match a `Tx` to `cp` when `tx.counterpartyId == cp.id`, **or** (no/!matching
  counterpartyId) `tx.merchant`'s normalized name == `cp.name`'s normalized name
  — the same rule `counterpartyTxCounts` uses.
- Active-ledger scoped; sorted **date-desc** (then time-desc), like the feed.
- **Includes pending** (the detail shows everything for the merchant).
- Pure/additive ⇒ existing selectors unchanged ⇒ `ParityTests` green. Unit-tested
  (id-match, name-match, ledger scoping, ordering).

### 2. New screen — `CounterpartyDetailView(counterparty:)`

A `List` with:
- **Summary section** over `merchantTransactions(...)`:
  - **Transactions:** the count.
  - **Total:** `store.displayMoneyBase(sum of tx.amount)` (net).
  - **Average:** `displayMoneyBase(total / count)`.
- **Transactions section:** a flat, date-desc list — each transaction rendered with
  the existing **`TxRow`**, wrapped in a `Button` that opens the **Edit** sheet
  (`@State editing: Tx?` + `.sheet(item:) { EditTransactionSheet(txn:) }`).
- `.navigationTitle(counterparty.name)`.

### 3. Entry point — navigate from `CounterpartyAdminView`

Make each merchant row a **`NavigationLink { CounterpartyDetailView(counterparty: cp) }`**
showing name + verified seal + the `N×` count. The inline **Verify** button is
removed (it duplicates the swipe/context-menu Verify, which stays) so the row reads
as a tappable detail link; Rename/Verify/Delete remain in swipe + context menu.

## Out of scope
- A spend trend / sparkline on the detail.
- Reaching the detail from a transaction's merchant text (rows aren't linked that way).
- Adding a counterparty filter to the main feed's filter sheet (separate deferred item).
- Editing the merchant (verify/rename/delete) **from** the detail — those stay in the admin.

## Testing

**Engine (FinchCore):**
- `merchantTransactions` returns txns linked by `counterpartyId` and by matching
  name; excludes other-ledger and non-matching txns; newest-first. `ParityTests` green.

**App (build + manual sim):**
- Merchants admin → tap a merchant → detail shows its **count / total / average** and
  a date-desc list of its transactions; tapping one opens Edit.
- Verify/Rename/Delete still work from the row's swipe / context menu.
- iOS + macOS build (shared `TxRow` / nav).

## Notes
- `store.merchants` is the active-ledger counterparty list; `Counterparty` =
  `{id, ledgerId, name, isVerified}`.
- PR targets `feat/frontend`.
