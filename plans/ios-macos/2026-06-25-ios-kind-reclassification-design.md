# Transaction kind reclassification (iOS)

**Date:** 2026-06-25
**Status:** Design approved, pending implementation
**Scope:** iOS `EditTransactionSheet` (+ FinchCore tests). **No engine change.** iPad/Mac share the view. iOS-original enhancement (net-new beyond web — the web edit form has no kind picker).

## Problem

The Edit sheet treats a transaction's `kind` as fixed — you can't re-type a miscategorized expense as income, or link/unlink a refund, without delete-and-recreate. The engine already supports it: `updateTransaction` accepts a `kind` patch and rebuilds the legs for single-account entries (`Transactions.swift:340`). Only the UI is missing.

## Goal

Add a **kind picker** to `EditTransactionSheet` for **expense / income / refund** on simple (single-account, non-split, non-transfer) entries. Changing kind re-signs the amount and (for refund) manages the source link; the in-place leg rebuild preserves the entry id, attachments, tags, status, and timestamps.

## Non-goals

- **No transfer / adjustment / opening reclassification.** Those are different leg shapes (`validateShape` rejects an in-place change; transfers are already guarded `acctLegs > 1 && touchesMoney`; adjustments/opening have no standard edit UI). Supporting them would require destructive delete-and-recreate (loses id/attachments/tags/refund-links/timestamps) — explicitly out.
- **No kind change on split transactions** (would require re-signing every split leg) — gated out.
- No engine/schema/action change; no web change.

## Key decisions (locked)

1. **Bounded to expense ↔ income ↔ refund** (same leg shape: 1 account leg + category leg) — the set the engine already rebuilds in place.
2. **No engine change** — reuse `updateTransaction`'s existing `kind` patch + single-account leg rebuild.
3. **Gate the picker** to single-account, non-split, non-transfer/adjustment entries.
4. The UI sends a **correctly-signed amount** for the target kind (engine's refund guard needs amount > 0); refund link is set/cleared by the picker.

## Detailed design

### `EditTransactionSheet` (FinchApp)

- New `@State private var selectedKind: Kind` where `Kind` is a local enum `{ expense, income, refund }`, initialized from `txn.kind` (falling back to expense/income by sign if `txn.kind` is empty — but `txn.kind` is set for these). The picker is only rendered when the entry is reclassifiable (see gating), so transfer/adjustment never instantiate it.
- **Gating:** show the kind `Picker` only when `txn.kind != "transfer"` **and** `txn.kind != "adjustment"` **and** `!isSplit`. (Same simple-entry condition already used for account/currency edits.)
- **`selectedKind` drives** (replacing the current `txn.kind`/`txn.amount > 0` checks where they choose income-vs-expense behavior):
  - **Category filter:** `selectedKind == .income ? categories where kind == "income" : kind != "income"`. (If the prior category no longer fits, the user re-picks; the engine treats category kind as decoration, so a mismatch won't error.)
  - **Refund source field:** shown when `selectedKind == .refund` (was `txn.kind == "refund"`).
  - **Amount sign** (below).
- **Picker placement:** in the amount/category `Section`, above the category row.

### Save (`save()`)

- Compute the signed amount from `selectedKind`: `let signed = (selectedKind == .expense ? -1.0 : 1.0) * abs(parsed)` (income/refund positive; refund guard satisfied).
- **If `selectedKind.rawValue != txn.kind`** (kind changed):
  - `patch["kind"] = .string(selectedKind.rawValue)`
  - `patch["amount"] = .double(signed)` (always send on kind change, to re-sign even when magnitude is unchanged).
  - refund link: if `selectedKind == .refund` → `patch["refundedTransactionId"] = refundedTxId.map(.string) ?? .null`; if leaving refund → `patch["refundedTransactionId"] = .null`.
- **If kind unchanged:** existing behavior (send amount only when `abs(signed - originalNative) > 0.001`; the refund branch stays as today). Reuse the existing sign source so non-kind-change edits behave exactly as before.
- Dispatch unchanged: `store.apply(.updateTransaction, Args(["id": …, "patch": .object(patch)]))`.

### Engine (no change — verified)

`updateTransaction` (`Transactions.swift:311–392`): `touchesMoney` includes `kind`; transfers (`acctLegs > 1`) throw `error.tx.transferLegEdit` (so a transfer can never reach the picker anyway); for single-account entries it sets `ep.kind` and rebuilds both legs from the patched amount/category, re-validating shape (refund requires amount > 0). Attachments/tags/status/id/timestamps are preserved (in-place rebuild, not delete).

## Facts (verified)

- `updateTransaction` kind patch: `Transactions.swift:324` (`kind` ∈ touchesMoney), `:326-327` (transfer guard), `:340` (`ep.kind = .set(k)`), leg rebuild `:346-391`.
- `EditTransactionSheet.save()` current patch builder: `:267-309` (amount sign `originalNative`, account/currency gated to non-transfer, refund-source branch). Category filter `:101`. Transfer/refund UI branches `:137,148,154`.
- Refund shape guard: `Entries.swift:290` (refund account leg amount must be > 0).

## Testing

- **FinchCore (`updateTransaction` kind change — lock the path the UI relies on):**
  - expense → income: seed an expense, apply `updateTransaction` with `kind: income`, `amount: +x`; assert the projected `kind == "income"`, amount positive, the two legs still sum to zero (balanced).
  - expense → refund: with a positive amount accepted (no shape error); refund → expense with `refundedTransactionId: null` + negative amount.
  - (Optional) transfer kind change rejected — assert `updateTransaction` with `kind` on a 2-leg transfer throws `error.tx.transferLegEdit` (documents the guard).
- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests green.
- **Manual (sim):** edit an expense → switch to **income** → save → it shows as income (positive); switch to **refund** → pick a source → save; a transfer's editor shows **no** kind picker; a split's editor shows no kind picker; attachments/tags survive the change.

## Out of scope

Transfer/adjustment/opening reclassification; delete-and-recreate; kind change on splits; web changes.
