# macOS parity — Phase 2: file/PDF receipt picker

**Date:** 2026-06-27
**Status:** Design approved, pending implementation
**Scope:** Give macOS a native Finder file picker (with PDF support) for receipts, alongside the existing iOS PhotosPicker. UI + a new `AttachmentWriter` method. No engine change.
**Roadmap:** Phase 2 of `2026-06-27-macos-parity-roadmap-design.md`.

## Premise

Both add-receipt sites (`AddTransactionSheet`, `EditTransactionSheet`) use
`PhotosPicker(matching: .images)`. PhotosPicker *does* work on macOS, but it only reaches the
Photos library — there's **no Finder file picking and no PDF support** (the engine's
`setEntryAttachment` already accepts `kind` ∈ {image, pdf}). Phase 2 adds a `.fileImporter`
path on macOS.

## Design

### 1. `AttachmentWriter.writeFile(url:entryId:store:)`  *(new, `WriteScreens/AttachmentWriter.swift`)*

Mirrors the existing `write(item:)` but takes a file URL:

```swift
    @MainActor
    static func writeFile(url: URL, entryId: String, store: FinchStore) async throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        let (kind, mime): (String, String) =
            ext == "pdf"  ? ("pdf", "application/pdf") :
            ext == "png"  ? ("image", "image/png") :
                            ("image", "image/jpeg")          // jpg/jpeg/heic/… → jpeg
        let attId = "att-\(UUID().uuidString.prefix(8).lowercased())"
        let dir = store.attachmentsRoot.appendingPathComponent(entryId, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeExt = ext.isEmpty ? "dat" : ext
        let rel = "attachments/\(entryId)/\(attId).\(safeExt)"
        try data.write(to: store.attachmentsRoot.deletingLastPathComponent().appendingPathComponent(rel))
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try store.apply(.setEntryAttachment, Args([
            "entryId": .string(entryId), "kind": .string(kind), "relPath": .string(rel),
            "mimeType": .string(mime), "byteSize": .double(Double(data.count)), "sha256": .string(sha)]))
    }
```

### 2. `EditTransactionSheet` — entry exists (`txn.id`)

Add `@State private var showingFileImporter = false` and `import UniformTypeIdentifiers`.
Replace the lone `PhotosPicker` (line ~217) with a platform split:

```swift
                    #if os(macOS)
                    Button { showingFileImporter = true } label: { Label("Add receipt…", systemImage: "paperclip") }
                        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.image, .pdf]) { result in
                            if case .success(let url) = result { Task { await addReceiptFile(url) } }
                        }
                    #else
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label("Add receipt photo", systemImage: "camera")
                    }
                    #endif
```
Add a sibling of `addReceipt(_:)`:

```swift
    private func addReceiptFile(_ url: URL) async {
        do { try await AttachmentWriter.writeFile(url: url, entryId: txn.id, store: store) }
        catch { errorMessage = i18nMessage(error) }
    }
```
(Match `addReceipt`'s existing error handling — reuse its `do/catch`/`errorMessage` pattern.)

### 3. `AddTransactionSheet` — entry created on save (deferred write)

Add `@State private var showingFileImporter = false`, `@State private var pickedFileURL: URL?`,
and `import UniformTypeIdentifiers`. Replace the `PhotosPicker` (line ~131) with:

```swift
                        #if os(macOS)
                        Button { showingFileImporter = true } label: {
                            Label(pickedFileURL == nil ? "Add receipt…" : "Receipt selected", systemImage: "paperclip")
                        }
                        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.image, .pdf]) { result in
                            if case .success(let url) = result { pickedFileURL = url }
                        }
                        #else
                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            Label(pickedPhoto == nil ? "Add receipt photo" : "Receipt photo selected", systemImage: "camera")
                        }
                        #endif
```
After the existing deferred photo write (the `if let eid, let photo = pickedPhoto { … }` block,
line ~418), add the file equivalent (harmless on iOS — `pickedFileURL` is nil there):

```swift
                if let eid, let url = pickedFileURL {
                    Task { try? await AttachmentWriter.writeFile(url: url, entryId: eid, store: store) }
                }
```

## Out of scope
- Decimal/keyboard input audit (PhotosPicker works on macOS; `DecimalInput` already locale-aware
  — no real gap; sanity-check only, no code). Drag-and-drop attach. iOS PDF picking (kept
  images-only via PhotosPicker). Engine changes.

## Testing
- **Build:** FinchApp (iOS) + FinchMac (macOS) — both `** BUILD SUCCEEDED **`.
- **macOS run:** FinchMac launches; the receipt control reads **"Add receipt…"** and opens a
  Finder dialog filtered to images + PDF. (Full pick-through is a native dialog — not reliably
  scriptable; relying on build + code review + parity with the proven `write(item:)`.)
- **iOS:** unchanged — PhotosPicker still adds image receipts.

## Notes
- Collision: `AddTransactionSheet`/`EditTransactionSheet`/`AttachmentWriter` — re-check
  `gh pr list` + rebase before pushing. PR → `feat/frontend`.
