# Feed display prefs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Checkbox steps.

**Goal:** Two Settings toggles — Group by month + Relative dates — that the activity feed honors.

**Architecture:** Two `@AppStorage` prefs (default on); a Settings "Activity feed" section; `ActivityFeedView` month-buckets + grouped/flat render; `TxRow` honors the relative-dates pref. UI-only.

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-27-feed-display-prefs-design.md`.

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS). No `Co-Authored-By`. No engine change. PR → `feat/frontend`.
- `ActivityTab.swift` is an actively-edited file — keep edits to the listed blocks; **re-check `gh pr list --base feat/frontend --state open` before pushing**.

---

### Task 1: Settings toggles

**Files:** Modify `ios/FinchApp/Sources/FinchApp/Tabs/SettingsAppearanceView.swift`

- [ ] **Step 1:** Add the two prefs to `SettingsAppearanceView` (next to the existing `@AppStorage`):

```swift
    @AppStorage("finch.feed.groupByMonth") private var groupByMonth = true
    @AppStorage("finch.feed.relativeDates") private var relativeDates = true
```

- [ ] **Step 2:** Add an "Activity feed" `Section` in the `List`, immediately **before** the `.navigationTitle("Appearance & Language")`:

```swift
            Section("Activity feed") {
                Toggle("Group by month", isOn: $groupByMonth)
                Toggle("Relative dates", isOn: $relativeDates)
            }
```

- [ ] **Step 3: Build iOS + macOS** (commands in Task 2 Step 5 — or build now). Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/SettingsAppearanceView.swift
git commit -m "feat(ios): Settings — Activity feed toggles (group by month, relative dates)"
```

---

### Task 2: Feed honors the prefs

**Files:** Modify `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift`

- [ ] **Step 1: `ActivityFeedView` reads the group pref + a month-label helper**

Add the pref to `struct ActivityFeedView` (near the other `@AppStorage`/`@State`):

```swift
    @AppStorage("finch.feed.groupByMonth") private var groupByMonth = true
```
Add a helper (near `recompute()`):

```swift
    private func monthLabel(_ key: String) -> String {
        guard let d = AppDate.isoDay.date(from: "\(key)-01") else { return key }
        return d.formatted(.dateTime.month(.wide).year())
    }
```

- [ ] **Step 2: Month-bucket in `recompute()`**

Replace the day-bucket loop:

```swift
        var order: [String] = []
        var byDay: [String: [Tx]] = [:]
        for txn in f.prefix(visibleCount) {
            if byDay[txn.date] == nil { order.append(txn.date) }
            byDay[txn.date, default: []].append(txn)
        }
        sections = order.map { DaySection(id: $0, txns: byDay[$0] ?? []) }
```
with:

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

- [ ] **Step 3: Conditional render**

Replace the flat render:

```swift
                    ForEach(sections.flatMap { $0.txns }) { txn in
                        row(txn)
                    }
```
with:

```swift
                    if groupByMonth {
                        ForEach(sections) { section in
                            Section(monthLabel(section.id)) {
                                ForEach(section.txns) { txn in row(txn) }
                            }
                        }
                    } else {
                        ForEach(sections.flatMap { $0.txns }) { txn in row(txn) }
                    }
```

- [ ] **Step 4: Re-render on toggle**

After `.onChange(of: sort) { _, _ in recompute() }`, add:

```swift
        .onChange(of: groupByMonth) { _, _ in recompute() }
```

- [ ] **Step 5: `TxRow` honors the relative-dates pref**

In `struct TxRow`, add the pref (near `let txn`):

```swift
    @AppStorage("finch.feed.relativeDates") private var relativeDates = true
```
At the top of `relativeOrShort(_:)`, add the guard:

```swift
    private func relativeOrShort(_ ymd: String) -> String {
        guard relativeDates else { return ymd }
        guard let d = AppDate.isoDay.date(from: ymd) else { return ymd }
        ...
```
(Insert only the `guard relativeDates else { return ymd }` line as the first statement; leave the rest of the function unchanged.)

- [ ] **Step 6: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift
git commit -m "feat(ios): activity feed honors group-by-month + relative-dates prefs"
```

---

### Task 3: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Build to a known path + install** (avoid stale builds):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
cd ios && xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/fdp-dd >/dev/null 2>&1
xcrun simctl terminate "$SIM" com.juchengquan.finch 2>/dev/null
xcrun simctl install "$SIM" /tmp/fdp-dd/Build/Products/Debug-iphonesimulator/FinchApp.app
xcrun simctl launch "$SIM" com.juchengquan.finch -initialTab ledger
```
(Seed a few transactions across ≥2 months + recent days if the ledger is sparse — entry + 2 balanced postings, `exchange_rate=1`.)

- [ ] **Step 2: Verify**
  - **Default:** feed shows a **"June 2026"** month header, with **Today / Yesterday** rows under it. Screenshot `/tmp/fdp-default.png`.
  - Drive the toggles via `@AppStorage` if Settings nav is AX-flaky:
    `xcrun simctl spawn "$SIM" defaults write com.juchengquan.finch finch.feed.groupByMonth -bool NO` → relaunch → **flat, no month header**. Screenshot `/tmp/fdp-flat.png`.
    `defaults write … finch.feed.relativeDates -bool NO` → relaunch → rows show raw **`2026-06-25`**. Screenshot `/tmp/fdp-absolute.png`.
  - Clean up: `defaults delete` both keys, remove `/tmp/fdp-dd` + any seed.

- [ ] **Step 3 (no commit):** report; if a check fails, return to the relevant task.

---

## Self-review notes
- Spec coverage: Settings toggles + prefs (T1), month-bucket + grouped/flat render + label + onChange (T2 S1–4), TxRow relative-dates guard (T2 S5), build (T2 S6), manual incl. both toggles (T3). ✓
- Type consistency: `@AppStorage("finch.feed.groupByMonth"/"finch.feed.relativeDates")` keys match across Settings + feed + TxRow; `monthLabel(_:) -> String`; `DaySection` reused. ✓
- No engine change; `@AppStorage` re-renders live; `onChange(groupByMonth)` re-buckets. ✓
