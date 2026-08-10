# Ledger page changes — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Activating a ledger becomes a swipe, the ledger detail's three action rows become one `⋯` menu, and the row that showed the wrong ledger's transactions is removed.

**Architecture:** Four small, independent edits to three existing UIKit view controllers plus one catalog purge. No new types, no new screens, no `FinchCore` changes. `LedgersVC` gains a leading swipe provider it does not currently have; `LedgerDetailVC` loses its `actions` and `activity` sections and gains the `⋯` toolbar item that `AccountDetailVC` and `BudgetDetailVC` already carry; `BudgetDetailVC` changes one glyph.

**Tech Stack:** Swift, UIKit (`UICollectionViewDiffableDataSource`, `UISwipeActionsConfiguration`, `UIMenu`), SwiftUI only where an existing sheet is presented unchanged.

## Global Constraints

- Target the branch `feat/frontend`. Never `main`.
- No `Co-Authored-By` trailer in commit messages.
- `ios/scripts/ci-local.sh --ui` is the gate and must print `gate passed` before pushing. PR checks are ubuntu-only; the Apple suite runs post-merge, so a green local gate IS the gate.
- Do not pass `SIM_NAME`; the script derives the simulator from the worktree name.
- Every user-facing string goes through `String(localized:)`. New keys require the catalog to be regenerated and **committed**, or i18n guard 1 fails (it diffs against HEAD).
- Do not touch `frontend/` or `ios/FinchCore/`. `git diff --stat origin/feat/frontend...HEAD -- frontend/ ios/FinchCore/` must be empty.
- macOS renders `LedgerListView` / `LedgerDetailView` (SwiftUI), NOT these view controllers. This plan deliberately does not change the Mac; see "Deliberately out of scope".

---

## File Structure

| File | Change |
|---|---|
| `ios/FinchApp/Sources/FinchAppUIKit/LedgersVC.swift` | Add `leadingSwipeActionsConfigurationProvider` + `leadingSwipeActions(at:)` |
| `ios/FinchApp/Sources/FinchAppUIKit/LedgerDetailVC.swift` | Add `⋯` toolbar menu; delete `.actions` and `.activity` sections; rename the currency row |
| `ios/FinchApp/Sources/FinchAppUIKit/BudgetDetailVC.swift` | `ellipsis.circle` → `ellipsis` (one line) |
| `ios/FinchApp/Sources/FinchShared/Resources/*.xcstrings` | Regenerate; manually purge two removed keys |
| `ios/FinchApp/Tests/FinchAppUITests/LedgerActionsUITests.swift` | **Create** — swipe activates, active row offers no activation, `⋯` holds the three actions |

---

## Task 1: The leading swipe activates a ledger

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppUIKit/LedgersVC.swift:92` (provider registration) and `:184` (beside `swipeActions(at:)`)
- Test: `ios/FinchApp/Tests/FinchAppUITests/LedgerActionsUITests.swift`

**Interfaces:**
- Consumes: `store.activeLedgerId` (String), `store.ledgers` ([Ledger]), `ledgerByID[String: Ledger]`, and the existing `makeActive`-equivalent write.
- Produces: `leadingSwipeActions(at:) -> UISwipeActionsConfiguration?`, used only by this file.

**Context an implementer cannot see from the diff:**

`LedgersVC` today registers only a trailing provider. Its Delete is `style: .normal` with a red background on purpose — a full swipe must not delete a whole ledger — so nothing here should introduce `.destructive` either.

The active ledger already shows a checkmark (`LedgersVC.swift:131`), so the swipe is an accelerator, not the only signal.

**The already-active row shows a grey, non-acting "Active" chip.** `UIContextualAction` has **no** `isEnabled`, so a "disabled" action is really a grey action whose handler does nothing. Make it read as *status* (checkmark + "Active"), not as a button that refuses to work. Known limitation, accepted: VoiceOver still announces it as a button, because contextual actions expose no disabled trait.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchApp/Tests/FinchAppUITests/LedgerActionsUITests.swift`:

