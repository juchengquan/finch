# iOS 26 Liquid Glass artifacts: the tab-switch smear & the resume shadow

Two separate visual glitches appeared when finch moved onto iOS 26's Liquid Glass
chrome. Both are **Apple's rendering**, not finch's data or layout — but each has a
finch-side fix. This is the post-mortem: symptoms, what they actually are, everything
we ruled out, and what shipped.

> **The single most important lesson: the Simulator is NOT a valid proxy for the
> Liquid Glass compositor.** It repeatedly reported a fix as "working" when the
> physical device still showed the artifact. **Every glass fix must be verified on a
> real device.** Screenshots also miss the compositor's glass layers — you need
> device eyes or video.

---

## Issue 1 — the tab-switch "smear" / "block"

**Symptom.** Scroll a list tab (e.g. Activity) down, tap another tab. For ~130ms the
outgoing page's rows smear over the incoming page's title area — a flashing "block".

**Root cause.** iOS 26's `TabView` **cross-dissolves** tab content on switch (iOS 18
swapped instantly). When the outgoing list is scrolled, its dense rows dissolve over
the incoming page's large-title whitespace — a high-contrast overlap that reads as a
smear. Scroll position only controls how *ugly* the same dissolve looks.

**What didn't work.** SwiftUI's animation controls can't reach it: `.transaction { $0.animation = nil }`
and a `disablesAnimations` selection binding both had **zero effect** — the dissolve
lives in the backing `UITabBarController`, below SwiftUI's animation system.

**Fix (shipped).** `Shell/AdaptiveShell.swift` → `DisableTabContentTransition`: a tiny
`UIViewControllerRepresentable` placed inside one tab that walks up to the backing
`UIKitTabBarController` and installs a **forwarding `UITabBarControllerDelegate`**. The
delegate returns a **zero-duration transition animator** via the *public* hook
`tabBarController(_:animationControllerForTransitionFrom:to:)`, making the swap instant
again. It forwards every other delegate call to SwiftUI's own coordinator (so selection
still works) and degrades to a no-op if the controller can't be found. Public API only,
no private symbols.

---

## Issue 2 — the resume "shadow"

**Symptom.** Leave finch and return; for ~2–3s a shadow lingers around the top
bar / search field on a scrolled transaction list. **Device-only** — invisible on the
simulator to the eye (though a sim video/energy-diff shows a faint trace).

**Root cause.** iOS 26's *adaptive* Liquid Glass scroll-edge effect (`.soft` /
`.automatic`) re-samples the content under the glass on resume and slowly re-converges —
that convergence *is* the shadow. **But it only happens on PUSHED (non-root) scroll
views.** A top-level tab's scroll view (Accounts, Budgets) stays clean; a page you
*navigate into* (the Activity feed, an account's detail) shadows. Bisected on device:
it is **not** the content, rows, headers, search bar, large title, nav-bar background,
or the data — it is purely **navigation depth** (root vs pushed).

**Proven NOT a data refresh.** Instrumented on resume: **0** `reprojectActiveLedger`,
**0** Activity `recompute`, **0** view body re-evaluations (`Self._printChanges`). finch
runs no code at all on resume; the effect is entirely Apple's.

**Fix (shipped).** `Tabs/AccountsTab.swift` → present the compact drill-in pages
(`ActivityFeedView`, `AccountDetailView`) as a **top-level `.fullScreenCover`** (`DrillTarget`)
instead of a `NavigationStack` push. A top-level cover is a *root* scroll view, so the
adaptive effect never re-converges — the shadow never forms **while the bars stay fully
transparent `.soft`**. Each cover gets its own `NavigationStack` (so the detail pages'
sheets / inner drill-ins still work) and a "‹" chevron that dismisses. **Compact
(iPhone) only** — iPad's split-view selection path is untouched.

---

## Alternatives considered (all rejected, most on-device)

| Approach | Result |
|---|---|
| `.scrollEdgeEffectStyle(.hard)` | Kills the shadow, but bars become a fixed dim — **loses the transparent look**. (Shipped earlier as a fallback in PR #626.) |
| `.scrollEdgeEffectHidden()` | Sim-clean but **still shadowed on device**; also removes the edge dim (content bleeds into the bars on the sim). |
| SwiftUI style "reset" (pulse / snap / tick / fade / foreground-timing) | Any `.hard`↔`.soft` toggle is a visible **blink** (a re-render), never reliably clean on device. |
| UIKit effect reset (`topEdgeEffect.isHidden`/`.style` poke) | Synchronous poke doesn't re-seed the effect → shadow remains; a rendered `.hard` frame re-seeds it but *is* the blink. |
| Structural: selection binding, `.searchable` presence/placement, title mode, nav-bar background, `Group` wrapper | None fixed it on device (the sim's bisection misled repeatedly). |
| Wrap the pushed page in its **own** `NavigationStack` (nested) | **Intermittent** — a nested stack isn't reliably treated as top-level. |
| Present as a **modal** (top-level cover) | Reliably kills the shadow → **this is the fix.** The slide-up/"Done" feel is softened with a "‹" chevron. |
| Slide-*from-right* overlay (push-like feel) | Only reliable at the true window level; a nested overlay shadowed intermittently. Up-slide cover is the dependable top-level presentation. |

**Also universal, not fixable, not ours:** the nav-bar title briefly renders gray→black
on resume (visible once the shadow is gone). That's iOS activating the nav bar from its
background snapshot during the scale-up — it happens on *every* app's resume.

---

## Takeaways for future glass work

1. **Verify on a physical device.** The simulator's glass is a crude approximation and
   gave false positives for ~8 different shadow "fixes."
2. Screenshots miss compositor glass layers; use device eyes or `recordVideo`.
3. Root-vs-pushed matters for the scroll-edge effect on resume. If a new full-screen
   scrolled page shadows on resume, presenting it top-level (cover) fixes it while
   keeping `.soft`.
4. Remove these workarounds if Apple makes the adaptive path / tab dissolve behave —
   retest each iOS point release.
