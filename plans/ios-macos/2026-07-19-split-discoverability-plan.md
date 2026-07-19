# Split Discoverability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the existing Splits feature on the Add/Edit transaction sheets with an always-visible split icon on the Category row, so assigning multiple categories is discoverable.

**Architecture:** Give the shared `CategoryPickerRow` an optional split affordance (`onSplit`/`splitSummary`/`splitEnabled`) that renders a trailing split-icon button and reflects split state; wire it from the Add and Edit sheets to the existing `SplitEditorView` flow, removing the buried "Split…" buttons. No engine/schema change.

**Tech Stack:** SwiftUI (iOS 17 / macOS 14 floor); XCTest; XcodeGen (`FinchApp.xcodeproj`); `xcodebuild`.

## Global Constraints

- **Worktree / branch:** `/tmp/finch-split` on `feat/ios-split-discoverability` (off `origin/feat/frontend`). PR targets `feat/frontend`.
- **Environment:** `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before any `xcodebuild`/`xcodegen`. Run `xcodegen generate` (from `/tmp/finch-split/ios`) after adding a file. Sim `ios-finch2`; iOS `-derivedDataPath /tmp/dd-cat`, mac `/tmp/dd-catmac`.
- **Commits:** no `Co-Authored-By` trailer. Conventional `feat(ios): …` subjects.
- **No engine/schema change.** Reuse `SplitEditorView` and the `setTransactionSplits` action unchanged. Do not touch `FinchCore`.
- **Split icon:** SF Symbol `arrow.triangle.branch`.
- **Copy (verbatim; en source == key):** `"Split across %lld categories"` (Swift `"Split across \(count) categories"`), accessibility labels `"Split across categories"` / `"Edit split"`. New keys join the tracked zh-Hans batch.
- **`CategoryPickerRow` has exactly two consumers** — `AddTransactionSheet` and `EditTransactionSheet` — so the new params default (nil/false) and don't affect anything else.

## File Map

| File | Task | Responsibility |
|------|------|----------------|
| `ios/FinchApp/Sources/FinchApp/WriteScreens/CategoryPickerRow.swift` | 1 | `splitSummaryText(count:)` helper + the row's split affordance |
| `ios/FinchApp/Tests/FinchAppTests/SplitSummaryTests.swift` | 1 (create) | helper tests |
| `ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift` | 2 | wire the split affordance; remove the buried "Split…" button |
| `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift` | 2 | same, on the single-category branch |

---

### Task 1: `CategoryPickerRow` split affordance + `splitSummaryText`

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/CategoryPickerRow.swift`
- Create: `ios/FinchApp/Tests/FinchAppTests/SplitSummaryTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `func splitSummaryText(count: Int) -> String?` (nil for < 2). `CategoryPickerRow` gains `var splitSummary: String? = nil`, `var splitEnabled: Bool = false`, `var onSplit: (() -> Void)? = nil`. Task 2's Add/Edit sheets pass these.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchApp/Tests/FinchAppTests/SplitSummaryTests.swift`:

```swift
import XCTest
@testable import FinchApp

final class SplitSummaryTests: XCTestCase {
    func test_single_or_zero_is_nil() {
        XCTAssertNil(splitSummaryText(count: 0))
        XCTAssertNil(splitSummaryText(count: 1))
    }
    func test_two_or_more_summarizes() {
        XCTAssertEqual(splitSummaryText(count: 2), "Split across 2 categories")
        XCTAssertEqual(splitSummaryText(count: 3), "Split across 3 categories")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /tmp/finch-split/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/SplitSummaryTests 2>&1 | grep -E "error:|cannot find|TEST SUCCEEDED|TEST FAILED"
```

Expected: FAIL — `cannot find 'splitSummaryText' in scope`.

- [ ] **Step 3: Add the helper + the split affordance**

In `ios/FinchApp/Sources/FinchApp/WriteScreens/CategoryPickerRow.swift`, add the helper just below the imports (above the `struct CategoryPickerRow` doc comment):

