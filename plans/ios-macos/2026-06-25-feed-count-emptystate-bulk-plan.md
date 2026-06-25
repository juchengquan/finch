# Feed: result count + no-results state + bulk confirm/delete — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the transaction feed: show a result count, a "no matching transactions" state, and bulk Confirm/Delete in Select mode.

**Architecture:** All in `ActivityFeedView`. UI-only — bulk actions loop the existing single `confirmTransaction` / `deleteTransaction`; count/empty-state derive from the already-computed filtered list. No engine change.

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-25-feed-count-emptystate-bulk-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS) — `ActivityFeedView` is shared.
- Commits: **no `Co-Authored-By` trailer**.
- No engine/DB/parity changes. PR targets `feat/frontend`.

---

### Task 1: Result count + no-results state + bulk Confirm/Delete

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift`

- [ ] **Step 1: Add state**

Alongside the other `@State` vars (e.g. after `@State private var hasMore = false`), add:

```swift
    @State private var filteredCount = 0
    @State private var confirmingBulkDelete = false
```

- [ ] **Step 2: Track the filtered count in `recompute()`**

In `recompute()`, after `let f = filteredTxns()`, add:

```swift
        filteredCount = f.count
```

- [ ] **Step 3: Add the count caption + no-results view to the List**

In `body`, inside the `List { … }`, replace:

```swift
                    if store.txns.isEmpty {
                        Section { Text("No transactions in this ledger yet.").foregroundStyle(.secondary) }
                    }
                    if pendingCount > 0 {
```
with:

```swift
                    if store.txns.isEmpty {
                        Section { Text("No transactions in this ledger yet.").foregroundStyle(.secondary) }
                    } else {
                        Text("\(filteredCount) transaction\(filteredCount == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                    if !store.txns.isEmpty, sections.isEmpty {
                        ContentUnavailableView {
                            Label("No matching transactions", systemImage: "line.3.horizontal.decrease.circle")
                        } description: {
                            Text("Try adjusting your search or filters.")
                        } actions: {
                            if hasActiveQuery { Button("Clear filters & search") { searchQuery = ""; filter = TxFilter() } }
                        }
                        .listRowBackground(Color.clear)
                    }
                    if pendingCount > 0 {
```

- [ ] **Step 4: Add the `hasActiveQuery` helper**

Near `pendingCount` (the other computed vars), add:

```swift
    private var hasActiveQuery: Bool { !searchQuery.isEmpty || filter.isActive }
```

- [ ] **Step 5: Bulk buttons in the Select bottom bar**

Replace the selection bottom-bar block:

```swift
            if isSelecting {
                ToolbarItem(placement: .bottomBar) {
                    Button("Recategorize \(selected.count)") { showingBulkCat = true }
                        .disabled(selected.isEmpty)
                }
            }
```
with:

```swift
            if isSelecting {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Confirm \(selected.count)") { bulkConfirm() }
                        .disabled(selected.isEmpty)
                    Spacer()
                    Button("Recategorize \(selected.count)") { showingBulkCat = true }
                        .disabled(selected.isEmpty)
                    Spacer()
                    Button("Delete \(selected.count)", role: .destructive) { confirmingBulkDelete = true }
                        .disabled(selected.isEmpty)
                }
            }
```

- [ ] **Step 6: Bulk-delete confirmation dialog**

Next to the other `.sheet`/modifiers (e.g. after `.sheet(isPresented: $showingBulkCat) { … }`), add:

```swift
        .confirmationDialog("Delete \(selected.count) transaction\(selected.count == 1 ? "" : "s")?",
                            isPresented: $confirmingBulkDelete, titleVisibility: .visible) {
            Button("Delete \(selected.count)", role: .destructive) { bulkDelete() }
            Button("Cancel", role: .cancel) {}
        }
```

- [ ] **Step 7: Bulk action helpers**

Near the existing `delete(_:)` / `confirm(_:)` helpers, add:

```swift
    private func bulkConfirm() {
        run { for id in selected { try store.apply(.confirmTransaction, Args(["id": .string(id)])) } }
        isSelecting = false; selected.removeAll()
    }
    private func bulkDelete() {
        run { for id in selected { try store.deleteTransaction(id) } }   // also unlinks receipts
        isSelecting = false; selected.removeAll()
    }
```

- [ ] **Step 8: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`. (If `ToolbarItemGroup`/`.bottomBar` errors on macOS, gate the selection group with `#if os(iOS)` — the existing single item was already `.bottomBar`, so it should be fine.)

- [ ] **Step 9: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift
git commit -m "feat(ios): feed result count + no-results state + bulk confirm/delete"
```

---

### Task 2: Manual simulator verification

**Files:** none. Raise the iPhone 17 Pro window by name; use AXPress where coordinate taps miss.

- [ ] **Step 1: Install + launch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"; xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```

- [ ] **Step 2: Verify**
  - Open a feed → a **count caption** ("N transactions") shows at the top and updates with search/filter.
  - Apply a filter/search matching **nothing** → **"No matching transactions"** + **Clear filters & search** (which resets and brings the list back).
  - **Select** → pick a few rows → bottom bar shows **Confirm N · Recategorize N · Delete N**.
    - **Confirm N** → the picked pending rows lose their pending state; selection exits.
    - **Delete N** → confirmation dialog → rows removed (receipts unlinked); selection exits.
  - Screenshot evidence to `/tmp/feedbulk-<state>.png`.

- [ ] **Step 3 (no commit):** report; if a check fails, return to Task 1.

---

## Self-review notes
- Spec coverage: count (T1 S2-S3), no-results + Clear (T1 S3-S4), bulk Confirm/Delete + confirm dialog + helpers (T1 S5-S7), cross-platform build (T1 S8), manual (T2). ✓
- Type consistency: `filteredCount`, `confirmingBulkDelete`, `hasActiveQuery`, `bulkConfirm()`/`bulkDelete()`, `TxFilter()`, `store.deleteTransaction`/`.confirmTransaction` consistent. ✓
- UI-only: no engine/parity changes. ✓
