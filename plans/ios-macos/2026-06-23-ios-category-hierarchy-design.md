# Category hierarchy, icons & colors (iOS Power Tools)

**Date:** 2026-06-23
**Status:** Design approved, pending implementation
**Scope:** iOS `CategoryAdminView` (Settings › Power Tools › Categories) + the
`CategoryRow` projection. iPad/Mac share the same view. **No FinchCore engine
changes** — the engine already supports the full feature.

## Problem

The web Categories manager is a **3-level forest** (parent › child › grandchild)
with per-category **icon** and **color**, expand/collapse, search, create-child,
and reparenting. The iOS `CategoryAdminView` is a **flat, single-level list** that
shows only name + kind: no hierarchy, no icons, no colors, no search. This is the
largest Power-Tools parity gap.

Crucially, the **FinchCore engine is already feature-complete** (see Engine facts
below): `createCategory`/`updateCategory` accept `parentId`/`icon`/`color`, the
3-level depth cap and cycle prevention are enforced, and deleting a parent
promotes its children up a level (`parent_id` FK `ON DELETE SET NULL`). The iOS
**projection and UI** simply don't use any of it. So this is a projection + model
+ UI job.

## Goal

Bring iOS Categories to parity with the web:

- Render the **3-level tree** with inline expand/collapse and indentation.
- Per-category **icon** (12 shared glyphs) and **color** (8 shared swatches),
  with parent → child inheritance when unset.
- **Search** that filters across levels and force-expands ancestors of matches.
- **Create a child** category directly under a parent.
- **Reparent** by **drag-to-move** (with engine-validated depth/cycle rejection).
- **Edit** name / icon / color (and kind on create), and **delete** with a clear
  "subcategories move up a level" note.

Cross-platform **pack parity** is a hard requirement: category icon/color values
live inside the synced/exported `.finch` pack, so iOS stores the **same shared
vocabulary** the web uses and renders it natively.

## Non-goals

- No FinchCore engine changes (hierarchy/icon/color/validation already exist).
- No web changes.
- No sibling **sort_order** editing in CP1 (optional in CP2; see Checkpoints).
- No bulk operations, no category merge.
- Kind (expense/income) remains **create-only** (matches web + current iOS).

## Key decisions (locked)

1. **Tree UX = inline expand/collapse** (one scrolling `List`, web-like), not
   drill-in navigation. Keeps the whole tree visible/navigable in one place.
2. **Reparent = drag-to-move** (`.draggable` / `.dropDestination`), not a parent
   picker. A "Move to…" action is the agreed fallback if the gesture tests badly.
3. **Icons/colors = shared set, native rendering.** Store the web's exact 12 icon
   short-names + 8 hex colors (pack parity); render with SF Symbols (a new mapper)
   + a new `Color(hex:)` helper. Reuse `AccountSheet`'s swatch-picker UI shape.

## Detailed design

### Data layer (small, additive)

- **`CategoryRow`** (`ios/FinchCore/.../Project/Category.swift`) gains
  `icon: String?` and `color: String?`.
- **`Projection.categories()`** (`Projections+State.swift`) SELECTs `icon, color`
  in addition to the current 5 columns; keeps `ORDER BY sort_order`.
- No other call sites change shape (the new fields are optional).

### Icon model

- A `CategoryIcon` enum/mapper following the existing `Icons.swift` convention
  (`AccountTypeIcon`/`TxnKindIcon`): `name → SF Symbol`. The 12 shared names and
  their SF Symbols (to be verified to exist at build):

  | stored | SF Symbol |
  |---|---|
  | `fork` | `fork.knife` |
  | `home` | `house.fill` |
  | `car` | `car.fill` |
  | `bag` | `bag.fill` |
  | `film` | `film.fill` |
  | `heart` | `heart.fill` |
  | `sync` | `arrow.triangle.2.circlepath` |
  | `tag` | `tag.fill` |
  | `coins` | `dollarsign.circle.fill` |
  | `wallet` | `wallet.pass.fill` |
  | `chart` | `chart.pie.fill` |
  | `doc` | `doc.fill` |

  Unknown/`nil` stored name → a neutral default (`tag.fill`), matching the web's
  `'tag'` fallback.

### Color model

- New **`Color(hex:)`** extension (iOS has none today). Shared, reusable infra;
  parses `#rrggbb`.
- The 8 shared swatches (from web `lib/colors.ts` `categoryHex`):
  `#d16b7a #d1714f #ae8a0d #31a773 #00a6ae #00a0c5 #8085dc #b273c0`.
  Default `#00a0c5`.
- **Inheritance:** effective icon/color = own → parent's → default, walking up the
  chain (mirrors web). A grandchild with neither uses its chain.

### Tree view (CP1) — `CategoryAdminView` rebuild

- Build a **forest** from the flat `[CategoryRow]`: a `parentId → [children]` map,
  rendered parent (indent 0) → child (indent 1) → grandchild (indent 2).
