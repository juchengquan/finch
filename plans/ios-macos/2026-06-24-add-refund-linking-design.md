# Add Transaction: refund creation + linking (iOS)

**Date:** 2026-06-24
**Status:** Design approved, pending implementation
**Scope:** iOS Add Transaction form — a new **Refund** type that can optionally link to the original transaction. One small parity-safe engine tweak. Transfer/adjust untouched.

## Problem

A **refund** is a transaction `kind` — a *positive* amount that **nets against its
category** — and it can carry `refundedTransactionId` (the original expense it
offsets). The engine fully supports this (`Entries.Kind.refund`, validated
positive; `refunded_entry_id`; the projection resolves the link). But **iOS has no
refund UI at all**: the Add type picker is only `expense / income / transfer /
adjust`, and nothing in Add or Edit creates a refund or sets the link.

Two id facts that shape the design:
- A transaction's UI id (`Tx.id`) is the **account-leg posting id**.
- `refundedTransactionId` is stored **directly** as `refunded_entry_id` (no
  resolution) — it must be the **entry id**. The projection resolves entry→posting
  for *display*, so the write side needs the entry id.

## Goal

Add a **Refund** type to the Add form (expense/income, plus the line-item extras),
with an optional picker to choose the original transaction it refunds. The picker
hands the engine the chosen transaction's id; the engine normalizes it to the
entry id.

## Design

### 1. Engine — normalize `refundedTransactionId` (one parity-safe line)

In `Transactions.addTransaction` (both currency branches), resolve the passed id to
the canonical entry id before storing:

```swift
let refundedEntryId = try a.refundedTransactionId.flatMap { try Entries.resolveEntryRef(db, $0)?.entryId }
```

…and pass `refundedEntryId` (instead of `a.refundedTransactionId`) to both
`postEntry`/`postSimple`. `resolveEntryRef` "handles both" posting and entry ids and
is **idempotent for an entry id** (entry id → same entry id), so existing callers /
parity fixtures (which already pass entry ids) are unchanged. Run `ParityTests` to
confirm.

### 2. Add form — the Refund type

- **`AddTransactionSheet.Kind`** gains `.refund` (5th segment; `label` "Refund",
  `iconName` via `TxnKindIcon.icon(for: "refund")` = `arrow.uturn.left.circle`).
- Introduce a helper: `private var isLineItem: Bool { kind == .expense || kind == .income || kind == .refund }`.
  - **Field set:** show `expenseIncomeFields` (amount/merchant/category/account/
    currency) when `isLineItem` (was `expense/income`; the `else` adjust branch
    keeps `kind == .adjust`).
  - **Extras gating:** the existing status / tags / receipt sections and the
    merchant→counterparty suggestions switch from `kind == .expense || kind ==
    .income` to `isLineItem` (refund gets them too).
  - **Split stays expense/income-only** (unchanged gate) — no split refunds.

### 3. Refunded-transaction picker (refund only)

New state:

```swift
@State private var refundedTxId: String? = nil
```

In `expenseIncomeFields`, when `kind == .refund`, add a row:
- shows the picked transaction's merchant + date, or "Refunds (optional)" when none;
- tapping opens a sheet listing **recent expenses** in the active ledger
  (`store.txns` filtered to `kind == "expense"` / amount < 0, active ledger, newest
  first), searchable by merchant; selecting sets `refundedTxId = tx.id`; a "Clear"
  option unsets it.

(Keep the picker self-contained — a small `RefundSourcePickerView(onPick:)` sheet,
or reuse the searchable-list pattern. Optional: leaving it empty records an unlinked
refund.)

### 4. Save (refund branch)

Refund routes through the same `addTransaction` path as expense/income, with:
- **positive amount:** `signed = (kind == .income || kind == .refund) ? abs(value) : -abs(value)`.
- **explicit kind:** add `args["kind"] = .string("refund")` for refund (so a positive
  amount isn't read as income). (Expense/income keep inferring kind from sign.)
- **the link:** `if let refundedTxId { args["refundedTransactionId"] = .string(refundedTxId) }`.
- status / tags / receipt / counterparty-create all apply as today (now gated by
  `isLineItem`); the existing `applyReturningId` + receipt `Task` flow is unchanged.

### 5. Reset on type change

When `kind` changes away from `.refund`, clear `refundedTxId` (an `.onChange(of:
kind)` already may exist for category validity; add the reset there or alongside).

## Out of scope
- A refund **badge** on transaction rows / showing the link in **Edit** (separate
  follow-up — this task is create + link in Add).
- Split refunds; transfer/adjust.
- Web changes (engine resolve is iOS-local and parity-safe).

## Testing

**Engine (FinchCore):**
- Create an expense (entry `e1`); `addTransaction` with `kind: "refund"`,
  positive amount, and `refundedTransactionId` = e1's **posting** id → the refund
  entry's `refunded_entry_id` == `e1` (resolved). Passing e1's **entry** id yields
  the same (idempotent).
- `ParityTests` stay green (`swift test`).

**App (build + manual sim):**
- Add → **Refund**: line-item fields appear; a "Refunds (optional)" row lists recent
  expenses; pick one, enter amount + category → save.
- The saved refund is positive, nets its category, and (in data) links the chosen
  expense. Leaving the picker empty saves an unlinked refund.
- Transfer/Adjust unaffected; **split** not offered on Refund.

## Notes
- `refundedTransactionId` arg accepts the picked `Tx.id` (posting id); the engine
  resolve (§1) normalizes it — no need to surface an `entryId` on `Tx` (which would
  risk parity-fixture drift).
- PR targets `feat/frontend`.
