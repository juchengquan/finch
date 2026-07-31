# Migrating finch's iOS UI to UIKit — plan

**Status:** Phases 0–2 IMPLEMENTED (2026-07-31) · **Date:** 2026-07-29 · **Decided
parameters:** iPhone + iPad move to UIKit; `FinchMac` stays SwiftUI; Watch and Widget
stay SwiftUI (no UIKit exists on those platforms); incremental strangler migration,
shipping continuously.

> ## Where this stands — 2026-07-31
>
> | Phase | State |
> |---|---|
> | **0 — source split** | **Done.** `.swift` counts: `FinchShared` 56 · `FinchAppSwiftUI` 91 · `FinchAppUIKit` 23 (iOS-only). |
> | **1 — UIKit shell** | **Done, shipping by default on iPhone.** `project.yml` excludes `FinchApp.swift` from the iOS target; the phone boots `@main UIKitAppDelegate`. Not gated. |
> | **2 — pushed destinations** | **Done, gated behind `-uikitActivity YES`.** 21 screens across 18 `*VC.swift` files. |
> | **3 — iPad** | **Not started.** iPad still runs the SwiftUI shell — see below. |
> | **4 — opportunistic** | Not started; optional by design. |
>
> The estimates below are the pre-implementation forecast, kept as written so the
> forecast can be judged against the outcome. Do not read them as remaining work.
>
> **The Phase 3 seam is live in the code today.** `UIKitShell.makeRoot` returns the
> hosted SwiftUI `AppRootHost` whenever horizontal size class is `.regular`, so iPhone
> and iPad run *different shells*. Anything verified on the phone needs re-checking on
> iPad until Phase 3 lands.

**Why:** ownership of the UI layer. **NOT the resume shadow** — see the revision
note. Read `ios26-shadow-variant-matrix.md` first, including its 2026-07-30
addendum.

> ## VALIDATED 2026-07-30 — conversion fixes the failing case
>
> `CategoriesView` is the one real finch screen that shadows under a UIKit root.
> Converted to UIKit (`CategoriesVC` in the pilot), same data, same root: **clean**.
> That is the treatment fixing the failing case, which is far stronger than the
> earlier tests that took already-clean screens and showed they stayed clean.
>
> With reproducer A, UIKit-page-under-UIKit-root is now clean everywhere it has
> been tried. **The plan is validated end to end; what remains is a cost decision.**
>
> **Two real conversions, for the estimate:**
>
> | screen | SwiftUI | UIKit | reused unchanged |
> |---|---:|---:|---|
> | `AccountDetailView` | 320 | ~250 | store, selectors, write chokepoint |
> | `CategoriesView` | 574 | ~160 | same |
>
> **Read those with the caveat that both conversions covered SCROLL CONTENT only.**
> Omitted: the calendar mode and holdings section (Account detail); reorder/drag,
> merge/multi-select, import and copy-to-ledger (Categories). Those are real work —
> drag-and-drop reordering in a collection view is fiddly — and would plausibly add
> 30–50% on top. Treat Phase 2's 3–4 weeks as the optimistic end.
>
> ## REVISED AGAIN 2026-07-30 — FULL migration is the only thing that works
>
> The coverage tests settled the shape of this. Under a UIKit root, hosted SwiftUI
> screens are **unpredictable**: `AccountDetailView` and `ActivityFeedView` are
> clean at every volume; `CategoriesView` shadows — and still shadows after adding
> the pinned search drawer that is the only structural property separating it from
> the clean ones. Five explanations have now been tested to destruction (`TabView`,
> SwiftUI-content, volume, sections, pinned search drawer).
>
> So **hosting is a transition state, not an end state**, and the only configuration
> verified clean everywhere is **UIKit root + UIKit page**. That makes the full
> migration of pushed screens the one approach that actually fixes the bug — which
> is what this plan now describes.
>
> **Sequencing consequence:** `RightSlideDrill` STAYS during the migration. Each
> unconverted pushed screen keeps its cover; the cover is removed per route as that
> screen converts. The app is never mid-flight broken and the bug never regresses.
>
> The earlier revision below is kept for history.
>
> ## Superseded revision — 2026-07-30 (earlier)
>
> Two findings from testing at realistic volume (2,000 transactions) removed the
> urgency this plan was written under:
>
> 1. **The shipped `RightSlideDrill` fix is sound at scale.** There is nothing
>    broken to escape. Users with real ledgers are fine today.
> 2. **A UIKit shell does not fix the bug.** Coverage testing across the app's
>    real drill destinations found `CategoriesView` SHADOWS under a UIKit root,
>    while `AccountDetailView` and `ActivityFeedView` do not. So Phase 1 would
>    leave an unknown subset of screens still shadowing and require per-screen
>    conversion anyway — with no way to predict which screens need it except by
>    testing each one, and no basis at all for screens written later.
>
> So this migration should be judged **purely as a control/ownership decision**,
> on its own merits and timetable. If that is not compelling by itself, do not do
> it. The phases below stand; only the justification changed.

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

