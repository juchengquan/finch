# Opening-balance display (iOS)

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** FinchCore (populate `AccountRow.openingBalanceBase` in the accounts projection) + `AccountDetailView` display + a projection test. **No schema/model change** (the field already exists). Tier-3 parity / iOS completeness.

## Problem

An account's opening balance is entered at creation (the `open-<id>` opening entry is the source of truth) but is **never shown again** — not in the account detail. Separately, `AccountRow.openingBalanceBase` exists on the model and `Selectors.holdingValue` reads it for cost basis, but the accounts projection never populates it, so it's always `nil` (cost basis silently treats it as 0).

## Decisions (locked)

1. **Populate `openingBalanceBase` properly** (not a separate display-only path). This surfaces the opening balance AND correctly feeds `Holdings` cost basis — a latent fix. The holdings-number change is intended; call it out in the PR and keep ParityTests green.
2. **Detail-only display** (`AccountDetailView`). The Add sheet already shows opening balance at creation; it's add-only (non-editable), so no edit-sheet change.

## Detailed design

### FinchCore — populate `openingBalanceBase`

In `Projections+State.swift` `accountRows(...)`:
- Add a correlated subquery to the SELECT:
  ```sql
  (SELECT p.amount_base FROM postings p
    WHERE p.entry_id = 'open-' || a.id AND p.account_id = a.id
    LIMIT 1) AS openingBalanceBase
  ```
  (The opening entry id is `open-<accountId>` with a single account-leg posting whose `amount_base` is the opening balance in base currency — see `Entries.postOpening`. NULL when the account has no opening entry, i.e. opening balance was 0.)
- Map it: `openingBalanceBase: r["openingBalanceBase"]` in the `AccountRow(...)` init (the param already exists, currently unset).

No schema/model/`AccountRow` change — the field is already declared.

### FinchApp — `AccountDetailView`

In the header Section (after the existing balance/reconcile rows), add an opening-balance row shown only when meaningful:
```swift
if let ob = account.openingBalanceBase, ob != 0 {
    LabeledContent("Opening balance", value: store.displayMoneyBase(ob))
}
```
(`displayMoneyBase` matches the other figures in the view; `openingBalanceBase` is base currency.)

### Holdings (side effect — verify, no code change)

`Selectors.holdingValue` already does `costBasis = account.openingBalanceBase ?? 0 + Σ confirmed txns`. With the projection now populating `openingBalanceBase`, investment cost basis / unrealized-FX become correct. No code change here — just confirm existing Holdings/Parity tests still pass (and update any fixture that assumed a 0 opening, if present).

## Facts (verified)

- `Entries.postOpening`: opening entry id `open-<accountId>`, kind `.opening`, one account leg `amount = r2(openingBalance)`; **not** posted when amount is 0 (returns nil). `Projection.run` excludes `kind = 'opening'`, so the opening entry is NOT in the projected `Tx` list — it must be read from `postings` directly.
- `postings`: `entry_id`, `account_id`, `amount_base REAL NOT NULL` (Schema.swift). The opening posting's `amount_base` is the base-currency opening balance.
- `AccountRow.openingBalanceBase: Double?` exists (Models.swift) + its init param; `accountRows` projection does **not** set it today. `Holdings.swift` reads it for cost basis.
- `AccountDetailView` header renders balance + the reconcile badge; `store.displayMoneyBase` formats base amounts.
- 0 open PRs touch `Account*`/`Projections`/`Holdings` (collision-checked); the other session is in Insights/charts, settings, budget frequencies — disjoint.

## Testing

- **FinchCore:** create an account with an opening balance (`createAccount` with `openingBalance`) → `Projection.accounts` → assert `openingBalanceBase` equals it (base); an account created with no/zero opening → `openingBalanceBase == nil`.
- **Regression:** full FinchCore suite incl. ParityTests + Holdings tests stay green (the cost-basis change is the intended fix; reconcile any fixture that presumed a 0 opening).
- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests + FinchCore green.
- **Manual (sim):** an account created with an opening balance shows an "Opening balance" row in its detail; an account with none does not.

## Out of scope

Editing the opening balance (add-only by design); showing it in the Add/Edit sheet; schema/model changes; web changes.
