# Privacy-Mode Calendar Dots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When privacy mode is on, each day cell of the month calendar shows presence dots — green for income, red for spending — instead of going completely blank.

**Architecture:** One shared SwiftUI component, `Common/MonthCashCalendar.swift`, is edited; its three hosting screens each pass one new `masked: store.privacyMode` argument. The masked/unmasked decision is extracted into a pure static `marks(income:expense:masked:)` function so it can be unit-tested without a view, following the repo's `SplitVisibilityMapping` pattern.

**Tech Stack:** Swift 5.9+, SwiftUI, XCTest, XcodeGen, Bun (localization pipeline only).

**Design spec:** `ios/docs/privacy-calendar-dots-design-2026-07-31.md`

## Global Constraints

- **Working directory is `/private/tmp/finch-wren/ios`** (a git worktree on branch `feat/ios-privacy-calendar-dots`). Do not `cd` to the original repo root.
- **Prefix every `xcodebuild` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`** — `xcode-select -p` points at CommandLineTools on this machine.
- **`FinchApp.xcodeproj` is generated and git-ignored.** Run `xcodegen generate` after adding any new file under `FinchApp/Sources/` or `FinchApp/Tests/` — new files do not enter the project otherwise.
- **The code must compile for macOS too.** `FinchMac` shares these exact sources. No iOS-only API in `MonthCashCalendar.swift` outside an existing `#if os(iOS)` block.
- **Deployment floor is iOS 17 / macOS 14 / watchOS 10.** No newer-OS-only API.
- **Privacy OFF must stay pixel-identical.** The amount-line stack keeps `spacing: 0`; the fixed 32pt slot keeps its height; `gridHeight` and `cellHeight(rows:)` are not touched.
- **Never render an amount while masked.** No `••••` masks either — dots or nothing.
- **User-facing strings must be `LocalizedStringKey`,** i.e. a literal inside `Text("…")`. Never hand-edit `Resources/Localizable.xcstrings` — it is generated (see Task 3).
- **Use `Text(verbatim:)` for non-localizable text** so it stays out of the extracted key set.
- **Commit messages: no `Co-Authored-By` trailer.** This repo omits it.
- **This session's simulator is `ios-finch-wren`.** Never boot, install to, or reset any other simulator — other sessions own theirs (`ios-finch5` is currently booted and is not yours).

---

### Task 1: The pure `marks` decision function

**Files:**
- Create: `FinchApp/Tests/FinchAppTests/MonthCashCalendarMarksTests.swift`
- Modify: `FinchApp/Sources/FinchApp/Common/MonthCashCalendar.swift` (add nested `Mark` enum + `marks` static function near the existing `weekRows` / `cellHeight` statics, around line 178-191)
- Modify: `FinchApp/Tests/FinchAppTests/PrivacyModeTests.swift` (add one test at the end, before the closing brace)

**Interfaces:**
- Consumes: nothing (first task).
- Produces:
  - `MonthCashCalendar.Mark` — `enum Mark: Hashable { case income, expense }`
  - `MonthCashCalendar.marks(income: Double, expense: Double, masked: Bool) -> [MonthCashCalendar.Mark]` — returns `[]` when `masked` is false; otherwise `.income` and/or `.expense` for whichever value is `> 0`, income always first.

- [ ] **Step 1: Create this session's simulator (skip if it already exists)**

```bash
xcrun simctl list devices | grep -q "ios-finch-wren" \
  || xcrun simctl create ios-finch-wren com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
```

- [ ] **Step 2: Write the failing test**

Create `FinchApp/Tests/FinchAppTests/MonthCashCalendarMarksTests.swift`:

