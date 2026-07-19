# Tags page — Settings top-level (move from Power Tools, Categories-style layout)

**Date:** 2026-07-19
**Status:** Design approved in discussion; plan follows.
**Scope:** FinchApp UI + **one read-only FinchCore selector**. No new mutations, no
schema, no wire/parity-action change, no web change. Take the Tags admin out of
Power Tools, promote it to a Settings top-level row, and restyle it to match the
Categories page (`CategoriesView` / `CategoryDetailView`).

This mirrors the **Categories page redesign** (`2026-07-19-categories-page-redesign-design.md`)
but for a **flat, color-only** domain. Tags have no hierarchy, no kind, no icon, and
no `sortOrder`; they are name-ordered and carry only `{ id, name, color }`
(`TagRow`). The engine exposes exactly three tag actions — `createTag`, `updateTag`,
`deleteTag` — all reused unchanged.

**Explicitly out of scope** (possible later phases, as with Categories):
- **Merge tags** — would need new `mergeTag` / `mergeTags` engine actions + web-parity fixtures.
- **Drag-reorder** — would need a new tag `sortOrder` column + action + parity work; low value for a flat list.
- Icons, expense/income kind split, hierarchy — not applicable to tags.

## Decisions

1. **Move out of Power Tools → Settings top-level.** Rename `TagAdminView` →
   `TagsView` (file + struct), matching the `CategoryAdminView → CategoriesView`
   rename. `SettingsRootList` gains
   `NavigationLink { TagsView() } label: { Label("Tags", systemImage: "tag") }`
   right after the **Categories** row (the two reference-data editors grouped).
   `SettingsPowerToolsView` drops its Tags link → Power Tools becomes **Rules,
   Merchants**. `SettingsRootList` is shared with the macOS Preferences window, so the
   Tags row appears on Mac automatically.