```swift
import XCTest

/// The ledger list's leading swipe. The active row is asserted separately because
/// its action is a status chip, not a button — see `LedgersVC.leadingSwipeActions`.
final class LedgerActionsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES",
                               "-uikitActivity", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// Swiping an inactive ledger right reveals Make active, and tapping it switches.
    func testTheSwipeActivatesAnInactiveLedger() throws {
        openLedgers()
        let row = inactiveLedgerRow()
        XCTAssertNotNil(row, "no inactive ledger to swipe")
        row!.swipeRight()
        let activate = app.buttons["Make active"].firstMatch
        XCTAssertTrue(activate.waitForExistence(timeout: 5),
                      "leading swipe offered no Make active action")
        activate.tap()
        // The checkmark is the list's own signal that the switch landed.
        XCTAssertTrue(app.cells.containing(NSPredicate(format: "label CONTAINS %@", "Business"))
                        .firstMatch.waitForExistence(timeout: 10))
    }

    /// The active ledger offers a status chip, never an action that would re-activate it.
    func testTheActiveLedgerOffersNoActivation() throws {
        openLedgers()
        let active = activeLedgerRow()
        XCTAssertNotNil(active, "could not find the active ledger row")
        active!.swipeRight()
        XCTAssertFalse(app.buttons["Make active"].waitForExistence(timeout: 2),
                       "the active ledger offered Make active")
    }

    // MARK: Reaching the ledger list

    private func openLedgers() {
        let ledger = app.buttons["Ledger"].firstMatch
        XCTAssertTrue(ledger.waitForExistence(timeout: 10), "no ledger corner control")
        ledger.tap()
        XCTAssertTrue(app.navigationBars["Ledgers"].waitForExistence(timeout: 10))
    }

    /// The seeded store activates "Personal"; any other row is inactive.
    private func inactiveLedgerRow() -> XCUIElement? {
        let row = app.cells.containing(NSPredicate(format: "label CONTAINS %@", "Business")).firstMatch
        return row.waitForExistence(timeout: 10) ? row : nil
    }

    private func activeLedgerRow() -> XCUIElement? {
        let row = app.cells.containing(NSPredicate(format: "label CONTAINS %@", "Personal")).firstMatch
        return row.waitForExistence(timeout: 10) ? row : nil
    }
}
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodegen generate --spec project.yml,project-mac.yml --quiet && \
  xcodebuild -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-ledger' \
  -only-testing:FinchAppUITests/LedgerActionsUITests test
```

Expected: `testTheSwipeActivatesAnInactiveLedger` FAILS with "leading swipe offered no Make active action". `testTheActiveLedgerOffersNoActivation` PASSES already (nothing is offered today) — that is correct; it is a regression guard, not a red-to-green test.

**Regenerate the project first.** A new test file that xcodegen has not seen is not in the target, and `-only-testing` then matches nothing and reports **TEST SUCCEEDED with zero tests run**.

- [ ] **Step 3: Register the leading provider**

In `configureCollectionView()`, directly after the existing trailing provider at `LedgersVC.swift:92`:

```swift
        config.leadingSwipeActionsConfigurationProvider = { [weak self] ip in
            self?.leadingSwipeActions(at: ip)
        }
```

- [ ] **Step 4: Implement the action**

Add beside `swipeActions(at:)`:

```swift
    /// Leading swipe: make this ledger the active one.
    ///
    /// The constructive verb goes on the LEADING edge, matching `AccountsListVC` and
    /// `BudgetsListVC` (both put "Add Transaction" there) with Delete trailing.
    ///
    /// No confirmation, deliberately: the detail row this accelerates has never asked
    /// for one, and the action is reversible — activating another ledger undoes it. A
    /// dialog on a reversible switch is how people learn to dismiss dialogs without
    /// reading them, which is what makes the Delete confirmation stop working.
    ///
    /// The ACTIVE ledger gets a grey, non-acting "Active" chip rather than a hidden
    /// action, so the gesture answers the same on every row. `UIContextualAction` has
    /// no `isEnabled`, so "disabled" can only mean "does nothing" — hence a checkmark
    /// and a status word rather than a button that visibly refuses. Known limitation:
    /// VoiceOver still announces it as a button; contextual actions expose no disabled
    /// trait.
    private func leadingSwipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath),
              let ledger = ledgerByID[id] else { return nil }

        if ledger.id == store.activeLedgerId {
            let current = UIContextualAction(style: .normal,
                                             title: String(localized: "Active")) { _, _, done in
                done(false)   // status, not an action
            }
            current.image = UIImage(systemName: "checkmark")
            current.backgroundColor = .systemGray3
            let config = UISwipeActionsConfiguration(actions: [current])
            config.performsFirstActionWithFullSwipe = false
            return config
        }

        let activate = UIContextualAction(style: .normal,
                                          title: String(localized: "Make active")) { [weak self] _, _, done in
            self?.store.activeLedgerId = ledger.id
            done(true)
        }
        activate.image = UIImage(systemName: "checkmark.circle")
        activate.backgroundColor = .systemBlue
        let config = UISwipeActionsConfiguration(actions: [activate])
        // Same reason Delete here is `.normal`: a whole-ledger switch should be a
        // deliberate tap on the revealed button, not the end of a fast flick.
        config.performsFirstActionWithFullSwipe = false
        return config
    }
```

