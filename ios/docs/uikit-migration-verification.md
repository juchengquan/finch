# UIKit migration — human verification checklist

Things that **cannot be verified programmatically** and are waiting on eyes. Tick as
you go; add findings inline under the item.

**Why this file exists.** `idb ui describe-all` does not expose toolbar items,
nav-bar buttons, search fields, or segmented controls in the accessibility tree, and
`simctl` screenshots do not contain the Liquid Glass compositor layers. So a whole
class of change builds green, passes 676 tests, and is still unverified.

**Aim at `frame.y + height/2`, never `frame.y`.** By the end of this work FIVE
"bugs" turned out to be missed taps. `describe-all` reports the row's TOP EDGE, and
tapping exactly there lands in the gap between rows: the Settings "Merchants" row is
`y=573 h=52`, so y=573 misses and y=599 hits. The same fraction-of-a-point error hit
a chevron accessory (off by 0.2pt) and a swipe button (Delete starts at x=175.3, so
x=175 falls between buttons). When something "does nothing", re-read the frame and
try the centre before believing it. Cross-checking against the SwiftUI screen under
the SAME coordinates is the cheapest way to tell a missed tap from a real defect —
if both fail, it is the tap.

**Pin the simulator when the machine is busy.** `ci-local.sh` picks a shared device
by default; a run of it WEDGED for 30 minutes on "iPhone 17 Pro" while other sessions
were building (load average 568). Killing it reported **exit code 0 having run only 4
of 9 checks** — a green exit that proved nothing. Use
`./scripts/ci-local.sh --sim "<this session's sim>"`, and confirm the summary really
says `all checks passed` rather than trusting the exit code.

