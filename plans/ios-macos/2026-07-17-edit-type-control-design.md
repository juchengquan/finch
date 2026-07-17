# Edit sheet type control + real transfer editing — design

**Date:** 2026-07-17
**Status:** approved (discussed in session)
**Scope:** iOS/macOS app only (`ios/`); the engine's existing `updateTransfer` is consumed, not changed.

## Problem

Tapping a transaction row opens `EditTransactionSheet`, which diverges from the
Add sheet the user just learned: the type is a small inline "Type" picker row
(line items only), and **transfer legs get a stripped form** — no type
indicator, no From/To accounts — even though every transfer renders as two
rows in the feed. The user expects: tap any row → an add/edit-style page with
the **type control on top**, and a transfer row → that page **locked on
Transfer** showing actual transfer fields.

## Decision

Give `EditTransactionSheet` the Add sheet's top type control (icon segmented,
toolbar principal slot), preselected to the transaction's kind, and make
transfer legs open a real transfer editor backed by the engine's
`updateTransfer`.

## Changes

### 1. Top type control (`EditTypeControl`)

A small custom icon bar in the toolbar **principal** slot (the system
segmented `Picker` can't disable individual segments, which this needs). Same
four glyphs/order as the Add sheet's `Kind` (`TxnKindIcon` icons for
expense / income / transfer / refund), ~44pt segments in the same ~190pt
footprint:

- **Line items** (kind ∈ {expense, income, refund}, not split): expense /
  income / refund segments are tappable and drive the existing `selectedKind`
  reclassification (#319 — the inline "Type" `Picker` row is REMOVED; this
  control replaces it). The **Transfer segment renders disabled** (grayed,
  non-interactive): the engine cannot convert a line item into a transfer.
- **Split line items** (`isSplit`, today's `canReclassify == false`): control
  shown locked on the current kind (all segments non-interactive).
- **Transfer legs** (`txn.kind == "transfer"`): control locked on Transfer.
- **Adjustment / opening** rows: control hidden entirely (these aren't one of
  the four types); the sheet keeps its plain "Edit Transaction" title only.
- Accessibility: each segment gets the kind's label; selected segment carries
  `.isSelected`; disabled segments are marked disabled.

### 2. Transfer legs become a real transfer editor

When `txn.kind == "transfer"` the form's first section becomes:

- **From / To accounts, read-only** (`LabeledContent`). Resolved from the
  entry's two legs: the counterpart leg is the other `store.txns` row with the
  same `transferGroupId`; **From** = the negative-amount leg, **To** = the
  positive one. (Accounts are immutable in `updateTransfer` — moving a
  transfer between accounts remains delete + recreate, out of scope.)
- **Amount editing:**
  - Same-currency legs: ONE "Amount" field (native currency), saved as
    `fromAmount` (the engine ratio-scales the other leg; same-currency equal
    amounts are preserved by scaling).
  - Cross-currency legs: TWO fields — "From amount" (from-leg currency) and
    "To amount" (to-leg currency) — patched together (`fromAmount` +
    `toAmount`). Prefill from `abs(nativeAmount)` of each leg.
- **Date / time / Note:** existing fields, but for transfer legs the save
  routes through `updateTransfer` (`date` yyyy-MM-dd, `time`, `note`) instead
  of the leg-level transaction patch. This also fixes a latent hazard: today a
  transfer leg's amount/date edits go through the single-leg patch path, which
  can diverge from the counterpart leg.
- **Save:** one `store.apply(.updateTransfer, Args(["id": txn.id, "patch":
  {…}]))` containing only changed keys (amounts when changed, date/time/note
  when changed). Unchanged → no apply (match today's no-op behavior). Errors
  via `i18nMessage` (the engine rejects zero/negative amounts and same-currency
  mismatches with localized messages).
- Sections that are leg-level today and stay untouched for transfer legs:
  Status, Tags, Receipt (whatever currently shows keeps showing); the Category
  row is **dropped for transfer legs** (a transfer has no category; today's
  form odd-showing expense categories there was part of the confusion).

### 3. Non-changes (explicit)

- Line-item editing (amount/merchant/category/account/currency/refund link/
  splits/receipts/tags/status) is untouched apart from the Type row moving to
  the toolbar control.
- Engine untouched (`updateTransfer` consumed as is; its ratio-scaling and
  cleared-leg preservation are existing behavior).
- Add sheet untouched. Feed rows untouched.
- Web parity: web's transfer editing lives in its Transfers admin page; this
  is iOS UX alignment, no data-model divergence.

## Testing

- Builds: FinchApp (iOS) + FinchMac; FinchAppTests green.
- New unit-testable seam: a small pure helper mapping (fromLeg, toLeg,
  edited fields) → `updateTransfer` patch dictionary; test: same-currency
  single-amount → `fromAmount` only; cross-currency both; unchanged → empty
  patch; date/time/note inclusion rules. (Add to FinchAppTests.)
- Manual checklist (PR body):
  1. Tap an expense row → sheet shows the type control on top, selected
     Expense; switching to Income reclassifies as before; Transfer segment
     grayed.
  2. Tap EITHER leg of a transfer → control locked on Transfer; From/To shown
     read-only; amount edit updates BOTH legs (check the other row after
     save); date/note edits stick.
  3. Cross-currency transfer: both amount fields, independent edits accepted.
  4. Split transaction: control locked; no reclassification.
  5. Adjustment row: no type control; sheet behaves as today.
  6. macOS: same states render.
