# Split moves into the Category subpage

**Status:** design, agreed 2026-08-01. Not yet implemented.
**Scope:** the Add/Edit transaction sheets' Category field. iOS + macOS (SwiftUI; there is no
UIKit add/edit screen — every UIKit screen hosts these same sheets in a `UIHostingController`).

## Goal

Splitting a transaction across categories stops being a separate editor reached by an unlabelled
icon, and becomes a mode of the Category picker you are already in: a **toggle at the top of the
subpage** that turns the category tree's single-select into multi-select, with the amounts collected
directly above it.

Splits keep meaning exactly what they mean today — they divide the transaction's total. Nothing about
the ledger model changes.

## What exists today

| Piece | Where |
|---|---|
| Category row | `CategoryPickerRow` — `WriteScreens/CategoryPickerRow.swift:16` |
| Category subpage | `CategoryPickerSheet` — same file, `:82`. Searchable indented tree, expand/collapse, staged-then-Confirm |
| Split entry point | A trailing `arrow.triangle.branch` button **inside the Category row**, `:46-58` |
| Split editor | `SplitEditorView` — `WriteScreens/SplitEditorView.swift`, presented as its own sheet |
| Engine write | `Transactions.setTransactionSplits` — `FinchCore/.../Domain/Transactions.swift:36` |

Today's behaviour worth carrying over deliberately, because each is a decision someone already made:

- **Any node is selectable**, parent or leaf (`CategoryPickerRow.swift:15`). A transaction can sit on
  a parent category.
- **The split icon is dimmed to 40% until a non-zero amount exists** (`:55-56`) and is absent
  entirely for refunds (callers pass `onSplit: nil`). Neither state explains itself.
- **Splits must be ≥2 rows summing to the total**, client-side (`SplitEditorView.swift:127-132`,
  tolerance `0.01 × rowCount`) and again in the engine (`Transactions.swift:44-49`, tolerance
  `0.005 × count`, raising `error.split.minTwo` / `error.split.sumMismatch`).
- **The last leg absorbs the rounding remainder** so category legs sum exactly to `-acctBase` with no
  FX residue (`Transactions.swift:57-62`).
- **A split's displayed category is the dominant (largest-magnitude) leg** (`Projection.swift:136-148`).

## The design

### Layout

The branch icon leaves the Category row. The subpage gains a toggle; when it is on, a pinned section
sits between the toggle and the tree holding the ticked categories with their amounts.

```
┌─────────────────────────────────┐
│ ✕        Category            ✓ │
├─────────────────────────────────┤
│  Split across categories   [ON] │
├─────────────────────────────────┤
│  Groceries          $ 40.00     │
│  Household          $ 18.20     │
│  ─────────────────────────────  │
│  Allocated  $58.20 / $58.20  ✓ │
├─────────────────────────────────┤
│ 🔍 Search                       │
│  ☑ Groceries                    │
│  ☐ Dining                       │
│    ☐ Coffee Shops               │
│  ☑ Household                    │
│  ☐ Utilities                    │
└─────────────────────────────────┘
```

Amounts live in the pinned section rather than on the tree rows, because the tree scrolls and is
indented — two splits can end up far apart, and the running `Allocated / Total` has nowhere natural to
sit. The tree stays a tree; the checkbox is the only thing added to it.

With the toggle **off** the subpage is exactly what it is today: single-select, radio-style checkmark,
staged then Confirm.

### Amount allocation

Rows the user has not typed into always share the leftover evenly. Typing into a row **pins** it; it
stops moving, and the unpinned rows re-divide what remains around it.

```
tick Groceries      →  Groceries  $58.20
tick Household      →  Groceries  $29.10   Household  $29.10
tick Dining         →  Groceries  $19.40   Household  $19.40   Dining  $19.40
type 10 in Dining   →  Groceries  $24.10   Household  $24.10   Dining  $10.00 🔒
untick Household    →  Groceries  $48.20                       Dining  $10.00 🔒
```

- Rounding remainder goes to the **last** row, matching what the engine already does internally.
- If pinned amounts already exceed the total, unpinned rows go to 0 and `Allocated` shows over-budget;
  Confirm is blocked (see below). Do not silently re-scale a pinned row — the pin is the user's
  explicit instruction.
- **Changing the transaction amount re-divides the unpinned rows** rather than discarding the split.
  This replaces `AddTransactionSheet.swift:215`, which currently nulls `pendingSplits` outright on any
  amount change.

### Toggling off, and ticking down to one

Toggle off keeps the **largest-amount** category and drops the rest. That is not an arbitrary choice:
it is the same dominant-leg rule `Projection.swift:136-148` already uses to decide which category a
split *displays*, so the survivor is the category the row was showing you anyway.

