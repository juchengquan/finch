# Future-dated transactions start pending — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A transaction dated after today starts as Pending rather than Confirmed, and the "To confirm" queue stops counting things that have not happened yet.

**Architecture:** One new pure `FinchCore` selector splits pending transactions into due-now and upcoming. Seven app-side screens stop filtering `pending == true` locally and call it instead. The Add sheet gains a date→status rule that stops applying once the user sets Status by hand. The Edit sheet is untouched.

**Tech Stack:** Swift, SwiftUI (Add sheet and five hosted screens), UIKit (`ActivityFeedVC`, `AccountDetailVC`, `TxListDetailVC`), `FinchCore` selectors.

## Global Constraints

- Target `feat/frontend`. Never `main`.
- No `Co-Authored-By` trailer.
- `ios/scripts/ci-local.sh --ui` must print `gate passed` before pushing.
- Do not pass `SIM_NAME`; the simulator is derived from the worktree name.
- **"Future" means `tx.date > today` as ISO **day** strings.** `Tx.date` is a `String` day (`Models.swift:13`); the time lives separately. Never compare timestamps — 19:00 today is still today.
- `today` is **passed in**, never read inside the selector. `FinchCore` is pure and its tests must be able to fix the date. The app passes `store.wallToday` (`FinchStore+ViewHelpers.swift:42` — "the real current day, for surfaces that mean literal today"), NOT `store.today`, which is data-anchored.
- No `frontend/` changes. iOS and web will group this bucket differently; that is accepted and no parity fixture covers it.

---

## File Structure

| File | Change |
|---|---|
| `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift` | **New** `pendingSplit(_:today:)` |
| `ios/FinchCore/Tests/FinchCoreTests/PendingSplitTests.swift` | **Create** — the selector's own tests |
| `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/AddTransactionSheet.swift` | date→status rule + `statusTouched` latch |
| `ios/FinchApp/Sources/FinchAppSwiftUI/Tabs/ActivityTab.swift` | use the selector; add an Upcoming section |
| `ios/FinchApp/Sources/FinchAppUIKit/ActivityFeedVC.swift` | same, as a collection-view section |
| `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/AccountDetailView.swift` | same |
| `ios/FinchApp/Sources/FinchAppUIKit/AccountDetailVC.swift` | same |
| `ios/FinchApp/Sources/FinchAppUIKit/TxListDetailVC.swift` | same (category / tag / merchant) |
| `ios/FinchApp/Sources/FinchAppSwiftUI/PowerTools/{Category,Tag,Counterparty}DetailView.swift` | same |
| `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/ReconcileSheet.swift` | **exclude** upcoming; no Upcoming section |
| `ios/scripts/zh-manual.json` + catalog | one new key, `Upcoming` |

**Not touched:** `EditTransactionSheet.swift`. Changing an existing record's status while someone corrects a date moves it out of budget totals, and nobody attributes that to the date field. Status is in the same sheet if they want it.

---

## Task 1: The selector

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests/PendingSplitTests.swift`

**Interfaces:**
- Produces: `Selectors.pendingSplit(_ txns: [Tx], today: String) -> (dueNow: [Tx], upcoming: [Tx])`. Every screen in Tasks 3–5 consumes exactly this.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchCore/Tests/FinchCoreTests/PendingSplitTests.swift`:

```swift
import XCTest
@testable import FinchCore

/// `pendingSplit` decides what the "To confirm" queue may nag about.
final class PendingSplitTests: XCTestCase {
    private func tx(_ id: String, _ date: String, pending: Bool) -> Tx {
        Tx(id: id, merchant: "m", category: nil, amount: -1, account: "a",
           date: date, pending: pending, ledgerId: "l")
    }

    func testConfirmedRowsAreInNeitherBucket() {
        let out = Selectors.pendingSplit([tx("a", "2026-08-01", pending: false)], today: "2026-08-12")
        XCTAssertTrue(out.dueNow.isEmpty)
        XCTAssertTrue(out.upcoming.isEmpty)
    }

    func testPastAndTodayArePendingNow() {
        let out = Selectors.pendingSplit([tx("a", "2026-08-01", pending: true),
                                          tx("b", "2026-08-12", pending: true)],
                                         today: "2026-08-12")
        XCTAssertEqual(out.dueNow.map(\.id), ["a", "b"])
        XCTAssertTrue(out.upcoming.isEmpty)
    }

    /// TODAY IS NOT UPCOMING. The boundary is `>`, not `>=` — a transaction entered
    /// today for later today must still be confirmable now.
    func testTodayIsNotUpcoming() {
        let out = Selectors.pendingSplit([tx("a", "2026-08-12", pending: true)], today: "2026-08-12")
        XCTAssertEqual(out.dueNow.map(\.id), ["a"])
        XCTAssertTrue(out.upcoming.isEmpty)
    }

    func testTomorrowOnwardsIsUpcoming() {
        let out = Selectors.pendingSplit([tx("a", "2026-08-13", pending: true),
                                          tx("b", "2026-09-01", pending: true)],
                                         today: "2026-08-12")
        XCTAssertTrue(out.dueNow.isEmpty)
        XCTAssertEqual(out.upcoming.map(\.id), ["a", "b"])
    }

    /// The split is computed against `today`, so an upcoming row becomes due on its
    /// date with nothing running. This is the property that makes the feature need no
    /// migration, so it is pinned.
    func testARowMovesBucketWhenItsDateArrives() {
        let rent = [tx("rent", "2026-09-01", pending: true)]
        XCTAssertEqual(Selectors.pendingSplit(rent, today: "2026-08-31").upcoming.map(\.id), ["rent"])
        XCTAssertEqual(Selectors.pendingSplit(rent, today: "2026-09-01").dueNow.map(\.id), ["rent"])
    }
}
```

