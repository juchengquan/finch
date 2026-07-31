# Privacy-mode calendar dots — design (2026-07-31)

## The problem

Turn privacy mode on and the month calendar goes blank. Every day cell loses both amount
lines, so the grid stops telling you anything at all — not even which days had money moving.

That blankness was deliberate. `FinchStore+ViewHelpers.swift:119-131`:

> Nil in privacy mode: the cells drop their amount lines entirely rather than render a grid
> of masks.

The reasoning holds — 30 cells of `••••` is noise. But dropping to nothing overshoots: the
*shape* of the month (which days were active, and in which direction) is not the secret.
The amounts are.

## The change

In privacy mode, a day cell draws **presence dots** instead of nothing:

| day has | privacy OFF | privacy ON (this change) |
|---|---|---|
| income only | `+1,850` green | one green dot |
| expense only | `−42.10` red | one red dot |
| both | both lines | green dot above red dot |
| neither | empty | empty (unchanged) |

**Presence only — never magnitude.** No size, opacity, or count scaling. A dot means "money
moved in / out that day" and nothing more. Magnitude-scaled dots were considered and rejected:
they let a shoulder-surfer read payday and rent day straight off the grid, which is the thing
privacy mode exists to prevent.

**Vertical, on the day number's axis.** The dots stack beneath the number, sharing its centre
line — the cell reads as one centred column. A day with only one kind puts its dot directly
under the number rather than hovering in the second row; colour already carries which kind it
is, so position carries nothing.

Privacy off: **nothing changes.** The exact amount lines render exactly as they do today.

## Scope

One component, `Common/MonthCashCalendar.swift`, which three screens share:

- `Tabs/ScheduledCalendarView.swift` (scheduled totals)
- `Tabs/ActivityTab.swift` (actual transaction totals)
- `WriteScreens/AccountDetailView.swift` (one account's totals)

All three inherit the behaviour from the single fix.

**Out of scope:** the Insights spending heatmap (`Common/ChartViews/CalendarHeatmap.swift`)
shades days by spend intensity and has no privacy handling at all. That is a real leak of the
same family, but it is a separate component with its own design question — deliberately left
for a follow-up, not folded in here.

## How the cell learns privacy is on

Today the component's only hint is that its `format` closure returned nil. Inferring "masked"
from that nil is rejected: it would make `nil` mean two things at once, so any future caller
returning nil for an unrelated reason would silently get dots, and it leaves nothing pure to
test.

Instead the caller says so explicitly, and the decision is a pure function:

```swift
enum Mark: Hashable { case income, expense }

/// Which presence dots a day cell draws. Empty unless masked — an unmasked
/// cell draws amount lines, never dots.
static func marks(income: Double, expense: Double, masked: Bool) -> [Mark]
```

`marks` returns `[]` when `masked` is false, and otherwise `[.income]` / `[.expense]` /
`[.income, .expense]` filtered by `> 0`. It sits beside the existing `weekRows` /
`cellHeight` / `monthIndex` statics — no new file, no new type.

`dayCell` then branches structurally, so the numbers are unreachable while masked. The two
branches keep **separate stacks with their own spacing** — the amount lines must stay at
`spacing: 0`, exactly as today, or the unmasked cell shifts:

```swift
Group {
    if masked {
        VStack(spacing: 3) {
            ForEach(Self.marks(income: amounts?.income ?? 0,
                               expense: amounts?.expense ?? 0,
                               masked: masked), id: \.self) { dot($0) }
        }
    } else if let a = amounts {
        VStack(spacing: 0) {                      // unchanged from today
            if a.income  > 0, let s = format(a.income)  { amountLine("+" + s, .green) }
            if a.expense > 0, let s = format(a.expense) { amountLine("−" + s, .red) }
        }
    }
}
.frame(height: 32)
```

A rejected alternative: have the component read `store.privacyMode` from the environment. The
component is deliberately store-agnostic — its header comment states that the semantics of the
amounts belong to the caller — and an environment read would break that boundary.

### Call sites

Each host adds one argument beside its existing `format:`:

```swift
MonthCashCalendar(
    …,
    format: { store.displayExactBase($0) },
    masked: store.privacyMode)          // new
```

## Layout

The dots live **inside the existing fixed 32pt slot**. Nothing about the grid geometry moves:
`gridHeight` stays `6 * 62 + 5 * 4`, `cellHeight(rows:)` is untouched, and the three carousel
pages keep identical heights. Toggling privacy must not shift a single row.

- dot diameter 6pt, `Circle().fill(…)`, 3pt vertical spacing between the two
- colours are the existing `.green` / `.red` the amount lines already use
- income dot above expense dot when both are present

The 6/3pt figures are the starting values; they may be nudged once seen on the simulator, but
only within the 32pt slot — the slot itself does not grow.

Must compile for macOS too — `FinchMac` shares these sources, so no iOS-only API.

## Accessibility

The dots are the cell's only content while masked, so left decorative they would make VoiceOver
read a bare day number. The dot stack gets a label and the cell combines its children, giving
"15, income and spending".

Three new localizable strings: `Income`, `Spending`, `Income and spending`.

These go through the generated-catalog pipeline — `xliff-keys.ts` → `extracted-keys.json` →
`build-xcstrings.ts` — and **both** the key set and the rebuilt catalog get committed. Skipping
this fails the i18n guard in CI. zh-Hans wording, if it needs pinning, belongs in
`scripts/zh-manual.json`, never in the catalog by hand.

## Testing

**`MonthCashCalendarMarksTests`** (new, `FinchApp/Tests/FinchAppTests/`) — follows the
`SplitVisibilityMapping` pattern of testing a pure static function directly. The component has
three callers and zero tests today. Matrix:

| masked | income | expense | expected |
|---|---|---|---|
| false | any | any | `[]` |
| true | 0 | 0 | `[]` |
| true | > 0 | 0 | `[.income]` |
| true | 0 | > 0 | `[.expense]` |
| true | > 0 | > 0 | `[.income, .expense]` (order fixed) |

**`PrivacyModeTests`** — add the missing assertion that `displayExactBase` returns nil under
privacy and a real string when off. That is the contract the calendar leans on, and nothing
currently guards it.

**Simulator check** — build and run via the `ios-build-launch` skill, open the Activity tab
calendar, toggle privacy (⌘⇧H / the palette), and screenshot both states. Confirm the dots
render on the number's axis and that no row height changes across the toggle. The simulator is
the real check on appearance here; measure with `idb ui describe-all` rather than eyeballing if
anything looks off.

**CI** — `ios/scripts/ci-local.sh` before pushing, rebased on `feat/frontend` first.

## Success criteria

1. Privacy on: active days show correctly-coloured dots; empty days stay empty.
2. Privacy off: pixel-identical to today.
3. No amount, in any form, renders anywhere in the grid while privacy is on.
4. Row heights and grid height identical across the privacy toggle.
5. VoiceOver announces the day and what kind of activity it had.
6. All three hosting screens get the behaviour with no per-screen logic.
