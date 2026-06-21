# Collapsible account groups (iOS Accounts tab)

**Date:** 2026-06-21
**Status:** Design approved, pending implementation
**Scope:** iOS Accounts tab (`AccountsTab`), both the iPhone (compact) list and the iPad/Mac three-column selection list. No web changes.

## Problem

On the iOS Accounts tab, account groups render as plain SwiftUI `List` `Section`s with a static, non-interactive header (group name + subtotal). All accounts in every group are always visible — groups cannot be collapsed. The web app already supports this (an `Accordion type="multiple"` on its Accounts page); native iOS lacks parity.

## Goal

Let the user collapse/expand each account group on the Accounts tab:
- Tapping a group header toggles that group.
- Groups collapse **independently** (multiple may be open), all **expanded by default** — matching the web's `type="multiple"`.
- A group's collapsed state **persists** across navigation and app launches.
- Works in both the iPhone compact list and the iPad/Mac three-column selection list.

## Design

### Component 1 — `AccountGroupCollapse` (persistence helper)

New file `ios/FinchApp/Sources/FinchApp/Common/AccountGroupCollapse.swift`. Mirrors
the existing `NotificationPrefs` UserDefaults pattern. Stores the set of
**collapsed** group names (not expanded) under one key, as a `[String]`. Storing
*collapsed* makes the default — absent — **expanded**, so untouched and
newly-created groups appear open automatically (web parity).

Functions take a `UserDefaults = .standard` parameter so tests can pass an
isolated suite:

```swift
enum AccountGroupCollapse {
    static let key = "finch.accounts.collapsedGroups"
    static func collapsed(_ defaults: UserDefaults = .standard) -> Set<String>
    static func isCollapsed(_ group: String, _ defaults: UserDefaults = .standard) -> Bool
    static func setCollapsed(_ group: String, _ collapsed: Bool, _ defaults: UserDefaults = .standard)
}
```

- `collapsed` reads the `[String]` array → `Set`.
- `isCollapsed` = membership.
- `setCollapsed` adds/removes the name and writes the array back.

Group identity is the group **name** `String` (the app already keys groups by name
via `store.accountGroupsOrdered: [String]` and `store.accounts(in:)`).

### Component 2 — `AccountsTab.groupedSections` (UI)

`groupedSections` is shared by both layouts, so editing it covers iPhone + iPad.

- Add view state seeded once on appear:
  `@State private var collapsedGroups: Set<String>` ← `AccountGroupCollapse.collapsed()`.
- Each group `Section`'s header becomes a tappable control:
  - leading **chevron** — `chevron.down` when expanded, `chevron.right` when collapsed,
  - the group name, a `Spacer()`, and the subtotal (`store.subtotalDisplay(for:)`).
  - Tapping toggles the group: mutate `collapsedGroups` and call
    `AccountGroupCollapse.setCollapsed(groupName, …)`.
- Section body renders rows only when expanded:
  `if !collapsedGroups.contains(groupName) { ForEach(store.accounts(in: groupName)) { row($0) }.onMove { … } }`.
  Collapsed → header only (subtotal stays visible, which is useful).
- The "Net worth" footer section is unchanged.

The header must remain a real `Section` header (so List section styling/stickiness
is preserved); make its content tappable via a `Button(role: nil)`/`.onTapGesture`
on the `HStack`, using `.contentShape(Rectangle())` so the whole header row is the
hit target. Buttons inside `List` headers are allowed.

### Interaction with reorder (EditMode)

Within-group drag reorder (`.onMove`) is unaffected: an expanded group reorders as
today; a collapsed group has no visible rows, so there's nothing to drag (and
cross-group drag isn't offered). Toggling remains available in edit mode.

## Out of scope

- Web changes.
- Any change to grouping, subtotals, net worth, reorder semantics, or the set of
  groups.
- An "expand/collapse all" control (YAGNI; can add later if asked).

## Testing

- **Unit** (`AccountGroupCollapseTests`, XCTest): using an isolated
  `UserDefaults(suiteName:)`, assert default is expanded (empty set / `isCollapsed`
  false), `setCollapsed(true)` then `isCollapsed` true and present in `collapsed()`,
  `setCollapsed(false)` removes it, and toggling is idempotent.
- **Build:** `xcodebuild -scheme FinchApp` (regenerate project after adding files).
- **Manual sim** (iPhone 17 Pro, see `ios/docs/simulator-ui-driving.md`): tap a group
  header → rows hide, chevron flips, subtotal remains; tap again → rows return;
  leave Accounts and return / relaunch → collapsed state persists; verify on the
  iPad layout too (regular width).
