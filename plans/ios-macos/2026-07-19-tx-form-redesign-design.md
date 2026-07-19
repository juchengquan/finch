# Add/Edit transaction form redesign — design

**Date:** 2026-07-19
**Status:** approved (brainstormed in session)
**Scope:** iOS/macOS app only (`ios/FinchApp`). No engine changes.

## Goal

Three UX improvements to the Add and Edit transaction forms:

1. **Reorder** the expense/income fields to a cleaner priority order.
2. **Bottom-sheet pickers** — long single-select pickers (Category, Account,
   Transfer From/To) open as a full-height sheet that slides up from the
   bottom, replacing today's pushed navigation list.
3. **Inline wrapping tag chips** — the tag list becomes toggleable chips that
   wrap across rows, with a "Show all / Show less" cap for large tag sets,
   replacing today's one-tag-per-row checklist.

## Current state (anchors)

- `AddTransactionSheet.formPage(_:)` — expense/income fields via
  `expenseIncomeFields(for:)`; the primary section today is **Amount, Merchant,
  Category, Split, Account**; a separate section holds **Date, Note**; then
  **Status**; then the inline **Tags** `Section` (a `Button` per `store.tags`
  with a trailing checkmark); then **Receipt**.
- `SearchablePickerRow` (`WriteScreens/SearchablePickerRow.swift`) — a
  `NavigationLink` that pushes `SearchablePickerList` (a `.searchable` List,
  single-select, pops on choose). Used for Category, Account, and Transfer
  From/To in both sheets.
- `EditTransactionSheet` — mirrors the Add layout (its own `Section` order +
  an identical inline Tags section, guarded by `!store.tags.isEmpty`).