#### Phase 3b — native columns (IN PROGRESS — Ledger done, Scheduled blocked)

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
2. **Budgets** — next. `BudgetsTab` is 607 lines; `BudgetDetailVC` already exists for
   the detail side.
3. **Activity** — `ActivityTab` is 665 lines. `ActivityFeedVC` already exists; this is
   mostly wiring it as a column rather than a pushed screen, plus the `focusedId`
   deep-link path.
4. **Accounts** — last, and by far the biggest. `AccountsTab` is 742 lines: collapsible
   groups, search, drag reorder, swipe actions on two edges, context menus. Budget it
   like `CategoriesVC`, not like `TagsVC`.
5. **Scheduled** — attempted first (it looks smallest at 329 lines) and was blocked on
   a scroll regression that turned out to be `TabChromeVC`, not the screen; see below.

**The detail column is nearly free** for 2, 3 and 4: `BudgetDetailVC`,
`TxListDetailVC` and `AccountDetailVC` were built in Phase 2 and take an id in their
initialiser, which is exactly what a detail column needs.

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

`TabChromeVC` is the fix — written and building, but **not on this branch**. It puts
the native content in a child and hosts the real `AddTransactionFAB` + focused-tx
sheet over it behind a passthrough view, so touches reach the collection view
everywhere except the button. The chrome is hosted rather than rebuilt on purpose: the
FAB honours `finch.fab.enabled`, the left/right position preference, hides during
multi-select and while the ledger cover is up, and seeds from the page's
`AddTxContext`. A UIKit copy of those rules would drift from the one the Mac renders.

- Signature: `TabChromeVC(content:tab:store:router:)`. Wrap every native tab root.
- Trap: name the stored property `appTab`, not `tab` — `UIViewController.tab` is
  `UITab?` on iOS 18+ and the override does not compile.
- **Land it with its first consumer, not before.** Today every tab root on this branch
  is SwiftUI, so `TabChromeVC` has nothing to wrap: merged alone it is dead code, and
  its guard test (`TabChromeUITests`) would go green against a *hosted* root, proving
  nothing. It belongs in the same PR as the first fully native root.
  **Vindicated the first time it was tried:** wrapped around a real native list it
  swallowed every touch and the tab would not scroll at all (see the Scheduled block).
  Merged on its own it would have shipped broken, under a green test.

##### RESOLVED 2026-08-01 — it was `TabChromeVC`, not the pager

The diagnosis below is **wrong**. It is kept because the way it went wrong is the
lesson.

**`TabChromeVC` swallowed every touch on the tab.** Its passthrough asked "did a
*descendant* claim this, rather than the hosting view's own background?" — but
`_UIHostingView.hitTest` returns the hosting view ITSELF for any point inside its
bounds. Logging the hit chain gave the identical view for a swipe on empty space and
for a tap on the FAB, so identity could never discriminate, and `.allowsHitTesting(false)`
on the backdrop does not change it either. Nothing underneath the chrome could scroll,
on any converted tab.

It surfaced on Budgets, where the symptom was the whole list refusing to move rather
than "the calendar is stuck". Fixing it there fixed Scheduled with no change to
`ScheduledListVC` at all. The button now publishes its own rect (`FABFrameKey`) and the
passthrough tests geometry.

Why it read as a calendar-only, pager-shaped bug: every observation on this screen was
made *through* that broken chrome, and calendar mode was simply the branch being looked
at. `MonthCashCalendar`'s `.page TabView` was never involved. The `.frame(height: 420)`
added to "leave a strip to drag from" was compensating for the wrong cause and is gone —
unbounded, the grid self-sizes to 359.3pt against the SwiftUI control's 359.4, and both
gestures work: a vertical pan scrolls the page, a horizontal one pages the month.