```swift
import XCTest
@testable import FinchApp

/// The privacy-mode day-cell decision: which presence dots a cell draws.
/// `MonthCashCalendar` is shared by Scheduled, Activity and Account detail,
/// so this one function is the guard for all three.
final class MonthCashCalendarMarksTests: XCTestCase {
    // Privacy OFF: the cell draws real amount lines, so it must never ask for
    // dots — not even on a busy day.
    func test_unmasked_isAlwaysEmpty() {
        XCTAssertEqual(MonthCashCalendar.marks(income: 1850, expense: 42.10, masked: false), [])
        XCTAssertEqual(MonthCashCalendar.marks(income: 0, expense: 0, masked: false), [])
    }

    func test_masked_quietDayHasNoDots() {
        XCTAssertEqual(MonthCashCalendar.marks(income: 0, expense: 0, masked: true), [])
    }

    func test_masked_incomeOnly() {
        XCTAssertEqual(MonthCashCalendar.marks(income: 1850, expense: 0, masked: true), [.income])
    }

    func test_masked_expenseOnly() {
        XCTAssertEqual(MonthCashCalendar.marks(income: 0, expense: 42.10, masked: true), [.expense])
    }

    // Order is fixed: income dot sits above the expense dot.
    func test_masked_bothKeepsIncomeFirst() {
        XCTAssertEqual(MonthCashCalendar.marks(income: 1850, expense: 42.10, masked: true),
                       [.income, .expense])
    }

    // Presence ONLY. A one-cent day and a ten-thousand day must be
    // indistinguishable — magnitude is exactly what privacy mode hides.
    func test_masked_magnitudeNeverLeaks() {
        XCTAssertEqual(MonthCashCalendar.marks(income: 0.01, expense: 0, masked: true),
                       MonthCashCalendar.marks(income: 10_000, expense: 0, masked: true))
        XCTAssertEqual(MonthCashCalendar.marks(income: 0, expense: 0.01, masked: true),
                       MonthCashCalendar.marks(income: 0, expense: 10_000, masked: true))
    }
}
```

- [ ] **Step 3: Add the missing `displayExactBase` guard to `PrivacyModeTests.swift`**

The calendar leans on this returning nil, and nothing currently tests it. Insert before the final closing brace of `final class PrivacyModeTests`:

```swift
    // The calendar cells' formatter — nil under privacy is the contract the
    // month grid depends on to swap amount lines for presence dots.
    func test_displayExactBase_nilUnderPrivacy_realFigureWhenOff() {
        let store = FinchStore()
        XCTAssertNotNil(store.displayExactBase(1234.5))
        XCTAssertTrue(store.displayExactBase(1234.5)?.contains("1") ?? false)
        store.privacyMode = true
        XCTAssertNil(store.displayExactBase(1234.5))
    }
```

- [ ] **Step 4: Regenerate the Xcode project so the new test file is compiled**

```bash
cd /private/tmp/finch-wren/ios && xcodegen generate
```

Expected: `Created project at /private/tmp/finch-wren/ios/FinchApp.xcodeproj`

- [ ] **Step 5: Run the tests to verify they fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-wren' \
  -only-testing:FinchAppTests/MonthCashCalendarMarksTests 2>&1 | tail -30
```

Expected: **compile failure**, `type 'MonthCashCalendar' has no member 'marks'`. That counts as red — the test cannot run until the function exists.

- [ ] **Step 6: Write the minimal implementation**

In `Common/MonthCashCalendar.swift`, directly above the existing `/// Week rows a month actually needs…` comment (near line 177), add:

```swift
    /// Income / expense presence for one day — privacy mode's stand-in for the
    /// amount lines. Presence only: never magnitude, never a count.
    enum Mark: Hashable { case income, expense }

    /// Which presence dots a day cell draws. Empty unless masked: an unmasked
    /// cell draws real amount lines and never dots. Income first — its dot sits
    /// above the expense one, mirroring the line order it replaces.
    static func marks(income: Double, expense: Double, masked: Bool) -> [Mark] {
        guard masked else { return [] }
        var out: [Mark] = []
        if income > 0 { out.append(.income) }
        if expense > 0 { out.append(.expense) }
        return out
    }
```

