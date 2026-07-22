# Month-sectioned account transactions — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the account-detail transaction list into month sections (like the Activity feed),
extract the feed's inline month-grouping into one shared tested helper, and add per-month header
figures — net change on both surfaces, plus the account's end-of-month balance on account detail.

**Architecture:** A new pure `MonthGrouping` helper (app-level, unit-tested) owns the
`[Tx] → month sections` transform, the month label, and the net-change sum. `ActivityTab` is
refactored onto it (behavior-preserving) and gains a net figure in its month headers.
`AccountDetailView` month-sections its confirmed transactions behind the same
`finch.feed.groupByMonth` toggle, with `net · end-of-month balance` headers (the balance reuses the
existing `store.runningBalanceBase` cache — the newest row of a date-descending month section *is*
the end-of-month balance).

**Tech Stack:** Swift 6 / SwiftUI, XCTest (`FinchAppTests`), the `FinchCore` `Tx` projection type.

**Design doc:** `plans/ios-macos/2026-07-22-account-month-sections-design.md`

## Global Constraints

- **Honor the shared toggle** `@AppStorage("finch.feed.groupByMonth")` (default `true`). Off ⇒ both
  surfaces render flat exactly as today.
- **`MonthGrouping` is pure** — operates on `[Tx]`, no store / `Date()` / I/O — so it is unit-tested.
- **Figures use `store.displayMoneyBase(...)`** (base→display, privacy-aware). `Tx.amount` is already
  in ledger base.
- **Pending stays ungrouped**; account rows keep their per-row date (`TxRow` defaults unchanged);
  scope is the feed + account detail only.
- **Build both** `FinchApp` (simulator) and `FinchMac`; `xcodegen generate` after adding the new
  file; `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- **Never call `Money.format` in a view** — use the `store.display*` helpers.
- **Do not drive the simulator** during implementation — build + run the test suites; on-device
  verification is done by the controller afterward.

---

### Task 1: The shared `MonthGrouping` helper + unit tests

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Common/MonthGrouping.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/MonthGroupingTests.swift`

**Interfaces:**
- Produces:
  - `MonthGrouping.Section` — `struct Section: Identifiable { let id: String; let txns: [Tx] }`
    (`id` is the `"yyyy-MM"` key).
  - `MonthGrouping.sections(_ txns: [Tx]) -> [Section]` — order-preserving month grouping.
  - `MonthGrouping.label(_ key: String) -> String` — `"2026-09"` → `"September 2026"`.
  - `MonthGrouping.net(_ txns: [Tx]) -> Double` — sum of base amounts.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchApp/Tests/FinchAppTests/MonthGroupingTests.swift`:

```swift
import XCTest
@testable import FinchApp
import FinchCore

final class MonthGroupingTests: XCTestCase {
    private func tx(_ id: String, _ date: String, amount: Double = -10) -> Tx {
        Tx(id: id, merchant: "m", amount: amount, account: "a", date: date)
    }

    func test_sections_groupByMonth_preservingOrder() {
        // date-descending input across two months
        let input = [tx("1", "2026-09-20"), tx("2", "2026-09-05"), tx("3", "2026-08-31")]
        let s = MonthGrouping.sections(input)
        XCTAssertEqual(s.map(\.id), ["2026-09", "2026-08"])        // newest month first, order preserved
        XCTAssertEqual(s[0].txns.map(\.id), ["1", "2"])
        XCTAssertEqual(s[1].txns.map(\.id), ["3"])
    }

