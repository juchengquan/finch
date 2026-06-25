# Tag colors on transaction rows — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a transaction's tags as small colored chips on its feed row.

**Architecture:** A `rowTags` computed in `TxRow` (mapping `Tx.tags` → `TagRow` via `store.tags`) rendered as tinted/colored capsules next to the category chip. UI-only, no engine change.

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-25-row-tag-colors-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS) — `TxRow` is shared.
- Commits: **no `Co-Authored-By` trailer**. No engine/parity changes. PR targets `feat/frontend`.

---

### Task 1: Tag chips in `TxRow`

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift`

- [ ] **Step 1: Add the `rowTags` computed var**

In `struct TxRow`, before `var body: some View`, add:

```swift
    private var rowTags: [TagRow] {
        guard let ids = txn.tags, !ids.isEmpty else { return [] }
        return ids.compactMap { id in store.tags.first { $0.id == id } }
    }
```

- [ ] **Step 2: Render the chips next to the category chip**

In `TxRow`'s body, replace the category chip block:

```swift
                if let cat = store.categoryName(txn.category) {
                    Text(cat).font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
```
with:

```swift
                HStack(spacing: 4) {
                    if let cat = store.categoryName(txn.category) {
                        Text(cat).font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    ForEach(rowTags.prefix(3)) { tag in
                        Text(tag.name).font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((Color(hex: tag.color ?? "") ?? .secondary).opacity(0.2), in: Capsule())
                            .foregroundStyle(Color(hex: tag.color ?? "") ?? .secondary)
                    }
                    if rowTags.count > 3 {
                        Text("+\(rowTags.count - 3)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
```

- [ ] **Step 3: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`.
(If `ForEach(rowTags.prefix(3))` needs an explicit id, use `ForEach(Array(rowTags.prefix(3))) { … }` — `TagRow` is `Identifiable`, so the `ArraySlice` form should be fine; switch only if the compiler complains.)

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift
git commit -m "feat(ios): tag colors on transaction rows"
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
(If no transaction is tagged, tag one: open a transaction → Edit → tap a tag → save. Give the tag a color in Power Tools › Tags for the color to show.)

- [ ] **Step 2: Verify**
  - A tagged transaction's row shows colored **tag chips** (name tinted by tag color) next to the category chip.
  - A tag with no color falls back to gray; >3 tags shows "+N"; untagged rows are unchanged.
  - Screenshot evidence to `/tmp/rowtagcolors.png`.

- [ ] **Step 3 (no commit):** report; if it fails, return to Task 1.

---

## Self-review notes
- Spec coverage: `rowTags` map (T1 S1), colored chips + cap/overflow next to category (T1 S2), cross-platform build (T1 S3), manual (T2). ✓
- Type consistency: `rowTags: [TagRow]`, `Color(hex:)`, `store.tags`, `txn.tags` consistent. ✓
- No engine change. ✓
