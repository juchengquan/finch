# Adjust Balance relocation — design

**Date:** 2026-07-17
**Status:** approved (brainstormed with user)
**Scope:** iOS/macOS app only (`ios/`). Engine, projections, and the web app are untouched.

## Problem

"Adjust Balance" occupies the 5th segment of the Add-transaction sheet's type
control, but it is an **account-maintenance operation**, not a transaction the
user composes: it has its own field set (account + target balance), posts a
derived difference, and is conceptually a sibling of Reconcile (whose guided
flow already posts an adjustment at finish). Carrying it in the Add sheet costs
a cramped 5-segment control, a 5th pager page, and extra state/gating in an
already-large file.

## Decision

Remove the `adjust` kind from the Add sheet entirely and relocate the feature
to a small dedicated sheet opened from the **account detail's ⋯ menu** — the
one entry point (no list-row menu, no palette entry, no residual link in the
Add sheet; user decision).

## Changes

### 1. `AddTransactionSheet` slims to 4 types

- `Kind` drops `.adjust` → Expense / Income / Transfer / Refund, in that order.
- Delete `adjustFields`, the `targetBalance` state, and the
  `.adjustAccountBalance` save branch.
- The pager (`TabView` pages), the toolbar segmented control + scrub gesture,
  and `typeControlWidth = 190` are otherwise unchanged — 4 segments simply get
  roomier. iOS and macOS both (the control is shared).
- `Kind`-dependent gating that referenced `.adjust` (`k != .adjust` sections,
  `isLineItem`) simplifies accordingly.

### 2. New `AdjustBalanceSheet` (`ios/FinchApp/Sources/FinchApp/WriteScreens/AdjustBalanceSheet.swift`)

Locked to the account it is opened for (no account picker — user decision):

- **Header row (read-only):** account name + current balance, formatted in the
  account's native currency (`displayMoney(balance, from: currency)`).
- **New balance:** decimal `TextField`, `keyboardType(.numbersAndPunctuation)`
  (leading minus allowed — credit-card balances), parsed via `DecimalInput`.
- **Date:** `DatePicker`, date-only (`[.date]`) — the `adjustAccountBalance`
  action takes only a `date`; today's Add sheet shows a time wheel whose value
  is silently discarded for adjustments, so the dedicated sheet drops it.
- **Note:** optional, trailing-aligned (same row style as the Add sheet).
- **Footer:** "Posts an adjustment for the difference from the account's
  current balance." (verbatim from today's Add-sheet footer).
- **Save:** `store.apply(.adjustAccountBalance, Args(...))` with the exact
  argument shape the Add sheet posts today: `accountId` (string),
  `targetBalance` (double), `date` (yyyy-MM-dd), plus `note` only when
  non-empty (no time argument — the engine action doesn't take one, hence the
  date-only picker above). Errors via
  `errorAlert(i18nMessage(error))`. Empty/unparseable balance → inline
  "Enter a new balance." (same message as today).
- **Chrome:** `NavigationStack` + inline title "Adjust Balance", xmark cancel /
  checkmark save toolbar (house sheet style).

### 3. Entry point — `AccountDetailView` ⋯ menu

- New item **"Adjust balance…"**, `TxnKindIcon.icon(for: "adjustment")`
  (`slider.horizontal.3`), placed directly **after Reconcile** (conceptual
  siblings; Reconcile stays the guided path that can also post an adjustment).
- Presents `AdjustBalanceSheet(account:)` as a sheet.

### Non-changes (explicit)

- Engine action `adjustAccountBalance`, projections, and feed/EditSheet
  rendering of `adjustment` rows: untouched (`EditTransactionSheet` already
  only guards against reclassifying adjustment rows).
- Reconcile flows (sheet + guided session) untouched.
- Widgets/Watch/deep links never referenced the adjust kind.
- **Web parity:** deliberate iOS-ahead UX divergence — the web Add dialog keeps
  its adjust type; engine behavior identical on both. Record in the next
  handoff refresh.

## Testing

- `bun`-equivalent unit tests don't apply; **FinchAppTests** must stay green
  (no test references `Kind.adjust` today).
- Builds: FinchApp (iOS) **and** FinchMac.
- Manual checklist (PR body):
  1. Add sheet shows 4 types; form swipe pages across exactly 4; scrub works.
  2. Account detail ⋯ → "Adjust balance…" → sheet shows that account + current
     balance; saving a new balance posts an adjustment row for the difference.
  3. Negative target balance accepted (credit card).
  4. Cancel posts nothing.
  5. macOS: Add sheet has 4 segments; account detail menu item works.
