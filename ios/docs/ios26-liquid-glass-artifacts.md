# iOS 26 Liquid Glass artifacts: tab-switch smear & resume shadow

Two separate visual glitches appeared when finch moved onto iOS 26's Liquid
Glass chrome. Both are **Apple's rendering**, not finch's data or layout —
each has a finch-side fix. This is the post-mortem: symptoms, what they
actually are, what we ruled out, what shipped, and what was tried and
abandoned along the way.

> **The single most important lesson: you cannot CAPTURE the Liquid Glass
> compositor.** `simctl` screenshots and `recordVideo` read the simulator's
> internal framebuffer, which does not contain the glass layers — after a
> resume, a pushed page and a root page are byte-identical. macOS
> `screencapture` is TCC-blocked under tmux. Human eyes are the instrument.
>
> The corollary that cost the most: "cannot be captured" is not "does not happen
> here". The shadow reproduces on the simulator and is plainly visible to a person.
> See `ios26-shadow-variant-matrix.md` for the 21-variant evidence.

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
top bar / search field on a scrolled transaction list.

**It reproduces on the SIMULATOR** and is clearly visible to a human — what it
resists is *capture*. `simctl` screenshots and `recordVideo` read the framebuffer,
which does not contain the glass layers, so a shadowed page and a clean one come
out byte-identical. An earlier version of this file called it "device-only,
invisible on the simulator", and that mistake is why several rounds burned device
cycles they did not need.

**Root cause.** iOS 26's *adaptive* Liquid Glass scroll-edge effect (`.soft`
/ `.automatic`) re-samples the content under the glass on resume and slowly
re-converges — that convergence *is* the shadow. It is **not** the content, rows,
headers, search bar, large title, nav-bar background, or the data; that much was
bisected on device and holds.

**A push shadows because of the push TRANSITION, not because of where it ends up.**
This is the 21-variant sweep's verdict (`ios26-shadow-variant-matrix.md`) and it
replaces two earlier framings that were both wrong:

- ~~"only pushes on the main tab-bar `NavigationStack` shadow"~~ — wrong in both
  directions. A push on a stack that is *not* the tab's still shadows, and a push
  *can* be perfectly clean.
- ~~"root vs pushed"~~ — wrong framing. A UIKit root-replace via
  `setViewControllers(animated: true)` lands on a genuine root and still shadows,
  because it runs UIKit's push machinery.

**Only two configurations are clean:**

- **Family A — modally presented, with no `TabView` inside the presentation.**
  Native pushes work *inside* it. A `TabView` behind the presentation is harmless;
  one inside it is not.
- **Family B — never invokes a push transition at all.** The destination is the
  stack's root, or an overlay. The real tab bar stays.

The **sharpened rule survives**: a push *inside* a cover is clean (device-confirmed
2026-07-28, independently reconfirmed by the matrix). That is why a multi-level flow
is fixed by moving only its *entry* off the tab stack into a cover — the deeper
levels then push natively inside it, with no shadow and native swipe-back, which is
what the shipped Ledger and Settings flows rely on.

**Proven NOT a data refresh.** Instrumented on resume: **0**
`reprojectActiveLedger`, **0** Activity `recompute`, **0** view body
re-evaluations (`Self._printChanges`). finch runs no code at all on resume;
the effect is entirely Apple's.

---

## Fix (shipped) — RightSlideDrill (state-driven, device-verified)

`Shell/RightSlideDrill.swift` (iOS-only) presents a SwiftUI view as a **full-screen
`.overFullScreen` cover with a right-slide animation** (push feel, not modal feel)
from the top-most presented VC. The presented view is a **root**, so iOS 26's glass
doesn't re-converge on resume — no shadow, bars stay fully `.soft` transparent.

