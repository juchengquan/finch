# Accounts group parity — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (or executing-plans). Checkbox steps. The design doc beside this is authoritative; **the shipped Budgets implementation is the reference** — mirror it, don't invent.

**Goal:** Accounts ⋯ gets Add Group (full sheet: name+color+account picker) replacing Manage Groups; empty groups render; color dots on headers + reorder editor; dead group-admin views removed. UI-only (engine shipped in #485).

## Global Constraints
- Builds: FinchApp (iOS) + FinchMac (macOS) `** BUILD SUCCEEDED **`; `AccountReorderTests` must stay 12/12. No `Co-Authored-By`. No engine/web changes. PR → `feat/frontend`.

---

### Task 1: AccountsTab — Add Group sheet + empty groups + dots

**Files:** Modify `Tabs/AccountsTab.swift`, `FinchStore+ViewHelpers.swift`; reference `Tabs/BudgetsTab.swift` (the shipped mirror source).

- [ ] **Step 1 (empty groups):** in `FinchStore+ViewHelpers.swift`, replace `accountGroupsOrdered`'s body (first-appearance walk over `accounts`) with `accountGroups.map(\.name)` + a comment mirroring the Budgets one ("includes EMPTY groups — a freshly added group shows immediately"). Leave `accounts(in:)`/`subtotalDisplay` untouched.
- [ ] **Step 2 (⋯ item):** in AccountsTab's `standardToolbar`, replace the Manage Groups item (`showingGroups = true`, line ~142) with the Add Group item — mirror BudgetsTab's exactly: `Button { addingGroup = true } label: { Label("Add Group", systemImage: "folder.badge.plus") }`. Swap state `showingGroups` → `addingGroup = false`; replace the `.sheet(isPresented: $showingGroups) { NavigationStack { AccountGroupsView() } }` with `.sheet(isPresented: $addingGroup) { AddAccountGroupSheet() }`.
- [ ] **Step 3 (sheet):** append `AddAccountGroupSheet` to AccountsTab.swift — copy BudgetsTab's `AddGroupSheet` wholesale and adapt: `store.ungroupedAccounts` / `store.accountGroupsOrdered` / `store.accounts(in: g)` for the picker sections (name via `a.name ?? "—"`); selection set of account ids; footer text *"Select accounts below to move them into this new group (optional)."*; `add()` creates `ag-<uuid8>` via `.createAccountGroup` (+color) then `.updateAccount` groupId patches; ✕/✓ toolbar; `.listSectionSpacing(10)` iOS; row insets 4/20.
- [ ] **Step 4 (dots):** group-header Button label in `groupedSections` (before `Text(groupName)`): `if let hex = store.accountGroups.first(where: { $0.name == groupName })?.color, let c = Color(hex: hex) { Circle().fill(c).frame(width: 8, height: 8) }`. Same dot in `reorderList`'s real-group rows resolved by gid (mirror BudgetsTab's editor dot).
- [ ] **Step 5:** build iOS; commit AccountsTab + ViewHelpers: `feat(ios): Accounts — Add Group sheet (name+color+member picker), empty groups render, group color dots`.

---

### Task 2: Dead-code removal

**Files:** Delete `WriteScreens/AccountManagementViews.swift`'s `AccountGroupsView` struct (keep the file's other content); delete `Common/GroupAdminView.swift` entirely; fix BudgetsTab's stale comment referencing GroupAdminView.

- [ ] **Step 1:** `git grep -n "GroupAdminView\|AccountGroupsView"` — confirm the only remaining references are the ones being deleted + BudgetsTab's comment. If ANYTHING else consumes them, STOP and report instead of deleting.
- [ ] **Step 2:** remove `AccountGroupsView`; delete `GroupAdminView.swift`; update BudgetsTab's comment (the "(Group reordering lives inside Manage Groups — GroupAdminView …)" note → "(Group reorder lives in the Reorder editor; create via Add Group.)").
- [ ] **Step 3:** `xcodegen generate` (file removed) + build BOTH platforms + run `-only-testing:FinchAppTests/AccountReorderTests` (12/12). Commit: `chore(ios): remove dead group-admin views (GroupAdminView, AccountGroupsView)`.

---

### Task 3: Verification (controller)
- [ ] Builds + tests from Tasks 1–2. Sim (ios-finch2): SQL-insert an empty colored account group → renders with dot + $0.00 subtotal; ⋯ shows Add Group, no Manage Groups. DB spot-check after a human sheet-create. Human pass: sheet flow + dots + reorder editor dot.

---

## Self-review notes
- Mirror-source discipline: every Task-1 element points at the shipped Budgets twin. ✓
- `accountGroupsOrdered` change preserves order semantics (store.accountGroups is projected ORDER BY sort_order, name — same source the old walk reflected transitively). Search behavior: `groupsToShow` filters empty-on-search as before. ✓
- Strings all exist in catalog except the accounts-variant footer prompt → note for zh batch. ✓
- Dead-code deletion gated on a grep proof (Task 2 Step 1). ✓
