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

## 2b. Phase 2 — the converted Account detail (`-uikitActivity YES`)

Accounts → any account row.

**Already verified on the simulator** (ios-finch5, seeded): the screen pushes
without crashing (the per-section header/footer layout is the part that would
throw), and the titleView, the List/Calendar picker, the pinned search bar and
the empty-state row all render. Everything below still needs eyes.

- [x] **Title area**: name over balance, and the reconcile seal beside the
      balance. Verified green on `Everyday` (fresh) and absent on `Brokerage`
      (never reconciled); **the orange overdue seal on `Savings` is still
      unchecked**.
- [ ] **⋯ menu**: Edit, Reconcile, Adjust balance… each open the right sheet.
- [ ] **Archive** leaves the page (the account stops resolving, so the VC pops).
- [ ] **Delete** raises the confirmation, and deleting an account that still has
      transactions is refused with the engine's message rather than silently
      doing nothing.
- [x] **Month headers** show `net · end-of-month balance` on the first line and
      `Income … · Spent …` beneath, and **stay correct after a write**. Verified
      by measurement: July read `$5,903.50 · $11,453.50` / `Spent $2,496.50`,
      and flipping one −$58.20 row to pending moved all three to `$5,961.70 ·
      $11,511.70` / `$2,438.30`, with no relaunch; flipping back restored them.
      June's end balance + July's net = July's end balance exactly.
      *This is where the staleness bug fixed in `f08e810` was found — headers
      are the one thing a diffable data source will not refresh for you, so
      re-check them after any change to how sections are built.*
- [ ] **Group-by-month off** (⋯ on the Activity feed sets the shared flag)
      collapses this screen to one "Transactions" section.
- [ ] **Calendar mode**: the grid appears, a tapped day filters the rows
      beneath, the footer reads "Money in · out of this account…", and the
      no-selection fallback shows the anchored month with net only — *no*
      running balance, since that fallback includes pending rows.
- [ ] **Row gestures** (shared with the feed now, so check them once on each):
      swipe right ⇒ Duplicate; swipe left ⇒ status toggle at the edge, Delete
      inboard raising a confirmation; long-press ⇒ Edit / Duplicate / Preview
      receipt (only when the row has an attachment) / status / Delete.
      *Partly verified already*: swipe-left renders green **Confirm** at the
      edge with red **Delete** inboard, and a full swipe performs the status
      toggle in both directions (the safe action, as intended). Duplicate,
      Delete-with-confirm and the long-press menu are still unchecked.
- [x] **Holdings section** — verified, after creating a position (see §2e: the
      demo seed contains no holdings, so this had never rendered once). Brokerage
      shows `Holdings` → `AAPL  $1,900.00`. **An AAPL position is left on the
      `ios-finch5` sim on purpose**; delete it and this item becomes untestable
      again.
- [ ] **No resume shadow** on this screen: scroll, background, wait ~3s, reopen.

## 2d. Phase 2 — the converted Budget detail (`-uikitActivity YES`)

Budgets → any budget row. `.budgets` is now a UIKit nav tab, so **re-check §1 on
this tab too** — its structure changed, not just its detail screen.

**Already verified on the simulator**: every section renders with correct figures
(progress `$167.80 of $600.00`, `$432.20 left`, the cycle range, the History
chart with its 600 reference line, `Last 4 cycles · budget $600.00`, This cycle's
rows); tapping a past bar opens that cycle (`2026-05-01 – 2026-05-31`), tapping
the same bar clears it, the current-cycle bar never selects, and switching bars
updates the summary. The Budgets root keeps its search field, title, toolbar and
add button, with no doubled nav bar.

- [ ] **⋯ → Edit** opens BudgetSheet; **⋯ → Delete** confirms, and deleting leaves
      the page.
- [ ] **`+`** opens the Add sheet pre-filled with this budget's category (and its
      account when the budget is account-filtered), and is **disabled when there
      are no accounts**.
- [ ] **Income budget** (`Vacation Fund`): the Income section shows Saved and,
      when set, Target date.
- [ ] **Pending next cycle** + **Clear pending amount** — needs a budget with a
      pending amount; none of the seeded budgets has one.
- [ ] **A multi-month cycle** (quarterly/yearly budget) month-sections both this
      cycle and a selected past cycle *at the same time*. This is the case whose
      identifiers had to be namespaced — if they ever collide the app crashes
      rather than misdraws, so it is worth exercising deliberately.
- [ ] Tapping a row opens the editor; the rows have **no swipe actions**, matching
      the SwiftUI screen.

## 2e. Phase 2 — the converted Holdings screen (`-uikitActivity YES`)