**A `UIHostingConfiguration` does NOT inherit environment objects.** The `hosted()`
helper used for presented controllers injects them; hosted CELL content does not, and
a SwiftUI view reading `@EnvironmentObject` will TRAP ("No ObservableObject of type
FinchStore found") the instant the cell appears. That crashed the app on first open of
the converted Backup & Sync screen. Wire the environment by hand in every
`UIHostingConfiguration` whose content needs it.

**The simulator's accessibility service can wedge**, especially under sustained
load. The symptom is `describe-all` returning a single `Application` element while
the UI renders perfectly in a screenshot. It is not an app failure and not an empty
screen — fall back to screenshots, and do not drive multi-field sheets blind.

**A regenerated string catalog must be COMMITTED to pass its own check.** The
catalog step is `build-xcstrings.ts && git diff --quiet`, so a correct-but-uncommitted
catalog fails with "does not match a fresh build" — which reads like a content
problem and is not one.

**`idb ui tap` does not flip a `UISwitch`.** Even a tap provably inside the switch's
frame does nothing; only a short DRAG across it works
(`idb ui swipe <x-8> <y> <x+24> <y> --duration 0.3`). A switch that ignores taps is a
tooling limitation, not a broken action.

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

## 2f. Phase 2 — the converted Categories screen (`-uikitActivity YES`)

Settings → Categories. `.settings` is now a UIKit nav tab, so **re-check §1 on that
tab too**. This is the screen the migration was justified by: the only one measured
to shadow under a UIKit root, and measured to be fixed by conversion.

**Already verified on the simulator**: the screen pushes and renders (pinned search,
kind picker as the first row, parent-only chevrons, count pills); the chevron expands
Dining to three children indented 14pt; Income switches to its own set; searching
"cof" surfaces `Dining → Coffee Shops` (parent shown because a descendant matches,
force-expanded); select mode ticks rows, **dims and disables the parent of a ticked
row**, and enables "Merge (2)"; the survivor prompt reports "3 transactions will be
combined", the correct union of 2 + 1. Swatch rendering was A/B'd against the SwiftUI
screen and is identical — the seeded categories simply carry no per-category icon or
colour, so both fall back to the default cyan tag.

- [ ] ⚠️ **REORDER BY DRAG IS ENTIRELY UNVERIFIED, AND IT IS THE RISKIEST ITEM ON
      THIS PAGE.** `idb` has no drag command — only press-move-release, which never
      triggers a UIKit drag lift — so the gesture cannot be automated at all (a slow
      swipe was tried; the order did not change). If the drop never arrives, ⋯ →
      Reorder strands the user in a mode where nothing works. Check all four
      outcomes: drop on a row's **top quarter** (lands before it), **bottom quarter**
      (after it), **middle** (nests under it), and on the **"Top level"** row
      (un-nests). Also confirm the engine's refusals surface as messages: nesting a
      parent under its own child, and exceeding 3 levels.
      *What IS tested:* `CategoryDropZone.at(pointY:cellMinY:cellHeight:)` has 5 unit
      tests for the quarter boundaries and the zero-height fallback, and
      `CategoryReorder` was already unit-tested. Only the UIKit drag/drop plumbing
      is unproven.
- [ ] **Tapping a row** drills to the category's transactions. NOTE that target is
      still hosted SwiftUI in a PUSHED page — reproducer B — so `CategoryDetailView`
      can still shadow until it too is converted. Converting this screen fixes THIS
      screen.
- [ ] **Swipe-left**: Edit at the outer edge (so a careless full swipe edits, never
      deletes), then Delete, then Merge…. **Long-press** adds "Copy to another
      ledger…".
- [ ] **Delete** names the category and reports its impact (transaction count and
      how many children promote up a level).
- [ ] **Pairwise Merge…** from a row: the target picker excludes the row itself and
      its descendants, and the keep-name prompt appears AFTER the picker dismisses
      (chaining dismiss+present in one transaction can drop the second).
- [ ] **Import from another ledger…** and **Copy to another ledger…** both toast a
      count, including "Nothing new to copy" when the target already has them.
- [ ] **The empty state** for a kind with no categories keeps the kind picker
      visible above it (switch to a ledger with no income categories).
- [ ] **No resume shadow** — the whole point. Scroll, background, wait ~3s, reopen,
      and compare against the same screen with the flag off, which should still
      shadow.

## 2g. Phase 2 — the converted Tags screen (`-uikitActivity YES`)

Settings → Tags. Flat list, so much less to go wrong than Categories: no tree, no
reorder, no drag.

**Already verified on the simulator**: 8 tags render with their own swatch colours,
count pills and no chevrons; select mode ticks rows and enables "Merge (2)"; the
survivor prompt reports "4 transactions will be combined" for business (3) + gift
(1); the swipe reveals **Edit at the outer edge, then Merge…, then Delete inboard**
(so a full swipe edits, never deletes); the delete confirmation reads "business is
removed from 3 transactions."; and searching "zzz" empties the list **without** the
"No tags yet" message, with every row returning when the search clears. Both
destructive prompts were cancelled, so no data changed.

- [ ] **New tag** (`+`) creates one, and **Edit** renames / recolours it.
- [ ] **Deleting an UNUSED tag** shows the title with no message body (the count
      line is suppressed when nothing references it).
- [ ] **Pairwise Merge…** from a row: the picker lists every other tag, and the
      keep-name prompt appears AFTER the picker dismisses.
- [ ] **Import from another ledger…** / **Copy to another ledger…** toast a count,
      including "Nothing new to copy".
- [ ] **The real empty state** — a ledger with no tags at all shows "No tags yet".
- [ ] **No resume shadow**: scroll, background, wait ~3s, reopen.
- [ ] Tapping a row drills to the tag's transactions — still hosted SwiftUI in a
      pushed page, so `TagDetailView` can shadow until it too is converted.

## 2h. Phase 2 — the converted Merchants screen (`-uikitActivity YES`)

Settings → Merchants.

**Already verified on the simulator**: rows render with verified seals and count
pills; the swipe reveals **Rename outermost, Delete, then Merge… innermost**, so a
full swipe renames (confirmed when a long swipe opened the Rename sheet pre-filled —
the intended safety property); and **both** delete branches are right — "This
permanently deletes Adobe." for a merchant with 0 transactions, and "Acme Corp
Payroll — 3 transactions keep the name but lose the merchant link." for one with 3.
Both prompts were cancelled, so no data changed.

- [ ] **Long-press** gives Rename / **Verify or Unverify** / Merge… / Delete. The
      verify toggle is merchant-only and exists ONLY here, never on the swipe — and
      it is the one action on this screen nobody has exercised. Check the seal
      appears and disappears on the row.
- [ ] **Rename** actually renames (the sheet was opened but Save was never tapped).
- [ ] **Add Merchant** (`+`) creates one.
- [ ] **Merge…**, single and multi-select, with the keep-name prompt appearing after
      the picker dismisses.
- [ ] **The empty state** — a ledger with no merchants shows the full-screen "No
      merchants" placeholder **and no search bar**. Both halves matter: a stray
      search bar over a placeholder would read as a bug.
- [ ] **No resume shadow**: scroll, background, wait ~3s, reopen.
- [ ] Tapping a row drills to the merchant's transactions — still hosted SwiftUI in
      a pushed page, so `CounterpartyDetailView` can shadow until converted.

## 2i. Phase 2 — the converted Currencies screen (`-uikitActivity YES`)

Settings → Currencies.

**Already verified on the simulator**: the controls section renders (auto-update on,
"Last updated Jul 30, 2026 at 00:47", "Refresh now" tinted, and the privacy footer);
USD shows `1.0000` as the hub **with no switch**, CAD/EUR/GBP/JPY show 4-decimal
rates with green switches, and inactive AED shows "—" with its switch off; tapping a
row pushes the history screen; search filters to a single currency; and the tracking
switch works **both ways** — dragging CAD off removed it from the Active group and
dragging it back on restored it between USD and EUR, so the write, the regrouping and
the cell reconfigure are all confirmed. The tracked set was left as found.

- [ ] **Auto-update toggle** actually persists (it writes
      `finch.fx.autoUpdate`; absent key means ON, so check it survives a relaunch in
      BOTH states — the off state is the one a bug would hide).
- [ ] **Refresh now** — needs network. Check the spinner shows, then one of "Updated
      N rates" / "Nothing to update" beside the row, or the error alert when offline.
      Nothing here has been exercised: the sim run never triggered a fetch.
- [ ] **Toggling ON a currency with no stored rate** must fetch immediately
      (manual-act semantics) — pick one showing "—". This is the one branch of
      `setTracked` that was deliberately avoided on the sim, because it hits the
      network.
- [ ] **The search bar hides on scroll here** (plain `.searchable`), unlike
      Categories/Tags which pin it. Confirm that is still what you want.
- [ ] **No resume shadow**: scroll, background, wait ~3s, reopen.
- [ ] `ExchangeRateHistoryView` is still hosted SwiftUI in a pushed page, so it can
      shadow until converted.

## 2j. Phase 2 — the converted Category / Tag / Merchant detail (`-uikitActivity YES`)

One screen, `TxListDetailVC`, reached three ways: Settings → Categories / Tags /
Merchants → any row. **All three drill chains are now native end to end** — the first
time any chain has been — so the shadow check below is the one that actually tests
the migration's premise.

**Already verified on the simulator, all three entry points**:
- Category (Groceries): Transactions 7 (matching the parent's count pill), Total
  −$317.10, Average −$45.30 — 317.10 ÷ 7 exactly; the pending −$42.18 row sits under
  "To confirm (1)" with its clock and "reimbursable" chip and is correctly
  **excluded** from the total.
- Tag (business): rows carry the "business" chip.
- Merchant (Acme Corp Payroll): 3 / $12,600.00 / $4,200.00 — 3 × 4,200 — with the
  green income kind bar rather than the expense red.

Because it is one implementation, a defect found through any entry point affects all
three; conversely a fix only needs verifying once, except where the SOURCE differs
(membership rules, below).

- [ ] **Row gestures** — the shared `TxRowActions` again (swipe right ⇒ Duplicate;
      swipe left ⇒ status toggle at the edge, Delete inboard with a confirmation;
      long-press ⇒ the same menu **without** Preview receipt, since the SwiftUI row
      passes no `previewReceipt` here).
- [ ] **The summary updates after a write** — delete or flip a row and check
      Transactions / Total / Average all move. They sit under fixed identifiers, so
      they depend on the reconfigure.
- [ ] **Membership matches each parent's count pill** — the one thing that is NOT
      shared, since each `Source` calls a different selector. Category includes split
      legs; tag is "tagged in this ledger"; merchant goes through
      `merchantTransactions`. Spot-check one of each against the pill on its parent.
- [ ] **No resume shadow, on BOTH screens of each chain**: the list, then the
      detail, for Categories / Tags / Merchants. Compare against the flag off, where
      the detail is hosted SwiftUI in a pushed page and should still shadow. **This
      is the check the whole migration exists to pass.**

## 2k. Row fidelity: the earlier converted screens render a poorer row

Not a bug report, a scope note. `CategoryDetailVC` hosts the shared SwiftUI `TxRow`
verbatim, so its rows carry tag chips, the pending clock, the expense/income kind bar
and relative dates (`Jul 28 · 12:00`).

`ActivityFeedVC` and `AccountDetailVC` do NOT — they build cells by hand with
category, date and amount only. That was inherited from the migration pilot, and it
means those two screens are visibly plainer than their SwiftUI originals.

- [ ] Decide whether to switch them to a hosted `TxRow` too. Arguments both ways:
      hosting is exact and free of drift, but those lists are the ones expected to
      hold thousands of rows, and they also need a leading selection tick that the
      shared row knows nothing about. Worth measuring scroll performance at 2,000
      rows before committing either way.

## 2l. Phase 2 — the converted rate history (`-uikitActivity YES`)

Settings → Currencies → any currency.

**Already verified**: CAD shows "Jul 29, 2026 · 0.7092" with the ECB source badge,
and the ⋯ menu offers "Delete all CAD rates" with the currency interpolated. Nothing
was deleted.

- [ ] **The sparkline** — *never rendered*, because the seeded data carries fewer
      than three rates per currency and the chart is deliberately hidden below three
      points. Same class of gap as Holdings: the demo seed cannot exercise it. Add a
      few manual rates, or check against real data.
- [ ] **Per-row delete** confirms with "{currency} · {date}", and **deleting the last
      row pops the screen** (that pop re-derives the row set after the write — a
      behaviour easy to lose in translation).
- [ ] **Delete all** confirms with "Delete N rates" and pops.
- [ ] The ⋯ menu is **empty when there are no rates** (the SwiftUI screen hides the
      item, leaving an empty menu — check that reads acceptably).

## 2m. Every drill chain is now native end to end

With `TxListDetailVC` and `ExchangeRateHistoryVC` landed, no converted list pushes a
hosted SwiftUI screen any more. That makes the following the decisive test of the
whole migration — if any of these still shadow, the premise is wrong:

- [ ] **Categories → a category → background ~3s → reopen.** No shadow on either.
- [ ] **Tags → a tag.** Same.
- [ ] **Merchants → a merchant.** Same.
- [ ] **Currencies → a currency.** Same.
- [ ] **Accounts → an account**, and **Accounts → All Transactions**. Same.
- [ ] For contrast, repeat any one of them with the flag OFF, where the detail is
      hosted SwiftUI in a pushed page — that one **should** still shadow. A run where
      neither shadows proves nothing.

## 2n. Phase 2 — the converted Experimental Labs (`-uikitActivity YES`)

Settings → Experimental Labs (scroll down; the row sits under the tab bar).

**Already verified**: the screen renders with the Rules row, the Sync header and
footer, and the iCloud toggle, and the conditional status rows are correctly
**absent** while sync is disabled — the only state a simulator without an iCloud
account can produce.

- [ ] **Everything behind the iCloud toggle is unexercised**, because the sync layer
      is inert scaffold here: the bootstrapping and syncing progress rows, Status /
      Pending changes / Last sync, the red error line, and the Resync button
      (disabled without an account). Needs a device with iCloud and a provisioned
      container.
- [x] **Rules** pushes the converted manager (see §2o). **Correction:** one hosted
      SwiftUI push does remain — `SettingsBackupsView`, behind Backup & Sync →
      Backups (see §2r). It is 235 lines and was left out of scope.
- [ ] **Two strings are newly translatable**: "Subscribed to N ledgers" and "iCloud
      account required" ship English-only from the SwiftUI screen (plain `String` to
      `LabeledContent(value:)`). The conversion routes them through the catalog,
      where they now sit **untranslated** — so nothing changes for a zh-Hans user
      yet. They want a translation in `scripts/zh-manual.json`.

## 2o. Phase 2 — the converted Rules manager (`-uikitActivity YES`)

Settings → Experimental Labs → Rules.

**Already verified**: the screen pushes and renders the inline title, the `+` button
and the empty-state row.

**Nothing else could be**: the demo seed contains NO RULES, so every row-level
behaviour below is unexercised — the same gap as Holdings and the rate sparkline.
Create a rule first, then work through these.

- [ ] **Row layout**: name with "priority N" beneath, the "N×" match count (hidden
      at zero — a rule that never matched shows nothing, not a "0×" that reads like
      failure), and the Active switch.
- [ ] **The Active switch** writes and survives a relaunch. Remember `idb ui tap`
      will not flip a `UISwitch` — drag it.
- [ ] **Swipe LEFT → Delete** (confirmation: "This permanently deletes the rule.").
- [ ] **Swipe RIGHT → Backfill** — this edge exists only on this screen. It applies
      the rule to existing transactions, so check the match count moves.
- [ ] **Long-press** gives Backfill and Delete.
- [ ] ⚠️ **The two-way sheet split is the load-bearing one.** A rule using only CP1
      fields must open the EDITOR; a rule using CP2 fields, nested groups, `not` or a
      split must open READ-ONLY. Sending an unparseable rule to the editor would
      silently rewrite it on save, so make a rule of each kind and confirm which
      sheet appears.

## 2p. Phase 2 — the converted Appearance & Language (`-uikitActivity YES`)

Settings → Appearance & Language.

**Already verified, both directions**: all eight sections with their headers and
footers; turning "Use system size" OFF grows the slider and the "Sample —
$1,234.56" row **and** flips the footer to "Overrides the system text size inside
finch."; turning it back on removes both and restores the original footer.

- [ ] **Theme** — System / Light / Dark changes the app immediately (this is the
      live one; it drives `applyAppearancePreference` on the window) and the LOCK
      SCREEN follows it too.
- [ ] **Text-size slider** actually resizes type across tabs, and the sample row
      tracks it as you drag.
- [ ] **Language** — picking one writes `AppleLanguages`, turns the footer ORANGE
      with "Relaunch finch to apply the new language.", and the language really
      changes after a relaunch. **Set it back to System afterwards**, or the sim
      stays in that language.
- [ ] **Group by month / Relative dates** change the Activity feed and an account's
      list.
- [ ] **Reconcile reminder** — the pull-down offers Off plus the day options and the
      chosen one shows on the row; the Accounts list's badge colour follows it.
- [ ] **Haptic feedback**, **Adjust Balance in Add sheet**, **Floating add button**
      + its position picker each take effect where advertised.
- [ ] Every preference **survives a relaunch** — they are plain UserDefaults writes,
      but the OFF states are the ones a bug would hide.

## 2q. Phase 2 — the converted Notifications settings (`-uikitActivity YES`)

Settings → Notifications.

**Already verified**: all four kind toggles render, and a Weekly digest round-trip
reads 1 → 0 → 1, so the write and the cell reconfigure both work.

- [ ] **The denied-permission nudge** — unverified, because notifications are
      GRANTED on this simulator. Deny them (or use a fresh sim and decline the
      prompt) and check the orange "Notifications are turned off" block appears
      above the toggles, with its caption and a working "Open Settings" link.
- [ ] **Turning a kind off actually stops its notifications** — the toggle calls
      `NotificationService.refresh()`, and rescheduling is what adds or removes the
      pending requests. Check with `xcrun simctl push` or by waiting for a budget
      alert, not just by re-reading the switch.
- [ ] Preferences **survive a relaunch**.

## 2r. Phase 2 — Security, Backup & Sync, About (`-uikitActivity YES`)

**Already verified**: Security renders with its two conditional rows correctly
absent while the policy is Off; Backup & Sync renders both sections and all three
hosted buttons (Import .finch, Export .finch, Export transactions (.csv)); About
renders versions, the database summary with its dynamic row counts, a "Clean" audit
and the red force-import row.

### Security — treat with care
- [ ] ⚠️ **Changing the lock policy locks the app IMMEDIATELY**, even to "After
      background" and even while in the foreground. On a simulator with no enrolled
      biometrics and no device passcode that is UNRECOVERABLE without reinstalling —
      it happened during this work. Test on a device, or on a sim with a passcode
      set. This is `BiometricGate`'s behaviour, shared with the SwiftUI screen, not
      something the conversion introduced.
- [ ] **"Lock after"** appears only for After-background / After-idle, and the chosen
      timeout is the one actually enforced.
- [ ] **"Require Face ID for export & destructive actions"** appears only while
      locking is on, and genuinely prompts on export and on force import.

### Backup & Sync
- [ ] **Import / Export / Export CSV** each work — a file importer, a share sheet,
      and a CSV share. Import REPLACES the database, so use a scratch ledger.
- [ ] **Last backup** and the **Backups count** update after a backup runs.
- [ ] ⚠️ **The Backups row pushes `SettingsBackupsView`, which is STILL hosted
      SwiftUI in a pushed page** — the one remaining reproducer-B screen. Check
      whether it shadows; converting it is the obvious next job if it does.

### About
- [ ] **Audit problems list** — unexercised, because the audit is Clean. Needs a
      ledger with problems.
- [ ] ⚠️ **Force import** — untested on purpose. It replaces the live database with
      an audit-REJECTED pack and cannot be undone. When you do test it, confirm the
      biometric prompt appears BETWEEN the confirmation and the replacement.
- [ ] The database row counts match reality after an import.

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

## 4b. Scope correction — two screens on the Phase 2 list need no conversion

`ScheduledDetailView` and `TransactionDetailView` were both queued for conversion.
Neither should be: **they are unreachable from the compact UIKit shell**, so a
converted version could not be reached from any path.

The evidence, all of it grep-able:

- Each is referenced from exactly ONE place — `AdaptiveShell.swift:353` and
  `:342` — and both sit in a `ThreeColumnShell`'s **detail column**, not in any
  push or cover.
- The compact path opens a SHEET instead. `ScheduledTab.swift:71`:
  `if let selection { selection.wrappedValue = t.id } else { editing = t }`, and
  `ActivityTab.swift:328`: `else if let selection { … } else { editing = txn }`.
  A `selection` binding exists only in three-column mode, so on iPhone a row tap
  goes straight to `ScheduledSheet` / `EditTransactionSheet`.
- The three-column mode runs on WIDE windows, which Phase 1 deliberately keeps on
  the SwiftUI split shell (`UIKitShell.makeRoot`: `wide → AppRootHost`). No
  `nativeRoute` handler is installed there, so the seam returns its default
  `false` and the SwiftUI screen is used regardless.
- `FinchMac` keeps the SwiftUI screens either way.

And the motivating bug does not apply: the iOS 26 resume shadow affects **pushed**
screens. A split-view detail column is never pushed, so neither screen can exhibit
it — converting them buys nothing even in principle.

Converting either would mean shipping a view controller that nothing constructs.
The only way to make them reachable is a PRODUCT change — giving the iPhone a
read-only detail screen where it currently opens the editor — which is a design
decision, not a migration step.

**What to do instead.** The remaining compact-reachable pushed screens are the
`PowerTools` set (Categories, Tags, Merchants, FX, and so on). `CategoriesView` is
the strongest next candidate: it is the one screen MEASURED to shadow under a
UIKit root while `AccountDetailView` did not, and converting it was measured to
fix that (see `ios26-shadow-variant-matrix.md`). It is the case with proven value.

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
