# In-app receipt attachment preview — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tap a receipt in the Edit form to preview it (image/PDF) via Quick Look, on iOS and macOS.

**Architecture:** A path helper (`attachmentURL`) + a tappable Receipts row that sets a `previewURL`, shown by SwiftUI's `.quickLookPreview($url)` (Approach A — pure SwiftUI, cross-platform, no bridge). A UIKit/AppKit bridge (Approach B) is the documented fallback if A doesn't compile at the iOS 17 / macOS 14 floor.

**Tech Stack:** Swift / SwiftUI, QuickLook, XcodeGen.

Spec: `plans/ios-macos/2026-06-25-receipt-attachment-preview-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'` **and** FinchMac (macOS) `-destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`. The macOS build is the **A/B gate**.
- Commits: **no `Co-Authored-By` trailer**.
- No engine / DB / parity changes. PR targets `feat/frontend`.

---

### Task 1: Tap-to-preview a receipt (Approach A; B only if A fails to build)

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/FinchStore+ViewHelpers.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift`
- Modify (if A succeeds): `ios/swiftui-vs-uikit.md`

- [ ] **Step 1: Add the file-URL helper**

In `FinchStore+ViewHelpers.swift`, right after the `attachmentsRoot` computed property, add:

```swift
    /// Absolute on-disk URL for an attachment (`relPath` already includes "attachments/…").
    public func attachmentURL(for att: AttachmentRow) -> URL {
        attachmentsRoot.deletingLastPathComponent().appendingPathComponent(att.relPath)
    }
```

- [ ] **Step 2: Import QuickLook + add preview state**

In `EditTransactionSheet.swift`, add to the imports:

```swift
import QuickLook
```
and add a state var alongside the others (e.g. after `@State private var pickedPhoto: PhotosPickerItem?`):

```swift
    @State private var previewURL: URL?
```

- [ ] **Step 3: Make each receipt row tappable**

In the `Section("Receipts")`, replace the row:

```swift
                    ForEach(attachments) { att in
                        HStack {
                            Image(systemName: att.kind == "pdf" ? "doc.richtext" : "photo")
                                .foregroundStyle(.secondary)
                            Text(att.originalFilename ?? att.kind.capitalized)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { removeAttachment(att) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
```
with:

```swift
                    ForEach(attachments) { att in
                        Button { previewURL = store.attachmentURL(for: att) } label: {
                            HStack {
                                Image(systemName: att.kind == "pdf" ? "doc.richtext" : "photo")
                                    .foregroundStyle(.secondary)
                                Text(att.originalFilename ?? att.kind.capitalized).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "eye").font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { removeAttachment(att) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
```

- [ ] **Step 4: Add the Quick Look modifier (Approach A)**

In `EditTransactionSheet.swift`, find the existing `.sheet(isPresented: $showingSplit) { SplitEditorView(txn: txn) }` line and add, right after it:

```swift
            .quickLookPreview($previewURL)
```

- [ ] **Step 5: Build iOS + macOS — the A/B gate**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: **both** `** BUILD SUCCEEDED **`.
- **If both succeed → Approach A stands. Skip Step 6; go to Step 7.**
- **If `.quickLookPreview` errors on either platform → do Step 6 (Approach B), then re-run this build.**

- [ ] **Step 6: Fallback to Approach B (ONLY if Step 5 failed on `.quickLookPreview`)**

Remove the `.quickLookPreview($previewURL)` line. Create
`ios/FinchApp/Sources/FinchApp/WriteScreens/ReceiptPreview.swift`:

```swift
import SwiftUI
import QuickLook
#if os(iOS)
import UIKit

/// Quick Look preview of a single file (image/PDF). iOS: QLPreviewController in a
/// representable. (macOS handled by the caller via NSWorkspace.)
struct ReceiptPreview: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController(); c.dataSource = context.coordinator; return c
    }
    func updateUIViewController(_ c: QLPreviewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in c: QLPreviewController) -> Int { 1 }
        func previewController(_ c: QLPreviewController, previewItemAt i: Int) -> QLPreviewItem { url as NSURL }
    }
}
#endif
```

Then in `EditTransactionSheet.swift` replace the modifier with a platform split —
on iOS present `ReceiptPreview` in a sheet, on macOS open via `NSWorkspace`. Change
the row action (Step 3) to:

```swift
                        Button {
                            #if os(iOS)
                            previewURL = store.attachmentURL(for: att)
                            #else
                            NSWorkspace.shared.open(store.attachmentURL(for: att))
                            #endif
                        } label: { … }   // (same label as Step 3)
```
and add (instead of `.quickLookPreview`):

```swift
            #if os(iOS)
            .sheet(item: Binding(get: { previewURL.map(IdentifiableURL.init) },
                                 set: { previewURL = $0?.url })) { item in
                ReceiptPreview(url: item.url).ignoresSafeArea()
            }
            #endif
```
with a small `private struct IdentifiableURL: Identifiable { let url: URL; var id: String { url.path } }` near the view. (macOS uses `NSWorkspace`, no sheet.)

- [ ] **Step 7: (If A stands) note it in the policy doc**

In `ios/swiftui-vs-uikit.md`, under "Likely future bridges", update the Quick Look
line to note it's **not** needed — SwiftUI's `.quickLookPreview($url)` handles
in-app receipt preview (iOS 14+/macOS 13+) with no bridge. (Skip if Approach B was used.)

- [ ] **Step 8: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/FinchStore+ViewHelpers.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift \
        ios/swiftui-vs-uikit.md
# (if Approach B: also add ios/FinchApp/Sources/FinchApp/WriteScreens/ReceiptPreview.swift)
git commit -m "feat(ios): tap a receipt to preview it (Quick Look)"
```

---

### Task 2: Manual simulator verification

**Files:** none. Raise the iPhone 17 Pro window by name; use AXPress where coordinate taps miss.

- [ ] **Step 1: Install + launch + ensure a receipt exists**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"; xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```
(If no transaction has a receipt, add one first: open a transaction → Edit → "Add receipt photo" → pick a Photos sample image → save.)

- [ ] **Step 2: Verify**
  - Open a transaction with a receipt in **Edit** → the receipt row shows an **eye** affordance.
  - Tap the row → **Quick Look opens** showing the image (zoom/share available) → Done dismisses back to Edit.
  - **Swipe-to-delete still works** on the row.
  - (If a PDF receipt is available, it previews too.)
  - Screenshot evidence to `/tmp/receipt-preview-<state>.png`.

- [ ] **Step 3 (no commit):** report; if a check fails, return to Task 1.

---

## Self-review notes
- Spec coverage: helper (T1 S1), tappable row (T1 S3), `.quickLookPreview` primary (T1 S4) with B fallback gated on the cross-platform build (T1 S5-S6), doc note (T1 S7), manual (T2). ✓
- Type consistency: `attachmentURL(for:)`, `previewURL: URL?`, `.quickLookPreview($previewURL)` / `ReceiptPreview(url:)` consistent. ✓
- Cross-platform: the macOS build is the explicit A/B decision gate. ✓
