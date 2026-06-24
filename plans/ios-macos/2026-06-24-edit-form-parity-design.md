# Edit Transaction: parity with Add (status + account + refund link)

**Date:** 2026-06-24
**Status:** Design approved, pending implementation
**Scope:** iOS Edit Transaction sheet — add three controls the Add form/engine already support. One small parity-safe engine tweak. Transfers/adjust mostly excluded; currency + counterparty-in-Edit deferred.

## Problem

The Add form was recently enriched (tags, status, receipt, counterparty, splits,
refunds, transfer tags/status). The **Edit** sheet now lags — the engine's
`updateTransaction` accepts `account`, `currency`, `kind`, `refundedTransactionId`,
`status`, … but the Edit UI only surfaces merchant/note/date/amount/category/tags/
receipts/split + a one-way Confirm + reviewed-toggle + delete.

This closes the three highest-value gaps:
- **Status** — Edit has only a one-way "Confirm transaction" button (pending →
  confirmed); you can't set confirmed → pending or choose freely.
- **Account** — `Tx.account` change is supported by the engine but, by the form's
  own comment, "not surfaced here."
- **Refund link** — a refund's `refundedTransactionId` can be set at creation (Add)
  but never viewed/changed/fixed afterward.

## Design

### 1. Engine — resolve the refund-link patch (one parity-safe line)

`Transactions.updateTransaction` sets the refund link directly (line ~341):

```swift
if has("refundedTransactionId") { ep.refundedEntryId = .set(strOrNil(patch["refundedTransactionId"])) }
```

Change it to resolve via `resolveEntryRef` (mirroring `addTransaction` line ~223),
so a passed **posting id** normalizes to the **entry id** the column needs:

```swift
if has("refundedTransactionId") {
    ep.refundedEntryId = .set(try strOrNil(patch["refundedTransactionId"]).flatMap { try Entries.resolveEntryRef(db, $0)?.entryId })
}
```

`resolveEntryRef` is idempotent for an entry id (entry id → same), so the web
parity `WRITE_SEQUENCE` (which passes entry ids) is unchanged ⇒ `ParityTests` green.

### 2. Edit form — Status picker

Replace the one-way **"Confirm transaction"** button with a **Status `Picker`**
(Confirmed / Pending), exactly like the Add form:

- New `@State private var status: Entries.Status` initialized in `init` from the
  transaction: `txn.pending == true ? .pending : .confirmed`.
- A `Picker("Status", selection: $status)` with the two tags (placed where the
  Confirm button was, or in its own section).
- The **"Mark reviewed" toggle stays** (it's `reviewedAt`, a separate field).
- It's a header field, so it's transfer-safe (works regardless of kind).

### 3. Edit form — Account picker

Add a `SearchablePickerRow(title: "Account", …)` like Add:

- New `@State private var accountId: String` initialized from `txn.account` (which
  is the account **id** in the projection).
- Options = `store.accounts` (id/name).
- **Hidden for transfers** (`txn.kind == "transfer"`): the engine only accepts
  header-only patches for multi-account-leg entries. Show for expense/income/refund.

### 4. Edit form — Refund link

For **refund-kind** transactions (`txn.kind == "refund"`) only, add a "Refunds" row
reusing `RefundSourcePickerView`:

- New `@State private var refundedTxId: String?` initialized from
  `txn.refundedTransactionId` (a posting id post-projection — matches the picker's
  `Tx.id`).
- The row shows the linked transaction's merchant (or "Optional"); tapping opens
  `RefundSourcePickerView { refundedTxId = $0 }` (its "None" option clears it).

### 5. Save — fold into the existing patch

The Edit `save()` already builds a `patch` dict for `updateTransaction`
(amount/category/note/date/time) and applies it. Extend it:

```swift
if status != originalStatus { patch["status"] = .string(status.rawValue) }
if txn.kind != "transfer", accountId != txn.account, !accountId.isEmpty { patch["account"] = .string(accountId) }
if txn.kind == "refund", refundedTxId != txn.refundedTransactionId {
    patch["refundedTransactionId"] = refundedTxId.map(JSONValue.string) ?? .null
}
```

(`originalStatus` captured in `init`.) Tags continue via the existing
`setTransactionTags` call. No new `applyReturningId` needed — it's a patch on an
existing entry.

## Out of scope
- **Currency** editing; **counterparty** suggestions/“Create” in Edit (deferred).
- **Kind change** (reclassifying a normal tx into a refund, or vice-versa).
- Editing a **transfer's** amount/category/account (pre-existing behavior; the new
  account/refund rows are simply hidden for transfers).
- Splits — already editable via the existing `SplitEditorView`.

## Testing

**Engine (FinchCore):**
- `updateTransaction` with `patch.refundedTransactionId` = an expense's **posting
  id** → stored `refunded_entry_id` is that expense's **entry id** (resolved);
  passing the entry id yields the same (idempotent).
- `ParityTests` green (`swift test`).

**App (build + manual sim):**
- Edit a confirmed tx → flip Status to **Pending** → save → it's pending (and back).
- Edit an expense → change **Account** → save → the tx moves to the other account.
- Edit a **refund** → its "Refunds" row shows the linked purchase → change it /
  clear it → save → the link updates.
- Transfers show **no** Account/Refund rows (Status still shown).

## Notes
- `Tx.account` = `postings.account_id` (id), so the Account picker pre-selects and
  patches by id directly.
- PR targets `feat/frontend`.
