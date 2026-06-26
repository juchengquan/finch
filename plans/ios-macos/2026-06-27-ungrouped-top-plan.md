# Ungrouped-at-top — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven). Checkbox steps.

**Goal:** Ungrouped accounts/budgets render as bare rows at the top of their list, with no "Ungrouped" group section.

**Architecture:** Helpers return named groups only + expose ungrouped items; each tab renders a header-less ungrouped section before the group `ForEach`. UI-only.

Spec: `plans/ios-macos/2026-06-27-ungrouped-top-design.md`.

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Build: FinchApp (iOS) must `** BUILD SUCCEEDED **`. (macOS unaffected — no `.wheel`/ScheduledCalendar touch.) No `Co-Authored-By`. No engine change. PR → `feat/frontend`.
- `AccountsTab`/`BudgetsTab`/`FinchStore+ViewHelpers` are recently-touched — keep edits to the listed blocks; **re-check `gh pr list --base feat/frontend --state open` before pushing**.

---

### Task 1: Helpers — named groups only + ungrouped accessors

**Files:** Modify `ios/FinchApp/Sources/FinchApp/FinchStore+ViewHelpers.swift`

- [ ] **Step 1:** Replace `accountGroupsOrdered` to skip ungrouped, and add `ungroupedAccounts`:

```swift
    public var accountGroupsOrdered: [String] {
        var seen = Set<String>(); var out: [String] = []
        for a in accounts { let g = a.groupName ?? "Ungrouped"; if seen.insert(g).inserted { out.append(g) } }
        return out
    }
```
→

```swift
    public var accountGroupsOrdered: [String] {
        var seen = Set<String>(); var out: [String] = []
        for a in accounts { guard let g = a.groupName else { continue }; if seen.insert(g).inserted { out.append(g) } }
        return out
    }
    /// Accounts with no group — rendered bare at the top of the list (no "Ungrouped" header).
    public var ungroupedAccounts: [AccountRow] { accounts.filter { $0.groupName == nil } }
```

- [ ] **Step 2:** Replace `budgetGroupsOrdered` to skip ungrouped, and add `ungroupedBudgets`:

```swift
    public var budgetGroupsOrdered: [String] {
        var seen = Set<String>(); var out: [String] = []
        for b in budgets {
            let g = b.groupId.flatMap { budgetGroupNames[$0] } ?? "Ungrouped"
            if seen.insert(g).inserted { out.append(g) }
        }
        return out
    }
```
→

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
(Leave `accounts(in:)` / `budgets(in:)` unchanged.)

---

### Task 2: AccountsTab — ungrouped bare section at top

**Files:** Modify `ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift`

- [ ] **Step 1:** After the `filteredAccounts(in:)` method, add:

```swift
    /// Ungrouped accounts, narrowed by the search query — rendered bare at the top.
    private var filteredUngroupedAccounts: [AccountRow] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let accts = store.ungroupedAccounts
        guard !q.isEmpty else { return accts }
        return accts.filter { ($0.name ?? "").lowercased().contains(q) }
    }
```

- [ ] **Step 2:** In `groupedSections`, replace the empty-state + ForEach head:

```swift
        if searchActive && groupsToShow.isEmpty {
            Section { Text("No matching accounts").foregroundStyle(.secondary) }
        }
        ForEach(groupsToShow, id: \.self) { groupName in
```
→

```swift
        if searchActive && groupsToShow.isEmpty && filteredUngroupedAccounts.isEmpty {
            Section { Text("No matching accounts").foregroundStyle(.secondary) }
        }
        // Ungrouped accounts: bare rows pinned to the top, no "Ungrouped" header.
        if !filteredUngroupedAccounts.isEmpty {
            Section { ForEach(filteredUngroupedAccounts) { account in row(account) } }
        }
        ForEach(groupsToShow, id: \.self) { groupName in
```

---

### Task 3: BudgetsTab — ungrouped bare section at top

**Files:** Modify `ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift`

- [ ] **Step 1:** After the `filteredBudgets(in:)` method, add:

```swift
    /// Ungrouped budgets, narrowed by the search query — rendered bare at the top.
    private var filteredUngroupedBudgets: [BudgetRow] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let buds = store.ungroupedBudgets
        guard !q.isEmpty else { return buds }
        return buds.filter { $0.name.lowercased().contains(q) }
    }
```

- [ ] **Step 2:** In `groupedSections`, replace the empty-state + ForEach head:

```swift
        if searchActive && groupsToShow.isEmpty {
            Section { Text("No matching budgets").foregroundStyle(.secondary) }
        }
        ForEach(groupsToShow, id: \.self) { groupName in
```
→

```swift
        if searchActive && groupsToShow.isEmpty && filteredUngroupedBudgets.isEmpty {
            Section { Text("No matching budgets").foregroundStyle(.secondary) }
        }
        // Ungrouped budgets: bare rows pinned to the top, no "Ungrouped" header.
        if !filteredUngroupedBudgets.isEmpty {
            Section { ForEach(filteredUngroupedBudgets) { budget in row(budget) } }
        }
        ForEach(groupsToShow, id: \.self) { groupName in
```

- [ ] **Step 3: Regenerate + build iOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/FinchStore+ViewHelpers.swift ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift ios/FinchApp/Sources/FinchApp/Tabs/BudgetsTab.swift
git commit -m "feat(ios): ungrouped accounts/budgets render bare at the top (drop Ungrouped group)"
```

---

### Task 4: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Build to a known path + install:**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
cd ios && xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/ug-dd >/dev/null 2>&1
xcrun simctl list devices booted | grep -q "$SIM" || { xcrun simctl boot "$SIM"; open -a Simulator; sleep 5; }
xcrun simctl terminate "$SIM" com.juchengquan.finch 2>/dev/null
xcrun simctl install "$SIM" /tmp/ug-dd/Build/Products/Debug-iphonesimulator/FinchApp.app
xcrun simctl launch "$SIM" com.juchengquan.finch -initialTab budgets
```
(If the ledger is empty, uninstall→reinstall first so the demo re-seeds — it has ungrouped Health.)

- [ ] **Step 2: Verify Budgets** → **Health** is a bare row at the **top**, no "Ungrouped"
  header, above Essentials/Lifestyle. Screenshot `/tmp/ug-budgets.png`.

- [ ] **Step 3: Verify Accounts** — make one account ungrouped, relaunch:

```bash
C=$(xcrun simctl get_app_container "$SIM" com.juchengquan.finch data); DB="$C/Library/Application Support/finch.sqlite3"
sqlite3 "$DB" "UPDATE accounts SET group_id=NULL WHERE id='cash';"
xcrun simctl terminate "$SIM" com.juchengquan.finch 2>/dev/null
xcrun simctl launch "$SIM" com.juchengquan.finch -initialTab accounts
```
Confirm **Cash** floats to the **top** as a bare row (no "Ungrouped" header); named groups
follow. Screenshot `/tmp/ug-accounts.png`. Clean up `/tmp/ug-dd` after.

- [ ] **Step 4 (no commit):** report; if a check fails, return to the relevant task.

---

## Self-review notes
- Spec coverage: helpers named-only + ungrouped accessors (T1); AccountsTab bare section + empty-state (T2); BudgetsTab same (T3); build (T3 S3); manual budgets + accounts (T4). ✓
- Type consistency: `ungroupedAccounts: [AccountRow]`, `ungroupedBudgets: [BudgetRow]`; `filteredUngrouped*` mirror `filtered*(in:)`; `accounts(in:)`/`budgets(in:)` unchanged. ✓
- No engine change; reorder sheet untouched; macOS path untouched. ✓