- [ ] **Step 7: Run both test classes to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-wren' \
  -only-testing:FinchAppTests/MonthCashCalendarMarksTests \
  -only-testing:FinchAppTests/PrivacyModeTests 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`, 6 + 5 tests passing.

- [ ] **Step 8: Commit**

```bash
git add FinchApp/Sources/FinchApp/Common/MonthCashCalendar.swift \
        FinchApp/Tests/FinchAppTests/MonthCashCalendarMarksTests.swift \
        FinchApp/Tests/FinchAppTests/PrivacyModeTests.swift
git commit -m "feat(ios): pure marks() decision for privacy-mode calendar dots

Presence only — masked cells map income/expense > 0 to at most two dots,
unmasked cells always get an empty list because they draw real amounts.
Also pins displayExactBase's nil-under-privacy contract, which the month
grid depends on and nothing tested."
```

---

### Task 2: Draw the dots and wire the three hosts

**Files:**
- Modify: `FinchApp/Sources/FinchApp/Common/MonthCashCalendar.swift` (add the `masked` property near `format` at line 20; rewrite the amounts slot inside `dayCell`, lines 225-251; add the `dot(_:)` view beside `amountLine`, line 256)
- Modify: `FinchApp/Sources/FinchApp/Tabs/ScheduledCalendarView.swift:57-61`
- Modify: `FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift:95-101`
- Modify: `FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift:177-183`

**Interfaces:**
- Consumes: `MonthCashCalendar.Mark`, `MonthCashCalendar.marks(income:expense:masked:)` from Task 1.
- Produces: `MonthCashCalendar` gains a required `let masked: Bool` property. Every construction site must pass it — there are exactly the three listed above.

- [ ] **Step 1: Add the `masked` property**

In `Common/MonthCashCalendar.swift`, directly below the existing `format` property (line 19-20):

```swift
    /// Formats a magnitude for a cell line; nil drops the line (privacy mode).
    let format: (Double) -> String?
    /// Privacy mode: cells trade their amount lines for presence dots. The
    /// caller owns the flag for the same reason it owns `format` — this view
    /// deliberately knows nothing about the store.
    let masked: Bool
```

- [ ] **Step 2: Rewrite the amounts slot in `dayCell`**

Replace the whole `dayCell` function (lines 225-251) with:

```swift
    private func dayCell(_ day: Int, iso d: String,
                         amounts: (income: Double, expense: Double)?, height: CGFloat) -> some View {
        let isSel = d == selectedDay, isToday = d == wallToday
        let marks = Self.marks(income: amounts?.income ?? 0,
                               expense: amounts?.expense ?? 0,
                               masked: masked)
        return VStack(spacing: 2) {
            // Today gets a filled accent circle (white number); other days plain.
            Text("\(day)")
                .font(.callout).fontWeight(isToday ? .semibold : .regular)
                .foregroundStyle(isToday ? Color.white : .primary)
                .frame(width: 26, height: 26)
                .background(isToday ? Color.accentColor : Color.clear, in: Circle())
            // Fixed-height two-line slot (rows align whether or not a day has
            // amounts). Privacy mode swaps the exact figures for presence dots
            // INSIDE the same slot — the grid must not shift when it toggles.
            Group {
                if masked {
                    VStack(spacing: 3) {
                        ForEach(marks, id: \.self) { dot($0) }
                    }
                } else if let a = amounts {
                    // Exact figures (cents only when non-zero), sign-prefixed;
                    // nil from `format` drops the line.
                    VStack(spacing: 0) {
                        if a.income > 0, let s = format(a.income) { amountLine("+" + s, .green) }
                        if a.expense > 0, let s = format(a.expense) { amountLine("−" + s, .red) }
                    }
                }
            }
            .frame(height: 32)
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .background(isSel ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { selectedDay = (selectedDay == d ? nil : d) }
    }
```

- [ ] **Step 3: Add the `dot` view**