**Before writing the assignment above, check how the detail page's `makeActive()` (`LedgerDetailVC.swift:266`) performs the switch and use the SAME call.** If it goes through `store.apply(...)` or a helper rather than assigning `store.activeLedgerId` directly, match it — two ways to switch ledgers is exactly the drift this codebase keeps warning about. Read that function first and adjust.

- [ ] **Step 5: Run the tests and confirm both pass**

Same command as Step 2. Expected: `Executed 2 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add ios/FinchApp/Sources/FinchAppUIKit/LedgersVC.swift \
        ios/FinchApp/Tests/FinchAppUITests/LedgerActionsUITests.swift
git commit -m "feat(ios): a leading swipe makes a ledger active"
```

---

## Task 2: The detail's actions become a ⋯ menu

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppUIKit/LedgerDetailVC.swift` — `SectionID` (`:28`), the cell registration cases (`:161`–`:180`), `applySnapshot` (`:247`), `didSelectItemAt` (`:327`–`:330`)
- Test: `ios/FinchApp/Tests/FinchAppUITests/LedgerActionsUITests.swift` (extend)

**Interfaces:**
- Consumes: the existing private methods `makeActive()` (`:266`), `presentEdit(_:)` (`:273`), and `confirmDelete(_:from:)`. **All three are kept and called from the menu instead of from rows** — do not reimplement them.
- Produces: nothing other files use.

**Context an implementer cannot see from the diff:**

`LedgerDetailVC` has **no toolbar setup at all** today — there is no `configureToolbar()` to extend. Add one and call it from `viewDidLoad()`, modelled on `AccountDetailVC.swift:653–677`.

`confirmDelete` takes a source view for the popover anchor. From a `UIMenu` there is no cell to anchor to; pass `nil` if the signature allows, or anchor to the bar button item's view. **Check the signature and the iPad presentation before assuming** — an unanchored action sheet crashes on iPad.

- [ ] **Step 1: Write the failing test**

Append to `LedgerActionsUITests`:

```swift
    /// The detail page's three actions live in the ⋯ menu, and the actions SECTION is gone.
    func testTheDetailActionsLiveInTheOverflowMenu() throws {
        openLedgers()
        app.cells.containing(NSPredicate(format: "label CONTAINS %@", "Personal")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5) == false,
                      "Edit is still a row; it belongs in the ⋯ menu")
        let more = app.buttons["More"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), "no ⋯ item on ledger detail")
        more.tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Make active ledger"].exists)
        XCTAssertTrue(app.buttons["Delete"].exists)
    }

    /// The row that showed the WRONG ledger's transactions is gone.
    func testViewAllActivityIsGone() throws {
        openLedgers()
        app.cells.containing(NSPredicate(format: "label CONTAINS %@", "Personal")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Base currency"].waitForExistence(timeout: 5),
                      "detail did not load")
        XCTAssertFalse(app.staticTexts["View all activity"].exists)
    }