2. **Categories-style list.** Large title "Tags"; cross-platform **search**
   (the `SearchableModifier` used by `CategoriesView`) filtering by name
   (case-insensitive substring). Rows use the Categories row **visual**: a 26pt
   **color swatch** (the tag's color, or a default when unset) + name + trailing
   **transaction-count pill** (`.quaternary` capsule, `.caption.monospacedDigit()`).
   Because **every** tag row navigates to its detail (unlike Categories, where only
   parents disclose and leaves reserve an empty slot), each row also shows a trailing
   **disclosure chevron** to signal the tap-through — a deliberate, small divergence.
   No icon (tags are color-only), no tree, no kind picker.

3. **Tap a row → its transactions.** Tapping navigates to a new **`TagDetailView`**
   via `.navigationDestination(item: $selectedTagId)`, mirroring Categories'
   `selectedCategoryId`. *(Behavior change: today a tap opens the rename sheet; editing
   now moves to swipe / context menu — exactly the Categories interaction.)*

4. **Edit / Delete via swipe + context menu.** Trailing swipe: **Edit** (declared
   first ⇒ full-swipe default, accent tint) then **Delete** (red) — Edit outermost so a
   careless full swipe never deletes (the Categories rule). Context menu: **Edit**,
   **Delete**. No Merge (out of scope). Both Edit and the toolbar **+** reuse the
   existing **`TagEditSheet`** unchanged (name + color palette, ✕/✓ toolbar).

5. **Delete impact.** A centered, window-level `.alert` (the delete-confirmation style
   already used by `TagAdminView` / Activity / Categories), whose message spells out
   impact using `tagTxCounts`: **"\<name\> is removed from N transactions."** Omit the
   count clause when N is 0 (a plain "Delete \<name\>?"). This is a small upgrade over
   today's countless message, matching the Categories delete-impact feel. Uses the
   existing `deleteTag` chokepoint.

6. **Toolbar.** Browse-only: a single **`+`** (`primaryAction`) → `TagEditSheet(tag: nil)`.
   No `⋯` menu (Reorder / Merge don't exist for tags). `TagsView` is pushed into the
   Settings `NavigationStack`, so it gets a back button + this `+`.

7. **Empty state.** Centered "No tags yet / Tap + to add one" (mirror Categories'
   `emptyKindMessage`, minus the kind split).

## Components (FinchApp unless noted)

### `PowerTools/TagsView.swift` (renamed from `TagAdminView.swift`)
- `struct TagsView` (was `TagAdminView`). `@EnvironmentObject store`; `@State`:
  `selectedTagId: String?`, `creating: Bool`, `editing: TagRow?`, `deleting: TagRow?`,
  `search: String`, `errorMessage: String?`.
- `counts = Selectors.tagTxCounts(store.txns, store.activeLedgerId)`.
- `rows = store.tags.filter { search empty || $0.name.localizedCaseInsensitiveContains(search) }`.
- `List`: if `store.tags` empty → empty state; else `ForEach(rows) { row($0, counts) }`.
- `row`: `Button { selectedTagId = tag.id } label: { swatch + name (maxWidth:.infinity, leading) + count pill + chevron }`,
  `.swipeActions(edge: .trailing) { Edit; Delete }`, `.contextMenu { Edit; Delete }`.
- `.navigationTitle("Tags")`, `.modifier(SearchableModifier(text: $search))`,
  `.navigationDestination(item: $selectedTagId) { id in if let t = store.tags.first(where: { $0.id == id }) { TagDetailView(tag: t) } }`.
- Delete `.alert` (centered) with the count message → `delete(_:)` calls
  `store.apply(.deleteTag, Args(["id": .string(t.id)]))`.
- Toolbar `+` → `creating = true`; `.sheet(isPresented: $creating) { TagEditSheet(tag: nil) }`,
  `.sheet(item: $editing) { TagEditSheet(tag: $0) }`.
- **`TagEditSheet` stays in this file, unchanged** (name + `TagPalette.hexes` color
  swatches; `createTag` / `updateTag`).

**`SearchableModifier` note:** it is currently `private` in `CategoriesView.swift`.
Promote it to a small shared `Common/SearchableModifier.swift` and use it from both
`CategoriesView` and `TagsView` (removes duplication; low-risk). *(Fallback: duplicate
the ~6-line modifier privately in `TagsView` to keep the change local.)*

### `PowerTools/TagDetailView.swift` (new — mirrors `CategoryDetailView`)
- `struct TagDetailView { let tag: TagRow; @EnvironmentObject store; @State editing: Tx?; @State duplicating: Tx? }`.
- `txns = Selectors.tagTransactions(store.txns, tag.id, store.activeLedgerId)`;
  `total = txns.reduce(0) { $0 + $1.amount }`.
- Body: stats `Section` (Transactions count, Total `store.displayMoneyBase(total)`,
  Average when non-empty); "Transactions" `Section` of `TxRow` — tap → `EditTransactionSheet`,
  leading-swipe **Duplicate** for `expense`/`income`, context menu Edit / Duplicate.
  Title = `tag.name`. Sheets: `EditTransactionSheet(txn:)`, `AddTransactionSheet(prefill:)`.
  (Structurally identical to `CategoryDetailView`.)

### `FinchCore/Sources/FinchCore/Selectors/Selectors.swift` (the only engine change)
- Add `public static func tagTransactions(_ txns: [Tx], _ tagId: String, _ ledgerId: String) -> [Tx]`:
  filters `txns` to `ledgerId` where `tags` contains `tagId`, using the **same predicate
  as `tagTxCounts`** (same pending/opening handling) so the detail list length equals the
  row's count pill. Refactor `tagTxCounts` to share that predicate (or add a private
  helper both call). **Pure, read-only — no new action, mutation, schema, or wire change.**

### `Tabs/SettingsTab.swift`
- `SettingsRootList`: insert the `TagsView()` `NavigationLink` after the Categories row.
- `SettingsPowerToolsView`: remove the `NavigationLink("Tags") { TagAdminView() }`.

## Data flow / actions
- **Reads:** `store.tags` (name-ordered projection), `Selectors.tagTxCounts`,
  `Selectors.tagTransactions` (new).
- **Writes (existing chokepoints only):** `createTag`, `updateTag` (via `TagEditSheet`),
  `deleteTag` (via the delete alert). No new actions; nothing new for CloudKit-mutation
  replay or the write-parity sequence.

## i18n
New / relocated user-facing strings: the "Tags" `Label` (top-level), "No tags yet",
"Tap + to add one", the delete-impact message, and `TagDetailView`'s stat labels
("Transactions" / "Total" / "Average", already localized via the Categories detail).
Run the zh-Hans pipeline (`ios/scripts/build-xcstrings.ts`) after; add `zh-manual.json`
entries as needed, keeping the web term for tag (标签).

## macOS parity
No Mac-specific work: `SettingsRootList` (shared with the Preferences window) surfaces
the Tags row automatically, `SearchableModifier` already branches per platform, and
`TagDetailView` reuses the cross-platform `TxRow`.

## Testing
- **`FinchCoreTests`:** unit-test `tagTransactions` — membership (`tags` contains id),
  ledger scoping, empty when none, and **count equals `tagTxCounts[id]`** for the same data.
- **Manual sim pass:** Settings shows **Tags** at top level and **not** in Power Tools;
  list renders swatches + count pills; search filters; tap → detail (stats + tx list);
  swipe Edit → sheet; swipe Delete → count alert → removed; `+` → add. macOS Preferences
  shows the row.
- **No parity fixtures** (no new actions).

## Files
- Rename `PowerTools/TagAdminView.swift` → `PowerTools/TagsView.swift` (struct rename; keep `TagEditSheet`).
- New `PowerTools/TagDetailView.swift`.
- Edit `Tabs/SettingsTab.swift`.
- Edit `FinchCore/Sources/FinchCore/Selectors/Selectors.swift` (+ a `FinchCoreTests` case).
- (Recommended) New `Common/SearchableModifier.swift` (promoted) + update `CategoriesView.swift` to use it.
- `xcodegen generate` (the rename + new files enter the Xcode project).

## Risks / notes
- A concurrent session works on `feat/ios-tags-single-row` (tag *rendering* in `TxRow`
  chips) — a different area from this admin page; overlap is unlikely, but coordinate at
  merge time if both land together.
- The tap-target change (tap-to-rename → tap-to-open-transactions) is intentional
  Categories parity; the row's edit affordance is now the swipe/context menu.
