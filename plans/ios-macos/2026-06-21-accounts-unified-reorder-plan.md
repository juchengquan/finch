# Unified Account Reorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One "Reorder" mode on the Accounts tab where accounts drag across groups (re-parent) and whole groups reorder, persisted on Done.

**Architecture:** A pure, unit-tested core (`AccountReorder`: `ReorderRow` + `buildRows`/`applyMove`/`persistencePlan`) drives a flat reorder `List` that `AccountsTab` shows while `editMode.isEditing`. Account moves keep their flat position (membership derived by walking); group moves rebuild by new group order. On Done, only changed rows are persisted via `updateAccountGroup`/`updateAccount`.

**Tech Stack:** Swift / SwiftUI, XcodeGen, XCTest.

Spec: `plans/ios-macos/2026-06-21-accounts-unified-reorder-design.md`.

## Global Constraints

- iOS deployment target **26.0**; local builds need `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- After creating files: `cd ios && xcodegen generate` (the `.xcodeproj` is generated).
- New types are `internal` so `@testable import FinchApp` sees them.
- Commits: **no `Co-Authored-By` trailer**.
- `AccountRow` (FinchCore): `init(id: String, balance: Double, …, name: String? , groupId: String?, groupName: String?, sortOrder: Int?, …)`.
- `AccountGroupRow == GroupRow { id: String; name: String }`; `store.accountGroups` is ordered incl. empty groups; `store.accounts` is projection-ordered.
- An account move to Ungrouped sets `groupId` to `JSONValue.null` (→ `group_id = NULL`).
- Sim destination: `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
- This builds on existing uncommitted work in this branch (chevron-free rows, "Done" button, group long-press Edit/Delete). Do not revert those.

---

### Task 1: `AccountReorder` pure logic + tests

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Common/AccountReorder.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/AccountReorderTests.swift`

**Interfaces — Produces:**
- `enum ReorderRow: Identifiable, Equatable { case group(id: String?, name: String); case account(AccountRow) }` with `var id: String`.
- `enum AccountReorder`:
  - `static func buildRows(groups: [AccountGroupRow], accounts: [AccountRow]) -> [ReorderRow]`
  - `static func applyMove(_ rows: [ReorderRow], from: IndexSet, to: Int) -> [ReorderRow]`
  - `static func persistencePlan(_ rows: [ReorderRow]) -> (groups: [(id: String, order: Int)], accounts: [(id: String, groupId: String?, order: Int)])`

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchApp/Tests/FinchAppTests/AccountReorderTests.swift`:

```swift
import XCTest
@testable import FinchApp
import FinchCore

final class AccountReorderTests: XCTestCase {
    private func acct(_ id: String, _ gid: String?) -> AccountRow {
        AccountRow(id: id, balance: 0, name: id, groupId: gid, groupName: nil, sortOrder: 0)
    }
    private let groups = [AccountGroupRow(id: "g1", name: "Bank"), AccountGroupRow(id: "g2", name: "Cards")]
    // a1,a2 in g1; a3 in g2; a4 ungrouped
    private var accounts: [AccountRow] { [acct("a1","g1"), acct("a2","g1"), acct("a3","g2"), acct("a4", nil)] }

    func test_build_interleavesGroupsThenUngroupedLast() {
        let rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        XCTAssertEqual(rows.map(\.id), [
            "g:g1:Bank", "a:a1", "a:a2", "g:g2:Cards", "a:a3", "g:ungrouped:Ungrouped", "a:a4"
        ])
    }

    func test_persistencePlan_assignsGroupAndOrder() {
        let rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        let plan = AccountReorder.persistencePlan(rows)
        XCTAssertEqual(plan.groups.map { "\($0.id):\($0.order)" }, ["g1:0", "g2:1"])
        XCTAssertEqual(plan.accounts.map { "\($0.id):\($0.groupId ?? "nil"):\($0.order)" },
                       ["a1:g1:0", "a2:g1:1", "a3:g2:0", "a4:nil:0"])
    }

    func test_accountMove_acrossGroup_reparents() {
        // Move a1 (idx 1, in g1) down to just after a3 (into g2).
        var rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        // rows: 0 g1,1 a1,2 a2,3 g2,4 a3,5 ungrouped,6 a4 → move idx1 to 5 (after a3)
        rows = AccountReorder.applyMove(rows, from: IndexSet(integer: 1), to: 5)
        let plan = AccountReorder.persistencePlan(rows)
        let a1 = plan.accounts.first { $0.id == "a1" }!
        XCTAssertEqual(a1.groupId, "g2", "a1 should re-parent to g2")
    }

    func test_accountMove_cannotLandAboveFirstHeader() {
        var rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        rows = AccountReorder.applyMove(rows, from: IndexSet(integer: 4), to: 0) // a3 to very top
        if case .group = rows[0] {} else { XCTFail("row 0 must remain a header") }
    }

    func test_groupMove_movesWholeBlock_andRenumbers() {
        // Move g2 (idx 3) above g1 (to 0).
        var rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        rows = AccountReorder.applyMove(rows, from: IndexSet(integer: 3), to: 0)
        XCTAssertEqual(rows.map(\.id), [
            "g:g2:Cards", "a:a3", "g:g1:Bank", "a:a1", "a:a2", "g:ungrouped:Ungrouped", "a:a4"
        ])
        let plan = AccountReorder.persistencePlan(rows)
        XCTAssertEqual(plan.groups.map { "\($0.id):\($0.order)" }, ["g2:0", "g1:1"])
    }

    func test_ungroupedHeaderMove_isNoOp() {
        let rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        let moved = AccountReorder.applyMove(rows, from: IndexSet(integer: 5), to: 0) // ungrouped header
        XCTAssertEqual(moved.map(\.id), rows.map(\.id))
    }
}
```