In the same file, directly after the `amountLine` function (which ends at line 264):

```swift
    /// One presence dot — privacy mode's stand-in for an amount line. Fixed
    /// size on purpose: scaling it by amount would leak the magnitude the
    /// mask exists to hide.
    private func dot(_ mark: Mark) -> some View {
        Circle()
            .fill(mark == .income ? Color.green : Color.red)
            .frame(width: 6, height: 6)
    }
```

- [ ] **Step 4: Pass the flag from the Scheduled tab**

In `Tabs/ScheduledCalendarView.swift`, line 61, replace:

```swift
                    format: { store.displayExactBase($0) })
```

with:

```swift
                    format: { store.displayExactBase($0) },
                    masked: store.privacyMode)
```

- [ ] **Step 5: Pass the flag from the Activity tab**

In `Tabs/ActivityTab.swift`, line 101, replace:

```swift
                                format: { store.displayExactBase($0) })
```

with:

```swift
                                format: { store.displayExactBase($0) },
                                masked: store.privacyMode)
```

- [ ] **Step 6: Pass the flag from Account detail**

In `WriteScreens/AccountDetailView.swift`, line 183, replace:

```swift
                format: { store.displayExactBase($0) })
```

with:

```swift
                format: { store.displayExactBase($0) },
                masked: store.privacyMode)
```

- [ ] **Step 7: Build for the simulator**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-wren' 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`. A missing-argument error here means a construction site was missed — `rg -n "MonthCashCalendar\(" FinchApp/Sources` should list exactly the three above.

- [ ] **Step 8: Re-run the unit tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-wren' \
  -only-testing:FinchAppTests/MonthCashCalendarMarksTests \
  -only-testing:FinchAppTests/PrivacyModeTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 9: Commit**

```bash
git add FinchApp/Sources/FinchApp/Common/MonthCashCalendar.swift \
        FinchApp/Sources/FinchApp/Tabs/ScheduledCalendarView.swift \
        FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift \
        FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift
git commit -m "feat(ios): show presence dots on the calendar in privacy mode

The month grid went fully blank with privacy on — the amounts are the
secret, the shape of the month isn't. Masked cells now draw a green dot
for a day with income and a red one for a day with spending, stacked on
the day number's axis inside the existing 32pt slot so no row moves.

Scheduled, Activity and Account detail all inherit it from the one
shared component."
```

---

### Task 3: VoiceOver label for the dots

