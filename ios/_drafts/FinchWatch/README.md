# FinchWatch (draft — not wired as a build target)

The Apple Watch glance for Phase 7: reads the `WidgetSnapshot` the phone writes to
the App Group and shows net worth + budget usage + this week's spend.

**Why it's a draft, not a built target:** the **watchOS platform runtime is not
installed** in the build environment used here (only the SDK headers), so the
target can't be compiled/verified — unlike the iOS extensions and the macOS app,
which all build. To avoid committing an unverified target, the sources live here
and the project.yml wiring is omitted.

To enable it (with watchOS installed): move this folder back to `ios/FinchWatch/`,
add `watchOS: "26.0"` to `options.deploymentTarget`, add a `FinchWatch` target
(type: application, platform: watchOS, entitlements: FinchWatch.entitlements,
CODE_SIGNING_ALLOWED: NO) + scheme, then `xcodegen generate`.