- [ ] **Step 2: Regenerate + run tests to verify they fail**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:FinchAppTests/AccountReorderTests 2>&1 | grep -E "error:|cannot find|TEST SUCCEEDED|TEST FAILED"
```
Expected: FAIL — `cannot find 'AccountReorder' in scope`.

- [ ] **Step 3: Write the implementation**

Create `ios/FinchApp/Sources/FinchApp/Common/AccountReorder.swift`:

```swift
import Foundation
import FinchCore

/// A row in the flat reorder list: a group header (id == nil → Ungrouped) or an
/// account. Used only while reordering on the Accounts tab.
enum ReorderRow: Identifiable, Equatable {
    case group(id: String?, name: String)
    case account(AccountRow)

    var id: String {
        switch self {
        case .group(let gid, let n): return "g:\(gid ?? "ungrouped"):\(n)"
        case .account(let a): return "a:\(a.id)"
        }
    }
    var isAccount: Bool { if case .account = self { return true }; return false }
}

/// Pure reorder logic for the Accounts tab. SwiftUI-free → unit-testable.
enum AccountReorder {
    /// Flat snapshot: each real group (in order) + its accounts, then the
    /// Ungrouped bucket (pinned last) + its accounts.
    static func buildRows(groups: [AccountGroupRow], accounts: [AccountRow]) -> [ReorderRow] {
        var rows: [ReorderRow] = []
        for g in groups {
            rows.append(.group(id: g.id, name: g.name))
            for a in accounts where a.groupId == g.id { rows.append(.account(a)) }
        }
        rows.append(.group(id: nil, name: "Ungrouped"))
        for a in accounts where a.groupId == nil { rows.append(.account(a)) }
        return rows
    }

    /// Apply a List move under the group rules. Accounts keep their dropped
    /// position (membership is derived later by `persistencePlan`); real groups
    /// move as a block by rebuilding from the new group order; the Ungrouped
    /// header is pinned (its move is a no-op).
    static func applyMove(_ rows: [ReorderRow], from source: IndexSet, to destination: Int) -> [ReorderRow] {
        guard let src = source.first, src < rows.count else { return rows }
        switch rows[src] {
        case .account:
            var out = rows
            out.move(fromOffsets: source, toOffset: destination)
            if !out.isEmpty, out[0].isAccount {           // never leave an account above the first header
                let a = out.remove(at: 0); out.insert(a, at: 1)
            }
            return out
        case .group(let gid, _) where gid == nil:
            return rows                                    // Ungrouped header pinned
        case .group(let gid, _):
            return rebuildWithGroupOrder(rows, movedGroup: gid!, toFlatIndex: destination)
        }
    }

