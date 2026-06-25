# Edit Transaction: counterparty suggestions

**Date:** 2026-06-25
**Status:** Design approved, pending implementation
**Scope:** Bring the Add form's merchant counterparty suggestions ("pick / Create") to the Edit form's Merchant field. UI-only, mirrors #264. No engine change.

## Problem

The Add form (since #264) offers counterparty **suggestions** under the Merchant
field — tap an existing counterparty, or **Create "<name>"** for a new one — and the
engine resolves merchant→counterparty by name on save. The **Edit** form's Merchant
field is a plain `TextField` with none of that; it only benefits from the engine's
on-save name resolution (so you can't see matches or create a new merchant inline).

## Design

Mirror #264's Add-form members into `EditTransactionSheet` (near-verbatim):

- **State:** `@State private var createCounterpartyOnSave = false`.
- **`matchingCounterparties`** — top 5 `store.counterparties` whose name contains the
  typed merchant text, excluding an exact match (same as Add).
- **`merchantSuggestionRows`** — gated `txn.kind != "transfer"` and non-empty text:
  - a `Button` per match → `pickCounterparty(cp.name)`;
  - a **`Create "<name>"`** `Button` when no exact-name match → `createCounterpartyOnSave = true`.
- **`pickCounterparty(_ name:)`** — sets `merchant = name`; `createCounterpartyOnSave = false`.
- Render `merchantSuggestionRows` immediately **after** the Merchant `TextField` row.
- Reset the flag on text change: `.onChange(of: merchant) { _, _ in createCounterpartyOnSave = false }`.

(Edit's gate is `txn.kind != "transfer"`, matching Add's expense/income/refund intent;
transfers have a "Transfer" description, not a payee.)

### Save

In `save()`, **before** `store.apply(.updateTransaction, …)`, add (mirroring #264's
Add save):

```swift
        if createCounterpartyOnSave {
            let cpName = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cpName.isEmpty,
               !store.counterparties.contains(where: { $0.name.caseInsensitiveCompare(cpName) == .orderedSame }) {
                try store.apply(.createCounterparty, Args(["ledgerId": .string(store.activeLedgerId), "name": .string(cpName)]))
            }
        }
```

The `updateTransaction` that follows already patches `merchant`; the engine resolves
the (now-existing) merchant name to its counterparty — so picking a match links it,
and "Create" creates-then-links. No `counterpartyId` is passed.

## Out of scope
- Transfers (suggestions hidden). Any engine/parity change — the merchant→counterparty
  resolution on update is pre-existing.
- A picker UI different from Add's (we intentionally match Add for consistency).

## Testing

**App (build + manual sim — UI-only):**
- Edit an expense → type into Merchant → matching counterparties suggested; tap one →
  fills the name → save → linked. Type a new name → **Create "<name>"** → save → a new
  counterparty exists (Power Tools › Merchants) and the tx links.
- A transfer shows no suggestions.
- iOS + macOS build.

No engine test — the merchant→counterparty resolve + create path is covered by #264.

## Notes
- `store.counterparties` is the active-ledger list; the engine already re-resolves the
  counterparty when the `merchant` patch changes.
- PR targets `feat/frontend`.