```

`app.buttons["More"]` assumes the bar item carries that accessibility label. **Set it explicitly in Step 3** rather than relying on the system's name for an `ellipsis` glyph.

- [ ] **Step 2: Run and confirm it fails**

Expected: `testTheDetailActionsLiveInTheOverflowMenu` FAILS at "no ⋯ item on ledger detail"; `testViewAllActivityIsGone` FAILS at the `Base currency` assertion (it still reads "Display currency" until Task 3).

- [ ] **Step 3: Add the toolbar menu**

```swift
    /// Edit / Make active / Delete, matching `AccountDetailVC` and `BudgetDetailVC`.
    /// These were three rows in an `actions` section; the section is gone and the
    /// methods behind it are unchanged.
    private func configureToolbar() {
        let menu = UIMenu(children: [
            UIAction(title: String(localized: "Edit"), image: UIImage(systemName: "pencil")) { [weak self] _ in
                guard let self, let ledger = self.ledger else { return }
                self.presentEdit(ledger)
            },
            UIAction(title: String(localized: "Make active ledger"),
                     image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
                self?.makeActive()
            },
            UIAction(title: String(localized: "Delete"), image: UIImage(systemName: "trash"),
                     attributes: .destructive) { [weak self] _ in
                guard let self, let ledger = self.ledger else { return }
                self.confirmDelete(ledger, from: nil)
            },
        ])
        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: menu)
        more.accessibilityLabel = String(localized: "More")
        navigationItem.rightBarButtonItem = more
    }
```

Call `configureToolbar()` from `viewDidLoad()`. **`self.ledger` is a guess at the property name — read the file and use the real accessor** (the existing `didSelectItemAt` already resolves the ledger; reuse whatever it uses).

- [ ] **Step 4: Delete the two sections**

1. `SectionID` (`:28`) becomes `case summary, accounts, currency`.
2. Delete the `makeActiveID` / `editID` / `deleteID` / `activityID` cell-registration cases (`:161`–`:180`) and the four `static let` id constants.
3. In `applySnapshot`, delete the `.actions` and `.activity` `appendSections` / `appendItems` / `headers` lines.
4. In `didSelectItemAt`, delete all four cases (`:327`–`:330`). Leave the account-row case untouched.

- [ ] **Step 5: Run the tests**

Expected: `testTheDetailActionsLiveInTheOverflowMenu` PASSES. `testViewAllActivityIsGone` still fails on `Base currency` until Task 3 — that is expected and fine.

- [ ] **Step 6: Commit**

```bash
git add ios/FinchApp/Sources/FinchAppUIKit/LedgerDetailVC.swift \
        ios/FinchApp/Tests/FinchAppUITests/LedgerActionsUITests.swift
git commit -m "feat(ios): ledger detail actions move into a ⋯ menu

View all activity goes with them. It pushed ActivityFeedVC() with no
ledger argument, so the feed showed the ACTIVE ledger — on any other
ledger's page it opened a different ledger's transactions under this
one's heading."
```

---

## Task 3: The currency row says what the Edit sheet says

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppUIKit/LedgerDetailVC.swift:149`

**Context:** the detail calls this field "Display currency"; `LedgerManagementView.swift:125` — the only place it can be changed — calls it "Base currency". One field under two names reads as two settings.

- [ ] **Step 1: Rename**

```swift
                cfg.text = String(localized: "Base currency")
```

- [ ] **Step 2: Run the test**

Expected: `testViewAllActivityIsGone` now PASSES.

- [ ] **Step 3: Commit**

```bash
git add ios/FinchApp/Sources/FinchAppUIKit/LedgerDetailVC.swift
git commit -m "fix(ios): the ledger's currency row uses the Edit sheet's name for it"
```

---

## Task 4: One ⋯ glyph across the three detail screens

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppUIKit/BudgetDetailVC.swift:508`

**Context:** `AccountDetailVC` uses `ellipsis`, `BudgetDetailVC` uses `ellipsis.circle`. Ledger detail now uses `ellipsis`, so Budgets is the last one out of step. On iOS 26 a toolbar item already draws its own glass capsule, so the drawn circle doubles it.

- [ ] **Step 1: Change the glyph**

```swift
        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: menu)