    /// Recompute the real-group order after a header drag, then rebuild the flat
    /// rows so each group's accounts stay with it; Ungrouped stays last.
    private static func rebuildWithGroupOrder(_ rows: [ReorderRow], movedGroup gid: String, toFlatIndex dest: Int) -> [ReorderRow] {
        var order: [String] = []
        for r in rows { if case .group(let id?, _) = r { order.append(id) } }
        guard let from = order.firstIndex(of: gid) else { return rows }
        // target position = number of real-group headers strictly above `dest`,
        // not counting the moved group.
        var targetPos = 0
        for i in 0..<min(dest, rows.count) {
            if case .group(let id?, _) = rows[i], id != gid { targetPos += 1 }
        }
        order.remove(at: from)
        order.insert(gid, at: min(targetPos, order.count))
        // names + accounts from current rows.
        var nameOf: [String: String] = [:]
        var acctsOf: [String: [ReorderRow]] = [:]
        var ungroupedAccts: [ReorderRow] = []
        var current: String? = nil
        for r in rows {
            switch r {
            case .group(let id, let n): if let id { nameOf[id] = n; current = id; acctsOf[id] = [] } else { current = nil }
            case .account: if let c = current { acctsOf[c, default: []].append(r) } else { ungroupedAccts.append(r) }
            }
        }
        var out: [ReorderRow] = []
        for id in order { out.append(.group(id: id, name: nameOf[id] ?? "")); out.append(contentsOf: acctsOf[id] ?? []) }
        out.append(.group(id: nil, name: "Ungrouped")); out.append(contentsOf: ungroupedAccts)
        return out
    }

