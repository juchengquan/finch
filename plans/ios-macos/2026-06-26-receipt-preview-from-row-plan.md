# Preview receipt from a row — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tappable paperclip on feed rows with attachments that Quick Looks the receipt, plus a "Preview receipt" context-menu item.

**Architecture:** `TxRow` gets an optional `onPreviewReceipt` callback + paperclip; the feed holds `previewURL`, wires the callback + context menu, and adds `.quickLookPreview`. Reuses #289 helpers. No engine change.

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-26-receipt-preview-from-row-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS).
- Commits: **no `Co-Authored-By` trailer**. No engine/parity changes. PR targets `feat/frontend`.

---

### Task 1: Paperclip preview on feed rows

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift`

- [ ] **Step 1: Add the callback + receipts computed to `TxRow`**

In `struct TxRow`, after `let txn: Tx`, add:

```swift
    var onPreviewReceipt: ((Tx) -> Void)? = nil
```
After the `rowTags` computed var, add:

```swift
    private var receipts: [AttachmentRow] { store.attachments(for: txn.id) }
```

- [ ] **Step 2: Add the paperclip accessory in `TxRow.body`**

In `TxRow.body`, replace the trailing:

```swift
            Spacer()
            Text(store.displayMoneyBase(txn.amount)).fontWeight(.semibold)
```
with:
```swift
            Spacer()
            if let onPreviewReceipt, !receipts.isEmpty {
                Button { onPreviewReceipt(txn) } label: {
                    Image(systemName: "paperclip").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Preview receipt")
            }
            Text(store.displayMoneyBase(txn.amount)).fontWeight(.semibold)
```

- [ ] **Step 3: Add `previewURL` state + helper to `ActivityFeedView`**

In `struct ActivityFeedView`, near `@State private var editing: Tx?`, add:

```swift
    @State private var previewURL: URL?
```
Add the helper method (near the other private helpers, e.g. next to `row(_:)`):

```swift
    private func previewReceipt(_ tx: Tx) {
        if let first = store.attachments(for: tx.id).first { previewURL = store.attachmentURL(for: first) }
    }
```

- [ ] **Step 4: Pass the callback + context-menu item in `row(_:)`**

In `row(_:)`, change:

```swift
                TxRow(txn: txn)
```
to:
```swift
                TxRow(txn: txn, onPreviewReceipt: isSelecting ? nil : { previewReceipt($0) })
```
In the same `row(_:)`'s `.contextMenu { … }`, add (e.g. after the Edit button):

```swift
            if !store.attachments(for: txn.id).isEmpty {
                Button { previewReceipt(txn) } label: { Label("Preview receipt", systemImage: "paperclip") }
            }
```

- [ ] **Step 5: Add the Quick Look modifier to the feed**

In `ActivityFeedView.body`, after `.errorAlert($errorMessage)`, add:

```swift
        .quickLookPreview($previewURL)
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
Expected: both `** BUILD SUCCEEDED **`. (`.quickLookPreview` is already used in `EditTransactionSheet.swift`, so it's available cross-platform.)

- [ ] **Step 7: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift
git commit -m "feat(ios): preview a receipt from a transaction row"
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
```

- [ ] **Step 2: Seed a receipt on a visible transaction**

Inspect the DB + attachments dir, then insert an `attachments` row for a known entry and drop a matching file so `store.attachments(for:)` returns it:

```bash
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
C=$(xcrun simctl get_app_container $SIM com.juchengquan.finch data)
DB=$(find "$C" -name finch.sqlite3 | head -1)
sqlite3 "$DB" ".schema attachments"           # confirm columns (id, entry_id/posting_id, rel_path, kind, ...)
# find the attachments base dir (where attachmentURL resolves rel_path):
find "$C" -type d -name "*attach*" 2>/dev/null
# Then: INSERT a row linking the Pay/Coffee entry to a rel_path, and copy a small PNG to that path.
```
(If the table/dir shape makes direct seeding impractical, attach a receipt via the app's Edit → Add photo flow instead, then return to the feed.)

- [ ] **Step 3: Verify (relaunch first)**
  - `xcrun simctl launch $SIM com.juchengquan.finch`
  - The seeded transaction's feed row shows a **paperclip**; tap it → **Quick Look** opens the file (no Edit sheet). Other rows show no paperclip.
  - Long-press that row → **Preview receipt** context item also opens it.
  - Screenshot evidence to `/tmp/receiptrow.png`.

- [ ] **Step 4 (no commit):** report; if a check fails, return to Task 1.

---

## Self-review notes
- Spec coverage: TxRow callback + receipts (T1 S1), paperclip accessory (T1 S2), feed previewURL+helper (T1 S3), row callback + context menu (T1 S4), quickLookPreview (T1 S5), cross-platform build (T1 S6), manual (T2). ✓
- Type consistency: `onPreviewReceipt: ((Tx) -> Void)?`, `receipts: [AttachmentRow]`, `previewURL: URL?`, `store.attachments(for:)`/`attachmentURL(for:)`, `.quickLookPreview($previewURL)` consistent with #289. ✓
- No engine change; merchant-detail `TxRow(txn:)` unaffected (callback defaults nil). ✓