**Files:**
- Modify: `FinchApp/Sources/FinchApp/Common/MonthCashCalendar.swift` (add `marksLabel` beside `marks`; apply it in `dayCell`'s masked branch)
- Modify: `ios/scripts/extracted-keys.json` (regenerated, not hand-written)
- Modify: `FinchApp/Sources/FinchApp/Resources/Localizable.xcstrings` (regenerated, not hand-written)

**Interfaces:**
- Consumes: `MonthCashCalendar.Mark`, `MonthCashCalendar.marks(...)` from Task 1; the masked branch of `dayCell` from Task 2.
- Produces: `MonthCashCalendar.marksLabel(_ marks: [Mark]) -> Text?` — nil for an empty list.

Without this, a masked cell's only content is shapes, so VoiceOver reads a bare day number and the dots are silent.

- [ ] **Step 1: Add the label helper**

In `Common/MonthCashCalendar.swift`, directly after the `marks` function from Task 1:

```swift
    /// VoiceOver text for a masked cell. The dots are shapes — without this a
    /// screen reader would hear the day number and nothing else.
    static func marksLabel(_ marks: [Mark]) -> Text? {
        if marks == [.income, .expense] { return Text("Income and spending") }
        if marks == [.income] { return Text("Income") }
        if marks == [.expense] { return Text("Spending") }
        return nil
    }
```

Note `if marks == [...]` rather than a `switch` — Swift has no array patterns in `case`.

- [ ] **Step 2: Apply it to the masked branch**

In `dayCell`, replace the masked branch's `VStack` (from Task 2, Step 2) with:

```swift
                if masked {
                    VStack(spacing: 3) {
                        ForEach(marks, id: \.self) { dot($0) }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.marksLabel(marks) ?? Text(verbatim: ""))
                    .accessibilityHidden(marks.isEmpty)
                }
```

`Text(verbatim:)` keeps the empty fallback out of the extracted key set, and `accessibilityHidden` stops a quiet day becoming an empty VoiceOver stop.

- [ ] **Step 3: Build to confirm it compiles**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=ios-finch-wren' 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Regenerate the localization catalog**

Three new keys entered the source (`Income`, `Spending`, `Income and spending`). The catalog is generated — run all three stages from `ios/`:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -exportLocalizations -project FinchApp.xcodeproj -scheme FinchApp \
  -localizationPath /tmp/finch-loc -exportLanguage zh-Hans
bun run scripts/xliff-keys.ts > scripts/extracted-keys.json
bun run scripts/build-xcstrings.ts
```

- [ ] **Step 5: Confirm the three keys landed**

```bash
rg -n '"(Income|Spending|Income and spending)"' scripts/extracted-keys.json
```

Expected: all three present. If any is missing, the string is not reaching the compiler as a `LocalizedStringKey` — check it is a bare literal inside `Text("…")`, not a `String` variable.

- [ ] **Step 6: Verify the i18n guards pass**

```bash
git diff --stat scripts/extracted-keys.json FinchApp/Sources/FinchApp/Resources/Localizable.xcstrings
```

Expected: **both** files changed. Committing only one fails the CI guard. If `Localizable.xcstrings` did not change, re-run `bun run scripts/build-xcstrings.ts`.

- [ ] **Step 7: Commit**

```bash
git add FinchApp/Sources/FinchApp/Common/MonthCashCalendar.swift \
        scripts/extracted-keys.json \
        FinchApp/Sources/FinchApp/Resources/Localizable.xcstrings
git commit -m "feat(ios): VoiceOver label for the privacy calendar dots

The dots are plain shapes, so a masked cell would otherwise read as a
bare day number. Labels the dot stack with Income / Spending / Income and
spending, and hides it entirely on a quiet day so it isn't an empty stop.

Catalog and key set regenerated through the usual pipeline."
```

---

### Task 4: Verify on the simulator and against CI

**Files:** none modified — this task is verification, and any fix it turns up belongs in an amended Task 2 or 3 commit.

**Interfaces:**
- Consumes: everything from Tasks 1-3.
- Produces: evidence the feature works, and confirmation the branch is CI-clean.

- [ ] **Step 1: Build, install and launch on this session's simulator**

Use the **`ios-build-launch` skill**, targeting `ios-finch-wren`. Do not touch any other simulator.

**Drive this with launch arguments, not taps.** Foundation maps `-key value` launch args into
UserDefaults' argument domain (`FinchApp.swift:21-36`), so both the tab and privacy mode can be
set at launch. This matters: `idb` cannot reliably tap inside a SwiftUI `List(selection:)`, and
the Activity and Account-detail calendars both live in one. The **Scheduled tab defaults to its
calendar view** (`ScheduledTab.swift:14`), so it lands on a month grid with no interaction at
all — and it hosts the very same component.

Screenshots and traces go to the scratchpad, not the repo:

```bash
SHOT=/private/tmp/claude-501/-Users-blackmount8--repository-finch/1a3b651a-6da5-4210-b995-1f9556455cfc/scratchpad
```

**Shell variables do not survive between separate tool calls** — re-declare `SHOT` (and `UDID` in Step 5) at the top of each command block, or paste the literal path.

- [ ] **Step 2: Screenshot the calendar with privacy OFF**

```bash
xcrun simctl terminate ios-finch-wren com.juchengquan.finch 2>/dev/null
xcrun simctl launch ios-finch-wren com.juchengquan.finch -initialTab scheduled
sleep 3
xcrun simctl io ios-finch-wren screenshot "$SHOT/cal-privacy-off.png"
```

- [ ] **Step 3: Screenshot it with privacy ON**

`finch.privacy` is the UserDefaults key behind `store.privacyMode` (`FinchStore.swift:39`), and
the argument domain outranks the stored value — so this forces the masked state at launch
without touching the UI:

```bash
xcrun simctl terminate ios-finch-wren com.juchengquan.finch
xcrun simctl launch ios-finch-wren com.juchengquan.finch -initialTab scheduled -finch.privacy YES
sleep 3
xcrun simctl io ios-finch-wren screenshot "$SHOT/cal-privacy-on.png"
```

- [ ] **Step 4: Read both screenshots and check them against the success criteria**

Open both with the Read tool and confirm:
1. Privacy on: days with income show a green dot, days with spending a red one, days with both show green above red, quiet days are empty.
2. The dots sit on the day number's vertical axis, not offset left or right.
3. No amount, anywhere in the grid, while privacy is on.
4. Privacy off: the grid looks exactly as it did before this branch.

- [ ] **Step 5: Measure that no row moved**

Eyeballing has produced confidently wrong conclusions in this codebase before (#554, #563). Measure instead. Capture the accessibility tree in **both** states and diff the frames:

```bash
UDID=$(xcrun simctl list devices | grep "ios-finch-wren" | grep -oE '[0-9A-F]{8}-[0-9A-F-]{27}')

xcrun simctl terminate "$UDID" com.juchengquan.finch
xcrun simctl launch "$UDID" com.juchengquan.finch -initialTab scheduled
sleep 3
~/.local/idb-venv/bin/idb ui describe-all --udid "$UDID" > "$SHOT/tree-off.txt"

xcrun simctl terminate "$UDID" com.juchengquan.finch
xcrun simctl launch "$UDID" com.juchengquan.finch -initialTab scheduled -finch.privacy YES
sleep 3
~/.local/idb-venv/bin/idb ui describe-all --udid "$UDID" > "$SHOT/tree-on.txt"

grep -oE '"AXFrame": "[^"]*"' "$SHOT/tree-off.txt" | sort | uniq -c > "$SHOT/frames-off.txt"
grep -oE '"AXFrame": "[^"]*"' "$SHOT/tree-on.txt"  | sort | uniq -c > "$SHOT/frames-on.txt"
diff "$SHOT/frames-off.txt" "$SHOT/frames-on.txt"
```

The day-cell frames must be identical across the two — the 32pt slot does not grow, so no row moves. Frames that differ should only be the amount-line labels disappearing, never a cell or row geometry change.

If `describe-all` returns nothing or hangs, the accessibility tree has wedged (a known trap after an XCUITest run) — `xcrun simctl shutdown "$UDID" && xcrun simctl boot "$UDID"` and retry.

- [ ] **Step 6: Run the full local CI**

```bash
cd /private/tmp/finch-wren && git fetch origin feat/frontend && git rebase origin/feat/frontend
cd ios && ./scripts/ci-local.sh
```

Expected: green. The rebase is not optional — CI builds your branch merged into `feat/frontend`, so a branch that is behind can pass locally and fail in CI on code it does not own.

- [ ] **Step 7: Report results**

State plainly what passed and what did not, and paste the failing output if anything is red. Do not claim the feature works without having read the two screenshots.

---

## Notes for the implementer

- **The whole feature is ~25 lines of Swift.** If a task starts sprawling into other files, stop — something has been misread.
- **`store.wallToday` vs `store.today`** are different on purpose (see `ios/CLAUDE.md`). This change touches neither.
- **Do not "improve" the Insights heatmap** (`Common/ChartViews/CalendarHeatmap.swift`) while you are here. It has a real privacy gap and it is deliberately a separate follow-up.
- **Do not tighten `internal` members** in `FinchStore` or this component. The encapsulation boundary in this repo is the module, not the type.
