# Anchor delete confirmations at their source (iOS 26 popout positions)

**Date:** 2026-07-19
**Status:** Approved (anchor-at-source, all sites); executed inline.

## Problem

All 14 `confirmationDialog`s are attached at the screen-container level. Pre-iOS 26
that was invisible (iPhone action sheets always slid from the bottom); iOS 26 anchors
dialogs near their SOURCE view, so container-attached dialogs pop out at the top of
the screen, disconnected from the row/button that triggered them.

## Fix pattern

Move each `.confirmationDialog` onto its triggering view:
- Row swipe/context triggers → on the ROW content (not the swipe-action button — that
  view unmounts when the swipe collapses and would kill the presentation). Shared
  `deleting`-item state becomes a per-row derived binding:
  `isPresented: Binding(get: { deleting?.id == item.id }, set: { if !$0 { deleting = nil } })`.
- Toolbar ⋯ menu triggers → on the toolbar item's content.
- In-form button triggers → on that Button.
Pre-26 systems ignore anchors (bottom sheet as before); iPad/macOS get popovers at the
source — also an improvement.

## Sites (14)

| File | Dialog | Trigger → new anchor |
|---|---|---|
| ActivityTab | bulk "Delete N transactions?" | selection-bar Delete button |
| ActivityTab | "Delete transaction?" | txn row (swipe) |
| BudgetsTab | "Delete group?" | group header row (context menu) |
| AccountsTab | "Delete this account?" | account row (swipe/context/⌫) |
| AccountsTab | "Delete group?" | group header row (context menu) |
| AccountDetailView | "Delete this account?" | toolbar ⋯ menu |
| AccountDetailView | "Delete transaction?" | txn row (swipe) |
| BudgetDetailView | "Delete this budget?" | toolbar ⋯ menu |
| LedgerManagementView | "Delete this ledger?" | ledger row (swipe/context) |
| LedgerDetailView | "Delete this ledger?" | Delete button (form) |
| EditTransactionSheet | "Delete this transaction?" | Delete transaction button (form) |
| AddTransactionSheet | "Possible duplicate" | ✓ Save toolbar button |
| ExchangeRateHistoryView | "Delete all rates" | toolbar ⋯ menu |
| CategoryAdminView | "Delete <name>?" | category row (swipe/context) |

## Verification

Builds both platforms; FinchAppTests. Visual: `-openAdd` reaches the Add sheet;
row/toolbar cases are a human pass (positions only — no behavior change).
