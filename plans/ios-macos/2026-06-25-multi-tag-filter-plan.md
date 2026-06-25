# Feed multi-tag filter — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the feed filter by multiple tags (Any/All), replacing the single-tag picker.

**Architecture:** `ListOptions.tagId` → `tagIds` + `tagsMatchAll`; `selectTransactions` does Any/All; the filter sheet gets a multi-select tag list + Any/All toggle; `TxFilter` and the feed pass-through follow.

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-25-multi-tag-filter-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before app builds.
- Engine tests: `cd ios/FinchCore && swift test`. App builds: FinchApp (iOS) **and** FinchMac (macOS).
- Commits: **no `Co-Authored-By` trailer**. `tagId`/`tagIds` are iOS-only (parity-safe). PR targets `feat/frontend`.

---

### Task 1: Engine — `tagIds` + Any/All

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Models.swift` (`ListOptions`)
- Modify: `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift`
- Modify: `ios/FinchCore/Tests/FinchCoreTests/SelectTransactionsTagTests.swift`

- [ ] **Step 1: Migrate the test to `tagIds` (Any/All)**

Replace the whole `SelectTransactionsTagTests.swift` with:

```swift
import XCTest
@testable import FinchCore

final class SelectTransactionsTagTests: XCTestCase {
    private let txns = [
        Tx(id: "e1", merchant: "A", amount: -5, account: "a1", date: "2026-06-01", ledgerId: "l1", tags: ["t1"]),
        Tx(id: "e2", merchant: "B", amount: -5, account: "a1", date: "2026-06-02", ledgerId: "l1", tags: ["t2"]),
        Tx(id: "e3", merchant: "C", amount: -5, account: "a1", date: "2026-06-03", ledgerId: "l1", tags: nil),
        Tx(id: "e4", merchant: "D", amount: -5, account: "a1", date: "2026-06-04", ledgerId: "l1", tags: ["t1", "t2"]),
    ]

    func test_anyTag_default() {
        let out = Selectors.selectTransactions(txns, ListOptions(ledgerId: "l1", tagIds: ["t1", "t2"]))
        XCTAssertEqual(Set(out.map(\.id)), ["e1", "e2", "e4"])   // any of t1/t2
    }

    func test_allTags() {
        let out = Selectors.selectTransactions(txns, ListOptions(ledgerId: "l1", tagIds: ["t1", "t2"], tagsMatchAll: true))
        XCTAssertEqual(out.map(\.id), ["e4"])                    // both t1 AND t2
    }

    func test_noTagFilter_unchanged() {
        let out = Selectors.selectTransactions(txns, ListOptions(ledgerId: "l1"))
        XCTAssertEqual(Set(out.map(\.id)), ["e1", "e2", "e3", "e4"])
    }
}
```

- [ ] **Step 2: Run — expect FAIL (no `tagIds`)**

Run: `cd ios/FinchCore && swift test --filter SelectTransactionsTagTests 2>&1 | tail -15`
Expected: FAIL — `ListOptions` has no `tagIds`/`tagsMatchAll`.

- [ ] **Step 3: Update `ListOptions`**

In `Models.swift`, in `struct ListOptions`, replace `public var tagId: String?` with:

```swift
    public var tagIds: [String]?
    public var tagsMatchAll: Bool
