# Relative/short feed row dates — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven). Checkbox steps.

**Goal:** Show Today / Yesterday / "Jun 25" on feed rows instead of the raw ISO date.

**Architecture:** Rewrite `TxRow.dateTimeText` + add a `relativeOrShort` helper. UI-only.

Spec: `plans/ios-macos/2026-06-26-relative-row-dates-design.md`.

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS). No `Co-Authored-By`. No engine change. PR → `feat/frontend`.
- `ActivityTab.swift` is actively edited — keep the diff to `TxRow`; **re-check `gh pr list --base feat/frontend --state open` before pushing**.

---

### Task 1: Relative/short `dateTimeText`

**Files:** Modify `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift`

- [ ] **Step 1:** Replace the `dateTimeText` computed:

```swift
    private var dateTimeText: String {
        if let t = txn.time, !t.isEmpty { return "\(txn.date) · \(t)" }
        return txn.date
    }
```
with:

```swift
    private var dateTimeText: String {
        let base = relativeOrShort(txn.date)
        if let t = txn.time, !t.isEmpty { return "\(base) · \(t)" }
        return base
    }

    private func relativeOrShort(_ ymd: String) -> String {
        guard let d = AppDate.isoDay.date(from: ymd) else { return ymd }
        let today = AppDate.isoDay.date(from: store.today) ?? Date()
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: today)).day ?? 0
        if days == 0 { return String(localized: "Today") }
        if days == 1 { return String(localized: "Yesterday") }
        let sameYear = cal.component(.year, from: d) == cal.component(.year, from: today)
        return d.formatted(sameYear ? .dateTime.month(.abbreviated).day()
                                    : .dateTime.month(.abbreviated).day().year())
    }
```
(Change nothing else — `body`, `recompute()`, the feed render, etc. stay.)

- [ ] **Step 2: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`. (If the `.formatted(.dateTime…)` ternary trips type inference, split into an `if sameYear { return d.formatted(.dateTime.month(.abbreviated).day()) } else { return d.formatted(.dateTime.month(.abbreviated).day().year()) }`.)

- [ ] **Step 3: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift
git commit -m "feat(ios): feed rows show relative/short dates (Today/Yesterday/Jun 25)"
```

---

### Task 2: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Build to a known path + install** (avoid stale builds):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
cd ios && xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/rd-dd >/dev/null 2>&1
xcrun simctl terminate "$SIM" com.juchengquan.finch 2>/dev/null
xcrun simctl install "$SIM" /tmp/rd-dd/Build/Products/Debug-iphonesimulator/FinchApp.app
xcrun simctl launch "$SIM" com.juchengquan.finch -initialTab ledger
```
(If the ledger lacks recent rows, seed a couple — one dated `store.today`, one the prior day, one older — entry + 2 balanced postings, `exchange_rate=1`.)

- [ ] **Step 2: Verify**
  - Feed rows show **Today** / **Yesterday** / **`Jun 23`** (relative/short) instead of `2026-06-23`; rows with a time show `… · HH:MM`.
  - Screenshot evidence to `/tmp/relative-dates.png`. Clean up `/tmp/rd-dd` + any seed after.

- [ ] **Step 3 (no commit):** report; if a check fails, return to Task 1.

---

## Self-review notes
- Spec coverage: `dateTimeText` + `relativeOrShort` (T1 S1), build (T1 S2), manual (T2). ✓
- Type consistency: `relativeOrShort(_ ymd: String) -> String`; uses `AppDate.isoDay`, `store.today`, `String(localized:)`, `Date.FormatStyle`. ✓
- Surgical (`TxRow` only); no engine/feed change. "Yesterday" zh = logged follow-up. ✓