    /// Derive the persisted state by walking top→bottom: each real group gets the
    /// next group order; each account belongs to the most recent header (nil =
    /// Ungrouped) with a running per-group order.
    static func persistencePlan(_ rows: [ReorderRow]) -> (groups: [(id: String, order: Int)], accounts: [(id: String, groupId: String?, order: Int)]) {
        var groups: [(id: String, order: Int)] = []
        var accounts: [(id: String, groupId: String?, order: Int)] = []
        var currentGroup: String? = nil
        var groupOrder = 0
        var orderInGroup = 0
        for r in rows {
            switch r {
            case .group(let gid, _):
                if let gid { groups.append((id: gid, order: groupOrder)); groupOrder += 1 }
                currentGroup = gid
                orderInGroup = 0
            case .account(let a):
                accounts.append((id: a.id, groupId: currentGroup, order: orderInGroup)); orderInGroup += 1
            }
        }
        return (groups, accounts)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:FinchAppTests/AccountReorderTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Common/AccountReorder.swift \
        ios/FinchApp/Tests/FinchAppTests/AccountReorderTests.swift
git commit -m "feat(ios): AccountReorder pure logic for unified account/group reorder"
```

---

### Task 2: Wire the reorder mode into `AccountsTab`

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift`

**Interfaces — Consumes:** `ReorderRow`, `AccountReorder` (Task 1); existing `editMode`, `store`, `AccountRowView`, `errorMessage`.

- [ ] **Step 1: Add reorder state**

In `AccountsTab`, after the `editMode` declaration (inside the existing `#if os(iOS)` block) add:

```swift
    @State private var reorderRows: [ReorderRow] = []
```

- [ ] **Step 2: Build on enter / persist on Done**

In `body`, just after the existing `#if os(iOS) .environment(\.editMode, $editMode) #endif` modifier on `listContent`, add (inside the same `#if os(iOS)`):

```swift
            .onChange(of: editMode) { _, mode in
                if mode.isEditing {
                    reorderRows = AccountReorder.buildRows(groups: store.accountGroups, accounts: store.accounts)
                } else {
                    persistReorder()
                }
            }
```

- [ ] **Step 3: Render the flat reorder list**

In `listContent`, add a reorder branch as the FIRST non-empty case so it wins while editing. Replace:

```swift
    @ViewBuilder private var listContent: some View {
        if store.accounts.isEmpty {
            EmptyState(tab: .accounts)
        } else if let selection {
```

with:

```swift
    @ViewBuilder private var listContent: some View {
        if store.accounts.isEmpty {
            EmptyState(tab: .accounts)
        }
        #if os(iOS)
        else if editMode.isEditing {
            reorderList
        }
        #endif
        else if let selection {
```

- [ ] **Step 4: Add the `reorderList` view + `persistReorder`**

Add these members to `AccountsTab` (e.g. right after `groupedSections`), guarded for iOS:

```swift
    #if os(iOS)
    /// Flat, fully-draggable list used only while reordering: accounts move
    /// across groups, group headers move their whole block.
    private var reorderList: some View {
        List {
            ForEach(reorderRows) { row in
                switch row {
                case .group(_, let name):
                    Text(name).fontWeight(.semibold).foregroundStyle(.secondary)
                case .account(let a):
                    AccountRowView(account: a)
                }
            }
            .onMove { from, to in
                reorderRows = AccountReorder.applyMove(reorderRows, from: from, to: to)
            }
        }
        .environment(\.editMode, .constant(.active))
    }

    /// Persist the reordered state (only rows whose group/order changed).
    private func persistReorder() {
        let plan = AccountReorder.persistencePlan(reorderRows)
        let curGroupOrder = Dictionary(uniqueKeysWithValues: store.accountGroups.enumerated().map { ($1.id, $0) })
        let curAcct = Dictionary(uniqueKeysWithValues: store.accounts.map { ($0.id, ($0.groupId, $0.sortOrder ?? 0)) })
        do {
            for g in plan.groups where curGroupOrder[g.id] != g.order {
                try store.apply(.updateAccountGroup, Args(["id": .string(g.id), "patch": .object(["sortOrder": .int(g.order)])]))
            }
            for a in plan.accounts {
                let cur = curAcct[a.id]
                if cur?.0 != a.groupId || cur?.1 != a.order {
                    var patch: [String: JSONValue] = ["sortOrder": .int(a.order)]
                    patch["groupId"] = a.groupId.map(JSONValue.string) ?? .null
                    try store.apply(.updateAccount, Args(["id": .string(a.id), "patch": .object(patch)]))
                }
            }
        } catch { errorMessage = i18nMessage(error) }
        reorderRows = []
    }
    #endif
```

- [ ] **Step 5: Collapse the group context menu to a single "Reorder"**

In `groupedSections`, replace the two reorder items (the `#if os(iOS) … "Reorder Accounts" … #endif` button and the `"Reorder Groups"` button that opens `showingGroups`) with a single iOS-only item:

```swift
                .contextMenu {
                    #if os(iOS)
                    Button { withAnimation { editMode = .active } } label: {
                        Label("Reorder", systemImage: "arrow.up.arrow.down")
                    }
                    #endif
                    if let g = store.accountGroups.first(where: { $0.name == groupName }) {
                        Button { renamingGroupId = g.id; renameText = g.name } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { groupPendingDelete = g } label: { Label("Delete Group", systemImage: "trash") }
                    }
                }
```

- [ ] **Step 6: Build + run the full app suite**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD FAILED|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/AccountsTab.swift
git commit -m "feat(ios): unified Reorder mode — drag accounts across groups + move group blocks"
```

---

### Task 3: Manual simulator verification

**Files:** none. Reference: `ios/docs/simulator-ui-driving.md`. (Drag can't be scripted; the controller installs and the user verifies.)

- [ ] **Step 1: Install + launch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"; xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```
(Seed a 2nd group + accounts if the data has only Ungrouped, so cross-group is testable.)

- [ ] **Step 2: Verify**
  - Long-press a group → **Reorder** (single item) → flat list with drag handles, **Done** top-right.
  - Drag an account into another group → it re-parents; drag a group → its block moves.
  - **Done** → relaunch → new order + parents persist.
  - Long-press also shows **Edit** / **Delete Group**; account rows have no chevron and still open on tap.

- [ ] **Step 3 (no commit):** report results; if a check fails, return to the relevant task.

---

## Notes
- Work continues in the existing worktree/branch `fix/ios-group-longpress-edit`. PR targets **`feat/frontend`**.
- `editMode`, `reorderRows`, `reorderList`, `persistReorder`, and the `.onChange(of: editMode)` are all iOS-only (`#if os(iOS)`), matching the existing `editMode`.