```swift
/// "Split across N categories" when N ≥ 2 (a real split); nil for a single
/// category. Drives the Category row's split-state label.
func splitSummaryText(count: Int) -> String? {
    count >= 2 ? String(localized: "Split across \(count) categories") : nil
}
```

Then replace the `CategoryPickerRow` struct (the declaration through its `body`'s closing brace — i.e. the current lines `struct CategoryPickerRow: View {` … up to and including the `}` that closes `body`, leaving the private `CategoryPickerSheet` below it untouched) with:

```swift
struct CategoryPickerRow: View {
    let title: String
    let categories: [CategoryRow]         // kind-filtered rows (sort_order order)
    @Binding var selection: String
    /// Non-nil ⇒ the transaction is split: the row shows this summary instead of the
    /// picked category name, and tapping the row (or icon) reopens the split editor.
    var splitSummary: String? = nil
    /// Whether the split icon is actionable (a split needs a non-zero amount).
    var splitEnabled: Bool = false
    /// nil ⇒ no split affordance (e.g. refunds); non-nil ⇒ show the trailing split icon.
    var onSplit: (() -> Void)? = nil
    @State private var presented = false

    private var selectedName: String { categories.first { $0.id == selection }?.name ?? "—" }

    var body: some View {
        HStack {
            Button {
                if splitSummary != nil { onSplit?() } else { presented = true }
            } label: {
                HStack {
                    Text(title).foregroundStyle(.primary)
                    Spacer()
                    Text(splitSummary ?? selectedName).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onSplit {
                Button { onSplit() } label: {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.body)
                        .foregroundStyle(splitSummary != nil ? Color.accentColor : Color.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(splitSummary == nil && !splitEnabled)
                .opacity(splitSummary == nil && !splitEnabled ? 0.4 : 1)   // dim until an amount exists
                .accessibilityLabel(splitSummary != nil ? "Edit split" : "Split across categories")
            }
        }
        .sheet(isPresented: $presented) {
            CategoryPickerSheet(title: title, categories: categories, selection: $selection)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /tmp/finch-split/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/SplitSummaryTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **` (2 tests). The existing `AddTransactionSheet`/`EditTransactionSheet` call sites still compile unchanged (the new params default).

- [ ] **Step 5: Commit**

```bash
cd /tmp/finch-split && git add ios/FinchApp/Sources/FinchApp/WriteScreens/CategoryPickerRow.swift ios/FinchApp/Tests/FinchAppTests/SplitSummaryTests.swift && git commit -m "feat(ios): split affordance on CategoryPickerRow + splitSummaryText helper"
```

---

### Task 2: Wire the split affordance into the Add + Edit sheets

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift`, `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift`

**Interfaces:**
- Consumes: `CategoryPickerRow(... splitSummary: splitEnabled: onSplit:)`, `splitSummaryText(count:)` (Task 1); the existing `showingSplit`/`pendingSplits` state and `SplitEditorView` presentation in each sheet (unchanged).
- Produces: nothing downstream.

- [ ] **Step 1: Wire the Add sheet**

In `ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift`, in `expenseIncomeFields(for:)`, replace this block:

```swift
            if pendingSplits == nil {
                CategoryPickerRow(title: "Category", categories: categories(for: k), selection: $categoryId)
            }
            DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .environment(\.locale, AppDate.h24Locale)
            if k != .refund, DecimalInput.parse(amount) ?? 0 != 0 {
                Button {
                    showingSplit = true
                } label: {
                    HStack {
                        Text(pendingSplits == nil ? "Split…" : "Split across \(pendingSplits!.count) categories")
                        Spacer()
                        if pendingSplits != nil { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
```

with (Category row always shown, carrying the split affordance; the standalone button is gone):

```swift
            CategoryPickerRow(title: "Category", categories: categories(for: k), selection: $categoryId,
                splitSummary: splitSummaryText(count: pendingSplits?.count ?? 0),
                splitEnabled: (DecimalInput.parse(amount) ?? 0) != 0,
                onSplit: k == .refund ? nil : { showingSplit = true })
            DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .environment(\.locale, AppDate.h24Locale)
```

- [ ] **Step 2: Wire the Edit sheet**

In `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift`, in the single-category `else` branch, replace this line:

```swift
                        CategoryPickerRow(title: "Category", categories: categories, selection: $categoryId)
```

with:

```swift
                        CategoryPickerRow(title: "Category", categories: categories, selection: $categoryId,
                            splitEnabled: (DecimalInput.parse(amountText) ?? 0) != 0,
                            onSplit: effectiveKind == "refund" ? nil : { showingSplit = true })
```

Then remove the now-redundant standalone split button (these two-plus lines):

```swift
                        if effectiveKind != "refund", (DecimalInput.parse(amountText) ?? 0) != 0 {
                            Button("Split…") { showingSplit = true }
                        }
```

(The already-split branch — `if isSplit { Section("Split") { … } }` — and its `showingSplit` presentation are unchanged; this only touches the single-category `else` branch.)

- [ ] **Step 3: Build FinchApp**

```bash
cd /tmp/finch-split/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild build -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -derivedDataPath /tmp/dd-cat 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Build FinchMac (cross-platform check)**

```bash
cd /tmp/finch-split/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodebuild build -scheme FinchMac -destination 'platform=macOS' -derivedDataPath /tmp/dd-catmac CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run the split helper test (regression)**

```bash
cd /tmp/finch-split/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -only-testing:FinchAppTests/SplitSummaryTests 2>&1 | grep -E "error:|TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd /tmp/finch-split && git add ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift && git commit -m "feat(ios): surface split on the Category row in Add/Edit sheets"
```

---

## Manual sim verification (controller / human, after Task 2)

Build, install to `ios-finch2`:
1. Open the Add sheet (expense) → the Category row shows a **split icon** (`arrow.triangle.branch`) at its trailing edge, **dimmed** while the amount is empty.
2. Enter an amount → the icon **enables** → tap it → `SplitEditorView` opens → set two categories → back on the sheet the Category row reads **"Split across 2 categories"** with the icon emphasized; tapping the row or icon reopens the editor.
3. Refund kind → no split icon on the Category row.
4. Edit a single-category expense → the split icon is present (enabled, since the amount is set) → tap → split it → the Edit sheet's "Split" section appears.

## Out of scope

Multi-category-as-tags (rejected in the design), any change to `SplitEditorView` internals or the split engine, splitting transfers/adjustments, a total-less split flow (splitting stays gated on a non-zero amount), and web parity.

## Self-Review

**Spec coverage** — every decision maps to a task:
- D1 split affordance on the Category row (`onSplit` + trailing icon): **Task 1** (component) + **Task 2** (wiring).
- D2 always visible; enabled once an amount exists (`splitEnabled` → `.disabled`/dim): **Task 1** (behavior) + **Task 2** (passes `(parse ?? 0) != 0`).
- D3 row reflects split state ("Split across N categories", tap reopens editor): **Task 1** (`splitSummary`) + **Task 2** (Add passes `splitSummaryText(...)`; removes the old button + `if pendingSplits == nil`).
- D4 Edit-sheet parity (split a single-category txn): **Task 2** Step 2.
- D5 no engine/schema change: reuses `SplitEditorView`/`setTransactionSplits`; no FinchCore touched.

**Placeholder scan:** none — complete code and exact commands throughout.

**Type consistency:** `splitSummaryText(count:) -> String?` defined in Task 1, called in Task 2's Add wiring. `CategoryPickerRow`'s new params `splitSummary`/`splitEnabled`/`onSplit` defined in Task 1 and passed with those exact labels in Task 2 (Add passes all three; Edit passes `splitEnabled`/`onSplit`, `splitSummary` defaults nil since the single-category branch never renders for an already-split txn). The `(DecimalInput.parse(...) ?? 0) != 0` amount guard matches the pre-existing gate it replaces.