# Ungrouped items render bare at the top (no "Ungrouped" group)

**Date:** 2026-06-27
**Status:** Design approved, pending implementation
**Scope:** In the Accounts and Budgets lists, items with no group render as plain rows at the **top**, instead of inside a synthetic **"Ungrouped"** section. UI-only, no engine change.

## Problem

`accountGroupsOrdered` / `budgetGroupsOrdered` fold no-group items into a literal
`"Ungrouped"` group (positioned wherever the first such item falls), and the tabs render it
as a normal collapsible section with a header + subtotal. Desired: ungrouped items pinned to
the top as **bare rows** — no "Ungrouped" header, subtotal, or collapse.

Accounts + Budgets are the **only** grouped lists with this fallback ("all other pages" =
these two). The reorder/edit sheet (`AccountReorder`) keeps its labeled "Ungrouped" drop
bucket — unchanged (edit-mode needs the drop target).

## Design

### 1. `FinchStore+ViewHelpers.swift`

Make the ordered-group lists return **named groups only**, and add ungrouped accessors:

```swift
    public var accountGroupsOrdered: [String] {
        var seen = Set<String>(); var out: [String] = []
        for a in accounts { guard let g = a.groupName else { continue }; if seen.insert(g).inserted { out.append(g) } }
        return out
    }
    /// Accounts with no group — rendered bare at the top of the list.
    public var ungroupedAccounts: [AccountRow] { accounts.filter { $0.groupName == nil } }
```
```swift
    public var budgetGroupsOrdered: [String] {
        var seen = Set<String>(); var out: [String] = []
        for b in budgets {
            guard let g = b.groupId.flatMap({ budgetGroupNames[$0] }) else { continue }
            if seen.insert(g).inserted { out.append(g) }
        }
        return out
    }
    /// Budgets with no (resolvable) group — rendered bare at the top.
    public var ungroupedBudgets: [BudgetRow] {
        budgets.filter { $0.groupId.flatMap { budgetGroupNames[$0] } == nil }
    }
```
(`accounts(in:)` / `budgets(in:)` stay as-is — they're now only called with real names.)

### 2. `AccountsTab.swift`

Add a search-filtered ungrouped accessor (mirrors `filteredAccounts(in:)`):
```swift
    private var filteredUngroupedAccounts: [AccountRow] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let accts = store.ungroupedAccounts
        guard !q.isEmpty else { return accts }
        return accts.filter { ($0.name ?? "").lowercased().contains(q) }
    }
```
In `groupedSections`, extend the empty-state to consider ungrouped, and emit a **header-less
section** of ungrouped rows **before** the group `ForEach`:
```swift
        if searchActive && groupsToShow.isEmpty && filteredUngroupedAccounts.isEmpty {
            Section { Text("No matching accounts").foregroundStyle(.secondary) }
        }
        if !filteredUngroupedAccounts.isEmpty {
            Section { ForEach(filteredUngroupedAccounts) { account in row(account) } }
        }
        ForEach(groupsToShow, id: \.self) { groupName in
            …existing…
```
(No `onMove` on the bare section — reorder stays in the edit sheet.)

### 3. `BudgetsTab.swift`

Identical pattern:
```swift
    private var filteredUngroupedBudgets: [BudgetRow] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let buds = store.ungroupedBudgets
        guard !q.isEmpty else { return buds }
        return buds.filter { $0.name.lowercased().contains(q) }
    }
```
```swift
        if searchActive && groupsToShow.isEmpty && filteredUngroupedBudgets.isEmpty {
            Section { Text("No matching budgets").foregroundStyle(.secondary) }
        }
        if !filteredUngroupedBudgets.isEmpty {
            Section { ForEach(filteredUngroupedBudgets) { budget in row(budget) } }
        }
        ForEach(groupsToShow, id: \.self) { groupName in
            …existing…
```

## Out of scope
- `AccountReorder` edit sheet (keeps its "Ungrouped" bucket). Engine/data changes. Other
  tabs (no "Ungrouped" concept).

## Testing
- **Build:** FinchApp (iOS). (macOS already builds via #385; this doesn't touch that path.)
- **Manual (sim):**
  - **Budgets** → **Health** (ungrouped) appears as a bare row at the **top**, no "Ungrouped"
    header, above Essentials/Lifestyle.
  - **Accounts** → set one demo account's `group_id = NULL` (DB), relaunch → it floats to the
    top as a bare row, no "Ungrouped" header; the named groups follow.

## Notes
- Collision: `AccountsTab`/`BudgetsTab`/`FinchStore+ViewHelpers` are recently-touched; only a
  docs PR (#388) is open. Re-check `gh pr list` before pushing. PR → `feat/frontend`.
