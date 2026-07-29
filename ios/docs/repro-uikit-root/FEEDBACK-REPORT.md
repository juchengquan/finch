# Feedback Assistant report — draft

Paste into Feedback Assistant. Attach: the `repro-uikit-root` project (zip the
folder after running `xcodegen generate`, or attach the single `Sources/App.swift`
if a full project is not wanted), plus a **screen recording of the device**, since
the artifact does not appear in screenshots (see "Note on capture").

- **Area:** SwiftUI (secondary: UIKit)
- **Type:** Incorrect/Unexpected Behavior
- **Reproducibility:** Always
- **OS:** iOS 26.5 (23F77) — simulator and device

---

## Title

SwiftUI view pushed onto a UINavigationController shows a lingering scroll-edge glass shadow after app resume; an equivalent UIKit view controller does not

---

## Description

When a scrolled view is pushed onto a navigation stack and the app is backgrounded
and resumed, a dark band appears under the navigation bar and slowly fades over
roughly 2–3 seconds. It is the Liquid Glass scroll-edge effect re-converging.

The artifact appears whenever **SwiftUI is in the push path** — either the app is a
SwiftUI app, or the pushed page is a SwiftUI view hosted in a
`UIHostingController`. An equivalent page implemented as a `UITableViewController`,
pushed in the same UIKit app, does not show it. Apple's own apps (Files, Messages)
do not show it on the same OS build.

Root (non-pushed) scroll views never show it, and neither do scroll views inside a
modally presented hierarchy — only pushes.

## Steps to Reproduce

Using the attached `UIKitRootTest` project — a plain UIKit app:
`UIApplicationDelegate` → `UIWindow` → `UITabBarController` → `UINavigationController`.

1. Build and run on iOS 26.5.
2. Tap **A · Push a pure UIKit table** (a `UITableViewController` with 100 rows).
3. Scroll the list down so content sits under the navigation bar.
4. Press Home, wait ~3 seconds, reopen the app.
5. Watch the area directly under the navigation bar. **No shadow appears.**
6. Go back and tap **B · Push a SwiftUI List (hosted)** — the identical list built
   with SwiftUI `List`, wrapped in a `UIHostingController`, pushed onto the same
   navigation controller.
7. Repeat steps 3–5. **A dark band appears under the navigation bar on resume and
   fades over ~2–3 seconds.**

A and B differ only in whether the pushed page is UIKit or SwiftUI.

## Expected Result

The pushed SwiftUI page behaves like the pushed UIKit page: the scroll-edge effect
is already settled when the app returns to the foreground, with no transient band.

## Actual Result

The SwiftUI page shows a dark band under the navigation bar for ~2–3 seconds after
resume, while the UIKit page in the same app does not.

## Additional Notes

Ruled out by direct test, each holding everything else constant:

- **The tab bar.** Hiding it on the pushed page (`.toolbar(.hidden, for: .tabBar)`)
  does not help; removing the `TabView` entirely does not help.
- **Navigation depth.** Using `setViewControllers([page], animated: true)` — which
  animates like a push but ends with a single-view-controller stack — still shows
  it. The push *transition* appears to be what matters, not the resulting depth.
- **Page content.** A vanilla 100-row `List` behaves exactly like a complex
  production view; with and without `.searchable`.
- **Scroll-edge configuration.** The affected app sets none — everything is on
  system defaults. `.scrollEdgeEffectHidden(true, for: .bottom)` does not help.
  `.scrollEdgeEffectStyle(.hard)` avoids it but discards the transparent look.
  `.backgroundExtensionEffect()` avoids it but mirrors content into the bars.
- **Navigation owner.** A real `UINavigationController` (rather than SwiftUI's
  `NavigationStack`) does not help, as long as the page is SwiftUI.

Workarounds found, both with significant cost:

- Present the destination modally instead of pushing it (a full-screen cover with
  a custom right-slide transition, to preserve the push's look and feel).
- Never run a push transition — swap the stack's root, or overlay the destination.

### Note on capture

The artifact is **not present in captured images**: `xcrun simctl io … screenshot`
and `recordVideo` read a framebuffer that does not include the glass compositor
layers — a pushed page and a root page are byte-identical after resume. It is
plainly visible to a person watching the screen. Please evaluate by eye or with a
device screen recording rather than a simulator screenshot.
