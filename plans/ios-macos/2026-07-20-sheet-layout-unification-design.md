# Add/Edit sheet layout unification — design

**Date:** 2026-07-20
**Status:** Design agreed in a `/grill-me` interview; plan follows.
**Scope:** FinchApp write screens + `Common/Metrics.swift` + a new section-header helper.
**No** FinchCore/engine/schema change, **no** behavior change, **no** web change.

## Purpose

Five add/edit sheets have drifted apart in how they group, label, and hint:

- **AccountSheet** — string section headers on some groups, a lone one-row toggle section, a
  visible nav title, no type control.
- **BudgetSheet** — no section headers, footers for hints, and **hand-rolled duplicates** of the
  shared `TxnTypeToolbar` (a byte-identical `caption` and a near-identical segmented picker).
- **ScheduledSheet** — no section headers; its hint sits *inside* a section as an inline caption
  row rather than a footer.
- **Add/EditTransactionSheet** — the de-facto blueprint: `TxnTypeToolbar` control + caption, bare
  primary group, string headers on secondary groups (`Receipt`, `Details`, `Transfer`, `Account`).

Nothing about section-title spacing is tunable: `Metrics.sectionSpacing = 12` controls the gap
*between* sections, but header padding is the system's, and `TxnTypeToolbar.caption` hardcodes its
insets. This design unifies all five on the transaction blueprint and makes title spacing a global
token.

## Decisions (from the interview)

1. **Blueprint = `Add`/`EditTransactionSheet`.**
2. **Header rule — mixed (blueprint-faithful).** Bare: the type-caption section, the primary field
   group, the error section. A string header on **every** secondary group. (An earlier
   "every section gets a header" answer was given under a different blueprint and is superseded.)
3. **Accounts keeps its Type as a Picker row** and therefore keeps its **visible** nav title — no
   `.principal` control. `TxnTypeToolbar.segmented` sizes at 50pt/segment; Accounts' 6 types = 300pt
   against roughly 273pt of free nav-bar centre on a standard iPhone, and 6 icon-only account types
   (savings vs investment vs virtual) are far less legible than the transaction arrows.
4. **Title spacing becomes global.** A shared `finchSectionHeader(_:)` renders every labeled
   section title with tokenized padding; `Metrics` gains `headerTopPadding`, `headerBottomPadding`,
   and `captionInsets`. `sectionSpacing` is unchanged.
5. **The helper applies to all four sheet families, including the two transaction sheets** — a
   token only controls the family if the blueprint routes through it too; otherwise tuning a value
   silently desyncs the blueprint from the sheets unified against it.
6. **Hints are always section footers.** Footer styling otherwise stays system-native (no footer
   helper — the defect was placement, which this fixes).
7. **Accounts folds** the edit-only "Include in net worth" toggle into the primary section, rather
   than inventing a header for a single switch.
8. **BudgetSheet adopts the shared `TxnTypeToolbar`**, dropping its duplicated caption and picker.
9. **One PR.**

## Section map (the target)

| Sheet | Sections, in order |
|---|---|
| **Accounts** | primary *(Name, Type, Currency, Group, + net-worth toggle on edit)* · `Opening balance` · `Color` · error |
| **Budgets** | type caption · primary *(Name, Amount, Frequency, Start, Group)* + re-base warning as its **footer** · `Tracking` *(Categories, Accounts)* · `Rollover` · error |
| **Scheduled** | type caption · primary *(Name, Amount)* + variable-amount hint as its **footer** · `Account` *(Account/From/To, Category)* · `Schedule` *(Frequency, Day, Start)* · `Installment` · error |
| **Transactions** | unchanged names and grouping — labeled sections merely re-routed through the helper |

Bare (headerless) throughout: the type-caption section, the primary group, the error section.
`Account` reuses `EditTransactionSheet`'s existing vocabulary rather than inventing "Where".

## Components

### 1. `Common/Metrics.swift` (extend)
```swift
static let sectionSpacing: CGFloat = 12        // existing, unchanged
static let headerTopPadding: CGFloat = 16      // gap above a section title
static let headerBottomPadding: CGFloat = 6    // gap between title and its group
static let captionInsets = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
```
`captionInsets` is lifted verbatim from today's `TxnTypeToolbar.caption`, so that part is provably
neutral. The two header values are **starting points chosen to approximate the current system
rendering** — they are the first thing to check on the visual pass, and the whole point of the
tokens is that correcting them is a one-line change in this file.

