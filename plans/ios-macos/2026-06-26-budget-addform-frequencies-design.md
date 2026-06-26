# Budget add-form frequencies (parity with change-cycle + engine)

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** The create-budget form offers only 4 frequencies; the change-cycle sheet + engine + DB allow 6. Add the missing two. One-line UI change, no engine change.

## Problem

`BudgetSheet` (create/edit) offers `["weekly", "monthly", "quarterly", "yearly"]` — **4**.
But `BudgetDetailView`'s change-cycle sheet offers all **6**
(`["daily", "weekly", "biweekly", "monthly", "quarterly", "yearly"]`), and the engine
(`Budgets.validFreqs`) + the DB `CHECK(frequency IN (...))` both accept those 6. So you
can't pick **daily** or **biweekly** when creating a budget, only when changing an
existing one — an inconsistency (parity inventory, Tier 3).

## Design

In `BudgetSheet.swift`, change:

```swift
    let frequencies = ["weekly", "monthly", "quarterly", "yearly"]
```
to the canonical 6 (same order as `BudgetDetailView`):

```swift
    let frequencies = ["daily", "weekly", "biweekly", "monthly", "quarterly", "yearly"]
```
The picker already renders `Text($0.capitalized)`, so "Daily" / "Biweekly" label fine.
No engine/schema change — the backend already accepts all 6.

## Out of scope
- The "once" frequency (that's scheduled-only, not a budget cycle); any engine change.

## Testing
- **Build:** FinchApp (iOS) + FinchMac (macOS).
- **Manual (sim):** Budgets → add a budget → the **Frequency** picker now lists all 6
  (daily … yearly); creating a daily/biweekly budget saves without error.

## Notes
- Source of truth for budget frequencies: `Budgets.validFreqs` + `Schema.swift` CHECK
  (both the 6). PR targets `feat/frontend`.
