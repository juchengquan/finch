# Budgets: group reorder (groups-as-blocks) + sort-order fix

**Date:** 2026-07-17
**Status:** Design approved, pending implementation
**Scope:** Bring the Accounts "drag a group as a block" experience to Budgets, within what the engine can persist: (1) fix the page's group ordering to follow `budget_groups.sort_order`; (2) long-press context menu on Budgets group headers (Reorder / Edit / Delete, mirroring Accounts); (3) a **groups-only** reorder mode — collapsed rows, drag to reorder, persisted via `updateBudgetGroup sortOrder`. No engine change.

## Constraints that shaped the scope (verified)

- `budget_groups.sort_order` + `updateBudgetGroup {sortOrder}` exist on **both** platforms → group reorder persists. ✓
- `budgets` has **no `sort_order` on web or iOS** (`ORDER BY created_at`; shared pack schema) →
  within-group budget order **cannot** persist. Budget rows are therefore **excluded** from the
  reorder list (no false affordance); cross-group moves stay in Edit Budget's Group picker.
- Bug: `budgetGroupsOrdered` derives group order from first-appearance in the `created_at`-ordered
  budgets array, so the page ignores `sort_order` today. Must fix or reorder wouldn't show.
- Web has the mutation but no reorder UI → iOS-original enhancement (precedented), parity-safe.

## Design

### 1. Ordering fix (`FinchStore+ViewHelpers.swift`)

```swift
    public var budgetGroupsOrdered: [String] {
        let used = Set(budgets.compactMap(\.groupId))
        return budgetGroups.filter { used.contains($0.id) }.map(\.name)
    }
```
(`store.budgetGroups: [GroupRow]` is already projected `ORDER BY sort_order, name` and includes
empty groups — the `used` filter preserves today's hide-empty behavior. `budgets(in:)` unchanged.)

### 2. Group-header context menu (`BudgetsTab.swift`, mirrors AccountsTab)

New state (mirroring Accounts lines 30–32):
```swift
    @State private var reorderingGroups = false
    @State private var renamingGroupId: String?
    @State private var renameText = ""
    @State private var groupPendingDelete: GroupRow?
```
On the group-header Button in `groupedSections`, add:
```swift
                .contextMenu {
                    Button { reorderGroupsDraft = store.budgetGroups.filter { g in store.budgets.contains { $0.groupId == g.id } }
                             reorderingGroups = true } label: { Label("Reorder", systemImage: "arrow.up.arrow.down") }
                    if let g = store.budgetGroups.first(where: { $0.name == groupName }) {
                        Button { renamingGroupId = g.id; renameText = g.name } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { groupPendingDelete = g } label: { Label("Delete Group", systemImage: "trash") }
                    }
                }
```
Plus the rename `.alert` + delete `.confirmationDialog` mirroring Accounts verbatim
(`updateBudgetGroup {name}` / `deleteBudgetGroup`; message: "Budgets in this group become
ungrouped." — `ON DELETE SET NULL`, same as accounts).

### 3. Groups-only reorder sheet

State: `@State private var reorderGroupsDraft: [GroupRow] = []`. Presented as a sheet
(`.sheet(isPresented: $reorderingGroups)`) — simpler than Accounts' in-place editMode swap
because there are no item rows to interleave:

```swift
struct BudgetGroupReorderSheet: View {   // private, in BudgetsTab.swift
    @EnvironmentObject private var store: FinchStore
    @Binding var groups: [GroupRow]
    let counts: [String: Int]                       // groupId → budget count
    var onDone: ([GroupRow]) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { g in
                    HStack(spacing: 6) {
                        Text(g.name).fontWeight(.semibold)
                        Text("· \(counts[g.id] ?? 0) budgets").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .onMove { groups.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Groups")
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onDone(groups); dismiss() } } }
        }
    }
}
```
`onDone` persists by renumbering: `for (i, g) in groups.enumerated() {
try store.apply(.updateBudgetGroup, Args(["id": .string(g.id), "patch": .object(["sortOrder": .int(i)])])) }`
(errors → the tab's existing `errorMessage`). A collapsed row *is* the group — the block moves by
construction; the page re-renders in the new order via the §1 fix.

## Out of scope
- Budget rows in the reorder list (within-group order can't persist — engine/web parity).
- Adding `budgets.sort_order` (schema divergence). Accounts-style flat editor. Web UI. Engine changes.

## Testing
- **Unit:** `budgetGroupsOrdered` — respects `budgetGroups` order; hides empty groups. (ViewHelpers
  is store-bound; if not cheaply testable, verify via sim + code review and say so.)
- **Build:** FinchApp (iOS) + FinchMac (macOS).
- **Manual (sim, demo seed: Essentials/Lifestyle + ungrouped Health):** long-press a group header →
  menu shows Reorder/Edit/Delete; Reorder sheet lists collapsed group rows with counts; drag
  Lifestyle above Essentials → Done → **the page shows Lifestyle first** and persists across
  relaunch (sort_order written). Rename + delete-group flows work (Health stays bare/top per #390).

## Notes
- Collision: `BudgetsTab.swift`/ViewHelpers are hot — re-check `gh pr list` + rebase before pushing.
  New strings ("Reorder Groups", "· N budgets", "Budgets in this group become ungrouped.") →
  English fallback until the next zh batch. PR → `feat/frontend`.
