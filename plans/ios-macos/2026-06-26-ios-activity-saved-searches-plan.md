# Activity saved searches — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-ledger saved filter "searches" on the Activity feed — save the current (non-default) filter under a name, re-apply via chips, delete individually.

**Architecture:** FinchApp only (no engine/DB). (1) `TxFilter: Codable` + `SavedSearch` + a UserDefaults `SavedSearchStore`. (2) A chip row on `ActivityTab` (apply / "＋ Save" / context-delete). `TransactionFilterSheet` untouched.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), XcodeGen, XCTest (FinchAppTests via xcodebuild).

## Global Constraints

- **No engine/DB/schema change.** Persistence is UserDefaults (the iOS analogue of the web's localStorage).
- **Do NOT modify `TransactionFilterSheet.swift`** (hottest shared file) — the save trigger lives on the feed chip row.
- Per-ledger via `SavedSearch.ledgerId`; "non-default" check = `filter.isActive` (existing computed prop). Empty names are ignored.
- **Must build iOS AND macOS (FinchMac).** Sim `iPhone 17 Pro Max`. New files → `xcodegen generate`. FinchApp tests run via `xcodebuild test` (not `swift test`). `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit; **no `Co-Authored-By` trailer**.

---

## File Structure

**Modify (FinchApp):** `ios/FinchApp/Sources/FinchApp/WriteScreens/TransactionFilterSheet.swift` (one-line: `TxFilter: Codable`), `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift` (chip row).
**Create (FinchApp):** `ios/FinchApp/Sources/FinchApp/SavedSearchStore.swift`.
**Create (tests):** `ios/FinchApp/Tests/FinchAppTests/SavedSearchStoreTests.swift`.

---

### Task 1: `TxFilter: Codable` + `SavedSearch` + `SavedSearchStore`

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/TransactionFilterSheet.swift`
- Create: `ios/FinchApp/Sources/FinchApp/SavedSearchStore.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/SavedSearchStoreTests.swift`

**Interfaces:**
- Produces: `TxFilter: Codable`; `SavedSearch { id, name, ledgerId, filter }`; `SavedSearchStore` (`@Published searches`; `all(ledgerId:)`, `save(name:filter:ledgerId:)`, `remove(_:)`; `init(defaults:)`).

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchApp/Tests/FinchAppTests/SavedSearchStoreTests.swift`:

```swift
import XCTest
@testable import FinchApp

final class SavedSearchStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "test.savedsearch.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func test_save_and_all_scoped_per_ledger() {
        let s = SavedSearchStore(defaults: freshDefaults())
        s.save(name: "Dining", filter: TxFilter(categoryId: "c1"), ledgerId: "l1")
        s.save(name: "Other", filter: TxFilter(direction: "out"), ledgerId: "l2")
        XCTAssertEqual(s.all(ledgerId: "l1").map(\.name), ["Dining"])
        XCTAssertEqual(s.all(ledgerId: "l2").map(\.name), ["Other"])
    }

    func test_remove() {
        let s = SavedSearchStore(defaults: freshDefaults())
        s.save(name: "A", filter: TxFilter(status: "pending"), ledgerId: "l1")
        s.remove(s.all(ledgerId: "l1")[0].id)
        XCTAssertTrue(s.all(ledgerId: "l1").isEmpty)
    }

    func test_empty_name_ignored() {
        let s = SavedSearchStore(defaults: freshDefaults())
        s.save(name: "   ", filter: TxFilter(status: "pending"), ledgerId: "l1")
        XCTAssertTrue(s.all(ledgerId: "l1").isEmpty)
    }

    func test_persists_across_instances() {
        let name = "test.savedsearch.persist.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!; d.removePersistentDomain(forName: name)
        SavedSearchStore(defaults: d).save(name: "Keep", filter: TxFilter(minAmount: 50), ledgerId: "l1")
        XCTAssertEqual(SavedSearchStore(defaults: d).all(ledgerId: "l1").map(\.name), ["Keep"])
    }

    func test_txfilter_codable_roundtrip() throws {
        var f = TxFilter()
        f.direction = "out"; f.categoryId = "c1"; f.tagIds = ["t1", "t2"]; f.tagsMatchAll = true
        f.status = "pending"; f.from = Date(timeIntervalSince1970: 1_700_000_000)
        f.to = Date(timeIntervalSince1970: 1_700_100_000); f.minAmount = 5; f.maxAmount = 500
        let back = try JSONDecoder().decode(TxFilter.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back, f)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests/SavedSearchStoreTests 2>&1 | grep -iE "error:|cannot find|TEST SUCCEEDED|TEST FAILED"
```
Expected: FAIL to compile — `SavedSearchStore` undefined; `TxFilter` not `Codable`.

- [ ] **Step 3: Make `TxFilter` Codable**

In `TransactionFilterSheet.swift`, change `struct TxFilter: Equatable {` to `struct TxFilter: Equatable, Codable {`. (All stored members are Codable; the `private static let ymd` is unaffected. No other change.)

- [ ] **Step 4: Create `SavedSearchStore.swift`**

Create `ios/FinchApp/Sources/FinchApp/SavedSearchStore.swift`:

```swift
import Foundation

/// One saved Activity filter, scoped to a ledger.
struct SavedSearch: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    let ledgerId: String
    let filter: TxFilter
}

/// Per-ledger saved filter searches, persisted in UserDefaults (the iOS analogue
/// of the web's localStorage). Not part of the engine/DB.
final class SavedSearchStore: ObservableObject {
    @Published private(set) var searches: [SavedSearch] = []
    private let defaults: UserDefaults
    private let key = "finch.savedSearches"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let arr = try? JSONDecoder().decode([SavedSearch].self, from: data) {
            searches = arr
        }
    }

    func all(ledgerId: String) -> [SavedSearch] { searches.filter { $0.ledgerId == ledgerId } }

    func save(name: String, filter: TxFilter, ledgerId: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searches.append(SavedSearch(id: UUID().uuidString, name: trimmed, ledgerId: ledgerId, filter: filter))
        persist()
    }

    func remove(_ id: String) {
        searches.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(searches) { defaults.set(data, forKey: key) }
    }
}
```

- [ ] **Step 5: Run the tests**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests/SavedSearchStoreTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **` (5 tests).

- [ ] **Step 6: macOS build (FinchMac)**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/WriteScreens/TransactionFilterSheet.swift \
        ios/FinchApp/Sources/FinchApp/SavedSearchStore.swift \
        ios/FinchApp/Tests/FinchAppTests/SavedSearchStoreTests.swift
git commit -m "feat(ios): TxFilter Codable + SavedSearch + SavedSearchStore (UserDefaults)"
```

---

### Task 2: Saved-search chip row on `ActivityTab`

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift`

**Interfaces:**
- Consumes: `SavedSearchStore`, `SavedSearch` (Task 1); the feed's `@State filter: TxFilter` + `filter.isActive`; `store.activeLedgerId`.

- [ ] **Step 1: Add state**

In `ActivityTab`, add alongside the existing `@State private var filter = TxFilter()`:
```swift
    @StateObject private var savedSearches = SavedSearchStore()
    @State private var showingSaveSearch = false
    @State private var newSearchName = ""
```

- [ ] **Step 2: Insert the chip row in `body`**

In `body`, immediately after `if let headerSection { headerSection }` (the first row inside the `List`), add:
```swift
                    savedSearchRow
```

- [ ] **Step 3: Add the `savedSearchRow` + `chipLabel`**

Add these to `ActivityTab`:
```swift
    @ViewBuilder private var savedSearchRow: some View {
        let saved = savedSearches.all(ledgerId: store.activeLedgerId)
        if !saved.isEmpty || filter.isActive {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(saved) { s in
                        Button { filter = s.filter } label: { chipLabel(s.name, selected: filter == s.filter) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { savedSearches.remove(s.id) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    if filter.isActive, !saved.contains(where: { $0.filter == filter }) {
                        Button { newSearchName = ""; showingSaveSearch = true } label: { chipLabel("＋ Save", selected: false) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowBackground(Color.clear)
            .alert("Save search", isPresented: $showingSaveSearch) {
                TextField("Name", text: $newSearchName)
                Button("Cancel", role: .cancel) { newSearchName = "" }
                Button("Save") {
                    savedSearches.save(name: newSearchName, filter: filter, ledgerId: store.activeLedgerId)
                    newSearchName = ""
                }
            } message: { Text("Save the current filters as a named search.") }
        }
    }

    private func chipLabel(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(selected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(selected ? Color.white : Color.primary)
    }
```

- [ ] **Step 4: Build iOS + full FinchApp suite**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: macOS build (FinchMac)**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual verification on the simulator**

Activity tab:
- With **no filter** and no saved searches → no chip row.
- Apply a filter (filter sheet) → a **"＋ Save"** chip appears; tap → name alert → save → it becomes a named chip (and "＋ Save" disappears since the current filter is now saved).
- Clear filters, then tap the saved chip → the filter re-applies (feed updates); the chip highlights as selected.
- **Long-press** a chip → **Delete** removes it.
- Switch ledger → only that ledger's chips show.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch -initialTab activity
```

- [ ] **Step 7: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift
git commit -m "feat(ios): saved-search chips on the Activity feed (apply / save / delete)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-26-ios-activity-saved-searches-design.md`):
- `TxFilter: Codable` + `SavedSearch` + UserDefaults `SavedSearchStore` (per-ledger) → Task 1. ✓
- Chip row: tap-apply, "＋ Save" when `filter.isActive` & not already saved, context-delete → Task 2. ✓
- `TransactionFilterSheet` untouched → only the one-line Codable change there (no UI change). ✓
- No engine/DB change; build iOS+macOS; tests → Tasks 1-2. ✓

**Placeholder scan:** No TBD/TODO; full code in every step; sim step concrete. ✓

**Type consistency:** `SavedSearchStore(defaults:)` + `all(ledgerId:)`/`save(name:filter:ledgerId:)`/`remove(_:)` used identically in tests + `ActivityTab`; `SavedSearch.filter: TxFilter` requires `TxFilter: Codable` (Task 1 step 3); the chip row uses `filter.isActive` (existing) + `filter == s.filter` (Equatable) + `store.activeLedgerId`; `TxFilter(...)` memberwise init (synthesized) used in tests. ✓

---

## Out of scope

`TransactionFilterSheet` UI changes; rename; iCloud/sync; engine/DB changes.
