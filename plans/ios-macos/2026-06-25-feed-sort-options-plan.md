# Feed sort options — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a sort control (date / amount, each direction) to the transaction feed.

**Architecture:** A `TxSort` enum + `@State sort` in `ActivityFeedView`; `filteredTxns()` sorts the selector result in the view; a toolbar Sort menu. UI-only, no engine change.

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-25-feed-sort-options-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS).
- Commits: **no `Co-Authored-By` trailer**. No engine/parity changes. PR targets `feat/frontend`.

---

### Task 1: Feed sort options

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift`

- [ ] **Step 1: Add the `TxSort` enum**

In `ActivityTab.swift`, add a top-level enum (e.g. just below the imports, before `struct ActivityTab`):

```swift
enum TxSort: String, CaseIterable, Identifiable {
    case dateDesc, dateAsc, amountDesc, amountAsc
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dateDesc:   return "Newest first"
        case .dateAsc:    return "Oldest first"
        case .amountDesc: return "Largest amount"
        case .amountAsc:  return "Smallest amount"
        }
    }
    func sorted(_ txns: [Tx]) -> [Tx] {
        switch self {
        case .dateDesc:   return txns.sorted { $0.date != $1.date ? $0.date > $1.date : ($0.time ?? "") > ($1.time ?? "") }
        case .dateAsc:    return txns.sorted { $0.date != $1.date ? $0.date < $1.date : ($0.time ?? "") < ($1.time ?? "") }
        case .amountDesc: return txns.sorted { abs($0.amount) != abs($1.amount) ? abs($0.amount) > abs($1.amount) : $0.date > $1.date }
        case .amountAsc:  return txns.sorted { abs($0.amount) != abs($1.amount) ? abs($0.amount) < abs($1.amount) : $0.date > $1.date }
        }
    }
}
```

- [ ] **Step 2: Add the `sort` state**

In `struct ActivityFeedView`, next to `@State private var filter = TxFilter()`, add:

```swift
    @State private var sort: TxSort = .dateDesc
```

- [ ] **Step 3: Apply the sort in `filteredTxns()`**

Change the return of `filteredTxns()`:

```swift
        return Selectors.selectTransactions(base, opts)
```
to:
```swift
        return sort.sorted(Selectors.selectTransactions(base, opts))
```

- [ ] **Step 4: Recompute when sort changes**

After `.onChange(of: filter) { _, _ in recompute() }`, add:

```swift
        .onChange(of: sort) { _, _ in recompute() }
```

- [ ] **Step 5: Add the toolbar Sort menu**

In the `.toolbar { … }`, after the Filter `ToolbarItem` (the one with `accessibilityLabel("Filter")`), add:

```swift
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(TxSort.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort")
            }
```

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
git commit -m "feat(ios): feed sort options (date / amount)"
```

---

### Task 2: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Install + launch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"; xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```

- [ ] **Step 2: Verify**
  - Feed → tap the **Sort** menu (`arrow.up.arrow.down`) → four options, current one checkmarked.
  - **Oldest first** → list reverses (earliest dates on top); **Largest amount** → biggest-magnitude transactions first.
  - The sort persists across opening/closing the Filter and after **Clear filters**; combines with an active filter.
  - Screenshot evidence to `/tmp/feedsort.png`.

- [ ] **Step 3 (no commit):** report; if a check fails, return to Task 1.

---

## Self-review notes
- Spec coverage: `TxSort` enum (T1 S1), sort state (T1 S2), apply in filteredTxns (T1 S3), recompute (T1 S4), toolbar menu (T1 S5), cross-platform build (T1 S6), manual (T2). ✓
- Type consistency: `TxSort` (CaseIterable/Identifiable), `sort.sorted([Tx]) -> [Tx]`, `$sort` Picker binding, `recompute()` consistent. ✓
- No engine change; sort is view-level over the existing selector. ✓