    func test_sections_singleMonth_oneSection() {
        let s = MonthGrouping.sections([tx("1", "2026-09-20"), tx("2", "2026-09-01")])
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].id, "2026-09")
    }

    func test_sections_empty_isEmpty() {
        XCTAssertTrue(MonthGrouping.sections([]).isEmpty)
    }

    func test_label_wideMonthAndYear() {
        // en locale renders the wide month + year; assert the year is present and it isn't the raw key
        let out = MonthGrouping.label("2026-09")
        XCTAssertTrue(out.contains("2026"))
        XCTAssertNotEqual(out, "2026-09")
    }

    func test_label_malformedKey_returnsKey() {
        XCTAssertEqual(MonthGrouping.label("not-a-date"), "not-a-date")
    }

    func test_net_sumsSignedBaseAmounts() {
        let s = MonthGrouping.net([tx("1", "2026-09-01", amount: -54.20),
                                   tx("2", "2026-09-02", amount: 3200)])
        XCTAssertEqual(s, 3145.80, accuracy: 0.001)
    }

    func test_net_empty_isZero() {
        XCTAssertEqual(MonthGrouping.net([]), 0)
    }
}
```

- [ ] **Step 2: Run the tests, confirm they fail**

Run: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && cd ios && xcodegen generate && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination "id=$UDID" -only-testing:FinchAppTests/MonthGroupingTests`
Expected: FAIL to compile — `cannot find 'MonthGrouping' in scope`.
(`$UDID` = this session's simulator; resolve via `xcrun simctl list devices | grep "<sim name>"`.)

- [ ] **Step 3: Implement the helper**

Create `ios/FinchApp/Sources/FinchApp/Common/MonthGrouping.swift`:

```swift
import Foundation
import FinchCore

/// Groups a transaction list into month sections for the Activity feed and the
/// account-detail list. Pure (no store / clock / I/O) so it is unit-tested; both
/// surfaces call it, so the grouping lives in exactly one place.
enum MonthGrouping {
    struct Section: Identifiable {
        let id: String        // "yyyy-MM"
        let txns: [Tx]
    }

    /// Group `txns` into month sections, preserving input order (callers pass
    /// date-descending, so newest month comes first). Key is the `yyyy-MM` prefix
    /// of the ISO date string — no calendar math, so it's timezone-independent.
    static func sections(_ txns: [Tx]) -> [Section] {
        var order: [String] = []
        var byMonth: [String: [Tx]] = [:]
        for t in txns {
            let key = String(t.date.prefix(7))        // "yyyy-MM"
            if byMonth[key] == nil { order.append(key) }
            byMonth[key, default: []].append(t)
        }
        return order.map { Section(id: $0, txns: byMonth[$0] ?? []) }
    }

    /// "2026-09" -> "September 2026" (device locale, wide month). Returns the key
    /// unchanged if it doesn't parse.
    static func label(_ key: String) -> String {
        guard let d = AppDate.isoDay.date(from: "\(key)-01") else { return key }
        return d.formatted(.dateTime.month(.wide).year())
    }

    /// Net change of a month's transactions, in ledger-base amount (`Tx.amount` is
    /// base). Callers format with `store.displayMoneyBase`.
    static func net(_ txns: [Tx]) -> Double {
        txns.reduce(0) { $0 + $1.amount }
    }
}
```

- [ ] **Step 4: Run the tests, confirm they pass**

Run: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && cd ios && xcodegen generate && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination "id=$UDID" -only-testing:FinchAppTests/MonthGroupingTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Common/MonthGrouping.swift \
        ios/FinchApp/Tests/FinchAppTests/MonthGroupingTests.swift
git commit -m "feat(ios): shared, tested MonthGrouping helper for transaction month sections"
```

---

### Task 2: Refactor `ActivityTab` onto the helper + net figure in feed headers

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift` (`sections` state ~71, `DaySection`
  decl ~78, list body ~110-112, `monthLabel` ~242-246, `recompute` grouping ~253-260)

**Interfaces:**
- Consumes: `MonthGrouping.Section`, `MonthGrouping.sections`, `MonthGrouping.label`,
  `MonthGrouping.net` (Task 1).

This is a behavior-preserving refactor (the grouping code is a verbatim lift) **plus** one visible
change: the month headers gain a net figure. No new unit test — verified by the existing
`FinchAppTests` staying green and both targets building.

- [ ] **Step 1: Point the `sections` state at the shared type; delete `DaySection`**

At `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift:71`, change:

```swift
    @State private var sections: [DaySection] = []
```
to:
```swift
    @State private var sections: [MonthGrouping.Section] = []
```

Delete the local declaration at line 78:
```swift
    struct DaySection: Identifiable { let id: String; let txns: [Tx] }
```

- [ ] **Step 2: Replace the inline grouping in `recompute()`**

In `recompute()` (~253-260), replace:

```swift
        var order: [String] = []
        var byMonth: [String: [Tx]] = [:]
        for txn in f.prefix(visibleCount) {
            let key = String(txn.date.prefix(7))           // "yyyy-MM"
            if byMonth[key] == nil { order.append(key) }
            byMonth[key, default: []].append(txn)
        }
        sections = order.map { DaySection(id: $0, txns: byMonth[$0] ?? []) }
```
with:
```swift
        sections = MonthGrouping.sections(Array(f.prefix(visibleCount)))
```

The `dateShownIds` loop that follows it stays unchanged (it is the feed's per-day date de-dup, a
separate concern).

- [ ] **Step 3: Replace the private `monthLabel` with the shared label + add the net figure**

Delete the private helper (~242-246):
```swift
    private func monthLabel(_ key: String) -> String {
        guard let d = AppDate.isoDay.date(from: "\(key)-01") else { return key }
        return d.formatted(.dateTime.month(.wide).year())
    }
```

In the list body (~110-112), replace:
```swift
                    if groupByMonth {
                        ForEach(sections) { section in
                            Section(monthLabel(section.id)) {
                                ForEach(section.txns) { txn in row(txn) }
                            }
                        }
```
with:
```swift
                    if groupByMonth {
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.txns) { txn in row(txn) }
                            } header: {
                                HStack {
                                    Text(MonthGrouping.label(section.id)).textCase(nil)
                                    Spacer()
                                    Text(store.displayMoneyBase(MonthGrouping.net(section.txns)))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
```

(The `else` flat branch below it is unchanged.)

- [ ] **Step 4: Build + run the full `FinchAppTests`**

Run:
```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild -project FinchApp.xcodeproj -scheme FinchApp -destination "id=$UDID" build
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS'
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination "id=$UDID" -only-testing:FinchAppTests
```
Expected: both builds succeed; `FinchAppTests` all pass (no reference to `DaySection`/`monthLabel`
remains — grep to confirm: `grep -rn "DaySection\|monthLabel" ios/FinchApp/Sources` returns
nothing).

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift
git commit -m "refactor(ios): feed uses shared MonthGrouping; month headers show net change"
```

---

### Task 3: Month-section `AccountDetailView` with `net · end-balance` headers

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift`
  (add `@AppStorage`; `transactionsSection(_:)` confirmed branch ~151-158)

**Interfaces:**
- Consumes: `MonthGrouping.sections`, `MonthGrouping.label`, `MonthGrouping.net` (Task 1);
  `store.displayMoneyBase(_:)`, `store.runningBalanceBase(for:)` (existing).

- [ ] **Step 1: Add the shared toggle**

Add to `AccountDetailView`'s stored properties (near the other `@State`/`@AppStorage`, e.g. just
below the view's `@EnvironmentObject private var store`):

```swift
    @AppStorage("finch.feed.groupByMonth") private var groupByMonth = true
```

- [ ] **Step 2: Month-section the confirmed transactions**

In `transactionsSection(_:)`, replace the confirmed `Section` (~151-158):

```swift
        Section("Transactions") {
            if confirmed.isEmpty {
                Text("No transactions").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(confirmed, id: \.id) { t in txRow(t) }
            }
        }
```
with:
```swift
        if confirmed.isEmpty {
            Section("Transactions") {
                Text("No transactions").font(.caption).foregroundStyle(.secondary)
            }
        } else if groupByMonth {
            ForEach(MonthGrouping.sections(confirmed)) { section in
                Section {
                    ForEach(section.txns, id: \.id) { t in txRow(t) }
                } header: {
                    HStack {
                        Text(MonthGrouping.label(section.id)).textCase(nil)
                        Spacer()
                        // net change · this account's balance at the end of the month.
                        // The section is date-descending, so its first (newest) row's
                        // running balance IS the end-of-month balance — same cache the
                        // row shows, so header and row agree exactly.
                        Text(store.displayMoneyBase(MonthGrouping.net(section.txns))
                             + "  ·  "
                             + store.displayMoneyBase(store.runningBalanceBase(for: section.txns.first!)))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Section("Transactions") {
                ForEach(confirmed, id: \.id) { t in txRow(t) }
            }
        }
```

The pending `Section("To confirm (\(pending.count))")` above it is unchanged, and `txRow(_:)` is
unchanged (keeps the per-row date + running balance).

- [ ] **Step 3: Build both targets**

Run:
```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild -project FinchApp.xcodeproj -scheme FinchApp -destination "id=$UDID" build
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS'
```
Expected: both succeed.

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift
git commit -m "feat(ios): account detail groups transactions by month with net·balance headers"
```

---

## Controller verification (after Task 3, before the PR)

On the session's simulator (`idb` / screenshots — controller only):

- Account detail, toggle **on**: confirmed transactions render under month headers; each header
  shows `net · bal`, and `bal` equals the newest row's running-balance line in that section.
- Settings › Appearance toggle **off**: account detail and the feed both render flat (no headers,
  no figures).
- A **foreign-currency** account: header figures are in display currency (masked under privacy mode).
- The **Activity feed**: month headers now show the net figure; existing per-day date de-dup and
  pagination still work.
- A month with **only pending** items produces no confirmed section for it (pending shows in its
  own bucket).
