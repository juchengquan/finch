# Split discoverability — design

**Date:** 2026-07-19
**Status:** Design approved in discussion; plan follows.
**Scope:** FinchApp UI only — surface the existing **Splits** feature on the Add/Edit
transaction sheets. No FinchCore/engine/schema change (`SplitEditorView` and the
`setTransactionSplits` action already exist and work). No web change.

## Purpose

Assigning more than one category to a transaction is already fully supported via
**Splits** (multiple category legs whose amounts divide the total), but it is nearly
undiscoverable:

- On the **Add** sheet the **"Split…"** button doesn't exist until a non-zero amount is
  typed (`AddTransactionSheet.swift:253` gates it on `amount != 0`), and even then it's a
  plain text row buried *below the Date field*, far from the Category picker.
- On the **Edit** sheet, splitting is only reachable once a transaction *already has* ≥2
  legs — you can't split a normal single-category transaction from the UI.

A real user ("I did not see this on the UI") couldn't find it. This spec makes splitting
discoverable **where people categorize** — on the Category row — without touching the
split engine or editor.

## Not in scope: "multi-category as tags"

We explicitly considered letting a transaction carry several categories each at the
**full** amount (tag-style). Rejected: it breaks double-entry balance (two full-amount
category legs sum to 2× the account leg and trip the balance guard) and double-counts
category spend/budgets. Splits (amounts dividing the total) are the supported
multi-category mechanism; this spec only improves their **entry point**.

## Decisions

1. **Split affordance lives on the Category row.** `CategoryPickerRow` gains an optional
   `onSplit: (() -> Void)?`. When set, the row renders a **trailing split-icon button**
   (SF Symbol `arrow.triangle.branch`, tunable) as a *separate* tap target: the main row
   area still opens the category picker; the icon opens the split editor. Only the two
   transaction sheets pass `onSplit`, so no other screen changes.
2. **Always visible; enabled once an amount exists.** The split icon shows from the start
   (so the capability is discoverable), but is **disabled/dimmed until a non-zero amount
   is entered** — a split needs a total to divide across categories. (The amount field
   sits above Category on the sheet, so it is normally already filled by the time the user
   is choosing a category.) This replaces the current gate that hid the control entirely.
3. **The Category row reflects split state.** When splits are active, the row shows a
   split summary — **"Split across N categories"** — in place of the single category name,
   with the split icon emphasized; tapping the row *or* the icon reopens the editor. The
   old separate "Split…" button and the `if pendingSplits == nil` hiding of the picker are
   removed: one row that is single-or-split.
4. **Edit-sheet parity.** The same split-icon appears on the Edit sheet's Category row for
   **single-category, splittable** transactions (expense/income; not transfer/adjustment/
   opening), so an existing single-category transaction can be split. When a transaction
   is already split, the existing "Split" section behavior is unchanged.
5. **No engine/schema change.** Reuses `SplitEditorView` (unchanged) and the
   `setTransactionSplits` chokepoint (unchanged). Splitting stays limited to expense/income
   as today (a transfer/adjustment has no category leg to split).

## Components (all FinchApp)

- **`WriteScreens/CategoryPickerRow.swift`** — add optional `onSplit: (() -> Void)?` and a
  `splitSummary: String?` (nil = show the picked category; non-nil = show the summary text
  and mark the row as split). Restructure the row into an HStack: a main tappable area
  (opens the picker, or is inert/`splitSummary` when split) plus a trailing split-icon
  `Button` (its own tap target). The icon takes a `splitEnabled: Bool` to dim/disable.
- **`WriteScreens/AddTransactionSheet.swift`** — pass `onSplit` (sets `showingSplit = true`,
  reusing the current `SplitEditorView(... target: .draft ...)`), `splitSummary`
  (`pendingSplits.map { "Split across \($0.count) categories" }`), and `splitEnabled`
  (`DecimalInput.parse(amount) ?? 0 != 0`). Remove the standalone "Split…" button block and
  the `if pendingSplits == nil` wrapper so the Category row is always shown.
- **`WriteScreens/EditTransactionSheet.swift`** — pass `onSplit` on the Category row for
  splittable single-category transactions (the existing `canSplit`-style guard), opening the
  editor with `target: .existing(id:)`. Already-split transactions keep the current Split
  section.

## Data flow

Unchanged. The icon/row just triggers the existing flows: Add stages `pendingSplits` and
applies `setTransactionSplits` on save (already wired at `AddTransactionSheet.swift:484`);
Edit applies `setTransactionSplits` directly via the editor's `.existing` target.

## Error handling

Unchanged — `SplitEditorView` already validates that the split amounts sum to the total and
surfaces its own errors. Tapping the (dimmed) icon with no amount does nothing.

## Testing

- **Unit (FinchAppTests):** a tiny pure helper `splitSummaryText(count:)` → `"Split across
  \(count) categories"` (nil for < 2) is unit-tested; the rest is UI wiring.
- **Builds:** FinchApp + FinchMac.
- **Sim (ios-finch2):** fresh Add sheet shows the split icon on the Category row (dimmed);
  enter an amount → icon enables → tap → `SplitEditorView` → set two categories → row reads
  "Split across 2 categories". Open Edit on a single-category expense → split icon present →
  split it → the Split section appears.

## Out of scope

Multi-category-as-tags (rejected above), any change to `SplitEditorView`'s internals or the
split engine, splitting transfers/adjustments, a total-less split flow (splitting stays
gated on a non-zero amount), and web parity. New copy joins the tracked zh-Hans batch.