**`Tx`'s memberwise init may not match the argument list above.** Read `Models.swift` and adjust — `Tx` has many fields and most are optional. Do not change `Tx` to suit the test.

- [ ] **Step 2: Run it and confirm it fails**

```bash
cd ios && swift test --package-path FinchCore --filter PendingSplitTests
```

Expected: compile failure, `pendingSplit` does not exist.

- [ ] **Step 3: Implement**

```swift
    /// Split pending transactions into the ones worth confirming NOW and the ones that
    /// have not happened yet.
    ///
    /// `pending` means two different things in this app: the engine treats it as "has
    /// not counted yet" (excluded from spend, budgets and running balance), while the UI
    /// treats it as "needs your attention" — every screen pinned ALL pending rows into a
    /// "To confirm (N)" bucket. Once a future-dated transaction defaults to pending,
    /// those two readings come apart: next month's rent is correctly not-counted, and
    /// incorrectly nagging.
    ///
    /// `today` is a parameter, not a read of the clock, so this stays pure and its tests
    /// can fix the date. Callers pass `store.wallToday` — the literal current day — NOT
    /// `store.today`, which is anchored on the data.
    ///
    /// Day strings compare lexicographically because they are zero-padded ISO
    /// (`2026-08-12`), which is why this needs no date parsing. The boundary is `>`:
    /// something dated today is confirmable today.
    public static func pendingSplit(_ txns: [Tx], today: String) -> (dueNow: [Tx], upcoming: [Tx]) {
        var dueNow: [Tx] = []
        var upcoming: [Tx] = []
        for t in txns where t.pending == true {
            if t.date > today { upcoming.append(t) } else { dueNow.append(t) }
        }
        return (dueNow, upcoming)
    }
```

- [ ] **Step 4: Run the tests** — expected `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift \
        ios/FinchCore/Tests/FinchCoreTests/PendingSplitTests.swift
git commit -m "feat(core): pendingSplit separates what is due from what has not happened"
```

---

## Task 2: The Add sheet's default

**Files:**
- Modify: `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/AddTransactionSheet.swift` (`:52` date, `:58` status, `:335` picker)

**Context:** the sheet opens on `Date()`, so the rule almost never fires at open — it fires when the user moves the date. That is why this is a reactive rule, not a seeded default.

- [ ] **Step 1: Add the latch and the rule**

Beside the existing `@State private var status: Entries.Status = .confirmed`:

```swift
    /// Set once the user picks a Status by hand, after which the date stops driving it.
    ///
    /// Without this the sheet argues with the person using it: choose Confirmed on a
    /// future date (recording something paid in advance), nudge the date, and the app
    /// silently undoes the choice.
    @State private var statusTouched = false
```

On the date field, `.onChange(of: date)`:

```swift
        .onChange(of: date) { _, newDate in
            // Day-granular on purpose: dinner tonight at 19:00 entered at 15:00 is
            // TODAY, and confirming it is correct. Comparing timestamps would flip the
            // status on a five-minute nudge.
            guard !statusTouched else { return }
            status = FinchStore.isoDay(newDate) > store.wallToday ? .pending : .confirmed
        }
```

On the Status picker (`:335`), set the latch when the user changes it:

```swift
        .onChange(of: status) { _, _ in statusTouched = true }
```

**Order matters and is a trap.** The rule above ALSO assigns `status`, which fires the picker's `onChange` and latches immediately, freezing the rule after one use. Guard it — e.g. set a `suppressLatch` flag around the programmatic assignment, or drive the latch from the picker's own action rather than `onChange(of: status)`. **Verify by test, not by reading:** step 2's third case fails if this is wrong.

`FinchStore.isoDay` is the same helper `wallToday` uses; confirm its name and access level before calling it.

- [ ] **Step 2: Verify on the simulator**

There is no unit test for a SwiftUI `@State` rule, so this is a UI test or a hand check of exactly three cases:

1. Open Add, set the date to next month → Status shows **Pending**.
2. Set the date back to today → Status shows **Confirmed**.
3. Open Add, tap **Pending** by hand, then move the date to next month **and back to today** → Status stays **Pending** both times.

