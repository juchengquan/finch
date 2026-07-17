# Reorder mode: collapsed groups (accounts travel with the group)

**Date:** 2026-07-17
**Status:** Design approved, pending implementation
**Scope:** In the Accounts reorder mode, render each real group **collapsed to a single row**, so dragging a group visibly moves the whole block (its accounts are *inside* the dragged row). Tap to expand a group when moving accounts across groups. Pure-logic + UI; no engine change.

## Problem

The reorder *data* logic already moves a group's accounts with it on drop
(`AccountReorder.rebuildWithGroupOrder`, tested). But SwiftUI's `List.onMove` makes only the
grabbed row travel during the drag — so dragging a group header visually leaves its accounts
behind until the drop snaps everything. Looks broken; mid-group drops are ambiguous.

## Design

### 1. Pure logic (`Common/AccountReorder.swift` — extends the tested enum)

```swift
    /// Rows visible when `collapsed` groups hide their account rows. Ungrouped
    /// accounts (current == nil) are always visible.
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
    /// then apply the existing rules. Destination maps to the full index of the
    /// visible row at `destination` (or `rows.count` past the end) — so dropping
    /// an account just below a collapsed header lands at the END of that group.
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
(`ReorderRow` is `Equatable` with unique ids, so `firstIndex(of:)` is exact.)

### 2. UI (`Tabs/AccountsTab.swift`)

- State: `@State private var expandedReorderGroups: Set<String> = []` — **default: all
  collapsed**; reset to `[]` when entering edit mode (in the existing `.onChange(of: editMode)`).
- `reorderList`:
  - Derive `collapsed = Set(real group ids) − expandedReorderGroups` and iterate
    `AccountReorder.visibleRows(reorderRows, collapsed: collapsed)`.
  - **Real-group row:** chevron (`chevron.right`/`chevron.down`) + name + `· N accounts`
    caption; tapping toggles membership in `expandedReorderGroups` (Button, `.plain`).
    Ungrouped header: unchanged text row (its accounts always visible).
  - `.onMove` → `reorderRows = AccountReorder.applyVisibleMove(reorderRows, collapsed:
    collapsed, from: $0, to: $1)`.
- Persistence (`persistencePlan` on Done) unchanged — it walks the *full* `reorderRows`.

### Behavior summary
- Dragging a **collapsed group row** = dragging the block; accounts travel by construction.
- Dropping an **account** just below a collapsed header → joins that group (at its end).
- **Expanded** groups behave exactly as today (accounts drag individually; header drag still
  block-moves via the existing rules). Ungrouped pinned last, as before.

### 3. Tests (`AccountReorderTests.swift` — extend)
- `visibleRows` hides collapsed groups' accounts, keeps ungrouped visible.
- `accountCount` counts correctly.
- `applyVisibleMove`: collapsed group dragged below next group → block moves (full-array
  assertion); account dragged to just below a collapsed header → re-parents to that group's
  end; with `collapsed = []` behaves identically to `applyMove`.

## Out of scope
- The normal (non-edit) list; macOS reorder entry (reorder stays iOS-entry via context menu);
  custom drag previews; engine changes.

## Testing
- **Unit:** the new cases above (bun-free — XCTest via xcodebuild, or logic-only review if the
  test runner is slow locally; CI runs them).
- **Build:** FinchApp (iOS) + FinchMac (macOS).
- **Manual (sim):** demo seed (4 groups / 9 accounts) → long-press a group → Reorder → groups
  appear as single collapsed rows with counts; dragging one moves the whole group (verify order
  after Done); expand a group → move an account under another (collapsed) group → it re-parents.

## Notes
- Collision: `AccountsTab.swift` is hot (#455 just touched it) — re-check `gh pr list` + rebase
  before pushing. PR → `feat/frontend`.
