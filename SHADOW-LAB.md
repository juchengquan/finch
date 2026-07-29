# Shadow lab — throwaway branch, do not merge

This branch exists to answer one question: **is the iOS 26 Liquid Glass resume
shadow still there?** Re-run it when a new iOS lands (26.6, 27, …). If Apple has
fixed it, `RightSlideDrill` can be deleted and drills go back to plain
`NavigationStack` pushes with full transparency.

Findings and the decision live on `feat/frontend`:
**`ios/docs/ios26-shadow-variant-matrix.md`** (37 variants, what is ruled out, and
why `RightSlideDrill` was kept). Read that first — it will stop you re-running dead
ends.

---

## Re-run it

```bash
# 1. get the branch
git worktree add /tmp/finch-lab exp/ios26-shadow-lab
cd /tmp/finch-lab/ios

# 2. generate the project (FinchApp.xcodeproj is git-ignored)
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate

# 3. build
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/finch-lab-dd CODE_SIGNING_ALLOWED=NO

# 4. install + launch on YOUR session's simulator (see the note below)
UDID=$(xcrun simctl list devices | grep "<your-sim-name> (" | grep -oE '[0-9A-F-]{36}')
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || xcrun simctl boot "$UDID"
xcrun simctl install "$UDID" /tmp/finch-lab-dd/Build/Products/Debug-iphonesimulator/FinchApp.app
xcrun simctl launch "$UDID" com.juchengquan.finch -shadowLab YES
```

`-shadowLab YES` **sticks**, so tapping the app icon afterwards still opens the lab
(launch arguments only apply to the launch that passes them — an easy way to think
you are testing the lab when you are actually running the real app).
`-shadowLab NO` turns it back off.

> **Simulator:** each session uses its own named simulator (`ios-finch`,
> `ios-finch2`, …). Use yours; other booted simulators belong to other sessions.

## Procedure per variant

Open it → **scroll the list down** → press Home → wait ~3s → reopen → watch the
area under the top bar for a dark band that fades over ~2–3s.

**Start with variants 0 and 1.** They are calibration, not candidates:

- **0** — plain push, the pre-#636 shape. On iOS 26.5 this **shadows**.
- **1** — `RightSlideDrill` cover, what ships. On iOS 26.5 this is **clean**.

If **0 is now clean on the new OS, Apple has fixed it** — that is the whole point of
re-running this. Next step then: delete
`FinchApp/Sources/FinchApp/Shell/RightSlideDrill.swift`, turn each
`.rightSlideDrill(...)` back into a plain `navigationDestination` push, and check the
Ledger and Settings flows.

If 0 still shadows, nothing has changed and there is nothing to do.

## You must judge by eye

**The artifact cannot be captured.** `xcrun simctl io … screenshot` and
`recordVideo` read a framebuffer that does not contain the glass compositor layers —
after a resume, a pushed page and a root page are byte-identical. macOS
`screencapture` is TCC-blocked under tmux. Watch the simulator window, or record the
device.

Corollary: never conclude anything here from a screenshot, and always judge a
candidate against 0 and 1 **in the same session**. Every wrong conclusion in this
bug's history came from comparing against memory instead of a control.

## Extra launch arguments

`-barStyle 30|31|32|33|34|35|36|37` boots straight into one bar-appearance variant.
Needed because a UIKit appearance proxy only affects bars created *after* it is set,
so picking styles from the menu inside one session contaminates the comparison.

## What else is on this branch

- **`ios/FinchApp/Sources/FinchApp/Shell/ShadowLab.swift`** — all 37 variants.
- **`ios/docs/repro-uikit-root/`** — a minimal standalone UIKit app (one source
  file) showing that a pushed SwiftUI page shadows while an equivalent pushed
  `UITableViewController` does not, plus **`FEEDBACK-REPORT.md`**, a drafted
  Feedback Assistant report. Attach a device screen recording before filing.

Nothing here is meant for `feat/frontend`. The lab replaces the app shell behind
`#if DEBUG`, and the reproducer is a separate throwaway Xcode project.