Case 3 is the one that catches the latch bug above.

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(ios): a future-dated transaction starts pending"
```

---

## Task 3: The two Activity feeds

**Files:**
- `ios/FinchApp/Sources/FinchAppSwiftUI/Tabs/ActivityTab.swift` (`:304` filter, `:141` section)
- `ios/FinchApp/Sources/FinchAppUIKit/ActivityFeedVC.swift` (`:504`–`:507`)

- [ ] **Step 1: SwiftUI side**

Replace the local filter at `:304`:

```swift
        let split = Selectors.pendingSplit(f, today: store.wallToday)
        pendingTxns = TxSort.dateDesc.sorted(split.dueNow)
        upcomingTxns = TxSort.dateDesc.sorted(split.upcoming)
        let confirmed = f.filter { $0.pending != true }
```

Add `@State private var upcomingTxns: [Tx] = []` beside `pendingTxns` (`:72`), and a section after the To-confirm one:

```swift
                    if !upcomingTxns.isEmpty {
                        Section("Upcoming (\(upcomingTxns.count))") {
                            ForEach(upcomingTxns) { txn in row(txn) }
                        }
                    }
```

Use the SAME row builder as the To-confirm section — do not fork it.

- [ ] **Step 2: UIKit side**

`ActivityFeedVC` already has a `.pending` section. Add `.upcoming` to its `SectionID`, order it directly after `.pending`, and populate both from one `pendingSplit` call. Header: `String(localized: "Upcoming (\(upcoming.count))")`.

- [ ] **Step 3: Verify both** — run with `-uikitActivity YES` and `NO`. The two must show the same grouping; that dual run is what `NavigationUITests` exists to protect.

- [ ] **Step 4: Commit**

---

## Task 4: The five detail screens

**Files:** `AccountDetailView.swift:311`, `AccountDetailVC.swift:504`, `TxListDetailVC.swift`, `CategoryDetailView.swift:37`, `TagDetailView.swift`, `CounterpartyDetailView.swift:29`

Each does its own `filter { $0.pending == true }`. Each becomes one `pendingSplit` call plus an Upcoming section modelled on Task 3.

**`AccountDetailVC` also computes `confirmed` as `pending != true`** (`:505`). Leave that alone — upcoming rows are still pending, so they must not fall into the confirmed list as well.

- [ ] **Step 1** Convert each screen, one commit per pair (SwiftUI + its UIKit counterpart) so a regression bisects to one screen.
- [ ] **Step 2** After each, check the screen renders both buckets with seeded data.

---

## Task 5: Reconcile excludes upcoming

**Files:** `ios/FinchApp/Sources/FinchAppSwiftUI/WriteScreens/ReconcileSheet.swift:178`

Reconciling is matching against a bank statement. Something that has not happened cannot be on one, so upcoming rows are **dropped entirely** — no second section:

```swift
        // Upcoming rows are excluded, not grouped: you reconcile against a statement,
        // and a transaction dated next month cannot appear on one. Showing them here
        // would invite ticking something the bank has never seen.
        let pending = Selectors.pendingSplit(store.transactions(for: a.id),
                                             today: store.wallToday).dueNow
```

Check `:114` too — it takes `pending != true` for the confirmed side; that stays as-is.

- [ ] **Commit**

---

## Task 6: Strings, gate, PR

- [ ] **Step 1** Add `"Upcoming"` to `ios/scripts/zh-manual.json` (suggest `即将到来`), then:

```bash
cd ios && bun run scripts/build-xcstrings.ts
```

If the key does not appear, the extractor needs a fresh export — see how `extracted-keys.json` is produced in `ci-local.sh` step "i18n - extracted keys are current" and re-run that first. **Commit the catalog**: guard 1 diffs against HEAD.

Note the section titles interpolate a count, so the key is a format string — match how `"To confirm (%lld)"` is already stored rather than inventing a shape.

- [ ] **Step 2** Rebase, then `./scripts/ci-local.sh --ui` → `gate passed`.

- [ ] **Step 3** Push, PR against `feat/frontend`.

---

## Deliberately out of scope

- **Edit sheet** — see File Structure.
- **Scheduled templates** — a separate mechanism that posts on its date; unaffected.
- **Auto-confirming on the day** — nothing flips a status. An upcoming row becomes due-now because the split is computed against today, which is why no migration or background job is needed.
- **The web** — will keep one combined bucket. No parity fixture covers this selector, so nothing turns red; the divergence is accepted.

## Self-review notes

- Task 2's latch is the only genuinely tricky code here, and its failure mode is silent (the rule works once, then stops). Case 3 of Step 2 exists solely to catch it.
- The `>` boundary is asserted twice on purpose (`testTodayIsNotUpcoming`, `testPastAndTodayArePendingNow`); `>=` is the obvious slip and would make everything entered today unconfirmable.
- Seven screens is a lot of near-identical edits. They are grouped into commits by screen pair rather than done in one, so a regression bisects.
