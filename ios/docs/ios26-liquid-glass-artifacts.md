# iOS 26 Liquid Glass artifacts: tab-switch smear & resume shadow

Two separate visual glitches appeared when finch moved onto iOS 26's Liquid
Glass chrome. Both are **Apple's rendering**, not finch's data or layout —
each has a finch-side fix. This is the post-mortem: symptoms, what they
actually are, what we ruled out, what shipped, and what was tried and
abandoned along the way.

> **The single most important lesson: the Simulator is NOT a valid proxy
> for the Liquid Glass compositor.** It repeatedly reported a fix as
> "working" when the physical device still showed the artifact. Screenshots
> also miss the compositor's glass layers — you need device eyes or video.

---

## Issue 1 — the tab-switch "smear" / "block"

**Symptom.** Scroll a list tab (e.g. Activity) down, tap another tab. For
~130ms the outgoing page's rows smear over the incoming page's title area —
a flashing "block."

**Root cause.** iOS 26's `TabView` **cross-dissolves** tab content on
switch (iOS 18 swapped instantly). When the outgoing list is scrolled, its
dense rows dissolve over the incoming page's large-title whitespace — a
high-contrast overlap that reads as a smear. Scroll position only controls
how *ugly* the same dissolve looks.

**What didn't work.** SwiftUI's animation controls can't reach it:
`.transaction { $0.animation = nil }` and a `disablesAnimations` selection
binding both had **zero effect** — the dissolve lives in the backing
`UITabBarController`, below SwiftUI's animation system.

**Fix (shipped).** `Shell/AdaptiveShell.swift` → `DisableTabContentTransition`:
a tiny `UIViewControllerRepresentable` placed inside one tab that walks up
to the backing `UITabBarController` and installs a **forwarding
`UITabBarControllerDelegate`**. The delegate returns a **zero-duration
transition animator** via the *public* hook
`tabBarController(_:animationControllerForTransitionFrom:to:)`, making the
swap instant again. It forwards every other delegate call to SwiftUI's own
coordinator (so selection still works) and degrades to a no-op if the
controller can't be found. Public API only, no private symbols.

REMOVE if Apple makes the dissolve content-aware / offers an opt-out.

---

## Issue 2 — the resume "shadow"

**Symptom.** Leave finch and return; for ~2–3s a shadow lingers around the
top bar / search field on a scrolled transaction list. **Device-only** —
invisible on the simulator to the eye (though a sim video/energy-diff
shows a faint trace).

**Root cause.** iOS 26's *adaptive* Liquid Glass scroll-edge effect (`.soft`
/ `.automatic`) re-samples the content under the glass on resume and slowly
re-converges — that convergence *is* the shadow. **But it only happens on
PUSHED (non-root) scroll views.** A top-level tab's scroll view (Accounts,
Budgets) stays clean; a page you *navigate into* (the Activity feed, an
account's detail) shadows. Bisected on device: it is **not** the content,
rows, headers, search bar, large title, nav-bar background, or the data —
it is purely **navigation depth** (root vs pushed).

**Proven NOT a data refresh.** Instrumented on resume: **0**
`reprojectActiveLedger`, **0** Activity `recompute`, **0** view body
re-evaluations (`Self._printChanges`). finch runs no code at all on resume;
the effect is entirely Apple's.

---

## Fix (shipped) — RightSlideDrill

`Shell/RightSlideDrill.swift` (100 lines, iOS-only) plus call sites in
`Tabs/BudgetsTab.swift` and `Tabs/SettingsTab.swift`. Two free functions:

- `_rd_presentModal(_:)` — presents a SwiftUI view as a **full-screen
  modal with a right-slide animation** (push feel, not modal feel) from
  the key window's root view controller.
- `_rd_dismissModal()` — dismisses the currently presented cover.

A `UIViewControllerAnimatedTransitioning` does the slide-from-right
animation; a `UIViewControllerTransitioningDelegate` plugs it in.

The presented view is a **root** (not a pushed child), so iOS 26's Liquid
Glass doesn't re-converge its scroll-edge material on resume — no shadow,
while bars stay fully `.soft` and transparent.

The compact-mode call sites use it for drill-ins:

- `BudgetsTab`: tap a budget → `_rd_presentModal(BudgetDetailView(budgetId:))`
  with a custom `‹ Budgets` back button in the toolbar.
- `SettingsTab`: `SettingsRootList.onDrill` closure → `_rd_presentModal`
  for each of the 10 drill-in pages (Categories, Tags, Merchants, etc.).

The three app-wide `@EnvironmentObject`s (`FinchStore`, `DeepLinkRouter`,
`BiometricGate`) are re-injected on the hosted `UIHostingController`.
iPad/Mac (`selection != nil`) three-column paths are untouched.

---

## Approaches tried and rejected — all device-verified

| Approach | Result |
|---|---|
| `.scrollEdgeEffectStyle(.hard)` | Kills the shadow but bars become a fixed dim — **loses the transparent look**. Removed in PR #635 once a UIKit fix was thought to exist. |
| `.scrollEdgeEffectHidden()` | Sim-clean but **still shadowed on device**; also removes the edge dim. |
| SwiftUI style "reset" (pulse / snap / tick / fade / foreground-timing) | Any `.hard`↔`.soft` toggle is a visible **blink** (a re-render), never reliably clean on device. |
| UIKit effect reset (`topEdgeEffect.isHidden`/`.style` poke) | Synchronous poke doesn't re-seed the effect → shadow remains; a rendered `.hard` frame re-seeds it but *is* the blink. |
| Structural: selection binding, `.searchable` presence/placement, title mode, nav-bar background, `Group` wrapper | None fixed it on device (the sim's bisection misled repeatedly). |
| Wrap the pushed page in its **own** `NavigationStack` (nested) | **Intermittent** — a nested stack isn't reliably treated as top-level. |
| **`UIKitNavStack`** — `UINavigationController`-wrapped SwiftUI views, env re-injection, `UIKitNavLink` for declarative pushes | **Tried. Did not fix the shadow on device.** Replaced by `.fullScreenCover` drill (PR #628), then by RightSlideDrill. The earlier post-mortem on `feat/uikit-device-build` claimed this was the fix; the on-device test refuted that claim. |
| `.fullScreenCover` drill | Reliably kills the shadow (the presented view is a root), but the slide-up modal feel was jarring vs. the native slide-from-right push. Replaced by RightSlideDrill. |
| **RightSlideDrill** — full-screen modal with right-slide animation via `UIViewControllerAnimatedTransitioning` | Reliably kills the shadow, preserves slide-from-right push feel, keeps `.soft` transparency. **This is the fix.** |

---

## Also universal, not fixable, not ours

The nav-bar title briefly renders gray→black on resume (visible once the
shadow is gone). That's iOS activating the nav bar from its background
snapshot during the scale-up — it happens on *every* app's resume, not just
finch.

---

## Verification requirement

Every glass fix must be verified on a physical device. The simulator is
not a faithful proxy: it reports fixes as working when the device still
shows the artifact, and screenshots miss the compositor's glass layers.
This applies symmetrically to Issues 1 and 2.