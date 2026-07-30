# UIKit migration — human verification checklist

Things that **cannot be verified programmatically** and are waiting on eyes. Tick as
you go; add findings inline under the item.

**Why this file exists.** `idb ui describe-all` does not expose toolbar items,
nav-bar buttons, search fields, or segmented controls in the accessibility tree, and
`simctl` screenshots do not contain the Liquid Glass compositor layers. So a whole
class of change builds green, passes 676 tests, and is still unverified. Twice
during this work an automated "check" was actually a missed tap read as a bug.

Launch the app in each mode with:

```bash
UDID=$(xcrun simctl list devices | grep "<your-sim> (" | grep -oE '[0-9A-F-]{36}')
xcrun simctl launch "$UDID" com.juchengquan.finch                      # default shell
xcrun simctl launch "$UDID" com.juchengquan.finch -uikitActivity YES    # + converted feed
xcrun simctl launch "$UDID" com.juchengquan.finch -legacyShell YES      # pre-migration shell
```

---

## 1. Phase 1 — the UIKit shell (SHIPPED DEFAULT, not gated)

These were restored after a parity audit found the shell had dropped them. The first
two are functional, not cosmetic.

- [ ] **Idle lock actually fires.** Settings → Security → lock policy `onIdle`, then
      leave the app untouched past the timeout. It must lock. *(The 30s timer plus
      the touch observer are what make this policy work at all; without them a user
      with this setting is simply never locked.)*
- [ ] **Touch observer does not swallow input.** Tap rows, swipe rows, drag lists —
      everything still responds. *(The observer is a window-level recogniser; if it
      consumed touches, taps on list rows would die — that exact bug is why the
      SwiftUI version used a platform observer instead of a gesture.)*
- [ ] **Toasts appear.** Do something that toasts (e.g. confirm a transaction) and
      check the message shows above the shell, on any tab.
- [ ] **Import/loading HUD appears.** Import a `.finch` pack; the progress overlay
      shows and clears.
- [ ] **Appearance switching is live.** Settings → Appearance → Light/Dark/System
      changes immediately, without relaunch. Also check the **lock screen** follows it.
- [ ] **Text size applies.** Settings → text size steps change type across tabs,
      including on the converted feed.
- [ ] **Lock is above everything.** Open a sheet (Add transaction), then trigger the
      lock. The lock must cover the sheet completely. *(Security: as a child
      controller it would sit below presented sheets and leak account data.)*
- [ ] **Tab switching has no cross-dissolve flash** on a scrolled list.
- [ ] **Deep links / Spotlight / Siri** still land: `xcrun simctl openurl "$UDID"
      "finch://add"`, a Spotlight result, and an App Intent.
- [ ] **Ledger cover** opens from the top-left corner control on every content tab.
- [ ] **FAB** present on Accounts/Budgets/Scheduled/Insights, absent on Settings.

## 2. Phase 2 — the converted Activity feed (`-uikitActivity YES`)

Accounts → All Transactions.

- [ ] **Select** enters selection mode: rows show ticks, bottom bar shows live
      counts, Done exits.
- [ ] **Bulk confirm / recategorize / delete** each act on exactly the ticked rows.
- [ ] **Confirm all N pending** clears the pending bucket.
- [ ] **Filter** button opens the sheet; the filter applies on dismiss.
- [ ] **⋯ menu**: sort options change order; group-by-month toggles month sections
      off/on.
- [ ] **Load more** appears past 50 rows and adds 50 at a time.
- [ ] **Calendar mode**: the grid appears; tapping a day filters the rows beneath;
      the month total matches the grid's sums.
- [ ] **Saved searches**: ＋ Save names a search → appears as a chip → tapping
      re-applies its filter → long-press deletes it.
- [ ] **Swipe to delete** a row; **tap** a row opens the edit sheet.
- [ ] **No resume shadow**: scroll, background, wait ~3s, reopen. *(The point of the
      whole exercise. Compare against the same screen with the flag off, which
      should still shadow.)*

## 3. Accessibility — a concern raised by the tooling, not yet investigated

- [ ] The mode picker and saved-search chips are **not visible to `idb`'s
      accessibility tree**. If an automation tool cannot see them, VoiceOver may
      struggle too. Check both with the Accessibility Inspector and VoiceOver on.
- [ ] The converted feed's rows announce sensibly (category, date, amount) and the
      selection ticks announce their state.

## 4. Before the flag comes off

- [ ] Everything in §2 passes.
- [ ] `ActivityFeedView`'s `.rightSlideDrill(...)` entry replaced by the native push,
      and the SwiftUI screen dropped from the iOS target (`excludes:` in
      `project.yml`) while `FinchMac` keeps it.
- [ ] Re-run §1 afterwards — the tab gains a `UINavigationController`, which changes
      the shell's structure.

## 5. Open questions

- [x] **iPad keeps its split view.** Phase 1 originally built the tab bar
      unconditionally, so a wide window lost the three-column layout — a real
      regression, since iPad runs the same iOS app. Fixed: wide windows keep
      hosting the SwiftUI split shell, and the root swaps when the size class
      changes (iPad multitasking). Verified on an iPad Pro 11" sim: list column +
      detail placeholder, sidebar toggle, no tab bar.
- [ ] iPad, deeper: exercise selection into the detail column, and Split
      View/Slide Over resizing across the compact↔regular boundary (the root
      rebuilds; check nothing is lost).
- [ ] The `-legacyShell YES` escape hatch still works, so there is a way back if the
      UIKit shell misbehaves in the field.