```
In the init, replace the `tagId` parameter + assignment. Change the init's final param line from:

```swift
                maxAmount: Double? = nil, limit: Int? = nil, offset: Int? = nil,
                tagId: String? = nil) {
```
to:
```swift
                maxAmount: Double? = nil, limit: Int? = nil, offset: Int? = nil,
                tagIds: [String]? = nil, tagsMatchAll: Bool = false) {
```
and the last assignment line from:
```swift
        self.limit = limit; self.offset = offset; self.tagId = tagId
```
to:
```swift
        self.limit = limit; self.offset = offset; self.tagIds = tagIds; self.tagsMatchAll = tagsMatchAll
```

- [ ] **Step 4: Update `selectTransactions`**

In `Selectors.swift`, replace the tag-filter line:

```swift
        if let tag = opts.tagId { out = out.filter { ($0.tags ?? []).contains(tag) } }
```
with:
```swift
        if let tags = opts.tagIds, !tags.isEmpty {
            let want = Set(tags)
            out = out.filter {
                let have = Set($0.tags ?? [])
                return opts.tagsMatchAll ? want.isSubset(of: have) : !want.isDisjoint(with: have)
            }
        }
```

- [ ] **Step 5: Run — expect PASS, then full suite**

```bash
cd ios/FinchCore && swift test --filter SelectTransactionsTagTests 2>&1 | tail -10
swift test 2>&1 | tail -8
```
Expected: 3/3 filtered pass; full suite + ParityTests green.

- [ ] **Step 6: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Project/Models.swift \
        ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift \
        ios/FinchCore/Tests/FinchCoreTests/SelectTransactionsTagTests.swift
git commit -m "feat(ios): selectTransactions multi-tag filter (tagIds + Any/All)"
```

---

### Task 2: UI — multi-select tags in the filter sheet + feed

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/TransactionFilterSheet.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift`

- [ ] **Step 1: `TxFilter` multi-tag state**

In `TransactionFilterSheet.swift`, in `struct TxFilter`, replace `var tagId: String? = nil` with:

```swift
    var tagIds: Set<String> = []
    var tagsMatchAll: Bool = false
```
In `isActive`, replace `tagId != nil` with `!tagIds.isEmpty`.

- [ ] **Step 2: Multi-select tag UI in the sheet**

Replace the single Tag picker block:

```swift
                    if !store.tags.isEmpty {
                        Picker("Tag", selection: $draft.tagId) {
                            Text("Any").tag(String?.none)
                            ForEach(store.tags) { Text($0.name).tag(String?.some($0.id)) }
                        }
                    }
```
with:

```swift
                    if !store.tags.isEmpty {
                        ForEach(store.tags) { tag in
                            Button {
                                if draft.tagIds.contains(tag.id) { draft.tagIds.remove(tag.id) }
                                else { draft.tagIds.insert(tag.id) }
                            } label: {
                                HStack {
                                    Text(tag.name).foregroundStyle(.primary)
                                    Spacer()
                                    if draft.tagIds.contains(tag.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                            }
                        }
                        if draft.tagIds.count >= 2 {
                            Picker("Match", selection: $draft.tagsMatchAll) {
                                Text("Any tag").tag(false)
                                Text("All tags").tag(true)
                            }
                        }
                    }
```

- [ ] **Step 3: Feed pass-through**

In `ActivityFeedView.filteredTxns()`, replace `tagId: filter.tagId)` (the last `ListOptions` argument) with:

```swift
            tagIds: filter.tagIds.isEmpty ? nil : Array(filter.tagIds),
            tagsMatchAll: filter.tagsMatchAll)
```

- [ ] **Step 4: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/TransactionFilterSheet.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift
git commit -m "feat(ios): feed multi-tag filter (Any/All) UI"
```

---

### Task 3: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Install + launch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"; xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```
(Need ≥2 tags, with some transactions tagged — Power Tools › Tags + tag a few txns.)

- [ ] **Step 2: Verify**
  - Feed → Filter → tags show as a **multi-select** list (checkmarks); select 2 → feed shows **Any-of** matches; an **Any/All** toggle appears → switch to **All tags** → narrows to transactions with both.
  - Filter icon shows active; **Clear** resets; combine with another filter.
  - Screenshot evidence to `/tmp/multitag.png`.

- [ ] **Step 3 (no commit):** report; if a check fails, return to the relevant task.

---

## Self-review notes
- Spec coverage: engine tagIds+Any/All + migrated test (T1), TxFilter multi-state (T2 S1), sheet multi-select + toggle (T2 S2), feed pass-through (T2 S3), cross-platform build (T2 S4), manual (T3). ✓
- Type consistency: `tagIds: [String]?`/`tagsMatchAll` (ListOptions), `tagIds: Set<String>` (TxFilter), `selectTransactions`, feed args consistent. ✓
- Only the feed used `ListOptions.tagId`; parity-safe (iOS-only field). ✓
