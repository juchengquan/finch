# Receipt thumbnails — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show an image thumbnail (instead of a generic icon) for image attachments in the Edit sheet's receipt list.

**Architecture:** A new cross-platform `ReceiptThumbnail` view (loads `UIImage`/`NSImage` from the attachment URL); the Edit row uses it in place of its leading SF Symbol. UI-only, no engine change.

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-26-receipt-thumbnails-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds (a new file is added — generate is required).
- Builds: FinchApp (iOS) **and** FinchMac (macOS).
- Commits: **no `Co-Authored-By` trailer**. No engine/parity changes. PR targets `feat/frontend`.

---

### Task 1: `ReceiptThumbnail` + use it in Edit

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/WriteScreens/ReceiptThumbnail.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift`

- [ ] **Step 1: Create `ReceiptThumbnail.swift`**

```swift
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A ~40pt thumbnail for a receipt attachment: the image itself for image kinds,
/// a doc icon for PDFs. Loads the platform image off the file URL lazily.
struct ReceiptThumbnail: View {
    let url: URL
    let kind: String
    @State private var image: Image?
    private let side: CGFloat = 40

    var body: some View {
        Group {
            if kind == "pdf" {
                Image(systemName: "doc.richtext").foregroundStyle(.secondary)
            } else if let image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url) { if kind != "pdf", image == nil { image = Self.load(url) } }
    }

    private static func load(_ url: URL) -> Image? {
        #if canImport(UIKit)
        return UIImage(contentsOfFile: url.path).map(Image.init(uiImage:))
        #elseif canImport(AppKit)
        return NSImage(contentsOf: url).map(Image.init(nsImage:))
        #else
        return nil
        #endif
    }
}
```

- [ ] **Step 2: Use it in the Edit attachment row**

In `EditTransactionSheet.swift`, inside `ForEach(attachments) { att in … }`, replace:

```swift
                                Image(systemName: att.kind == "pdf" ? "doc.richtext" : "photo")
                                    .foregroundStyle(.secondary)
```
with:

```swift
                                ReceiptThumbnail(url: store.attachmentURL(for: att), kind: att.kind)
```
(Leave the rest of the row — `Text(att.originalFilename ?? att.kind.capitalized)`, the
`Spacer()`, the `eye` image, the tap `previewURL = …`, and the swipe-delete — unchanged.)

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

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/ReceiptThumbnail.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift
git commit -m "feat(ios): receipt thumbnails in the Edit attachment list"
```

---

### Task 2: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Install + seed an image attachment**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
xcrun simctl list devices booted | grep -q "$SIM" || { xcrun simctl boot "$SIM"; open -a Simulator; sleep 5; }
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install "$SIM" "$APP"; xcrun simctl terminate "$SIM" com.juchengquan.finch 2>/dev/null
C=$(xcrun simctl get_app_container "$SIM" com.juchengquan.finch data)
# live DB = the finch.sqlite3 with entries (skip tmp/import-staging copies):
DB=""; while IFS= read -r f; do [ "$(sqlite3 "$f" 'SELECT count(*) FROM entries' 2>/dev/null || echo 0)" -gt 0 ] 2>/dev/null && { DB="$f"; break; }; done < <(find "$C" -path '*tmp*' -prune -o -name finch.sqlite3 -print)
AS=$(dirname "$DB"); ATT="$AS/attachments"; mkdir -p "$ATT"
# a small but clearly-an-image PNG so the thumbnail is visibly not the icon:
base64 -D -o "$ATT/thumb-test.png" <<'B64'
iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAOklEQVR42u3OMQ0AAAgDsOFfNCCAd9PQS5rkLDsQERERERERERERERERERERERERERERERERERHxbQ0K8gGF4q2BqgAAAABJRU5ErkJggg==
B64
EID=$(sqlite3 "$DB" "SELECT id FROM entries WHERE description='Coffee' LIMIT 1")
SZ=$(stat -f%z "$ATT/thumb-test.png"); SHA=$(shasum -a 256 "$ATT/thumb-test.png" | cut -d' ' -f1)
sqlite3 "$DB" "INSERT OR REPLACE INTO entry_attachments (id,ledger_id,entry_id,kind,rel_path,mime_type,byte_size,sha256,original_filename,created_at,updated_at) VALUES ('att-thumb','l1','$EID','image','attachments/thumb-test.png','image/png',$SZ,'$SHA','thumb-test.png',datetime('now'),datetime('now'));"
xcrun simctl launch "$SIM" com.juchengquan.finch
```

- [ ] **Step 2: Verify**
  - Open the **Coffee** transaction (tap its row) → Edit → the receipts section shows a
    **real image thumbnail** for `thumb-test.png` (not the generic photo icon); filename,
    preview tap, and swipe-delete still work.
  - Screenshot evidence to `/tmp/receiptthumb.png`.
  - Clean up: `sqlite3 "$DB" "DELETE FROM entry_attachments WHERE id='att-thumb'"; rm -f "$ATT/thumb-test.png"`.

- [ ] **Step 3 (no commit):** report; if a check fails, return to Task 1.

---

## Self-review notes
- Spec coverage: `ReceiptThumbnail` view (T1 S1), Edit row swap (T1 S2), cross-platform build (T1 S3), manual (T2). ✓
- Type consistency: `ReceiptThumbnail(url: URL, kind: String)`, `store.attachmentURL(for:)`, `att.kind` consistent with #289. ✓
- No engine change; PDFs + unreadable files fall back to an icon. ✓