**State-driven API** (not imperative — that mattered): use the
`.rightSlideDrill(item:)` / `(isPresented:)` view modifiers, so `DeepLinkRouter` /
App Intents / notifications / Spotlight can open a drill, not just a `Button` tap.
A `RightSlideDelegate` provides the transition; each cover gets an **interactive
left-edge swipe-to-dismiss** — a `UIScreenEdgePanGestureRecognizer` installed by
`RSDHostingController` once SwiftUI's inner nav exists, `require(toFail:)` that nav's
pop gesture, so it fires only at the cover **root** and defers to the native pop
deeper in. `_rd_present` carries an `onDismiss` that resets the driving state (so a
completed swipe stays in sync); present/dismiss happen on the next runloop.

Call sites (compact iOS only; iPad/Mac `selection != nil` three-column untouched):
- **Accounts** — account detail / "All Transactions"→Activity / Holdings.
- **Budgets** — budget detail (also fixed a deep-link dead path).
- **Settings** — its 10 first-level drill pages.
- **Ledger** — presented once at `TabBarShell` via
  `.rightSlideDrill(isPresented: $router.showLedger)` hosting a `NavigationStack`;
  LedgerList → LedgerDetail → "View all activity" then push **natively inside the
  cover** (no shadow, native swipe-back). The old per-tab `LedgerPush`
  `navigationDestination` (a main-tab-stack push) is retired.

The three app-wide `@EnvironmentObject`s (`FinchStore`, `DeepLinkRouter`,
`BiometricGate`) are re-injected on each hosted `UIHostingController`.

> **It was latently broken until 2026-07-28** — never actually presented a cover:
> `RightSlideDrill.swift` wasn't in the Xcode project (a `project.yml` YAML error broke
> `xcodegen`, so everyone built a stale `.xcodeproj`); `SlideRightAnimator` required a
> `.from` view that is nil under `.overFullScreen`, aborting every present; `import
> UIKit` sat outside `#if os(iOS)`. The "This is the fix" claim below predated those
> fixes.

**Settings 2nd-level detail** (Categories→a category, etc.) is intentionally left on
native `NavigationStack` push — device-confirmed it does NOT shadow (a push inside a
cover is fine; see the sharpened rule above).

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
| `.toolbar(.hidden, for: .tabBar)` on the pushed page | Still shadows — it is not the tab bar's glass (2026-07-29) |
| `NavigationStack` **wrapping** the `TabView` | Still shadows (2026-07-29) |
| `.scrollEdgeEffectHidden(true, for: .bottom)` | Still shadows (2026-07-29) |
| `.tabBarMinimizeBehavior(.onScrollDown)` | Still shadows (2026-07-29) |
| `.backgroundExtensionEffect()` on the pushed page | Kills the shadow but MIRRORS content into the bars — unusable (2026-07-29) |
| Native push with a hand-drawn bottom bar, no `TabView` at all | Still shadows (2026-07-29) |
| `UINavigationController` + `setViewControllers` (root-replace, not push) | Still shadows — the push TRANSITION is the trigger (2026-07-29) |
| **RightSlideDrill** — `.overFullScreen` cover, right-slide animation, state-driven, interactive edge-swipe | **The fix — device-verified 2026-07-28 for one- AND multi-level** (Accounts/Budgets/Settings + the Ledger flow). Kills the shadow, keeps slide-from-right + swipe-back and `.soft` transparency. Needed the three latent-bug fixes noted above before it actually presented a cover. |

---

## Also universal, not fixable, not ours

The nav-bar title briefly renders gray→black on resume (visible once the
shadow is gone). That's iOS activating the nav bar from its background
snapshot during the scale-up — it happens on *every* app's resume, not just
finch.

---

## Verification requirement

Every glass fix must be verified **by eye** — on the simulator at minimum, and
on a device before shipping. What fails is *capture*, not the simulator:
screenshots and video miss the compositor's glass layers entirely, so an
automated check will report any fix as working. Never conclude from a
screenshot. Always judge a candidate against a known-bad and a known-good
control in the same session.

See `ios26-shadow-variant-matrix.md` for the 21 navigation structures already
tested, the two families that are clean, and the options with their costs.