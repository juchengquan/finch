# Edit Transaction: currency editing

**Date:** 2026-06-25
**Status:** Design approved, pending implementation
**Scope:** Add a currency picker to the Edit form for expense/income/refund single-leg transactions. UI-only — the engine already accepts a `currency` patch. Transfers/splits excluded.

## Problem

`updateTransaction` accepts a `currency` patch (re-derives the account/category
legs with `orig_amount`+`orig_currency` and reconverts to base), and the Add form
has a currency picker — but the **Edit** form doesn't surface currency. This was the
deferred follow-up from the Edit-parity work (#283).

## Design

Mirror the Add form's currency control, gated like the #283 Account picker.

### Currency picker (in the "Amount & category" section)

- New `@State private var currencyCode: String`, initialized in `init` from the
  transaction's effective currency:
  `txn.currency ?? <currency of txn.account>`.
- A computed `currencyOptions` mirroring `AddTransactionSheet`:
  ```swift
  private var currencyOptions: [String] {
      var set = Set(store.accounts.compactMap { $0.currency })
      set.formUnion(store.exchangeRates.map { $0.currency })
      set.insert(accountCurrency)        // the (possibly edited) account's currency
      return set.sorted()
  }
  ```
  where `accountCurrency = store.accounts.first { $0.id == accountId }?.currency ?? store.displayCurrency`
  (`accountId` is the Edit form's account-picker state from #283, so options stay
  consistent if the account is changed).
- In the non-split `Section("Amount & category")`, after the Amount field, add — gated
  `if txn.kind != "transfer", currencyOptions.count > 1`:
  ```swift
  Picker("Currency", selection: $currencyCode) {
      ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
  }
  ```
  The Amount field is unchanged (the magnitude, now denominated in `currencyCode`).

### Save

In `save()`'s patch building (after the amount/category block), add:

```swift
if txn.kind != "transfer", currencyCode != (txn.currency ?? accountCurrency) {
    patch["currency"] = .string(currencyCode)
}
```

Folds into the existing `updateTransaction` apply. It composes with a simultaneous
account change: the engine resolves `patchCcy = patch["currency"] ?? (has("account") ? newAcctCcy : oldAcctCcy)`,
so an explicit `currency` patch wins, and otherwise the account's currency is used.

## Out of scope
- **Transfers** (header-only patches; the per-leg currencies aren't edited here) and
  **splits** (amount/currency hidden, as today) — consistent with the #283 account picker.
- Editing the FX **rate** itself (that's the Exchange Rates admin screen).
- The amount field's denomination label (it already shows the magnitude; the picker
  conveys the currency).

## Testing

**Engine (FinchCore) — confidence test:**
- Add an entry in the account's currency; `updateTransaction` with
  `patch.currency = <foreign>` (a currency with a known rate) → the entry's posting
  now carries `orig_currency = <foreign>` and a base amount derived via the rate.
  (Guards the patch path the UI relies on.) `ParityTests` stay green (no engine change).

**App (build + manual sim):**
- Open an expense whose account is in SGD → Edit shows a **Currency** picker when other
  currencies/rates exist; change it to USD → save → the transaction is now a
  foreign-currency entry (orig USD), figures reconvert.
- A same-currency change (back to the account currency) drops the foreign denomination.
- Transfers / splits show **no** currency picker.

## Notes
- No engine/DB/parity changes — the `currency` patch is pre-existing.
- PR targets `feat/frontend`.