### 2. `finchSectionHeader(_ title: String) -> some View` (new)
A single styled header view used as `Section { … } header: { finchSectionHeader("Tracking") }`:

```swift
Text(title)
    .font(.footnote)
    .foregroundStyle(.secondary)
    .textCase(nil)                                  // keep title case, as the sheets render today
    .padding(.top, Metrics.headerTopPadding)
    .padding(.bottom, Metrics.headerBottomPadding)
```

`.textCase(nil)` is required: SwiftUI's grouped-list headers otherwise upper-case the string, and
the existing sheets render "Receipt"/"Details" in title case. Lives beside the other shared
write-screen helpers.

### 3. `Common/TxnTypeToolbar.swift` (touch)
`caption(_:)` swaps its hardcoded `EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)` for
`Metrics.captionInsets`. `segmented`/`locked` are unchanged.

### 4. The five sheets
- **BudgetSheet** — replace the hand-rolled `.principal` `Picker` with `TxnTypeToolbar.segmented`
  and the hand-rolled heading with `TxnTypeToolbar.caption`; add `Tracking` and `Rollover` headers;
  move the cycle re-base warning into the primary section's footer (deleting its standalone note
  section).
- **ScheduledSheet** — move the inline variable-amount hint into the primary section's footer; add
  `Account`, `Schedule`, `Installment` headers.
- **AccountSheet** — fold the net-worth toggle into the primary section; route `Opening balance`
  and `Color` through the helper.
- **Add/EditTransactionSheet** — route existing labeled sections (`Receipt`, `Details`, `Transfer`,
  `Account`) through the helper. No renaming, no regrouping.

## Behavior, data flow, error handling

None of this touches state, `save()`, the store, or the engine — it is layout only. Every sheet
keeps its existing fields, bindings, validation, and error section. New user-facing strings are the
section headers `Tracking`, `Rollover`, `Account`, `Schedule`, `Installment`; they follow the
standard generated-localization pass for zh-Hans.

## Testing

- **Builds:** FinchApp + FinchMac.
- **No unit tests** — this is view layout; there is no pure logic introduced (the tokens are
  constants and the helper is a view).
- **Visual sign-off is the user's.** The simulator's UI-automation permission is currently revoked
  (`osascript` assistive access denied), so the agent can build, install, and screenshot a launch
  screen but cannot navigate into these sheets to verify spacing. This is the primary verification
  for a layout-only change, and it must be done by hand.

## Risks

- Touches **two shipped, heavily-used** sheets (Add/EditTransaction). The edits there are purely
  mechanical header swaps, but any token mismatch shows up first on the most-used screen.
- A custom header view that doesn't match iOS's default grouped-header styling will read as
  non-native. Tokens must be seeded to today's rendering, not guessed.

## Out of scope

A matching footer helper or footer tokens; moving Accounts' type into the toolbar; renaming or
regrouping any transaction section; per-context (sheet vs tab) `sectionSpacing` split; any
behavior, engine, or web change.

## Addendum — the sheet top-inset inconsistency (found during implementation)

The most visible inconsistency turned out not to be section titles at all. Measured with
`idb ui describe-all` (points, iPhone 402×874):

| sheet | nav bar ends | caption y | gap |
|---|---|---|---|
| Add/Edit Transaction | 132 | 138 | 6pt |
| Budget / Scheduled / Account | 132 | **167** | **35pt** |

**Root cause:** `AddTransactionSheet` already carried a hardcoded
`.contentMargins(.top, 6, for: .scrollContent)` (comment: *"Pull the 'Expense' caption close
under the nav bar"*) — an ad-hoc fix that was never generalized. Every other sheet inherited
SwiftUI's larger default inset, hence the 29pt discrepancy. It predates this branch: the
baseline `BudgetSheet` measures the same 167.

Ruled out by measurement first (each rebuilt and re-measured): `.navigationTitle`, the
`.principal` control, `TxnTypeToolbar.caption`, `listSectionSpacing`, the Form's content
(stripped to two sections), and the presentation site (AddTransactionSheet renders 138 even
when presented from BudgetSheet's own `.sheet(isPresented:)`).

**Fix:** `Metrics.sheetTopMargin` (= 6, measured) applied by a shared `finchSheetForm()`
(`finchSectionSpacing()` + the pinned top margin), adopted by all five sheets; the hardcoded
one-off in `AddTransactionSheet` is removed so the token is the single source of truth.
Verified: Budget / Scheduled / Add-Transaction captions all at y=138.