Accounts → ⋯ → Holdings. Note the entry is in the overflow menu, which `idb`
cannot see — reach it by tapping the ⋯ item and reading the menu from a
screenshot.

**The demo seed contains no holdings at all**, so nothing here (nor the account
detail's Holdings section) could be exercised until a position was created by
hand. One is now on the `ios-finch5` sim: AAPL in Brokerage, 10 shares, $1,500
basis, $190 price.

**Already verified**: the empty state (native `UIContentUnavailableConfiguration`,
correctly choosing "Tap + to add a position." over the no-investment-account
wording); the row after adding — `AAPL` / `10 shares` / `$1,900.00` / `$400.00`
gain, all arithmetically right; the price sheet round-tripping twice, with the row
redrawing **in place**; and the empty state clearing.

- [ ] **`+` is disabled when there are no investment accounts** (needs a ledger
      without one — switch ledgers, or archive the investment accounts).
- [ ] **Swipe-left → Delete** raises "Delete holding?" naming the symbol, and
      Cancel leaves the row alone.
- [ ] **Long-press → Delete** does the same.
- [ ] **Clearing the price** (empty field → Save) shows "No price" on the row and
      drops the gain/loss line.
- [ ] **A negative or garbage price** is refused with a message rather than
      silently dropped.

## 2c. Measured gaps against the SwiftUI screens

Both found with `idb ui describe-all` (numbers, not screenshots) while checking
Account detail. Neither is guessed.

- [x] **A converted tab lost its FAB, its externally-targeted transaction sheet,
      and its Ledger cover** — `navigationTab` bypassed `TabRootHost`, which
      supplied all three, so Accounts had been missing them since Phase 2 screen
      1. Fixed in `877951b` by moving that chrome into one `TabChrome` modifier
      both hosts apply. A/B verified. **Still worth re-checking by hand:** the
      externally-targeted sheet (deep link / Spotlight / App Intent to a specific
      transaction while a converted tab is selected) — only the FAB and the ledger
      cover were actually observed.
- [ ] **The converted tab root shows an INLINE title where SwiftUI showed a large
      one** (content sits ~52pt higher). The nav bar sets `prefersLargeTitles`,
      but the hosted stack-less root ends up inline. Cosmetic, affects Accounts
      and Budgets, and worth deciding before more tabs convert.
- [ ] **The floating add button is still absent on every converted PUSHED screen.**
      Measured: SwiftUI has `Add Transaction` at `y=764 h=56` on the account
      detail; the converted screen has no such element. Cause: the shell applies
      `.addTransactionFAB()` to the hosted tab *root*
      (`RootTabBarController.swift:234`), and a pushed UIKit VC covers it. The
      SwiftUI shell instead overlaid the FAB above the whole `NavigationStack`,
      so it survived pushes and read the pushed screen's `AddTxContext` to seed
      the sheet.
      *Not fixed here on purpose.* The fix belongs to the shell, and the shell
      is the **shipped default** — a full-frame hosting overlay over the nav
      controller risks swallowing touches app-wide, and moving the FAB out of
      the SwiftUI tree breaks the preference plumbing that seeds it for the
      screens still hosted in SwiftUI. Proposed shape when someone takes it: a
      small, intrinsically-sized hosting view constrained bottom-trailing on the
      `UINavigationController`'s view (so only the button area is interactive),
      plus an `AddTxContextProviding` protocol the top view controller
      implements to replace the SwiftUI preference. Both converted screens keep
      their toolbar `+`, so nothing is unreachable meanwhile.
- [ ] **Converted rows sit 9pt lower**: the "Transactions" header is at
      `y=289.7` vs SwiftUI's `280.7`, and the first row at `330.0` vs `321.0`.
      Consistent offset, so it is a top-inset or picker-height difference, not a
      per-row spacing drift. Decide whether it is worth matching.

## 3. Accessibility — a concern raised by the tooling, not yet investigated

- [ ] The mode picker and saved-search chips are **not visible to `idb`'s
      accessibility tree**. If an automation tool cannot see them, VoiceOver may
      struggle too. Check both with the Accessibility Inspector and VoiceOver on.
- [ ] The converted feed's rows announce sensibly (category, date, amount) and the
      selection ticks announce their state.

## 4. Before the flag comes off

- [ ] Everything in §2, §2b and §2c passes.
- [ ] `ActivityFeedView`'s `.rightSlideDrill(...)` entry replaced by the native push,
      and the SwiftUI screen dropped from the iOS target (`excludes:` in
      `project.yml`) while `FinchMac` keeps it — likewise `AccountDetailView`,
      which `AccountsTab` already asks `nativeRoute(.account(id))` for first.
- [ ] The FAB gap in §2c is resolved (or consciously accepted), since by then
      every drill destination is a converted push.
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
