# Preview a receipt from a transaction row

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** A receipt indicator on feed rows that have attachments, tappable to Quick Look — without opening Edit. UI-only, reuses #289. No engine change.

## Problem

In-app receipt preview (#289) is reachable only from the Edit sheet. The feed doesn't
show which transactions have a receipt, and there's no quick way to glance at one.

## Design

Reuse the existing helpers: `store.attachments(for: txId) -> [AttachmentRow]`,
`store.attachmentURL(for:) -> URL`, and `.quickLookPreview($url)` (#289).

### 1. `TxRow` — paperclip accessory

`TxRow` (shared by the feed + merchant detail) gains an optional callback so the
preview state stays in the feed:

```swift
    var onPreviewReceipt: ((Tx) -> Void)? = nil
    private var receipts: [AttachmentRow] { store.attachments(for: txn.id) }
```
Between the trailing `Spacer()` and the amount `Text`, when a preview handler is set
and the transaction has attachments, show a tappable paperclip:

```swift
            Spacer()
            if let onPreviewReceipt, !receipts.isEmpty {
                Button { onPreviewReceipt(txn) } label: {
                    Image(systemName: "paperclip").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)            // own tap target inside the row's Button
                .accessibilityLabel("Preview receipt")
            }
            Text(store.displayMoneyBase(txn.amount)).fontWeight(.semibold)
```
The merchant-detail usage (`TxRow(txn:)`) omits the callback ⇒ no paperclip there.

### 2. The feed — wire preview state + context menu

In `ActivityFeedView`:
- `@State private var previewURL: URL?`
- A helper:
  ```swift
  private func previewReceipt(_ tx: Tx) {
      if let first = store.attachments(for: tx.id).first { previewURL = store.attachmentURL(for: first) }
  }
  ```
- In `row(_:)`, pass the callback (disabled in selection mode so taps drive selection):
  ```swift
  TxRow(txn: txn, onPreviewReceipt: isSelecting ? nil : { previewReceipt($0) })
  ```
- Add a context-menu item (robust path + Mac parity, since the touch tap doesn't apply
  on Mac) to the existing `.contextMenu` in `row(_:)`:
  ```swift
  if !store.attachments(for: txn.id).isEmpty {
      Button { previewReceipt(txn) } label: { Label("Preview receipt", systemImage: "paperclip") }
  }
  ```
- Add the Quick Look modifier to the feed (alongside `.errorAlert`):
  ```swift
  .quickLookPreview($previewURL)
  ```

## Behavior
- The paperclip both **flags** rows with a receipt and **previews on tap**.
- **Multiple attachments → previews the first**; open Edit to see all (the Edit sheet
  already lists every attachment, #289).
- Tapping the paperclip does **not** open Edit (the inner `.borderless` button has its
  own tap target); tapping elsewhere on the row still opens Edit.

## Out of scope
- A paperclip on the merchant-detail rows (the callback isn't passed there).
- Previewing all attachments inline / a gallery; any engine change.

## Testing

**App (build + manual sim):**
- Seed/attach a receipt to a transaction → its feed row shows a **paperclip**; tap it →
  Quick Look opens the image/PDF (no Edit sheet). Rows without a receipt show none.
- Long-press a row with a receipt → **Preview receipt** in the context menu works too.
- iOS + macOS build.

No engine test — reuses the #289 attachment helpers (already covered).

## Notes
- `store.attachments(for:)` filters the in-memory attachment list (small); fine to call
  per visible row.
- PR targets `feat/frontend`.
