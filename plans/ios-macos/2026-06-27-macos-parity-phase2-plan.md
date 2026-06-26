# macOS parity — Phase 2 (file/PDF receipt picker) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (or executing-plans). Checkbox steps.

**Goal:** macOS gets a Finder file picker (images + PDF) for receipts; iOS keeps PhotosPicker.

**Architecture:** New `AttachmentWriter.writeFile(url:)` (file→attachment with type detection) + `.fileImporter` UI on macOS in both add-receipt sheets. No engine change.

Spec: `plans/ios-macos/2026-06-27-macos-parity-phase2-design.md`.

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS) — both `** BUILD SUCCEEDED **`. No `Co-Authored-By`. No engine change. PR → `feat/frontend`.
- These write-screens are shared/active — keep edits to the listed spots; **re-check `gh pr list` + rebase before pushing**.

---

### Task 1: `AttachmentWriter.writeFile`

**Files:** Modify `ios/FinchApp/Sources/FinchApp/WriteScreens/AttachmentWriter.swift`

- [ ] **Step 1:** Add a `writeFile` method inside `enum AttachmentWriter`, after the existing `write(item:)`:

```swift
    /// macOS/file-picker counterpart of `write(item:)` — copies a picked file
    /// (image or PDF) into the attachments tree and records it.
    @MainActor
    static func writeFile(url: URL, entryId: String, store: FinchStore) async throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        let (kind, mime): (String, String) =
            ext == "pdf"  ? ("pdf", "application/pdf") :
            ext == "png"  ? ("image", "image/png") :
                            ("image", "image/jpeg")
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
(`Foundation`/`CryptoKit`/`FinchCore` are already imported in this file.)

---

### Task 2: EditTransactionSheet — macOS file importer

**Files:** Modify `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift`

- [ ] **Step 1:** Add `import UniformTypeIdentifiers` (after the existing imports at top).

- [ ] **Step 2:** Add state near the other `@State` (e.g. next to `pickedPhoto` at line ~35):

```swift
    @State private var showingFileImporter = false
```

- [ ] **Step 3:** Replace the lone `PhotosPicker` block (line ~217):

```swift
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label("Add receipt photo", systemImage: "camera")
                    }
```
with:

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

- [ ] **Step 4:** Add `addReceiptFile` right after the existing `addReceipt(_:)` method:

```swift
    private func addReceiptFile(_ url: URL) async {
        errorMessage = nil
        do {
            try await AttachmentWriter.writeFile(url: url, entryId: txn.id, store: store)
            attachments = store.attachments(for: txn.id)
        } catch { errorMessage = i18nMessage(error) }
    }
```

---

### Task 3: AddTransactionSheet — macOS file importer (deferred write)

**Files:** Modify `ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift`

- [ ] **Step 1:** Add `import UniformTypeIdentifiers` (after the existing imports).

- [ ] **Step 2:** Add state near `pickedPhoto` (line ~43):

```swift
    @State private var showingFileImporter = false
    @State private var pickedFileURL: URL?
```

- [ ] **Step 3:** Replace the `PhotosPicker` block (line ~131):

```swift
                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            Label(pickedPhoto == nil ? "Add receipt photo" : "Receipt photo selected", systemImage: "camera")
                        }
```
with:

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

- [ ] **Step 4:** After the existing deferred photo write (`if let eid, let photo = pickedPhoto { … }`, line ~418), add:

```swift
                if let eid, let url = pickedFileURL {
                    Task { try? await AttachmentWriter.writeFile(url: url, entryId: eid, store: store) }
                }
```

- [ ] **Step 5: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit** (all 3 files together)

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/AttachmentWriter.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift
git commit -m "feat(ios): macOS file/PDF receipt picker (.fileImporter); iOS keeps PhotosPicker"
```

---

### Task 4: Verify on macOS

**Files:** none.

- [ ] **Step 1: Build + run FinchMac:**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project ios/FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/at-dd >/dev/null 2>&1
open /tmp/at-dd/Build/Products/Debug/finch.app   # product is named finch.app
```

- [ ] **Step 2: Verify** — open Add Transaction (⌘N) and an Edit sheet; the receipt control reads
  **"Add receipt…"** and clicking it opens a **Finder dialog filtered to images + PDF**. (Full
  pick-through is a native dialog — confirm the button + dialog appear; screenshot `/tmp/at-macos.png`.)
  iOS sim sanity: the receipt control is still the PhotosPicker. Clean up `/tmp/at-dd` after.

- [ ] **Step 3 (no commit):** report; if a check fails, return to the relevant task.

---

## Self-review notes
- Spec coverage: `writeFile` (T1); Edit macOS importer + `addReceiptFile` (T2); Add macOS importer + deferred write (T3); build (T3 S5); macOS run (T4). ✓
- Consistency: `writeFile(url:entryId:store:)` signature used by both sheets; `addReceiptFile` mirrors `addReceipt` (errorMessage + attachments refresh); `pickedFileURL` deferred like `pickedPhoto`; `import UniformTypeIdentifiers` for `[.image, .pdf]`. ✓
- No engine change; iOS path unchanged. ✓
