# Demo seed: budget groups

**Date:** 2026-06-27
**Status:** Design approved, pending implementation
**Scope:** Add budget groups to the simulator demo seed so the Budgets page shows grouped budgets. One block in `seedSimulatorDemo`. No engine/model change.

## Problem

`FinchStore.seedSimulatorDemo` (the `#if targetEnvironment(simulator)` demo seed) groups
**accounts** (`createAccountGroup`) but seeds **4 ungrouped budgets** (Groceries, Dining,
Shopping, Transport). The Budgets page demo never shows group sections. (`createBudgetGroup`
+ budget `groupId` already exist — this is just unused in the seed.)

## Design

In `seedSimulatorDemo` (`FinchStore.swift`), mirror the existing `accountGroups` pattern.
Replace the current budgets block (lines ~198–208) with:

```swift
        let budgetGroups: [(id: String, name: String)] = [
            ("bgg-essentials", "Essentials"),
            ("bgg-lifestyle", "Lifestyle"),
        ]
        for g in budgetGroups {
            try apply("createBudgetGroup", [
                "id": .string(g.id), "ledgerId": .string("personal"), "name": .string(g.name)])
        }

        let budgets: [(name: String, amount: Double, cat: String, group: String?)] = [
            ("Rent", 1500, "cat-rent", "bgg-essentials"),
            ("Groceries", 600, "cat-groceries", "bgg-essentials"),
            ("Utilities", 150, "cat-utilities", "bgg-essentials"),
            ("Transport", 200, "cat-transport", "bgg-essentials"),
            ("Dining", 300, "cat-dining", "bgg-lifestyle"),
            ("Shopping", 400, "cat-shopping", "bgg-lifestyle"),
            ("Entertainment", 120, "cat-entertainment", "bgg-lifestyle"),
            ("Health", 100, "cat-health", nil),                 // ungrouped (shows both states)
        ]
        for b in budgets {
            var args: [String: JSONValue] = [
                "ledgerId": .string("personal"), "name": .string(b.name), "type": .string("expense"),
                "amount": .double(b.amount), "frequency": .string("monthly"),
                "startDate": .string(monthStart(3)),
                "categoryIds": .array([.string(b.cat)])]
            if let g = b.group { args["groupId"] = .string(g) }
            try apply("createBudget", args)
        }
```

- **Two groups** ("Essentials", "Lifestyle") created via `createBudgetGroup` (ids
  `bgg-…`, like the account groups' `grp-…`).
- **8 budgets** (was 4): 4 in Essentials, 3 in Lifestyle, **Health left ungrouped** so the
  page also shows the ungrouped section. All categories already exist in the seed.
- `createBudget` accepts `groupId` (→ `budgets.group_id`), passed only when set.

## Out of scope
- The minimal/production starter seed (real users) — unchanged. Engine/model changes —
  none. Account-group changes — none.

## Testing
- **Build:** FinchApp (iOS) + FinchMac (macOS).
- **Manual (sim):** wipe app data so the demo re-seeds (uninstall/reinstall, or delete the
  DB), open **Budgets** → see **Essentials** (Rent/Groceries/Utilities/Transport) and
  **Lifestyle** (Dining/Shopping/Entertainment) group sections + an ungrouped **Health**.

## Notes
- Collision: `FinchStore.swift` is core/active — keep the diff to this one block, re-check
  `gh pr list` before pushing. PR targets `feat/frontend`.