Ticking down to a single category is the same outcome by a different route — a plain single-category
transaction with no split written, which is what the engine requires (a 1-row split is rejected).

No confirmation alert. The subpage is already a sheet inside a sheet, and Cancel discards everything
unsaved, so the work is recoverable without stacking a third modal.

### When Confirm is allowed

| State | Confirm | Writes |
|---|---|---|
| Toggle off | allowed | single category (today's behaviour) |
| Toggle on, 0–1 ticked | allowed | single category, no split |
| Toggle on, ≥2 ticked, each > 0, sum matches total | allowed | splits |
| Toggle on, ≥2 ticked, sum ≠ total | **blocked** | — |
| Toggle on, ≥2 ticked, transaction amount still empty | **blocked** | — |

The toggle is **always enabled**, including before an amount has been entered. With no amount, every
row is 0, rows with no amount are filtered out, and the existing "at least two splits" rule is what
blocks Confirm. The blocking reason must be **stated inline** — the point of moving this into a full
subpage is that there is finally room to say why, instead of a 40%-opacity icon that explains nothing.

Refunds render no toggle row at all, matching today's `onSplit: nil`.

### Tree semantics

Ticking a parent means **that parent only** — no cascade to children. Each split is exactly one
`categoryId`, so cascading would silently manufacture a split per child and re-divide amounts the user
had set. The expand/collapse chevron keeps doing the expanding; the checkbox only ever means "this one".

The "Uncategorized"/none row stays tickable — splits already accept a `nil` categoryId
(`SplitEditorView.swift:125`, and the engine handles `nil` legs).

### Repeated categories in existing data

The web app writes to the same ledger and split rows are free-form there, so a stored transaction may
carry the same category twice. Checkboxes cannot express that. On open, **merge repeated categories
into one row with the amounts summed**; Confirm rewrites them merged.

This is lossless for anything the app can see: the only field distinguishing two same-category legs is
`description`, which the UI never writes (`SplitEditorView.swift:138-139`) and which
`Projection.swift:146` hardcodes back to `nil` on read. The total is unchanged, so no balance moves.

### Write timing

Confirm in the subpage **only stages**. Splits are written by the Edit sheet's existing `save()`,
alongside every other field.

This changes today's behaviour, deliberately. `SplitEditorView.save()` currently calls
`store.apply(.setTransactionSplits, …)` immediately (`:140`) and dismisses, so editing a split commits
even if you then cancel the Edit sheet — while the category next to it stages like everything else.
Putting both on one screen makes that asymmetry indefensible.

The Add flow already stages into `pendingSplits` and is unchanged in kind.

## What this touches

**Changes**

- `CategoryPickerRow` — drop the trailing split button; take split state instead of an `onSplit`
  closure. A split row still displays the joined category names (`splitSummaryText`, unchanged) and
  tapping it opens the subpage with the toggle already on.
- `CategoryPickerSheet` — the toggle, the pinned amounts section, checkbox selection, allocation
  logic, validation messaging.
- `AddTransactionSheet` — feed split state through the row instead of presenting `SplitEditorView`;
  replace the amount-change wipe at `:215` with re-division.
- `EditTransactionSheet` — same, plus `save()` must write splits (see risk below).
- `SplitEditorView` — **retires**. Its only two call sites are the sheets above.

**Deliberately untouched** — these pass no split state, so the toggle never renders:

- Settings › Categories "Parent" picker (`PowerTools/CategoriesView.swift:507`)
- `ScheduledSheet.swift:97` and `:107`
- Scheduled templates' `splits_enabled` flag — a different feature (recurring splits, `Domain/Scheduled.swift`)
- `CategoryMultiPickerRow` / `BulkRecategorizeSheet` — separate multi-select, unrelated
- `SplitShellVC` / `SplitDisplayMode` / `SplitSelectionUITests` — `UISplitViewController`, a naming
  collision only
- **The engine.** No change to `setTransactionSplits`, the model, or validation.

## Risks

**The Edit sheet's `isSplit` becomes staged state.** Today it reads the *stored* transaction
(`EditTransactionSheet.swift:56`, `(liveTxn.splits?.count ?? 0) >= 2`) and gates four things: the
amount field and category patch (`save():409`), whether the transaction can be reclassified (`:88`),
and two section branches (`:127`, `:143`, `:211`). Once splits are staged, `isSplit` has to reflect the
staged selection, and `save()` — which currently skips the category path entirely when split — must
learn to call `setTransactionSplits`. **This is the one genuinely load-bearing change; a bug here
writes wrong legs to the ledger.** It is where the tests below should bite hardest.

**The subpage gets busier** — toggle, pinned amounts, and a searchable tree on one sheet. Accepted:
still better than a hidden icon that explains neither its disabled state nor what it does.

**New strings need catalog entries.** `ci-local.sh`'s i18n guards will fail the build otherwise, and
the guard diffs against HEAD, so an intentional `.xcstrings` change must be committed before it passes.

## Tests

Existing coverage is engine-level (`AddThenSplitTests`, `TagsSplitsTests`, `LegMetadataTests`,
`CategoryTransactionsTests`) plus the pure `splitSummaryText` helper (`SplitSummaryTests`). Nothing
drives the split UI end to end today.

Add:

- **Allocation unit tests** (pure function, no view): even division on tick; pinning on type;
  re-division on untick; re-division when the total changes; remainder to the last row; pinned rows
  exceeding the total.
- **Collapse unit test**: toggle off keeps the largest-amount category.
- **Merge unit test**: repeated categories fold into one row with summed amounts.
- **UI test** — tick two categories, Confirm, save, assert two legs and the transaction total unmoved.
- **UI test** — toggle off with three ticked, assert the largest survives as a plain category.
- **UI test (the regression that matters)** — open a split transaction in Edit, change the split,
  **Cancel the Edit sheet**, assert the ledger is unchanged. This is the behaviour the write-timing
  change introduces, and the one most likely to regress.

Write the failing test first in each case — for the Edit-cancel test especially, confirm it fails
against today's immediate-write behaviour before the change lands.

## Rejected alternatives

| Option | Why not |
|---|---|
| Amount field inline on each ticked tree row | Fields scatter across a scrolling indented tree; nowhere natural for the running total |
| Tick in the subpage, then a second screen for amounts | Keeps two screens, which is the thing being collapsed |
| Even split recomputed on *every* tick | Silently overwrites typed amounts on a screen whose job is entering amounts |
| New ticks start empty | The commonest case (split down the middle) costs two amount entries instead of zero |
| Splits *define* the total | Contradicts the constraint that splits only ever divide the total |
| Cascade parent ticks to children | One tap becomes N splits and re-divides everything |
| Leaf-only ticking | A category assignable with the toggle off becomes unassignable with it on; existing parent splits become uneditable |
| Keep `SplitEditorView` for repeated-category data | Two editors, and you cannot tell which you will get until it opens |

## Known gaps

Decided after the first version shipped (#694). Recorded here rather than in a chat log,
next to the reasoning that produced them.

**The tree shifts when you tick a category — accepted, not fixed.** Ticking inserts a
row into the amounts section above the tree, so everything below moves down by about
44pt; the first tick moves it ~90pt. It is enough to cause a mis-tap. The fix is not
free: the amounts sit above the tree by design, so keeping them there and keeping the
tree still are in tension. The options weighed were pinning the amounts to a bottom
safe-area inset (stable by construction — a bottom inset reserves space without pushing
content down), reserving the section's space when the toggle flips rather than on the
first tick (removes the worst jump only), and putting the amount inline on each ticked
row (perfectly stable, but scatters the fields down a scrolling tree with nowhere for
the running total). **Decision: keep the current design.** Revisit if it bites in use.

**A split transaction's total cannot be edited.** `isSplit` selects a form layout with
no Amount field, so once a transaction is split there is no way to change the figure the
split divides — you would have to collapse it to a single category, fix the amount, and
split again. Pre-existing behaviour, inherited from the old split editor; out of scope
for #694 and deliberately deferred. It is also the constraint that made `isSplit` awkward
to stage (see the Risks section).

**Uncategorized was briefly unavailable, and is back.** The rewrite moved category
choice into a tree that only rendered its "none" row when the caller passed a
`noneLabel`, which the transaction sheets do not — so an uncategorised split leg, which
the old editor allowed and the engine accepts (a nil category), could not be created.
Split mode now always offers the row. Single-select is deliberately unchanged: offering
"no category" on a plain transaction is a separate product decision, not a bug fix.

## Unrelated, found while comparing the two Activity implementations

Not part of this feature; recorded because it was discovered here and is otherwise
undocumented.

**The SwiftUI Activity screen has a dead setting.** Both implementations read the same
`finch.feed.groupByMonth` value, and both use it. The UIKit screen exposes it in an
`ellipsis.circle` overflow menu alongside sort; the SwiftUI screen's `arrow.up.arrow.down`
menu holds sort *only*, so nothing on that screen can change grouping — it inherits
whatever the UIKit screen last wrote. The unsettled question is which icon wins: `↑↓`
names sorting precisely but leaves grouping homeless, while `•••` holds both and
describes neither. Since UIKit ships, the cheap answer is to give SwiftUI the same
`•••` menu.

**The shipping filter icon never fills.** The SwiftUI screen swaps to
`line.3.horizontal.decrease.circle.fill` when a filter is active; the UIKit screen always
draws the unfilled variant, so on the screen users actually get there is no at-a-glance
sign that a filter is on.
