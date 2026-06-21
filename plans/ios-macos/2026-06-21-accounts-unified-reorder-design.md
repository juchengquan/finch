# Unified account reorder (iOS Accounts tab)

**Date:** 2026-06-21
**Status:** Design approved, pending implementation
**Scope:** iOS Accounts tab (`AccountsTab`). Compact (iPhone) + iPad three-column list. No web changes.

## Problem

Reordering on the Accounts tab is fragmented: accounts can only be dragged
*within* their group (SwiftUI sectioned `List` can't move rows across sections),
and group order is only editable in the separate "Manage Groups" screen. The user
wants one **"Reorder"** mode where you can drag an account anywhere — reorder it
*and* move it across groups — and also rearrange whole groups.

## Goal

A single **Reorder** mode (entered from a group's long-press menu) in which:
- An account can be dragged to any position, including **into another group**
  (re-parenting it), and into/out of the **Ungrouped** bucket.
- A **group** can be dragged to reorder it, moving as a **block** (its header +
  its accounts together).
- **"Done"** (standard top-right button) exits and persists.

This supersedes the interim split menu ("Reorder Accounts" / "Reorder Groups").

## Design

### Entry / exit

- Long-press a group → context menu item **"Reorder"** (single item; replaces the
  earlier "Reorder Accounts" + "Reorder Groups"). Sets `editMode = .active`.
- Top-right shows the standard **"Done"** button while `editMode.isEditing`;
  tapping it persists and sets `editMode = .inactive`.
- Edit / Delete Group context-menu items and the chevron-free account rows
  (already in this branch) stay as-is.

### Two render paths (`listContent`)

- **Normal** (`!editMode.isEditing`): today's sectioned, collapsible list.
- **Reorder** (`editMode.isEditing`): a single flat `List` with **one**
  `ForEach` over a working `[ReorderRow]`, so `.onMove` can cross groups.
  Collapsed groups are **force-expanded** here (all accounts visible to drag).

### Working model

```swift
enum ReorderRow: Identifiable, Equatable {
    case group(id: String?, name: String)   // id == nil → the Ungrouped bucket
    case account(AccountRow)
    var id: String { switch self { case .group(let gid, let n): return "g:\(gid ?? "ungrouped"):\(n)"; case .account(let a): return "a:\(a.id)" } }
}
```

`@State private var reorderRows: [ReorderRow] = []`, built when entering reorder
(snapshot from the store), edited locally during the drag, persisted on Done.

### Pure functions (the testable core)

1. `buildReorderRows(groups: [AccountGroupRow], accounts: [AccountRow]) -> [ReorderRow]`
   - Real groups in `accountGroups` order, each header followed by its accounts
     (accounts filtered by `groupId == group.id`, preserving projection order).
   - Then a single `.group(id: nil, name: "Ungrouped")` header followed by the
     accounts with `groupId == nil`. **Ungrouped is always last.**
   - A real group with no accounts still emits its header (drop target).

2. `applyMove(_ rows: [ReorderRow], from: IndexSet, to: Int) -> [ReorderRow]`
   - **Account moved:** standard single-row move, but clamp so it can never land
     above the first header (index 0 is always a header).
   - **Real-group header moved:** move the whole **block** (header +
     contiguous accounts up to the next header) and snap the destination to a
     group boundary (never inside another group's block). The Ungrouped block
     stays pinned last (a real group dropped after it is clamped to before it).
   - **Ungrouped header moved:** no-op (it's pinned, not draggable).

3. `persistencePlan(_ rows: [ReorderRow]) -> (groups: [(id: String, order: Int)], accounts: [(id: String, groupId: String?, order: Int)])`
   - Walk the flat rows top→bottom. Each `.group` increments a group index
     (real groups only) and becomes the "current group"; each `.account` is
     assigned `(currentGroupId, runningOrderWithinGroup)`.

### Persistence (on Done, one batch)

For the plan above, inside the normal write path:
- each real group → `updateAccountGroup` `{id, patch:{sortOrder: order}}`;
- each account whose `(groupId, order)` changed → `updateAccount`
  `{id, patch:{groupId: <id or null>, sortOrder: order}}` (only changed rows, to
  limit writes). `groupId` is set to JSON null for Ungrouped.
Errors surface via the existing `.errorAlert`. Then `editMode = .inactive`.

### Edit/Delete & drag affordances

- In reorder mode, rows show the standard move handles. Account rows keep no
  swipe/context actions during reorder (avoid gesture conflicts); group headers
  are plain (drag handle only).

## Out of scope

- Web changes; the Manage Groups screen (still works independently).
- Cross-**ledger** moves; archived accounts.
- Live persistence mid-drag (we persist once on Done).

## Testing

- **Unit (pure, FinchAppTests):** `buildReorderRows`, `applyMove`,
  `persistencePlan` —
  - build interleaves groups+accounts with Ungrouped last;
  - moving an account across a header re-parents it (plan reflects new groupId);
  - moving a group header moves its whole block and renumbers group order;
  - Ungrouped header move is a no-op; account can't go above the first header;
  - a real group can't be dropped below Ungrouped.
- **Build:** `xcodebuild -scheme FinchApp` (+ `xcodegen generate`).
- **Manual sim** (drag UX can't be scripted): enter Reorder via long-press →
  drag an account into another group, drag a group block, Done → verify the
  order/parent persists across relaunch.
