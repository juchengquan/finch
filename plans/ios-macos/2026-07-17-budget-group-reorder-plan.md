# Budgets group reorder — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (or executing-plans). Checkbox steps.

**Goal:** Budgets group order follows `sort_order`; long-press a group header → Reorder/Edit/Delete; a groups-only reorder sheet persists the new order.

**Architecture:** 2-line `budgetGroupsOrdered` fix (ViewHelpers) + BudgetsTab additions mirroring AccountsTab's group menu, plus a small `BudgetGroupReorderSheet`. No engine change.

Spec: `plans/ios-macos/2026-07-17-budget-group-reorder-design.md`.

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS) — both `** BUILD SUCCEEDED **`. No `Co-Authored-By`. No engine change. PR → `feat/frontend`.
- `BudgetsTab.swift`/`FinchStore+ViewHelpers.swift` are hot — keep edits to the listed spots; **re-check `gh pr list` + rebase before pushing**.

---

### Task 1: Ordering fix

**Files:** Modify `ios/FinchApp/Sources/FinchApp/FinchStore+ViewHelpers.swift`

- [ ] **Step 1:** Replace `budgetGroupsOrdered` (line ~185):

```swift
    public var budgetGroupsOrdered: [String] {
        var seen = Set<String>(); var out: [String] = []
        for b in budgets {
            guard let g = b.groupId.flatMap({ budgetGroupNames[$0] }) else { continue }
            if seen.insert(g).inserted { out.append(g) }
        }
        return out
    }
```
with:

```swift
    /// Group names in `budget_groups.sort_order` (store.budgetGroups is projected
    /// ORDER BY sort_order, name), keeping only groups that have budgets — same
    /// hide-empty behavior as before, but the order now honors user reordering.
    public var budgetGroupsOrdered: [String] {
        let used = Set(budgets.compactMap(\.groupId))
        return budgetGroups.filter { used.contains($0.id) }.map(\.name)
    }
```
(No unit test: this is store-bound; persistence + ordering are verified on the sim in Task 3.)

---

### Task 2: BudgetsTab — context menu + reorder sheet

**Files:** Modify `ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift`

- [ ] **Step 1: State.** After `@State private var searchQuery = ""` (line ~26), add:

```swift
    @State private var reorderingGroups = false
    @State private var reorderGroupsDraft: [GroupRow] = []
    @State private var renamingGroupId: String?
    @State private var renameText = ""
    @State private var groupPendingDelete: GroupRow?
```

- [ ] **Step 2: Context menu.** On the group-header Button in `groupedSections`, after `.accessibilityHint(...)` (line ~166), add:

```swift
                .contextMenu {
                    Button {
                        let used = Set(store.budgets.compactMap(\.groupId))
                        reorderGroupsDraft = store.budgetGroups.filter { used.contains($0.id) }
                        reorderingGroups = true
                    } label: { Label("Reorder", systemImage: "arrow.up.arrow.down") }
                    if let g = store.budgetGroups.first(where: { $0.name == groupName }) {
                        Button { renamingGroupId = g.id; renameText = g.name } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { groupPendingDelete = g } label: { Label("Delete Group", systemImage: "trash") }
                    }
                }
```

- [ ] **Step 3: Presentations.** After `.errorAlert($errorMessage)` (line ~56), add:

```swift
            .sheet(isPresented: $reorderingGroups) {
                BudgetGroupReorderSheet(groups: $reorderGroupsDraft,
                                        counts: Dictionary(grouping: store.budgets.compactMap(\.groupId), by: { $0 }).mapValues(\.count),
                                        onDone: persistGroupOrder)
            }
            .alert("Rename group", isPresented: Binding(
                get: { renamingGroupId != nil },
                set: { if !$0 { renamingGroupId = nil } })) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") { renameGroup() }
            }
            .confirmationDialog("Delete group?", isPresented: Binding(
                get: { groupPendingDelete != nil },
                set: { if !$0 { groupPendingDelete = nil } }),
                presenting: groupPendingDelete) { g in
                Button("Delete \(g.name)", role: .destructive) { deleteGroup(g) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Budgets in this group become ungrouped.")
            }
```

- [ ] **Step 4: Functions.** Next to the existing `delete(_ budget:)` (line ~195), add:

