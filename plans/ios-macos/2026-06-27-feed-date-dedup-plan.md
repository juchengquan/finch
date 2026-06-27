# Feed date de-dup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven). Checkbox steps.

**Goal:** In the Activity feed, show a row's date only when it differs from the row above.

**Architecture:** `TxRow` gains `showDate: Bool = true`; the feed computes the first txn of each same-date run and passes the flag. One file, no engine change.

Spec: `plans/ios-macos/2026-06-27-feed-date-dedup-design.md`.

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS) — both `** BUILD SUCCEEDED **`. No `Co-Authored-By`. No engine change. PR → `feat/frontend`.
- `ActivityTab.swift` is actively edited — keep edits to the listed spots; **re-check `gh pr list` + rebase before pushing**.

---

### Task 1: Suppress the repeated date

**Files:** Modify `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift`

- [ ] **Step 1 — `TxRow` flag.** In `struct TxRow` (line ~434), after `var onPreviewReceipt: ((Tx) -> Void)? = nil` (~line 438), add:

```swift
    var showDate: Bool = true
```

- [ ] **Step 2 — gate the date text.** Change the bottom-line date (line ~505):

```swift
                    Text(dateTimeText).font(.caption2).foregroundStyle(.secondary)
```
to:

```swift
                    if showDate { Text(dateTimeText).font(.caption2).foregroundStyle(.secondary) }
```
(Leave the `ForEach(rowTags…)` and `+N` siblings in the same `HStack` unchanged.)

- [ ] **Step 3 — feed state.** Near `@State private var sections: [DaySection] = []` (line ~77), add:

```swift
    @State private var dateShownIds: Set<String> = []
```

- [ ] **Step 4 — compute first-of-run** in `recompute()`. Immediately after `sections = order.map { DaySection(id: $0, txns: byMonth[$0] ?? []) }` (line ~286), add:

```swift
        var shown = Set<String>(); var last: String?
        for txn in sections.flatMap({ $0.txns }) {
            if txn.date != last { shown.insert(txn.id); last = txn.date }
        }
        dateShownIds = shown
```

- [ ] **Step 5 — pass the flag** in `row(_:)` (line ~320). Change:

```swift
                TxRow(txn: txn, onPreviewReceipt: isSelecting ? nil : { previewReceipt($0) })
```
to:

```swift
                TxRow(txn: txn, onPreviewReceipt: isSelecting ? nil : { previewReceipt($0) },
                      showDate: dateShownIds.contains(txn.id))
```

- [ ] **Step 6 — build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 7 — commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift
git commit -m "feat(ios): feed shows a row's date only when it changes (de-dup runs)"
```

---

### Task 2: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Build to a known path + install:**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
cd ios && xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/fdd-dd >/dev/null 2>&1
xcrun simctl list devices booted | grep -q "$SIM" || { xcrun simctl boot "$SIM"; open -a Simulator; sleep 5; }
xcrun simctl terminate "$SIM" com.juchengquan.finch 2>/dev/null
xcrun simctl install "$SIM" /tmp/fdd-dd/Build/Products/Debug-iphonesimulator/FinchApp.app
xcrun simctl launch "$SIM" com.juchengquan.finch -initialTab ledger
```
(The demo seed has multiple transactions on the same days — e.g. several on 2026-06-25. If the ledger is empty, uninstall→reinstall to re-seed.)

- [ ] **Step 2: Verify** — open the feed (Ledger → View all activity, or Accounts → All Transactions). For a day with multiple transactions, the **date shows on the first row only**; the following same-day rows omit it (any tag chips remain). Screenshot `/tmp/fdd-feed.png`. Clean up `/tmp/fdd-dd` after.

- [ ] **Step 3 (no commit):** report; if a check fails, return to Task 1.

---

## Self-review notes
- Spec coverage: `TxRow.showDate` (T1 S1–2), feed `dateShownIds` (S3–4), `row` passes flag (S5), build (S6), manual (T2). ✓
- Consistency: `showDate: Bool = true` default keeps AccountDetail/Counterparty unchanged; `dateShownIds` computed over `sections.flatMap{$0.txns}` (same order both render modes); compares raw `txn.date`. ✓
- No engine change. ✓