```

- [ ] **Step 2: Confirm nothing asserted the old glyph**

```bash
grep -rn "ellipsis.circle" ios/FinchApp/
```

Expected: no remaining hits in `FinchAppUIKit/`. If a UI test matches on it, update that test in the same commit.

- [ ] **Step 3: Commit**

```bash
git add ios/FinchApp/Sources/FinchAppUIKit/BudgetDetailVC.swift
git commit -m "style(ios): all three detail screens use the same ⋯ glyph"
```

---

## Task 5: The catalog, including the purge

**Files:**
- Modify: `ios/FinchApp/Sources/FinchShared/Resources/*.xcstrings`

**Context an implementer cannot see from the diff — read this before running anything:**

Two keys are **removed** by this work: `"View all activity"` and, if it was not reused, nothing else. Both `"Make active ledger"`, `"Edit"` and `"Delete"` survive (they moved into the menu, still `String(localized:)`).

**A removed key that has a translation does not disappear on its own.** The xliff export round-trips it back in, and BOTH i18n guards stay green while the stale key sits there forever. It has to be purged by hand from each `.xcstrings`.

New keys added: `"Make active"`, `"Active"`, `"More"`, `"Base currency"`. They need translations or they ship as English in every locale.

- [ ] **Step 1: Regenerate and inspect**

```bash
cd ios && ./scripts/extract-strings.sh   # confirm the real script name first
git diff --stat ios/FinchApp/Sources/FinchShared/Resources/
```

- [ ] **Step 2: Purge the removed key by hand**

Open each `.xcstrings` and delete the `"View all activity"` entry outright, including its translations. Confirm:

```bash
grep -c "View all activity" ios/FinchApp/Sources/FinchShared/Resources/*.xcstrings
```

Expected: `0` in every file.

- [ ] **Step 3: Translate the new keys**

Add the Chinese translations for `"Make active"`, `"Active"`, `"More"`, `"Base currency"`. Follow the tone of the existing ledger strings.

- [ ] **Step 4: Commit the catalog**

i18n guard 1 diffs against HEAD, so an uncommitted catalog change fails the gate even when it is correct.

```bash
git add ios/FinchApp/Sources/FinchShared/Resources/
git commit -m "i18n(ios): ledger action strings; purge the removed activity key"
```

---

## Task 6: Gate and open the PR

- [ ] **Step 1: Rebase onto the current base**

```bash
git fetch -q origin && git rebase origin/feat/frontend
```

The gate's own base check fails the run if the branch is behind, so do this first rather than after a 35-minute build.

- [ ] **Step 2: Run the gate with UI tests**

```bash
cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/ci-local.sh --ui
```

`--ui` is required: this branch's only new tests are UI tests, and `--full` does NOT imply them.

Expected: `gate passed`. If it reports xcstrings churn, `git checkout --` those files before pushing.

- [ ] **Step 3: Verify scope**

```bash
git diff --stat origin/feat/frontend...HEAD -- frontend/ ios/FinchCore/
```

Expected: empty.

- [ ] **Step 4: Push and open the PR against `feat/frontend`**

The PR body should carry the `ActivityFeedVC()` finding, since "removed a row" and "removed a row that showed the wrong ledger's data" are very different reviews.

---

## Deliberately out of scope

**macOS is untouched.** `LedgerListView` / `LedgerDetailView` (SwiftUI) still render on the Mac and under `-legacyShell YES` / `-uikitActivity NO`, so the Mac keeps its actions section and its "View all activity" row. This is a real divergence, and it is the same one every Phase 3b conversion has: `NavigationUITests` runs its suite once per implementation, so the SwiftUI half must keep working. **If you want the Mac to match, that is a second plan** — and note the SwiftUI row has the same wrong-ledger bug.

**Delete now appears in two places** (list trailing swipe, detail `⋯`). Left as-is: the detail is where someone who does not know the gesture goes.

**"Make active" appears in two places** for the same reason — a swipe is invisible, and the menu is the discoverable copy.

## Self-review notes

- Task 1's `store.activeLedgerId = ledger.id` is the ONE line in this plan that guesses at an existing mechanism. Step 4 says to read `makeActive()` first and match it; do not skip that.
- Task 2's `self.ledger` and `confirmDelete(_:from:)` signature are likewise unverified — both are flagged inline.
- `testTheActiveLedgerOffersNoActivation` passes before the change. That is intentional (regression guard), and Step 2 says so, so nobody reports it as a broken red-green cycle.
