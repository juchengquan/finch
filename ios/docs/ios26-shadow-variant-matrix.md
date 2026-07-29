# iOS 26 resume shadow — the 21-variant navigation matrix

A systematic sweep of navigation structures against the iOS 26 Liquid Glass
**resume shadow**, run on the simulator (iOS 26.5, iPhone 17 Pro) with a
throwaway lab that put every variant in one build. Read this before proposing a
navigation change to the compact shell — it records what has already been ruled
out, and why.

Companion to `ios26-liquid-glass-artifacts.md`, which describes the artifact and
the shipped fix. **This document supersedes that one on three points** (see
"Corrections" at the end).

---

## Method

`ShadowLab.swift` on the throwaway branch `exp/ios26-shadow-lab`: one DEBUG
build, `-shadowLab YES`, a menu of navigation structures all showing the **same
real `ActivityFeedView`**. Procedure per variant: open, scroll down, Home, wait
~3s, resume, watch under the top bar.

Two rules made this sweep trustworthy where earlier ones were not:

1. **Known-bad and known-good controls in the same session** (variants 0 and 1).
   Every wrong conclusion in this bug's history came from judging a variant
   against memory rather than against a control.
2. **The real view, not a mock** — a synthetic list risks "my mock doesn't
   reproduce it".

**The artifact cannot be captured programmatically.** `simctl` screenshots and
`recordVideo` read the simulator's internal framebuffer, which does not contain
the glass compositor layers: after a resume, a pushed page and a root page are
*byte-identical*, and both show the same generic zoom profile (−6.7 vs −6.0 luma
in the strip under the bar). macOS `screencapture` is TCC-blocked under tmux.
Human eyes are the only instrument — plan for that.

---

## The matrix

