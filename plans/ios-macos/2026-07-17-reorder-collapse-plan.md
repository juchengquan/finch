# Reorder collapsed groups — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (or executing-plans). Checkbox steps.

**Goal:** Accounts reorder mode shows each group as a single collapsed row (drag = whole block travels); tap to expand for cross-group account moves.

**Architecture:** 3 pure functions on `AccountReorder` (`visibleRows`, `accountCount`, `applyVisibleMove` → existing `applyMove`) + a reworked `reorderList` with an `expandedReorderGroups` state. Unit tests extend the existing suite. No engine change.

Spec: `plans/ios-macos/2026-07-17-reorder-collapse-design.md`.

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS) — both `** BUILD SUCCEEDED **`. Unit tests must pass. No `Co-Authored-By`. No engine change. PR → `feat/frontend`.
- `AccountsTab.swift` is hot (#455 recent) — keep edits to the listed spots; **re-check `gh pr list` + rebase before pushing**.

---

### Task 1: Pure logic + unit tests

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Common/AccountReorder.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/AccountReorderTests.swift`

- [ ] **Step 1: Add the three functions** inside `enum AccountReorder` (after `applyMove`, before `rebuildWithGroupOrder`):

```swift
    /// Rows visible when `collapsed` groups hide their account rows. Ungrouped
    /// accounts (current header == nil) are always visible.
    static func visibleRows(_ rows: [ReorderRow], collapsed: Set<String>) -> [ReorderRow] {
        var out: [ReorderRow] = []; var current: String? = nil
        for r in rows {
            switch r {
            case .group(let id, _): current = id; out.append(r)
            case .account: if current == nil || !collapsed.contains(current!) { out.append(r) }
            }
        }
        return out
    }

    /// Number of accounts under a real group header (for the collapsed row label).
    static func accountCount(of groupId: String, in rows: [ReorderRow]) -> Int {
        var current: String? = nil; var n = 0
        for r in rows {
            switch r {
            case .group(let id, _): current = id
            case .account: if current == groupId { n += 1 }
            }
        }
        return n
    }

    /// Translate a move expressed in *visible* indices into the full row array,
    /// then apply the existing rules. The destination maps to the full index of
    /// the visible row at `destination` (or past the end) — so dropping an
    /// account just below a collapsed header lands at the END of that group.
    static func applyVisibleMove(_ rows: [ReorderRow], collapsed: Set<String>,
                                 from source: IndexSet, to destination: Int) -> [ReorderRow] {
        let vis = visibleRows(rows, collapsed: collapsed)
        guard let vSrc = source.first, vSrc < vis.count else { return rows }
        guard let fSrc = rows.firstIndex(of: vis[vSrc]) else { return rows }
        let fDst = destination >= vis.count ? rows.count
                 : (rows.firstIndex(of: vis[destination]) ?? rows.count)
        return applyMove(rows, from: IndexSet(integer: fSrc), to: fDst)
    }
```

- [ ] **Step 2: Add unit tests** at the end of `final class AccountReorderTests` (fixtures `groups`/`accounts`/`acct` already exist; full rows = `["g:g1:Bank","a:a1","a:a2","g:g2:Cards","a:a3","g:ungrouped:Ungrouped","a:a4"]`):

```swift
    func test_visibleRows_hidesCollapsedGroupAccounts_keepsUngrouped() {
        let rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        let vis = AccountReorder.visibleRows(rows, collapsed: ["g1"])
        XCTAssertEqual(vis.map(\.id), ["g:g1:Bank", "g:g2:Cards", "a:a3", "g:ungrouped:Ungrouped", "a:a4"])
    }

    func test_accountCount_countsPerGroup() {
        let rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        XCTAssertEqual(AccountReorder.accountCount(of: "g1", in: rows), 2)
        XCTAssertEqual(AccountReorder.accountCount(of: "g2", in: rows), 1)
    }

    func test_visibleMove_collapsedGroup_movesWholeBlock() {
        let rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        // both groups collapsed → visible: [g1, g2, Ungrouped, a4]; drag g1 (0) below g2 (dest 2)
        let out = AccountReorder.applyVisibleMove(rows, collapsed: ["g1", "g2"], from: IndexSet(integer: 0), to: 2)
        XCTAssertEqual(out.map(\.id), ["g:g2:Cards", "a:a3", "g:g1:Bank", "a:a1", "a:a2", "g:ungrouped:Ungrouped", "a:a4"])
    }

    func test_visibleMove_accountBelowCollapsedHeader_joinsThatGroupsEnd() {
        let rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        // g1 collapsed → visible: [g1, g2, a3, Ungrouped, a4]; drag a4 (vis 4) to just below g2's a3 → dest 3 (before Ungrouped)
        let out = AccountReorder.applyVisibleMove(rows, collapsed: ["g1"], from: IndexSet(integer: 4), to: 3)
        let plan = AccountReorder.persistencePlan(out)
        XCTAssertEqual(plan.accounts.first { $0.id == "a4" }?.groupId, "g2")
    }

    func test_visibleMove_noCollapse_matchesApplyMove() {
        let rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        let a = AccountReorder.applyVisibleMove(rows, collapsed: [], from: IndexSet(integer: 1), to: 5)
        let b = AccountReorder.applyMove(rows, from: IndexSet(integer: 1), to: 5)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
    }
```

- [ ] **Step 3: Run the unit tests**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:FinchAppTests/AccountReorderTests 2>&1 | grep -E "Test Suite 'AccountReorderTests'|Executed|error" | tail -3
```
Expected: all (7 existing + 5 new = 12) pass. If an expectation mismatches, print the actual `out.map(\.id)` and reconcile against `applyMove`'s documented rules — fix the TEST only if the behavior matches the spec's intent; otherwise fix the logic.

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Common/AccountReorder.swift ios/FinchApp/Tests/FinchAppTests/AccountReorderTests.swift
git commit -m "feat(ios): AccountReorder visible-rows model (collapsed groups) + tests"
```

---

### Task 2: Reorder UI — collapsed group rows

**Files:** Modify `ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift`

- [ ] **Step 1: State.** Near `@State private var reorderRows` (line ~36), add:

```swift
    @State private var expandedReorderGroups: Set<String> = []   // reorder mode: groups start collapsed
```

- [ ] **Step 2: Reset on entry.** In `.onChange(of: editMode)` (line ~133), where `reorderRows` is built on `mode.isEditing`, also reset:

```swift
                    expandedReorderGroups = []
```
(inside the same `if mode.isEditing` branch, next to the `buildRows` call.)

- [ ] **Step 3: Rework `reorderList`** (line ~294). Replace the whole computed property with:

```swift
    private var reorderList: some View {
        let collapsed = Set(store.accountGroups.map(\.id)).subtracting(expandedReorderGroups)
        return List {
            ForEach(AccountReorder.visibleRows(reorderRows, collapsed: collapsed)) { row in
                switch row {
                case .group(let gid, let name):
                    if let gid {
                        // Collapsed-by-default group row: the drag handle moves the whole block.
                        Button {
                            if expandedReorderGroups.contains(gid) { expandedReorderGroups.remove(gid) }
                            else { expandedReorderGroups.insert(gid) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: expandedReorderGroups.contains(gid) ? "chevron.down" : "chevron.right")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 12)
                                Text(name).fontWeight(.semibold)
                                Text("· \(AccountReorder.accountCount(of: gid, in: reorderRows)) accounts")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(name).fontWeight(.semibold).foregroundStyle(.secondary)
                    }
                case .account(let a):
                    AccountRowView(account: a)
                }
            }
            .onMove { from, to in
                reorderRows = AccountReorder.applyVisibleMove(reorderRows, collapsed: collapsed, from: from, to: to)
            }
        }
        .environment(\.editMode, .constant(.active))
    }
```

- [ ] **Step 4: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift
git commit -m "feat(ios): Accounts reorder mode collapses groups — dragging a group moves the whole block visibly"
```

---

### Task 3: Manual simulator verification

**Files:** none.

- [ ] **Step 1:** Build to `/tmp/rc-dd`, fresh-install (demo seed: 4 groups / 9 accounts), launch `-initialTab accounts`.
- [ ] **Step 2:** Long-press a group header → **Reorder** → the sheet/list shows **collapsed group rows with counts** (`· 3 accounts`). Screenshot `/tmp/rc-reorder.png`. (The drag itself isn't automatable — verified by the unit tests; visually confirm the collapsed rows + chevron expand/collapse by tapping if reachable.)
- [ ] **Step 3:** Report; clean `/tmp/rc-dd`.

---

## Self-review notes
- Spec coverage: 3 functions + 5 tests (T1); state/reset/UI rework (T2); build both (T2 S4); manual (T3). ✓
- Consistency: `applyVisibleMove(rows:collapsed:from:to:)` signature matches UI call; `visibleRows` drives both ForEach and index translation from the same `collapsed` set; `persistencePlan` untouched (walks full rows). Localization: the `· N accounts` caption is a new user-facing string — acceptable as English-fallback until the next zh batch (note it in the PR). ✓
- No engine change; normal list untouched. ✓
