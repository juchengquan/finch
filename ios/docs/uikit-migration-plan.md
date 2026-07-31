# Migrating finch's iOS UI to UIKit — plan

**Status:** Phases 0–2 done · Phase 3 in progress · **Date:** 2026-07-29, revised
2026-08-01 · **Decided parameters:** iPhone + iPad move to UIKit; `FinchMac` stays
SwiftUI; Watch and Widget stay SwiftUI (no UIKit exists on those platforms);
incremental strangler migration, shipping continuously.

> ## Where this stands — 2026-08-01
>
> | Phase | State |
> |---|---|
> | **0 — source split** | **Done.** `.swift` counts: `FinchShared` 59 · `FinchAppSwiftUI` 93 · `FinchAppUIKit` 35 (iOS-only). |
> | **1 — UIKit shell** | **Done, shipping by default on iPhone.** `project.yml` excludes `FinchApp.swift` from the iOS target; the phone boots `@main UIKitAppDelegate`. Not gated. |
> | **2 — pushed destinations** | **Done, gated behind `-uikitActivity YES`.** 24 `*VC.swift` files. |
> | **3a — iPad container** | **Done (#646).** `UIKitShell.makeRoot` returns `SplitShellVC` at regular width and `RootTabBarController` at compact — both UIKit. The two shells no longer differ by framework. |
> | **3b — native columns + tab roots** | **In progress.** Done: Ledger (#648), Budgets (#658), Scheduled (#660) — each converted at BOTH widths. Remaining: **Activity**, **Accounts**. |
> | **4 — opportunistic** | Not started; optional by design. |
>
> **Forecast vs actual.** The estimates below are the pre-implementation forecast,
> kept as written so it can be judged against the outcome. It now can be, for phases
> 0–3a: forecast 2–4 days + 1.5–3 weeks + 3–4 weeks + 1–2 weeks; delivered across
> roughly one week of concentrated work, with Phase 2 landing 24 view controllers.
> The forecast was pessimistic on throughput and — see the 3b correction below —
> optimistic about what "convert a column" means. Do not read the estimates as
> remaining work.

**Why:** ownership of the UI layer. **NOT the resume shadow** — see *How this plan
changed*. Read `ios26-shadow-variant-matrix.md` first, including its 2026-07-30
addendum.

## How this plan changed, and why

Three turning points. Each was forced by evidence, and each is recorded because the
reasoning is what stops it being re-litigated.

1. **A UIKit shell alone does not fix the bug** (2026-07-30). Coverage testing at
   realistic volume found `CategoriesView` shadows under a UIKit root while
   `AccountDetailView` and `ActivityFeedView` do not — and it still shadowed after
   adding the pinned search drawer, the only structural property separating it from
   the clean ones. Five explanations were tested to destruction (`TabView`,
   SwiftUI-content, volume, sections, pinned search drawer). So hosting is a
   **transition state, not an end state**, and the plan became a full conversion of
   pushed screens rather than a shell swap. The shipped `RightSlideDrill` fix is
   sound at scale, so there was never anything broken to escape — this is a
   control/ownership decision, judged on its own merits.

2. **Conversion fixes the failing case** (2026-07-30, validation). `CategoriesView`
   converted to `CategoriesVC`, same data, same root: **clean**. Taking the one
   screen that fails and showing the treatment fixes it is far stronger than the
   earlier tests, which took already-clean screens and showed they stayed clean.
   Cost of the two real conversions: `AccountDetailView` 320 → ~250 lines,
   `CategoriesView` 574 → ~160, store/selectors/write-chokepoint reused unchanged.
   Read those with the caveat that both covered **scroll content only** — the
   omitted parts (calendar mode, holdings, reorder/drag, merge/multi-select,
   import/copy-to-ledger) are real work and plausibly add 30–50%.

3. **Phase 3b converts a tab's root and its iPad column together** (2026-07-31).
   Converting only the column leaves iPhone rendering the SwiftUI screen — two
   implementations of one list, which will drift. See the 3b correction below.

**Sequencing consequence, unchanged throughout:** `RightSlideDrill` STAYS during the
migration. Each unconverted pushed screen keeps its cover; the cover is removed per
route as that screen converts. The app is never mid-flight broken and the bug never
regresses.

---

## The constraint that shapes everything

From the 37-variant sweep and the UIKit-root reproducer:

| App root | Pushed page | Result |
|---|---|---|
| UIKit | UIKit | **clean** |
| UIKit | SwiftUI | shadows |
| SwiftUI | UIKit | shadows |
| SwiftUI | SwiftUI | shadows |

Two consequences the plan must respect:

1. **A UIKit shell alone buys nothing** — and worse, it is not even reliable for
   hosted screens: `CategoriesView` shadows under a UIKit root while
   `AccountDetailView` does not. Benefit arrives only when the root is UIKit *and*
   the specific page is UIKit. Phase 1 ships no user-visible improvement; that is
   expected.
2. **Only PUSHED pages shadow.** Tab roots are roots; sheets are presented. Both are
   already clean and never need converting for the bug.

## Approaches ruled out

Recorded so they are not re-proposed. Each was built or device-tested, not reasoned
about.

**`UIKitNavStack` — host the existing SwiftUI screens inside a `UINavigationController`.**
The cheap version of this plan: keep every screen, change only who owns the push. It
was specified in full, prototyped, and **device-tested — and it still shadowed.** The
trigger is a hosted SwiftUI *scroll view at navigation depth*, not which framework owns
the navigation controller, so wrapping the same screens in UIKit chrome changes nothing.
Neither `UIKitNavStack` nor `UIKitNavLink` exists in the codebase.

> **The part worth remembering is how it looked right.** An on-device prototype
> (2026-07-25) measured post-resume top-edge contrast at ~47 for a SwiftUI push against
> ~6 for a UIKit push and ~9 for a root — a clean, three-way separation that read as
> conclusive, and produced the confident wrong conclusion "SwiftUI `NavigationStack`
> re-converges the glass; a UIKit push does not." The 21-variant matrix later showed
> that framing is wrong in both directions (`ios26-shadow-variant-matrix.md`). A
> prototype that separates cleanly on one axis is not evidence that axis is the cause.

**A UIKit shell alone** (Phase 1 without Phase 2). Covered above: `CategoriesView`
shadows under a UIKit root. Kept as a phase because it is the prerequisite, not because
it fixes anything on its own.

## Scope: what must move, and what need not

**Mandatory (pushed destinations — these shadow): ~4,270 lines**

| | lines |
|---|---:|
| `PowerTools/*` (all pushed) | 2,568 |
| `ActivityFeedView` | 657 |
| `AccountDetailView` | 320 |
| `BudgetDetailView` | 271 |
| `HoldingsView` | 215 |
| `ScheduledDetailView` | 120 |
| `TransactionDetailView` | 119 |

**Optional (never shadows — convert only for control): ~12,000 lines**
five tab roots (`Accounts` 706, `Budgets` 595, `Scheduled`, `Insights`, `Settings`),
10 sheets (2,446 lines, presented), the `Path`/`Canvas` chart primitives (19 sites,
leaf views), and most of `Common`.

**Never moves:** `FinchCore` (55 files, 8,111 lines — the engine and all money/DB
logic), plus the non-view app layer (Sync 1,288, Notifications 415, AppIntents 286,
Spotlight 163, Security 166, DeepLink 82). `FinchMac`, Watch and Widget stay SwiftUI.

## What the conversion actually consists of

Counted across the UI layer: 403 `@State` → controller properties with explicit
reload · 159 `ForEach` → diffable data sources · 86 `.sheet` → `present(_:animated:)`
· 74 `Picker` · 59 `.toolbar` → `UIBarButtonItem` · 53 alerts/dialogs →
`UIAlertController` · 52 `TextField` → `UITextField` + delegate · 46
`Menu`/`contextMenu` → `UIMenu` · 25 `swipeActions` →
`UISwipeActionsConfiguration` · 24 `.searchable` → `UISearchController` · 11
`onMove`/`onDelete` → table editing.

**The store needs no rewrite.** `FinchStore` exposes 18 `@Published` properties;
UIKit controllers observe them with Combine sinks. The write chokepoint,
projection and selectors are untouched.

**The tests mostly survive.** 51 of 56 app-test files never import SwiftUI — they
test routing, civil dates, reorder logic, backup decisions, category forests. Only
5 files are view-coupled. That is 318 test functions carrying over nearly intact.

---

## Phases

### Phase 0 — Split the sources (prerequisite, 2–4 days)

Today `FinchApp` (iOS) and `FinchMac` compile the *same* directory, so the first
UIKit file would break the Mac build. Split into three:

- `FinchApp/Sources/FinchShared/` — store, router, notifications, sync, spotlight,
  security, intents, import/export. Compiled by **both**.
- `FinchApp/Sources/FinchAppSwiftUI/` — today's views. Compiled by **Mac always**,
  and by iOS until each screen is replaced.
- `FinchApp/Sources/FinchAppUIKit/` — new code. **iOS only.**

Update `project.yml`. **Exit:** both targets build, `ci-local.sh` green, zero
behaviour change.

### Phase 1 — The UIKit shell (1.5–3 weeks)

`UIApplicationDelegate` → `UIWindow` → `UITabBarController` (compact) /
`UISplitViewController` (regular) → per-tab `UINavigationController`s. Every existing
screen is hosted in a `UIHostingController`.

Also in this phase: the `DeepLinkRouter` bridge (deep links, Siri, notifications,
Spotlight, ⌘K all currently drive SwiftUI state), the app-root sheets (Add
transaction, command palette), and the biometric lock overlay.

> **Security gate:** the lock overlay currently sits as a `ZStack` sibling above the
> shell. In UIKit it must be a window-level overlay above the tab controller. Get
> this wrong and account data renders over the lock screen. Write a test for it.

**Known tax:** SwiftUI's `.toolbar` and `.searchable` do **not** bridge into a
hosting controller's `navigationItem` (verified — lab variant 20 and reproducer B).
Every hosted screen with bar items needs them rebuilt as `UIBarButtonItem`s /
`UISearchController` until that screen is converted. Budget for ~30 screens.

**Exit:** app behaves identically, all 318 tests pass, CI green. **No shadow
improvement yet** — by design.

### Phase 2 — Convert the pushed destinations (3–4 weeks)

In order of user impact. Each one converted is one page that stops shadowing, and
its `.rightSlideDrill(...)` becomes a plain push again:

1. `ActivityFeedView` (657) — `UICollectionView` list config + diffable data source
   + `UISearchController`. The template for the rest; do it first and carefully.
2. `AccountDetailView` (320) — same pattern, plus the mode picker and the seeded `+`.
3. `BudgetDetailView` (271), `HoldingsView` (215), `ScheduledDetailView` (120),
   `TransactionDetailView` (119).
4. `PowerTools` (2,568 across 15 files) — categories, rules, tags, merchants, FX.
   Mechanical, mostly table-driven, good after the pattern is proven.

**Keep `RightSlideDrill` throughout this phase.** Every screen not yet converted
stays behind its cover, and the cover is removed for that route only when its
screen lands in UIKit. That way no screen ever regresses to shadowing mid-migration.

**Exit:** `RightSlideDrill.swift` deleted once the LAST pushed screen converts;
every drill is a native push, native bar behaviour and swipe-back throughout, tab
bar visible during drills.

### Phase 3 — iPad (1–2 weeks)

`UISplitViewController` replaces `SplitViewShell`. The six screens that today take
an optional `selection: Binding<String?>?` to serve both layouts lose that pattern:
the UIKit list controller drives the split directly.

**Located, as of 2026-07-31** (there is no `SplitViewShell.swift` — it lives inside
`AdaptiveShell.swift`, and part of it was renamed):

- `FinchAppSwiftUI/Shell/AdaptiveShell.swift` — `struct SplitViewShell` at :292,
  reached from :16. 482 lines in the file.
- `FinchAppSwiftUI/Shell/MasterDetailShell.swift` — 80 lines.
- The six binding-carrying screens: `Tabs/ActivityTab.swift`, `Tabs/BudgetsTab.swift`,
  `Tabs/ScheduledTab.swift`, `Tabs/AccountsTab.swift`, `Tabs/LedgerTab.swift`,
  `WriteScreens/LedgerManagementView.swift`.
- The seam to cut: `UIKitShell.makeRoot` at :81-87, whose `wide` branch (:83-85)
  returns the hosted `AppRootHost`.

**Motivation differs from Phase 2, and that should be decided on explicitly.** The
resume shadow afflicts *pushed* screens; an iPad detail pane is a sibling column, not
a push, so Phase 3 buys **consistency and one shell instead of two**, not a bug fix.
See "Stopping early is a legitimate outcome" below — it applies with more force here
than to Phase 2.

#### Phase 3a — the container (DONE, 2026-07-31)

`SplitShellVC` is a real `UISplitViewController`; the columns are still hosted SwiftUI.
iPhone and iPad are one code path. Two constraints worth knowing before touching it:

- **`UISplitViewController.style` is fixed at init**, and a triple-column split view has
  no display mode meaning "primary + secondary, no supplementary" — the modes run
  `.oneBesideSecondary` (supplementary + secondary) to `.twoBesideSecondary` (all
  three). So the three-column tabs and the dashboard tabs need *different* split views,
  and `SplitShellVC` swaps between them on the arity boundary.
- **`SplitSelection` is a reference type** because the columns are hosted separately and
  it must outlive a split-view swap.

Verified by `SplitSelectionUITests` on both shells: selecting a row fills the detail
column, and switching section resets it.

#### Phase 3b — native columns + tab roots (IN PROGRESS — 3 of 5 done)

Replace each hosted list column with a `UIViewController`, and delete
`selection: Binding<String?>?` from the six screens that carry it. **This is the large
half** — 3a was days, this is the "1–2 weeks" the estimate above refers to, and probably
more given what Phase 2's conversions actually cost.

**Do them one at a time, in this order.** Each is independently shippable because
`SplitShellVC.install(columns:into:arity:)` sets each column separately — a native
`AccountsListVC` can sit beside four still-hosted columns.

1. **Ledger** — DONE 2026-07-31. Smallest list, fewest interactions.

> ### Correction, 2026-07-31 — steps 2–5 are much bigger than this list implies
>
> Ledger converted cheaply for a reason that does **not** generalise: `LedgersVC`
> serves BOTH platforms. On iPhone the ledger flow *is* the list (presented from the
> corner control), so one view controller covers the phone flow and the iPad column.
>
> The other four are not like that. Even under `-uikitActivity YES` the iPhone tab
> ROOT is still hosted SwiftUI — `RootTabBarController.navigationTab` builds
> `UIHostingController(rootView: StacklessTabRoot(tab:))` and only the *pushed*
> destinations are native. So a native list column for Accounts would serve iPad
> alone while iPhone keeps rendering `AccountsTab`: **two implementations of one
> list, which will drift.** That is the "Mac divergence" risk below, reproduced
> between iPhone and iPad — a bad trade to take on for one platform.
>
> **Convert the tab root and the iPad column together, one tab at a time** — the
> shape Ledger demonstrated by accident. Each tab then has ONE list serving compact
> (as a tab root) and regular (as a supplementary column), and
> `selection: Binding<String?>?` can finally be deleted from that screen, which this
> step list assumed but could not have achieved.
>
> This pulls Phase 4's tab-root work into 3b rather than leaving it optional, and
> makes each remaining step far larger than "replace a column". Re-estimate before
> starting.
2. **Budgets** — DONE 2026-08-01 (#658). `BudgetsListVC`, root + column.
3. **Scheduled** — DONE 2026-08-01 (#660). `ScheduledListVC`, root + column. Attempted
   FIRST (it looks smallest at 329 lines) and appeared blocked on a scroll regression
   for four attempts; it turned out to be `TabChromeVC` swallowing every touch, not the
   screen. See *the tab-chrome prerequisite* below.
4. **Activity** — NEXT. `ActivityTab` is 665 lines. `ActivityFeedVC` already exists; this
   is mostly wiring it as a column rather than a pushed screen, plus the `focusedId`
   deep-link path.
5. **Accounts** — last, and by far the biggest. `AccountsTab` is 742 lines: collapsible
   groups, search, drag reorder, swipe actions on two edges, context menus. Budget it
   like `CategoriesVC`, not like `TagsVC`.

**The detail column is nearly free** for the rest: `BudgetDetailVC`, `TxListDetailVC`
and `AccountDetailVC` were built in Phase 2 and take an id in their initialiser, which
is exactly what a detail column needs.

**Patterns to copy rather than reinvent**, established by the three that are done:

- Two-mode list — `onSelect: ((String?) -> Void)?`. Nil → compact, the row pushes its
  detail; set → the row reports its id and stays selected, driving the split's detail
  column. Drop the disclosure chevron in selection mode; it promises a push.
- Wrap every native tab root in `TabChromeVC(content:tab:store:router:)`.
- Re-assert the selection highlight after `dataSource.apply` — it clears it.
- Set the grouped-section gap explicitly: `Metrics.sectionSpacing` via each section's
  `contentInsets`. A collection view does not inherit `.finchSectionSpacing()`, and
  UIKit's own insetGrouped gap is ~36pt against SwiftUI's 12.
  (`UICollectionViewCompositionalLayoutConfiguration.interSectionSpacing` does **not**
  move a list layout — tried; the screenshots were byte-identical.)
- Combine each hosted row into ONE VoiceOver element
  (`.accessibilityElement(children: .combine)` + `.accessibilityAddTraits(.isButton)`).
  The SwiftUI rows were `Button`s, which aggregate; hosting the same view bare exposes
  every text separately — several swipes per row instead of one.
- Diffable ids must be unique; derive them so repeats cannot collide. Scheduled
  occurrences use `__occ__<day>|<templateId>` because a template can recur twice in a
  month, and a duplicate identifier is a crash rather than a glitch.

**Selection plumbing.** `SplitSelection` stays — it is already a plain `ObservableObject`
that UIKit owns. A native list VC writes `selection.account = id` in
`didSelectItemAt` and observes `$account` to keep its highlight in sync; the detail
column reads it exactly as now. Nothing about the shell changes.

**Watch for:** the compact path uses the SAME views. Deleting the `selection` binding
from `AccountsTab` must not disturb its `selection == nil` branch, which is what iPhone
pushes. Until a screen's compact path is *also* native, the SwiftUI file has to keep
working — so delete the binding only when both sides are converted, or keep it and let
it go unused.

##### Before any of them: the tab-chrome prerequisite

Converting a tab ROOT to a native `UINavigationController` silently loses the
add-transaction FAB and the focused-tx sheet. Both come from `TabChrome`, a SwiftUI
`ViewModifier` that `TabRootHost` and `StacklessTabRoot` apply — so a root with no
SwiftUI view in it gets neither, and nothing fails loudly. This already happened once
in Phase 2, when `navigationTab` bypassed `TabRootHost` and every converted tab lost
its chrome at once; it was found by eye.

`TabChromeVC` is the fix (shipped #658). It puts the native content in a child and hosts
the real `AddTransactionFAB` + focused-tx sheet over it behind a passthrough view, so
touches reach the collection view everywhere except the button. The chrome is hosted
rather than rebuilt on purpose: the FAB honours `finch.fab.enabled`, the left/right
position preference, hides during multi-select and while the ledger cover is up, and
seeds from the page's `AddTxContext`. A UIKit copy of those rules would drift from the
one the Mac renders.

- Signature: `TabChromeVC(content:tab:store:router:)`. Wrap every native tab root.
- Trap: name the stored property `appTab`, not `tab` — `UIViewController.tab` is
  `UITab?` on iOS 18+ and the override does not compile.
- **Land it with its first consumer, not before.** Merged alone it is dead code — every
  tab root was SwiftUI — and its guard test (`TabChromeUITests`) would go green against
  a *hosted* root, proving nothing.

**Passing touches through is the whole difficulty, and it is not obvious.** The
passthrough originally asked "did a *descendant* claim this, rather than the hosting
view's own background?" — but `_UIHostingView.hitTest` returns **the hosting view
itself for any point inside its bounds**. Logging the hit chain gave the identical view
for a swipe on empty space and for a tap on the FAB, so identity can never discriminate,
and `.allowsHitTesting(false)` on the backdrop does not change it. Written that way the
chrome swallowed every touch and nothing underneath it could scroll, on any converted
tab. The button now publishes its own window rect (`FABFrameKey`) and the passthrough
tests geometry, which also keeps the position preference and hidden states honest
instead of hard-coding a corner.

> **This cost four attempts on the wrong screen, and the reason generalises.**
> The symptom first appeared on Scheduled's calendar mode, and was diagnosed as gesture
> coordination — `MonthCashCalendar` is a `.page TabView`, so surely a pan starting
> inside it belonged to that pager. A `.frame(height: 420)` was added to "leave a strip
> to drag from". All of it was wrong: the pager was never involved, and Scheduled later
> shipped with that frame removed, the grid self-sizing to 359.3pt against the SwiftUI
> control's 359.4.
>
> *Build the control and compare* had been applied to the SCREEN — SwiftUI Scheduled
> against native Scheduled — but never to the CONTAINER. The control proved "my change
> broke it", and the search then stayed inside the calendar code, which is the one place
> the bug was not. **Bisect the container as well as the content**: one build with
> `TabChromeVC` bypassed answers it in minutes. It was only found because the same
> chrome broke Budgets, where the symptom was a whole list refusing to move and no
> pager to blame.

##### Two rules this screen paid for

**"Is it a leaf?" is the wrong question — ask "does it contain a scroll view?"**
Hosting a leaf in a cell is safe; hosting anything containing a scroll view is not. It
collapses, and it re-introduces reproducer B, the iOS 26 resume shadow this migration
exists to remove. `ScheduledCalendarView` returns a `List` — its own comment says the
`topRow` parameter exists to keep that `List` the nav stack's primary scroll view.
`MonthCashCalendar` looks like a grid of numbers and is a `.page TabView`
(`MonthCashCalendar.swift:74`), i.e. a horizontal pager. Both read as leaves and
neither is.

`TxRowCell`'s doc comment already states the rule the strict way ("a leaf —
`HStack`/`VStack`, no scroll view"), so the wording is not the problem; applying it is.
**Two merged VCs host `MonthCashCalendar` today** — `AccountDetailVC:215` and
`ActivityFeedVC:194` — and both are therefore hosting a pager inside a scroll view.
`AccountDetailVC`'s calendar does scroll, verified on the simulator, but only because
the balance card and mode picker sit above the grid and rows below it, so a pan has
somewhere to land outside the pager. That is layout luck, not compliance.

**Still open on those two.** Scheduled shipped with no gesture handling at all — its
jam was the chrome, not the pager — so nothing was written that would also protect
`AccountDetailVC` and `ActivityFeedVC` if their grid ever fills the viewport. Neither
has been tested in that configuration.

**Build the control first — and bisect the CONTAINER, not just the content.** Every
screen being converted has a working original one commit away on `feat/frontend`. When
converted behaviour looks wrong, build plain `feat/frontend`, install it and compare,
before theorising. But note what the control can and cannot tell you: on Scheduled it
correctly proved "my change broke it" and was then read as "my change to *this screen*
broke it", which sent four attempts into the calendar code. A control build localises
the regression to your diff, not to the file you were editing.

### Phase 4 — Opportunistic (ongoing, optional)

Sheets and charts convert only when you want control over them. **None of them shadow**,
so there is no deadline. A reasonable end state keeps the 10 sheets and the chart
primitives in SwiftUI permanently — they are leaf views with no navigation, which is
where SwiftUI is strongest and least buggy.

(Tab roots were originally listed here as optional. Phase 3b's correction pulled them
in: a tab's root and its iPad column have to convert together or the two widths run
different implementations of one list.)

---

## Risks

**Mac divergence (structural, permanent).** Every screen converted on iOS leaves the
Mac on the SwiftUI implementation. Two versions of the same screen, forever, and
they will drift. This is the real long-term cost of the chosen scope, and it is paid
whether or not the migration finishes.

**Localization (systemic, easy to get wrong).** The i18n pipeline extracts from
SwiftUI `Text` and `String(localized:)`. UIKit strings are plain `String` by default
— `UILabel.text`, `UIBarButtonItem(title:)` — and bypass extraction **silently**,
rendering English in zh-Hans with no guard firing. There are 61 `String(localized:)`
sites today. Add a CI check for user-facing string literals in the UIKit target
before Phase 2, not after.

**A hybrid app is two mental models.** For months, some screens are SwiftUI and some
UIKit, with a bridging layer between. Navigation bugs will land in the seam.

**Stopping early is a legitimate outcome.** After Phase 2 the bug is gone and ~4,270
lines have moved. Phases 3–4 are optional. Decide again at that point rather than
committing now.

**This may all be obsolete.** The shadow is Apple's bug in a first-year API. If iOS
26.6 fixes it, Phase 2's entire justification evaporates and only the "control"
motivation remains. **Re-run the shadow lab on every iOS release during this work**
(`exp/ios26-shadow-lab`, check variant 0) and be willing to stop.

## Effort

| Phase | Estimate |
|---|---|
| 0 · source split | 2–4 days |
| 1 · UIKit shell | 1.5–3 weeks |
| 2 · pushed destinations | 3–4 weeks |
| 3 · iPad | 1–2 weeks |
| **to bug-free + iPad** | **~7–10 weeks** |
| 4 · opportunistic | ongoing, optional |

Kept as the forecast, not as remaining work — see *Where this stands* for how it
compares with the outcome.

**Both pre-flight gates passed** (2026-07-30) and are recorded here only so they are
not re-run. The pilot was `AccountDetailVC`, converted end-to-end behind the existing
shell at roughly 1:1 lines. It then had to prove two things: that a converted screen is
clean at realistic volume (2,000 rows — yes), and that conversion fixes a screen KNOWN
to shadow (`CategoriesView` → `CategoriesVC` — yes, clean). The second was the gate the
whole plan hung on: if it had come back dirty, the migration would have been abandoned
as a bug remedy.