- **Row:** colored **icon badge** (background = effective color, glyph = effective
  SF Symbol) + name. Parents/children with children get a **chevron** (collapsed
  by default) and an inline **"+"** to create a child under them.
- **Expand/collapse** state held in view `@State` (a `Set<String>` of expanded
  ids). Not persisted (transient; matches the lightweight nature).
- **Search** field filters across all levels; when a descendant matches but its
  ancestors don't, the ancestors are force-expanded so the match is visible.
- **Tap a row → edit sheet.** A top-level **"+ Add category."**

### Edit sheet (CP1)

Reuse the existing `CategoryEditSheet` shape, extended:

- **Name** (`TextField`).
- **Kind** (expense/income) — **create-only**, as today.
- **Icon picker** — a grid of the 12 glyphs (selected ring), reusing the swatch
  selection idiom.
- **Color picker** — 8 swatches, the `AccountSheet` pattern driven by the 8 hex
  via `Color(hex:)`.
- Writes through `updateCategory` (patch: `name`/`icon`/`color`, `parentId` only
  via drag) / `createCategory` (`ledgerId`/`name`/`type`/`icon`/`color`/optional
  `parentId` when created under a parent).

### Reparent — drag-to-move (CP2)

- Each row is `.draggable(category.id)`; parent rows and a **"Top level"** drop
  zone are `.dropDestination(for: String.self)`.
- Drop sets the dragged category's `parentId` (or `nil` for top level) via
  `updateCategory`.
- **Validation is the engine's job:** it rejects self-parent, moving under a
  descendant, and exceeding 3 levels with localized `I18nError`s; we surface those
  via the existing `errorAlert`. The UI does not duplicate the rules (it may grey
  obviously-invalid drop targets as a nicety, but correctness comes from the
  engine).
- **Fallback:** if drag feels unreliable in testing, add a swipe/context-menu
  **"Move to…"** action that opens a filtered parent list. Same `updateCategory`
  call underneath.
- **Optional in CP2:** sibling reordering via `sort_order` (drag within a parent).
  Deferred unless cheap.

### Delete behavior

- Delete confirms with a note: **"Its subcategories move up a level"** (the
  engine's promote-on-delete via `ON DELETE SET NULL`) — so it isn't mistaken for
  a cascade that destroys children.

## Engine facts (already supported — no changes)

From research (`ios/FinchCore/.../Store/Domain/Categories.swift`,
`Storage/Schema.swift`):

- `createCategory` accepts `id?/ledgerId?/name/type?/icon?/color?/parentId?`.
- `updateCategory` patch keys: `name/type/icon/color/parentId` (→ columns
  `name/kind/icon/color/parent_id`).
- `deleteCategory` is a bare delete; `categories.parent_id … ON DELETE SET NULL`
  promotes children to top level recursively.
- Cycle prevention: self-parent + "under own descendant" guarded; **depth cap of
  3** enforced (`assertCanBeParent`/`assertSubtreeFitsUnder`,
  "Categories nest at most three levels deep").
- `categories` columns: `id, ledger_id, parent_id, name, kind, icon, color,
  sort_order, system, created_at, updated_at`.

## Checkpoints

- **CP1 — everything but drag.** Data layer (`CategoryRow` + projection), icon
  mapper + `Color(hex:)`, tree render (expand/collapse, badges, indentation),
  search, create-child, edit sheet (name/kind/icon/color), delete-with-note.
  All low-risk; the big visible win. Ships, verified on the simulator.
- **CP2 — drag-reparent.** `.draggable`/`.dropDestination` move + "Top level"
  zone, engine-validated rejection; optional sibling reorder; "Move to…" fallback
  if needed.

## Testing

- **FinchAppTests (unit):** `CategoryIcon` name→symbol mapping (all 12 + default);
  `Color(hex:)` parsing (valid `#rrggbb`, invalid → fallback); forest-builder
  helper (flat rows → parent/child/grandchild grouping, orphan handling); search
  predicate force-expanding ancestors.
- **Build gate:** iOS + macOS (FinchMac) build; full `FinchAppTests` green
  (CI now covers both per #251).
- **Manual (sim):** create child, set icon+color, expand/collapse, search,
  delete-with-promotion; (CP2) drag a category to a new parent + an invalid drop
  surfaces the depth/cycle error.

## Risks / open questions

- **Drag-across-parents in SwiftUI** is the main risk: `.onMove` only reorders
  within one collection, so cross-parent moves use `.draggable`/`.dropDestination`
  with custom drop targets, which can feel finicky on a nested list. Mitigations:
  generous drop zones, engine-validated rejection, and the "Move to…" fallback.
  This is why drag is isolated in CP2.
- **SF Symbol availability:** confirm each of the 12 mapped symbols exists on the
  deployment target; swap any missing one for the closest available glyph.
- **Indentation width on iPhone:** 3 levels + badge + name + chevron + "+" is
  tight; category names are short, so it should fit, but verify on the narrowest
  device.

## Out of scope

- Engine/web changes; category merge; bulk ops; per-row usage counts; editing
  kind after creation; persisting expand/collapse across launches.