```swift
    private func persistGroupOrder(_ groups: [GroupRow]) {
        do {
            for (i, g) in groups.enumerated() {
                try store.apply(.updateBudgetGroup, Args(["id": .string(g.id), "patch": .object(["sortOrder": .int(i)])]))
            }
        } catch { errorMessage = i18nMessage(error) }
    }
    private func renameGroup() {
        guard let id = renamingGroupId else { return }
        let name = renameText.trimmingCharacters(in: .whitespaces)
        renamingGroupId = nil
        guard !name.isEmpty else { return }
        do { try store.apply(.updateBudgetGroup, Args(["id": .string(id), "patch": .object(["name": .string(name)])])) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func deleteGroup(_ g: GroupRow) {
        do { try store.apply(.deleteBudgetGroup, Args(["id": .string(g.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
```

- [ ] **Step 5: The sheet.** At file end (after the existing private structs), add:

```swift
/// Groups-only reorder: each row IS the whole group (budgets can't be ordered
/// within a group — no budgets.sort_order in the shared schema), so dragging a
/// row moves the block by construction. Done renumbers budget_groups.sort_order.
private struct BudgetGroupReorderSheet: View {
    @Binding var groups: [GroupRow]
    let counts: [String: Int]
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(groups); dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 320)
        #endif
    }
}
```
(Note: `.navigationBarTitleDisplayMode` is shimmed no-op on macOS via PlatformCompat, so the `#if` is belt-and-braces — match whichever style neighboring sheets use if it differs.)

- [ ] **Step 6: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit** (both files, one commit)

```bash
git add ios/FinchApp/Sources/FinchApp/FinchStore+ViewHelpers.swift ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift
git commit -m "feat(ios): Budgets group reorder (groups-as-blocks) + honor budget_groups.sort_order"
```

---

### Task 3: Manual simulator verification

**Files:** none.

- [ ] **Step 1:** Build to `/tmp/bg-dd`, install on SIM `9500E54A-BC34-42E1-BC02-BC5E906B6901` (keep existing demo data — Essentials/Lifestyle + ungrouped Health), launch `-initialTab budgets`, screenshot the current group order.
- [ ] **Step 2: Persistence check via DB** (long-press isn't automatable; verify the engine path directly):

```bash
C=$(xcrun simctl get_app_container "$SIM" com.juchengquan.finch data); DB="$C/Library/Application Support/finch.sqlite3"
sqlite3 "$DB" "SELECT id,name,sort_order FROM budget_groups ORDER BY sort_order;"
# swap the two groups' sort_order, relaunch, screenshot: the page must show the new order
xcrun simctl terminate "$SIM" com.juchengquan.finch
sqlite3 "$DB" "UPDATE budget_groups SET sort_order = CASE name WHEN 'Essentials' THEN 1 ELSE 0 END WHERE name IN ('Essentials','Lifestyle');"
xcrun simctl launch "$SIM" com.juchengquan.finch -initialTab budgets
```
Expected: **Lifestyle now renders above Essentials** (proves the §1 ordering fix); ungrouped Health stays bare at top (#390). Restore the original order after. Screenshots `/tmp/bg-before.png` / `/tmp/bg-after.png`.
- [ ] **Step 3:** Report (the context menu + sheet flow itself is human-verified post-merge — long-press isn't scriptable); clean `/tmp/bg-dd`.

---

## Self-review notes
- Spec coverage: ordering fix (T1); menu + presentations + funcs + sheet (T2); builds (T2 S6); sim ordering/persistence proof (T3). ✓
- Consistency: `GroupRow` (budget groups) vs Accounts' `AccountGroupRow` typealias — same type; `updateBudgetGroup`/`deleteBudgetGroup` handlers verified; `errorMessage` + `i18nMessage` exist in BudgetsTab; `reorderGroupsDraft` filter matches `budgetGroupsOrdered`'s hide-empty rule. ✓
- New user-facing strings ("Reorder Groups", "· %lld budgets", "Budgets in this group become ungrouped.", "Rename group", "Delete group?") — English fallback until next zh batch (note in PR; "Rename group"/"Delete group?" already exist in the catalog from Accounts). ✓
