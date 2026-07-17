# Account rows: leading-swipe quick verbs

**Date:** 2026-07-17
**Status:** Approved, implemented inline.
**Scope:** Leading (right-)swipe on account rows gains the per-account quick verbs, following the
app's convention (transactions: Confirm; scheduled: Post; rules: Backfill):

- **Add Transaction** (green, `plus`) → `AddTransactionSheet(defaultAccountId:)` — full swipe
  triggers this (first action; safe, consistent with keeping full-swipe on the trailing edge).
- **Reconcile** (blue, `checkmark.circle`) → `ReconcileSheet(preselect:)` — per-account by
  nature; previously only preselected from Account Detail.

Both actions are merged into the row's context menu (`leadingActions · Divider · rowActions`)
per the macOS-parity rule: every swipe action stays mouse-reachable. Applied to both row sites
(three-column selection list + compact push list). Trailing edge unchanged (Edit/Archive/Delete,
full-swipe = Edit — deliberate keep). Budgets rows: candidate follow-up (natural verb: Contribute).

**Testing:** build iOS + macOS; sim launch sanity; swipe/menu flows human-verified post-merge
(gestures not scriptable). New string "Add Transaction" already in catalog ("Add Transaction" =
add-sheet title); "Reconcile" already in catalog.