| # | Structure | Shadow? |
|---|---|---|
| 0 | `TabView` › `NavigationStack` › **push** (pre-#636 shape) — *control* | **yes** |
| 1 | `RightSlideDrill` cover (shipped) — *control* | no |
| 2 | push + `.toolbar(.hidden, for: .tabBar)` | **yes** |
| 3 | `NavigationStack` **wrapping** the `TabView`, push on the outer stack | **yes** |
| 4 | root swap + `.move(edge: .trailing)` | no (opaque top bar — lab artifact, see 9) |
| 5 | push + `.scrollEdgeEffectHidden(true, for: .bottom)` | **yes** |
| 6 | push + `.backgroundExtensionEffect()` | no — but mirrors content into the bars; unusable |
| 7 | push + `.tabBarMinimizeBehavior(.onScrollDown)` | **yes** |
| 8 | cover › `NavigationStack` › **push** (no `TabView` inside) | no |
| 9 | root swap, `List` as the root, back control in the toolbar | no |
| 10 | `.fullScreenCover` + zoom transition | no (dismiss looks odd) |
| 11 | plain `.fullScreenCover` | no (returns from the bottom) |
| 12 | root swap + drag-to-go-back | no (drag reveals bare background — see 13) |
| 13 | SwiftUI slide-over, parallax + edge swipe | no (under-page text jitters) |
| 14 | slide-over, parallax snapped to the pixel grid | **no — clean and smooth** |
| 15 | slide-over, no parallax (static dim) | no |
| 16 | cover › **`TabView`** › `NavigationStack` › push | **yes** |
| 17 | slide-over sharing one nav bar | (bar came up empty — lab bug, see below) |
| 18 | native push, custom bottom bar, **no `TabView` anywhere** | **yes** |
| 19 | cover + drawn bottom bar + native push | no |
| 20 | real `UINavigationController`, `setViewControllers` (ROOT-replace) | **yes** |
| 21 | `.overFullScreen` cover, bottom strip transparent + hit-test passthrough | no — but rejected, see below |
| 22 | native `.fullScreenCover` straight to the page, no bar, deeper push inside | no |
| 23 | same, but right-slide (the shipped shape) | no |
| 24 | plain push of a **vanilla** 100-row `List` (no finch views) | **yes** |
| 25 | same vanilla list **+ `.searchable`** | **yes** |
| 26 | plain push of a **pure UIKit `UITableView`** | **yes** |
| — | Apple's **Files** and **Messages**, same sim, same OS, push + scroll + resume | **no** |
| A | **UIKit-rooted app**, push a `UITableViewController` | **no** |
| B | **UIKit-rooted app**, push a SwiftUI `List` in a `UIHostingController` | **yes** |
| C | **UIKit-rooted app**, same + `.searchable` | **yes** |

---

## What the matrix says

**A push shadows because of the push *transition*, not because of where it ends
up.** Variant 20 is decisive: it ends with a single-view-controller stack — a
genuine root — and still shadows, because `setViewControllers(animated: true)`
runs UIKit's push machinery. Every clean variant avoids that machinery entirely.

**Only two families are clean:**

- **Family A — modally presented AND no `TabView` inside the presentation**
  (1, 8, 10, 11, 19). Native pushes work *inside* it (8). A `TabView` behind the
  presentation is harmless; a `TabView` inside it is not (16).
- **Family B — never invokes a push transition** (4, 9, 12, 13, 14, 15). The
  destination is the stack's root, or an overlay. The real tab bar stays.

Everything else shadows: every push in the window hierarchy with or without a
`TabView` (0, 2, 3, 5, 7, 18), a push inside a cover that contains a `TabView`
(16), and a UIKit root-replace that animates as a push (20).

**The CONTENT is not the cause (24, 25).** A vanilla 100-row `List` with no finch
code in it shadows exactly like the real feed, with and without a search field.
finch also sets no scroll-edge or glass configuration anywhere — everything is on
Apple's defaults. So there is nothing to fix on our side of the page.

**Why don't Messages / WhatsApp / Files shadow?** Checked on the same simulator
and OS: they don't. The tempting explanation — that their pages are
`UITableView`/`UICollectionView` rather than SwiftUI `List`s — was tested as
variant 26 and is **WRONG**: a pure UIKit table pushed on our stack shadows too.

So the content technology does not matter, the navigation owner does not matter
(20 was a real `UINavigationController`), the `TabView` does not matter (18), and
our configuration does not matter (we set none). What distinguishes finch from
Files and Messages is that finch is a **SwiftUI app** — its window is rooted in
SwiftUI's hosting infrastructure — and theirs are not.

**Settled by the UIKit-root reproducer** (`repro-uikit-root/` on the lab branch —
a standalone UIKit app: `UIApplicationDelegate` → `UIWindow` →
`UITabBarController` → `UINavigationController`):

| App root | Pushed page | Result |
|---|---|---|
| UIKit | UIKit (A) | **clean** |
| UIKit | SwiftUI (B, C) | shadows |
| SwiftUI | UIKit (26) | shadows |
| SwiftUI | SwiftUI (0, 24, 25) | shadows |

**SwiftUI anywhere in the push path — the app's root OR the pushed page — is
sufficient to trigger it. Clean requires UIKit on both sides.** A is the only
clean push in 29 configurations, and it is exactly Files' shape.

Pushes inside a modally presented hierarchy with no `TabView` are also clean, and
navigation that never runs a push transition is clean.

**This settles the "convert to UIKit" question empirically: a UIKit SHELL is not
enough.** B *is* the shell-only configuration — UIKit app, UIKit navigation
controller, SwiftUI pages — and it shadows. Removing the artifact by conversion
would require UIKit on both sides, i.e. rewriting all 148 views (~20.5k lines),
while the Watch app and Widget must stay SwiftUI (no UIKit option exists on those
platforms) and the Mac app would need AppKit or its own SwiftUI copy. Months of
work and two or three UI codebases, against a ~100-line workaround that deletes in
one commit when Apple fixes this.

This is Apple's defect, not ours, and worth a Feedback Assistant report — this lab
is a good reproducer: one build, a known-bad control, a known-good control, and
one-variable isolations between them. Strategically it argues for the workaround
that is CHEAPEST TO DELETE, since a first-year-API bug is likely to be fixed.

**SwiftUI vs UIKit is not the axis for the NAVIGATION.** Variant 8 is a clean *SwiftUI* push; 16, 18
and 20 are shadowing pushes, one of them pure UIKit. This is the second time
UIKit has been tried and failed — `UIKitNavStack` on `feat/uikit-device-build`
was the first. Do not try a third.

**The consequence for design:** native nav-bar behaviour comes from the push
machinery, and the push machinery is what shadows. So on iOS 26.5 you cannot
have native push behaviour, a real `TabView`, and no shadow at once. Pick two.

---

## Options, with their bills

| Option | Native bar behaviour | Bottom bar | Cost |
|---|---|---|---|
| **Status quo** — `RightSlideDrill` (family A) | yes, inside the cover | hidden during a drill | ~100 lines of UIKit; the app-root-sheet-vs-cover bug class (PR #638) |
| **14** — SwiftUI slide-over (family B) | no — the bar slides with the page | real tab bar, in front | ~60 lines of SwiftUI; hand-rolled transition + back gesture |
| **19** — cover + drawn bar (family A) | yes | a replica | replica bar loses scroll-to-top on re-tap, minimise-on-scroll, keyboard avoidance, accessibility, and Apple's future restyling; plus hosting the app in a permanent cover |
| ~~**21**~~ — cover + real bar showing through | — | — | **REJECTED, see below** |

**Variant 21 is shadow-free but unusable, for a structural reason.** iOS 26's tab
bar glass samples what is BEHIND the bar. With the bar behind the cover, the only
thing it can sample is the stale tab page underneath — never the drill content in
front of it — so it renders flat and glassless, and no amount of tuning fixes
that. Confirmed on the sim, along with two further faults: the bar stops being
tappable once a page is pushed inside the cover, and it is absent from the
accessibility tree while the cover is up (VoiceOver cannot reach it).

**This reverses the ranking of the two "bottom bar + cover" options.** In variant
19 the drawn bar lives INSIDE the cover, so the drill content scrolls under it and
`.glassEffect()` samples the correct thing — a replica can look right where the
real bar cannot. A replica bar inside the presentation beats the real bar behind
it.

Notes on the rejected-looking ones: **4's opaque top bar and 12's bare-background
drag were lab bugs, not properties of the approach** — 4 wrapped the `List` in a
`VStack`, which cost it the scroll-edge effect, and a root swap has only one root
so nothing sits behind the detail. Variant 14 fixes both. **17's empty nav bar was
also a lab bug**: two layers declared toolbar content into the same bar at once.
Doing 17 properly requires the container to own the bar and every destination to
stop declaring its own — a real refactor across the drill pages.

**Whatever is chosen is a workaround for an Apple bug, so weigh deletability.**
`RightSlideDrill` is ~100 lines in one file. Family B is ~60 lines. A shell
restructure (18/19) is a project to unwind. Re-run this lab when iOS 26.6 / 27
lands: if Apple fixes the scroll-edge re-converge, the right move is to delete
the workaround and go back to plain `NavigationStack` pushes.

---

## Corrections to `ios26-liquid-glass-artifacts.md`

1. **"Device-only — invisible on the simulator to the eye" is wrong.** The
   shadow reproduces on the simulator and is clearly visible to a human;
   variant 0 was confirmed there. What is true is that it cannot be *captured*
   (see Method). This mattered: the old claim is why earlier rounds burned
   device cycles they did not need.
2. **The root cause line — "only pushes on the main tab-bar `NavigationStack`
   shadow" — is wrong in both directions.** Variant 3 shadows on a stack that is
   not the tab's, and variant 8 is a clean push. The accurate statement is the
   two-family rule above.
3. **"Root vs pushed" is the wrong framing.** Variant 20 is a root and shadows.
   The trigger is the push transition.

The "sharpened rule" — a push *inside* a cover is clean — **survives** and is
independently confirmed here (variant 8), so the shipped Ledger and Settings
flows are sound.
