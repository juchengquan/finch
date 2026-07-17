# Budget rows: leading-swipe quick verb (+ goal budget in the demo seed)

**Date:** 2026-07-17
**Status:** Approved, implemented inline.
**Scope:** Leading (right-)swipe on Budgets rows, one verb by budget type — both confirm-first
(sheets), per the Duplicate lesson. Plus: the demo seed gains an income/goal budget so the
Contribute surface is demo-able.

- **Expense budgets** → **Add Transaction** (green `plus`) → `AddTransactionSheet(defaultCategoryId:
  budget.categoryIds.first)` — quick-capture against the budget's category (no prefill for
  track-all budgets).
- **Income/goal budgets** → **Contribute** (green `dollarsign.circle`) → the existing
  `ContributeSheet(budgetId:)` (previously only reachable inside Budget Detail).
- Context menus gain the verb above a divider (macOS-parity rule); trailing (Edit/Delete)
  unchanged; both row sites (three-column + compact).
- **Seed:** `Vacation Fund` — `type: income` (engine → `is_recurring 0`, "Tracked via
  contributions"), target 2 000, saved 650, ungrouped. Verified in DB after fresh re-seed.
- Zero new strings ("Add Transaction"/"Contribute" already in the catalog).

**Testing:** builds iOS + macOS; fresh re-seed DB-verified; gesture pass human post-merge.
