# In-app attachment (receipt) preview (iOS/macOS)

**Date:** 2026-06-25
**Status:** Design approved, pending implementation
**Scope:** Tap a receipt in the Edit form's Receipts list to preview it (image/PDF) via Quick Look. Pure SwiftUI primary path; UIKit bridge as a documented fallback.

## Problem

Receipts can be attached to a transaction (photo picker → `AttachmentWriter` → file
on disk + `entry_attachments` row) and are listed in `EditTransactionSheet`'s
**Receipts** section — but the rows are display-only (icon + filename + swipe-to-
delete). There's **no way to view a receipt in-app** (0 Quick Look / PDFKit usage,
per the SwiftUI-vs-UIKit audit).

## Goal

Tapping a receipt row opens a **Quick Look preview** of its file (images + PDFs,
with Quick Look's built-in zoom/share). Works on iOS and macOS (FinchMac).

## Design

### 1. File-URL helper (FinchStore)

Add to `FinchStore+ViewHelpers.swift` (centralizing the pattern already used by
`AttachmentWriter` / `unlink` / tests):

```swift
/// Absolute on-disk URL for an attachment (relPath already includes "attachments/…").
public func attachmentURL(for att: AttachmentRow) -> URL {
    attachmentsRoot.deletingLastPathComponent().appendingPathComponent(att.relPath)
}
```

### 2. Preview — SwiftUI `.quickLookPreview` (primary, Approach A)

In `EditTransactionSheet`:
- `import QuickLook`
- New `@State private var previewURL: URL?`
- Make each Receipts row **tappable** (a `Button` wrapping the existing
  icon + filename `HStack`, `.buttonStyle(.plain)`) that sets
  `previewURL = store.attachmentURL(for: att)`. The existing
  `.swipeActions { Delete }` stays.
- Add `.quickLookPreview($previewURL)` to the Form/NavigationStack. Setting the
  binding presents the system Quick Look sheet; clearing it (Quick Look's Done)
  dismisses. This works on **both** iOS 17 and macOS 14 (the modifier is
  iOS 14+ / macOS 13+), so **no UIKit bridge is needed**.

This updates the SwiftUI-vs-UIKit policy's assumption (it listed Quick Look as a
"likely future UIKit bridge"; the SwiftUI modifier covers it). A one-line note will
be added to `ios/swiftui-vs-uikit.md`.

### 3. Fallback — UIKit/AppKit bridge (Approach B, only if A fails at the floor)

If `.quickLookPreview` proves unavailable or misbehaves at the iOS 17 / macOS 14
floor (verified at build time in Task 1), fall back to a `ReceiptPreview` wrapper:
- **iOS:** `QLPreviewController` in a `UIViewControllerRepresentable`, presented via
  `.sheet(item: $previewItem)`.
- **macOS:** `NSWorkspace.shared.open(url)` (opens the receipt in Preview.app).

The trigger, helper, and row changes (§1–§2) are identical either way; only the
presentation mechanism differs. The plan implements A and switches to B only if the
build/compile check fails.

## Out of scope
- Markup / annotation of receipts (Quick Look provides view + share only).
- Previewing from anywhere other than the Edit Receipts list (e.g. transaction rows
  or a gallery) — a later enhancement.
- Thumbnails in the list (the row keeps its icon).

## Testing

**Build:** `xcodebuild build` FinchApp (iOS) **and** FinchMac (macOS) — the macOS
build proves `.quickLookPreview` (or the fallback) compiles cross-platform. This is
the gate that decides A vs B.

**App tests:** the existing suite stays green (no engine change; `attachmentURL` is a
pure path helper — add a small unit test asserting it composes
`<root>/attachments/<entryId>/<file>` for a sample relPath if a FinchApp test
target fixture is convenient; otherwise covered by manual).

**Manual (sim):** attach a photo to a transaction → reopen Edit → tap the receipt
row → Quick Look opens showing the image; Done dismisses; swipe-to-delete still
works. (PDF path exercised if a PDF attachment is available.)

## Notes
- No engine / DB / parity changes — purely the app layer + one path helper.
- PR targets `feat/frontend`.