- `TagRow` (FinchCore): `id`, `name`, `color: String?`. `Color(hex:)` helper
  already exists (used by TxRow's tag chips).
- No `FlowLayout` exists yet.

## 1. Field reorder (expense/income — Add + Edit)

New primary section order:

1. **Account** (bottom-sheet picker — §2)
2. **Amount** (with the inline currency menu, unchanged from the combined row)
3. **Category** (bottom-sheet picker — §2)
4. **Date & time** (the existing `DatePicker`, moved up into this section)

Then, in order:
- **Split** row (expense non-refund, when amount ≠ 0) — unchanged behavior.
- **Refund** link (refund kind only) — unchanged.
- **Status** section — unchanged.
- **Tags** section — now the chip flow (§3).
- **Receipt** section — unchanged.
- **Details** section at the very bottom: **Merchant/Source** (with its
  existing typeahead `merchantSuggestionRows` + "Create <name>") and **Note**.
  Both are optional free-text, so they sit last.

Notes:
- The merchant `.onChange` auto-categorization still fires regardless of the
  field's position — unchanged.
- Transfer and Adjust field ORDER is unchanged (they don't have this
  expense-shaped set); they only pick up the sheet-picker swap (§2).
- Income uses the "Source" label for the merchant field, as today.

## 2. Bottom-sheet single-select picker

Convert `SearchablePickerRow` in place (so every call site upgrades at once):

- The row is a `Button` showing `title` + the selected name; tapping sets a
  local `@State private var presented = false`.
- `.sheet(isPresented: $presented)` presents the existing searchable list
  wrapped in a `NavigationStack`, with `.presentationDetents([.large])` and a
  visible drag indicator. Toolbar: a **Cancel** (leading) that dismisses
  without changing the binding.
- Selecting an option sets the binding and dismisses (same as today's
  pop-on-choose). The `.searchable` field + filtering are unchanged.
- Because this edits the shared component, Category, Account, and Transfer
  From/To all become bottom sheets in both Add and Edit with no call-site
  changes.

Sheet-on-sheet caveat: these forms are themselves presented as sheets, and the
Add sheet's type switcher is a paged `TabView`. Presenting a `.sheet` from a
form row inside them is supported (stacked sheets); the inner sheet's detents
apply to the inner sheet only.

## 3. Inline wrapping tag chips (Add + Edit)

Replace the inline one-tag-per-row `Section("Tags")` with a chip flow:

- **New `FlowLayout`** (`WriteScreens/FlowLayout.swift`) — a small custom
  `Layout` (iOS 17 floor) that lays subviews left-to-right and wraps to the
  next row on overflow. Reusable, no dependency.
- **New `TagChipFlow`** view, bound to `Binding<Set<String>>`:
  - Each tag renders as a chip: name in the tag's color; **selected** = filled
    tint (`Color(hex: tag.color)` background, readable foreground);
    **unselected** = faint outline. Tap toggles membership in the set.
  - **Show-all cap:** by default render all *selected* chips plus enough
    *unselected* chips to reach a cap (`maxCollapsedChips = 10`), then a
    trailing **"Show all (N)"** chip that expands to show every tag and becomes
    **"Show less"**. Selected chips are ALWAYS visible (never hidden behind the
    cap). When the total tag count ≤ cap, no show-all control renders.
  - `@State private var expanded = false` local to the flow.
- Both sheets swap their inline Tags `Section` for `Section("Tags") { TagChipFlow(selected: $selectedTags) }`, keeping the `!store.tags.isEmpty` guard.
- Multi-select semantics and the `selectedTags: Set<String>` binding are
  unchanged; only the presentation changes. Tag creation stays in the tag admin
  screen (list-only here).

## 4. Translucent scroll-edge top (Add sheet)

The Add sheet's paged `TabView` sets `.background(Color(uiColor:
.systemGroupedBackground))` (added so the pager's per-page backgrounds look
unified). That opaque fill extends under the toolbar, defeating the system's
**translucent scroll-edge** nav material — scrolled form content is hidden by a
solid band instead of blurring faintly under the bar (the behavior Accounts/
Budgets get for free as plain `Form`/`List` in a `NavigationStack`).

Goal: the top toolbar/type-switcher area becomes translucent so content scrolls
faintly-blurred beneath it, matching Accounts/Budgets. The fix must keep the
pager's pages visually unified (the reason the opaque background exists) — so
this is NOT a plain deletion: move the grouped background onto the Form content
(e.g. `.scrollContentBackground(.hidden)` + a background that does not extend
under the nav bar, or the toolbar-background / scroll-edge appearance APIs) and
verify the pages stay uniform while the top turns translucent.

This item is **visual-acceptance**: tune on the sim and verify by screenshot
against the Accounts scroll behavior, not by a single deterministic edit. The
Edit sheet (a plain `Form`) likely already behaves — verify; touch only if it
doesn't.

## Non-changes (explicit)

- Engine, save arg shapes (`tagIds`, `category`, `account`, transfer amounts),
  merchant auto-categorization, split/refund/receipt/status logic: untouched.
- Transfer/Adjust field order; macOS receipt file-importer path.
- The combined Amount+Currency row and the Liquid Glass type switcher (#499)
  stay as they are.

## Testing

- Builds: FinchApp (iOS) + FinchMac; FinchAppTests green.
- Unit-testable seam: the tag show-all partition logic (given all tags + the
  selected set + cap → the visible-collapsed subset always contains every
  selected id and is ≤ cap+selected) is pure — extract as a small static
  helper and test it. `FlowLayout` geometry and sheet presentation are not
  unit-tested (manual).
- Manual checklist (PR body):
  1. Expense Add: rows read Account, Amount, Category, Date & time; Merchant +
     Note are the last section.
  2. Category/Account tap → a full-height sheet slides up from the bottom;
     search works; pick dismisses and updates the row; Cancel leaves it
     unchanged.
  3. Transfer: From/To open as bottom sheets; Adjust: account opens as a sheet.
  4. Tags: chips wrap across rows; tap toggles color fill; with >10 tags a
     "Show all (N)" appears and a selected tag is always visible even collapsed;
     "Show less" re-collapses.
  5. Edit sheet: same picker sheets + tag chips; saving persists category /
     account / tags unchanged.
  6. macOS: pickers present; chips render/toggle.
