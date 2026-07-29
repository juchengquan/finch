# Migrating finch's iOS UI to UIKit — plan

**Status:** proposal · **Date:** 2026-07-29 · **Decided parameters:** iPhone + iPad
move to UIKit; `FinchMac` stays SwiftUI; Watch and Widget stay SwiftUI (no UIKit
exists on those platforms); incremental strangler migration, shipping continuously.

**Why:** ownership of the UI layer. **NOT the resume shadow** — see the revision
note. Read `ios26-shadow-variant-matrix.md` first, including its 2026-07-30
addendum.

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
