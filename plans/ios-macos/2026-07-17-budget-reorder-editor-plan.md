# Budget Reorder editor + modal chrome — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (or executing-plans). Checkbox steps. The design doc (`…-design.md`) carries the authoritative code shapes — read it first.

**Goal:** Budgets ⋯ → Reorder opens the Accounts-style in-place editor (blocks/expand/cross-group), and reorder mode on BOTH tabs shows only ✕ (cancel) / ✓ (save).

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds. Builds: FinchApp (iOS) + FinchMac (macOS) `** BUILD SUCCEEDED **`. FinchCore/FinchApp test suites must pass where touched (`swift test` from `ios/` for FinchCore; FinchAppTests idiom — read the suite). No `Co-Authored-By`. No engine change (actions all exist). PR → `feat/frontend`.
- **Mirror, don't refactor:** `AccountReorder`/`AccountsTab` are the reference implementation — copy their structure (incl. the exact `#if os(iOS)` gating around `EditMode`) rather than genericizing them.

---

### Task 1: `BudgetReorder` model + tests

**Files:** Create `ios/FinchApp/Sources/FinchApp/Common/BudgetReorder.swift`; Create `ios/FinchApp/Tests/FinchAppTests/BudgetReorderTests.swift`.

- [ ] Read `Common/AccountReorder.swift` (the whole ~150 lines incl. `visibleRows`/`accountCount`/`applyVisibleMove`) and `Tests/FinchAppTests/AccountReorderTests.swift` (12 tests). Write `BudgetReorder.swift` as its mirror over `BudgetRow` (`BudgetReorderRow`: `.group(id:String?,name:String)` / `.item(BudgetRow)`; ids `"g:…"`/`"i:\(id)"`; membership via `b.groupId`), with `plan(_:)` returning `(groups:[(id:String,order:Int)], items:[(id:String, groupId:String?, order:Int)])`.
- [ ] Mirror the full test suite (adjust fixtures: `BudgetRow` minimal init — read `Budget.swift` for required fields; a helper `bgt(_ id:,_ gid:)` like `acct`). Run FinchAppTests (read how — likely `xcodebuild test … -only-testing:FinchAppTests/BudgetReorderTests`; note #458 isolated these tests from the live DB). ALL must pass.
- [ ] Build iOS. Commit the 2 files: `feat(ios): BudgetReorder model — grouped reorder rows for budgets (+tests)`.

---

### Task 2: BudgetsTab editor + modal chrome (both tabs)

**Files:** Modify `Tabs/BudgetsTab.swift`, `Tabs/AccountsTab.swift`.

- [ ] **BudgetsTab** (mirror AccountsTab's structure section-by-section):
  1. State: `editMode` (copy AccountsTab's declaration + gating verbatim), `reorderRows: [BudgetReorderRow] = []`, `expandedReorderGroups: Set<String> = []`.
  2. ⋯ item (iOS-only, after Manage Groups): `Button { withAnimation { editMode = .active } } label: { Label("Reorder", systemImage: "arrow.up.arrow.down") }`.
  3. `.environment(\.editMode, $editMode)` on the content (where AccountsTab puts it, ~its line 146) + `.onChange(of: editMode)`: entering → build rows (`BudgetReorder.buildRows(groups: store.budgetGroups, budgets: store.budgets)`) + `expandedReorderGroups = []`; leaving → `persistReorder(); reorderRows = []`.
  4. `listContent`: `if editMode.isEditing { reorderList } else { …existing… }` (mirror AccountsTab's swap; keep the `#if os(iOS)` shape it uses).
  5. `reorderList`: mirror AccountsTab's — `let collapsed = Set(store.budgetGroups.map(\.id)).subtracting(expandedReorderGroups)`; ForEach over `BudgetReorder.visibleRows(reorderRows, collapsed: collapsed)`; real-group rows = chevron Button (`chevron.right/down`, name, `Text("· \(BudgetReorder.itemCount(of: gid, in: reorderRows)) budgets")`), Ungrouped header = plain secondary Text; item rows = `BudgetRowView(budget:)`; `.onMove { reorderRows = BudgetReorder.applyVisibleMove(reorderRows, collapsed: collapsed, from: $0, to: $1) }`; inner `.environment(\.editMode, .constant(.active))`.
  6. `persistReorder()` (next to `moveBudgets`):
     ```swift
     private func persistReorder() {
         guard !reorderRows.isEmpty else { return }
         let plan = BudgetReorder.plan(reorderRows)
         let curGroupOrder = Dictionary(uniqueKeysWithValues: store.budgetGroups.enumerated().map { ($1.id, $0) })
         let curGroupOf = Dictionary(uniqueKeysWithValues: store.budgets.map { ($0.id, $0.groupId) })
         do {
             for g in plan.groups where curGroupOrder[g.id] != g.order {
                 try store.apply(.updateBudgetGroup, Args(["id": .string(g.id), "patch": .object(["sortOrder": .int(g.order)])]))
             }
             for it in plan.items where curGroupOf[it.id] != it.groupId {
                 try store.apply(.updateBudget, Args(["id": .string(it.id), "patch": .object(["groupId": it.groupId.map(JSONValue.string) ?? .null])]))
             }
             try store.apply(.setBudgetOrder, Args(["ledgerId": .string(store.activeLedgerId),
                                                    "budgetIds": .array(plan.items.map { .string($0.id) })]))
         } catch { errorMessage = i18nMessage(error) }
     }
     ```
- [ ] **Modal chrome, both tabs:** restructure each `.toolbar` into `if editMode.isEditing { ✕ (topBarLeading, iOS) + ✓ (primaryAction) } else { the entire existing set unchanged }` — exact buttons in the design doc. ✕ = `reorderRows = []; withAnimation { editMode = .inactive }`; ✓ = `withAnimation { editMode = .inactive }`. In AccountsTab, remove the old inline `if editMode.isEditing` ✓-in-place-of-+ special case (subsumed). Keep every existing non-edit item byte-identical.
- [ ] Build iOS + macOS (both must pass — the `if` toolbar branches must respect the existing `#if os(iOS)` around `topBarLeading`/editMode). Commit both files: `feat(ios): Budgets Reorder editor (blocks/expand/cross-group) + modal ✕/✓ reorder chrome on both tabs`.

---

### Task 3: Verification (controller)
- [ ] FinchApp tests (both reorder suites) green; builds green.
- [ ] Sim (finch-fresh-6): screenshot Budgets pre-reorder; DB-proof ✓-persistence is impossible to script (drag) — instead verify the *chrome* by entering reorder… (entry = ⋯ menu tap, unscriptable) → rely on tests + code review; human pass post-merge: ⋯ → Reorder → only ✕/✓ visible → drag a collapsed group → ✓ → order persists; ✕ → discards. Same ✕/✓ check on Accounts.

---

## Self-review notes
- plan.items ordering = flat top-to-bottom walk → `setBudgetOrder` ids match the on-screen order incl. cross-group moves; membership diffs via `curGroupOf`. ✓
- Cancel path: `reorderRows = []` before exit → `persistReorder` guard no-ops (same trick as Accounts' guard). ✓
- `"· %lld budgets"` string exists since #461; "Reorder" exists; ✕/✓ are icons + a11y labels ("Cancel"/"Done" exist in catalog). No new fallback strings. ✓
- No engine change; #479 in-list drag untouched; Manage Groups untouched. ✓
