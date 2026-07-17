# Transaction rows: leading-swipe Duplicate

**Date:** 2026-07-17
**Status:** Design approved (verbs/edge/scope chosen interactively), pending implementation
**Scope:** A **Duplicate** quick verb on the transaction rows' **leading (right-)swipe**, in all
three transaction lists (Activity feed, Account Detail, Counterparty Detail). No engine change.

## Decisions (user-selected)
- Verb: **Duplicate** only (Recategorize/Preview-promotion skipped).
- Edge: **leading** — mostly empty today (Confirm only shows on pending rows); trailing stays
  Delete-only per the #468 lean-swipe principle.
- Scope: **all three lists** for consistent gestures.

## Semantics

`FinchStore.duplicateTransaction(_ txn: Tx)` (new, `FinchStore+ViewHelpers.swift`) re-posts via
the `addTransaction` chokepoint:
- **Copied:** account, merchant, category, signed amount, currency (if orig-currency), tags.
- **Fresh:** date = `today`, no time, status confirmed (engine default), kind derived from sign.
- **Not copied:** note, receipt attachments, refund link, pending status — a duplicate is a new
  event, not a clone of the old one's bookkeeping.
- **Eligibility:** expense/income rows only (`txn.kind`); transfers/adjustments/refunds have
  different leg shapes or links — the button simply doesn't appear on them.

```swift
    public func duplicateTransaction(_ txn: Tx) throws {
        var args: [String: JSONValue] = [
            "ledgerId": .string(activeLedgerId), "accountId": .string(txn.account),
            "amount": .double(txn.amount), "merchant": .string(txn.merchant),
            "date": .string(today)]
        if let c = txn.category { args["categoryId"] = .string(c) }
        if let cur = txn.currency { args["currency"] = .string(cur) }
        if let tags = txn.tags, !tags.isEmpty { args["tagIds"] = .array(tags.map { .string($0) }) }
        try apply(.addTransaction, Args(args))
    }
```

## Row wiring (each list, matching its local error pattern)

Leading swipe gains, after the existing pending-Confirm button:
```swift
            if ["expense", "income"].contains(txn.kind ?? "") {
                Button { /* local error wrapper */ store.duplicateTransaction(txn) } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }.tint(.indigo)
            }
```
- Ordering: Confirm stays first (pending rows' full right-swipe still confirms); on confirmed
  rows Duplicate is the only/first leading action, so a full right-swipe duplicates.
- **Context menus** gain the same Duplicate entry (macOS-parity rule). Counterparty Detail rows
  have no swipe/menu today — they gain the leading swipe + a context menu (Duplicate; its tap
  already opens Edit).
- Error handling per file: ActivityTab `run {}`, AccountDetailView/CounterpartyDetailView their
  local `errorMessage = i18nMessage(error)` pattern (add the state if Counterparty lacks it).
- The duplicated row appears at the feed top (dated today) via the store refresh — that's the
  feedback; no toast.

## Out of scope
- Duplicate for transfers/adjust/refund; a date/amount-tweaking "Duplicate…" sheet; Recategorize
  and Preview-receipt swipe promotions. Engine changes.

## Testing
- Build iOS + macOS. Sim: DB-verify a duplicate — count rows for a merchant, then (since swipes
  aren't scriptable) verify by calling path review + human pass post-merge; launch sanity.
- "Duplicate" is a new user-facing string → English fallback until the next zh batch.

## Revision (user feedback, same PR): prefilled Add sheet instead of silent post

Duplicating now **opens the Add Transaction sheet pre-filled** (kind, |amount|, merchant,
category, account, currency, tags; date = today, note blank) — the user tweaks and confirms
via **Save**. Rationale: a silent write gave no chance to adjust amount/date and an accidental
full swipe posted real financial data with no undo. Implementation: `AddTransactionSheet` gains
`prefill: Tx?` (seeded once in `seedDefaults()`, mirroring Edit's `%g` amount formatting);
the three call sites present `.sheet(item: $duplicating)`; the silent
`store.duplicateTransaction` helper was removed (no silent write path remains), and
CounterpartyDetailView's added error state was dropped again (nothing throws there now).
