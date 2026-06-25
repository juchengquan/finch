# Receipt thumbnails in the Edit attachment list

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** Show an image thumbnail (instead of a generic icon) for image attachments in the Edit sheet's receipt list. UI-only, no engine change.

## Problem

The Edit sheet lists each attachment with a generic `photo` / `doc.richtext` SF Symbol
(#289). You can't tell receipts apart at a glance without previewing each.

## Design

### 1. `ReceiptThumbnail` view (new file)

A small, focused, cross-platform thumbnail:

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
                Image(systemName: "photo").foregroundStyle(.secondary)   // placeholder / unreadable
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
PDFs keep the doc icon (a rendered PDF-page thumbnail is heavier — out of scope). The
placeholder `photo` icon also covers an unreadable/missing file, so the row never breaks.

### 2. Use it in the Edit attachment row

In `EditTransactionSheet.swift`, in the `ForEach(attachments)` row, replace the leading:

```swift
                                Image(systemName: att.kind == "pdf" ? "doc.richtext" : "photo")
                                    .foregroundStyle(.secondary)
```
with:

```swift
                                ReceiptThumbnail(url: store.attachmentURL(for: att), kind: att.kind)
```
Everything else in the row (filename `Text`, the `eye` affordance, tap-to-preview #289,
swipe-delete) is unchanged.

## Out of scope
- PDF page thumbnails; thumbnails anywhere other than the Edit list (the feed paperclip
  #327, the Add sheet); background-thread decode / downsampling (few small attachments).
- Any engine change — reuses `store.attachmentURL(for:)`.

## Testing

**App (build + manual sim):**
- Open a transaction with an **image** receipt in Edit → its row shows the **image
  thumbnail** (not the photo icon); the filename, preview tap, and swipe-delete still work.
- A **PDF** attachment still shows the doc icon. A missing/unreadable file falls back to
  the photo icon (no crash).
- iOS + macOS build.

No engine test — pure view, reuses the #289 attachment helpers.

## Notes
- `.task(id: url)` loads lazily and re-loads if the row's URL changes. Synchronous
  `UIImage(contentsOfFile:)` is fine for the handful of small attachments a transaction
  has; revisit with downsampling only if large receipts cause a hitch.
- PR targets `feat/frontend`.
