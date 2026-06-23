# Category drag-to-reparent + reorder (iOS Power Tools — CP2)

**Date:** 2026-06-23
**Status:** Design approved, pending implementation
**Scope:** iOS `CategoryAdminView` (Settings › Power Tools › Categories) drag interaction + a small, **iOS-only** `sortOrder` addition to `FinchCore.updateCategory`. Builds on CP1 (#258). iPad/Mac share the view.

## Problem

CP1 shipped the category tree (icons, colors, search, create-child, edit, delete-with-promotion) but **cannot move an existing category** — a parent is only set at create time. CP2 adds drag to **reparent** (move under a different parent / un-nest to top level) and **reorder siblings** (change order within a parent).

The engine already supports reparenting (`updateCategory` patches `parentId`, with self/descendant/depth-3 guards). It does **not** support writing `sort_order` — and neither does the web (`CategoryPatch` is `{name,type,icon,color,parentId}` on both, and the web has no category reorder UI). So **sibling reorder is a new capability**, not a parity restoration.

## Goal

In the existing category tree, via one drag gesture (Approach A, "position-sensitive outline drag"):

- **Reparent:** drop a row onto another row's middle → it nests under that row; drop onto a pinned **"Top level"** zone → it un-nests to the top.
- **Reorder:** drop a row in the gap between two siblings → it takes that position within the parent (`sort_order`).
- Invalid moves (self-parent, under-own-descendant, depth > 3) are rejected by the engine with its localized error, surfaced as a toast/alert.

## Key decisions (locked)

1. **Approach A — position-sensitive outline drag.** Where you release decides: over a row's **middle** = nest; in the **gap** between rows = reorder; **"Top level"** zone = un-nest. (Chosen over native `.onMove` and over button-based reorder.)
2. **Built in two verifiable steps:** **Step 1 = reparent** (drop-onto-row + Top-level zone), **Step 2 = reorder** (between-rows insertion). Each ships + is verified on the simulator before the next.
3. **iOS-only `sortOrder` divergence (documented).** Add `sortOrder` to `FinchCore.updateCategory`'s patch **only** — a deliberate iOS-ahead divergence, in the spirit of the existing D7 "Force import" iOS-only override. The web is **not** changed; it still loads packs (it reads `ORDER BY sort_order`, so it respects an iOS reordering) but cannot create one. Data round-trips both ways.

## Non-goals

- **No web changes.** (The divergence is intentional and documented.)
- No new engine reparent logic — the `parentId` path + guards already exist.
- No change to CP1 behavior (tree, icons, colors, search, create-child, edit, delete).
- No multi-select / cross-ledger drag; no drag of the equity/system categories (they're excluded from `pickableCategories` already).

## Detailed design

### Engine (FinchCore) — add `sortOrder` to `updateCategory` (iOS-only)

`ios/FinchCore/Sources/FinchCore/Store/Domain/Categories.swift`:
- Extend the update path to accept `sortOrder` in the patch and write `sort_order` — mirroring how `Groups.swift` handles it (`if let sortV = patch["sortOrder"] { sets.append("sort_order = ?"); bind.append(sortV.sqlBind) }`).
- The existing `parentId` guards (selfParent / underDescendant / depthCap) are unchanged and still run when `parentId` is in the patch.
- **Divergence marker:** a clear code comment noting this is an **iOS-only** capability the web's `updateCategory` lacks (like the D7 precedent), so future parity work knows it's deliberate.
- ParityTests: existing fixtures don't exercise `sortOrder`, so they stay green; no new parity fixture is added (that would require a web counterpart).

### Reorder math (pure, testable) — `CategoryReorder.swift` (FinchApp/PowerTools)

A pure module computing the writes for a drop, given the current rows + a `DropSpec(sourceId, targetId, position: .into | .before | .after)`:

- Resolve the **destination parent**: `.into target` → parentId = target.id; `.before`/`.after target` → parentId = target.parentId (same level as the target); Top-level zone → parentId = nil.
- Produce an ordered list of the destination parent's children with the source inserted at the right index (removed from its old position first).
- Emit the minimal write set:
  - the moved row: `updateCategory(id, patch: {parentId: <dest or null>, sortOrder: <index>})`,
  - the destination siblings whose index changed: `updateCategory(id, patch: {sortOrder: <newIndex>})` — i.e. **renumber the destination sibling group 0,1,2,…** (the `BudgetGroupsView.onReorder` pattern; small counts).
- Return `nil`/no-op when the drop is a no-op (same parent + same index) or obviously invalid (source == target, target is the source's own descendant — though the engine is the final guard).

Output type, e.g.: `struct CategoryMove { let id: String; let parentId: String?; let sortOrder: Int }` → list of moves to apply in order.

### Drag UI — `CategoryAdminView` (extends CP1)

- Each tree row is `.draggable(c.id)` (a plain `String` transfer) and a `.dropDestination(for: String.self)`.
- **Drop position within a row** is derived from the drop `location.y` vs the row height: top third → `.before`, middle third → `.into`, bottom third → `.after`. (SwiftUI `dropDestination`'s `isTargeted`/location, or an overlaid `GeometryReader` + drop handler.)
- **Visual feedback:** `.into` highlights the target row (tinted background, like a folder); `.before`/`.after` draw a thin **insertion line** at the gap, indented to the destination level.
- A pinned **"Top level"** drop target (a row/zone at the top or bottom of the list) for un-nesting.
- On drop: call `CategoryReorder.moves(...)`, then apply each `updateCategory` via `store.apply` in order; on engine throw, stop and surface `i18nMessage(error)` in the existing `errorAlert`. The store re-projects after each mutation, so the tree refreshes.

### Step 1 — reparent only (ships first)

- In Step 1, a drop **anywhere on a row** nests the dragged category under that row (`parentId = row.id`, `sortOrder` appended); the **Top-level** zone un-nests (`parentId = nil`, appended). The middle-vs-gap (`.into` vs `.before`/`.after`) distinction is **not** active yet — every on-row drop is a nest, keeping Step 1 to one easy-to-hit behavior.
- Uses the `sortOrder` engine addition to **append** the moved row under its new parent (`sortOrder = count of dest children`).
- Verified on the sim: drag a child onto another parent; drag to Top level; an invalid deep/cyclic drop shows the engine error.

### Step 2 — sibling reorder (adds the insertion path)

- Enable the top/bottom-third → `.before`/`.after` interpretation + the insertion-line feedback.
- A within-parent reorder renumbers that sibling group; a cross-parent `.before`/`.after` both reparents and positions.
- Verified on the sim: reorder two siblings; confirm order persists across relaunch (sort_order is durable) and that reparent (Step 1) still works.

## Engine facts (from CP1 research, unchanged)

- `updateCategory` patch currently: `name/type/icon/color/parentId` → cols `name/kind/icon/color/parent_id`. Guards: `selfParent`, `underDescendant`, `depthCap` (≤3), all keyed on `parentId`.
- `Groups.swift` already does `sort_order` in its update (the pattern to mirror).
- Projection orders categories `ORDER BY sort_order`; `CategoryRow` carries no `sortOrder` field today — **not needed** for the UI (the view orders via `pickableCategories`, which is already `ORDER BY sort_order`; reorder just changes the stored values and re-projects).

## Checkpoints (within CP2)

- **Step 1 — reparent:** engine `sortOrder` addition + `CategoryReorder` (the `.into`/top-level cases) + drag UI (nest highlight + Top-level zone). Tests: engine sort_order write; `CategoryReorder` into/top-level cases. Build iOS+macOS, FinchAppTests green, sim pass.
- **Step 2 — reorder:** `CategoryReorder` `.before`/`.after` cases + insertion-line UI. Tests: reorder math (within-parent + cross-parent positioning, renumber). Build gates + sim pass.

## Testing

- **FinchCore:** `updateCategory` with `{sortOrder}` patch updates `sort_order` → projection order changes (seed two siblings, swap, assert order). 
- **FinchApp (pure `CategoryReorder`):** `.into` → parentId=target, append; Top-level → parentId=nil, append; `.before`/`.after` → same-parent index + renumber; cross-parent `.before` → reparent + index; no-op detection; source==target guarded.
- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests green.
- **Manual (sim):** Step 1 — nest onto a parent, un-nest to Top level, invalid drop → error; Step 2 — reorder siblings, persists across relaunch, CP1 flows intact.

## Risks / open questions

- **Drop-position precision on a phone** is the main risk (distinguishing the three thirds + drawing the insertion line at the right indent). Mitigation: generous middle zone for nest, clear insertion-line feedback, and the two-step build so Step 1 (nest only) is solid before adding the gap path. If the gap interaction proves too fiddly in Step 2, fall back to a "Move up / Move down" action for reorder (still uses the `sortOrder` engine addition).
- **Renumber write volume:** a reorder issues one `updateCategory` per affected sibling (each re-projects). Sibling groups are small (a handful), matching the existing budget-group approach — acceptable.
- **Divergence drift:** the iOS-only `sortOrder` is documented in code; if the web later adds category reorder, the two engines reconverge.

## Out of scope

Web reorder; sibling reorder via anything but drag (unless the Step-2 fallback is needed); animations beyond default; reordering across kinds (expense↔income); persisting expand state.