**The rule this cost.** *Build the control and compare* was applied to the screen —
SwiftUI Scheduled against native Scheduled — but never to the CONTAINER. The control
proved "my change broke it", and the search then stayed inside the calendar code, which
is the one place the bug was not. Bisect the container as well as the content: bypassing
`TabChromeVC` for a single build answers it in minutes, and would have four attempts
earlier.

The "does it contain a scroll view?" rule still stands on its own merits — a hosted
`List` really would collapse, and `ScheduledCalendarView` really does return one. It
just was not what jammed this page.

##### The Scheduled block — the original diagnosis, kept as a record of how it misled

The code (`ScheduledListVC`, `TabChromeVC`, `TabChromeUITests`) lives on
`feat/ios-uikit-scheduled`, from the **closed** PR #652. List mode, the iPad column and
the tab-chrome work are all sound; only calendar mode is broken.

**Symptom.** In calendar mode a drag on the month grid does not scroll the page, so the
day sections below are unreachable.

**It is a regression, not a shipped bug.** A control build of plain `feat/frontend` on
an erased simulator scrolls fine. The same `MonthCashCalendar` inside a SwiftUI `List`
behaves; inside `UICollectionView` + `UIHostingConfiguration` it does not. So it is
gesture coordination, not layout — `List` coordinates the vertical pan and the
collection view does not.

**Ruled out:** stale build products, a corrupt simulator, content-size problems.

**Attempted and failed — do not repeat:** walking the cell for `UIScrollView`s whose
content fits their bounds and clearing `alwaysBounceVertical` / `bounces`, deferred a
runloop so SwiftUI has built the hierarchy. Compiles, changes nothing. Also superseded:
bounding the hosted grid with `.frame(height: 420)`, which only shrank the dead zone.

**Required next step: inspect before changing.** `recursiveDescription` on the cell, or
a breakpoint, to find which view actually owns the pan. Four attempts on this screen
failed because they reasoned about UIKit instead of looking at it.

Also settled while working on it: occurrence ids must be `__occ__<day>|<templateId>` —
the day belongs in the id because a template recurring twice in a month otherwise
produces a duplicate diffable identifier, which crashes rather than glitches.

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
somewhere to land outside the pager. That is layout luck, not compliance. Re-check both
when the gesture fix for Scheduled lands, and apply it to all three.

**Build the control first.** Every screen being converted has a working original one
commit away on `feat/frontend`. When converted behaviour looks wrong, build plain
`feat/frontend`, install it and compare, before theorising. One control build answered
in minutes what three rounds of reasoning about pagers and content sizes got wrong.

### Phase 4 — Opportunistic (ongoing, optional)

Tab roots, sheets and charts convert only when you want control over them. **None of
them shadow**, so there is no deadline. A reasonable end state keeps the 10 sheets
and the chart primitives in SwiftUI permanently — they are leaf views with no
navigation, which is where SwiftUI is strongest and least buggy.

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

## Pre-flight: two checks before committing weeks

The pilot already answers "can a screen be converted" — `AccountDetailVC` exists,
builds, reuses the store, selectors and write chokepoint unchanged, and came in at
roughly 1:1 lines against the SwiftUI original. Two things it has NOT yet proven,
and both are cheap:

1. **The converted screen is clean at realistic volume.** Verify `AccountDetailVC`
   at 2,000 rows specifically (the pilot is already seeded).
2. **Conversion fixes a screen that is KNOWN to shadow.** Convert `CategoriesView`
   — the one real screen that shadows under a UIKit root, with or without a search
   drawer — and confirm it goes clean. This is the strongest available evidence for
   the whole plan: take the failing case and show the treatment fixes it.

If (2) comes back clean, the plan is validated end to end. If it does not, the
migration does not fix the bug and should be abandoned as a bug remedy entirely.

## Earlier recommendation: a pilot, not Phase 0

Convert **one** drill end-to-end — `AccountDetailView` — behind the existing shell,
hosted the way Phase 1 would host it. It is 320 lines, it has a search field, swipe
actions, a toolbar, a context menu and sheets, so it exercises nearly every
conversion pattern in the codebase.

The pilot answers three questions cheaply: does a converted page actually stop
shadowing in *this* app (not just the reproducer); how long does a real screen take
against the estimate above; and how bad is the bridging seam in practice. If the
answers are good, start Phase 0. If not, nothing has been lost.
