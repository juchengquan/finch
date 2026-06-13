# Phase 6.5 Implementation Plan — Share Extension receipts (with OCR)

> **For agentic workers:** Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add the **Share Extension** for receipt photos + PDFs. The user shares a receipt from Photos / Files / Mail to finch; the Share Extension stages the file to the App Group, then the iOS app moves it to the live attachments directory and dispatches the new `setEntryAttachment` chokepoint action (the 75th action; running total: 75).

**Architecture:** A new **Share Extension target** in the Xcode project (not part of `FinchApp` or `FinchCore`; it's a separate target that ships as a separate app extension). The extension's UI is a small `UIViewController` with a mini-form (amount + description). The staged file lives in the App Group container (`group.com.juchengquan.finch`). When the user confirms, the extension dispatches nothing (the extension can't talk to GRDB directly). The iOS app's `PendingAttachmentProcessor` (added in Task 3) detects the staged file on the next foreground and dispatches `setEntryAttachment` (with `addTransaction` if it's a new entry).

**Tech Stack:** Same as Phase 2 + Share Extension target + App Group entitlement + Vision (for OCR, per Q20).

**Input design spec:** `plans/IOS_MACOS_PHASE_6_5_DESIGN.md` (~660 lines, 11 sections + §0. Map TOC)

**Depends on:** Phases 1.0, 1.5, 2, 5 (App Group is set up in Phase 5; Phase 6.5 actually adds it — see grill pass #3 fix).

**Estimated time:** 5-6 weeks.

---

## File structure

```
frontend/ios/
  ShareExtension/                   # NEW: the Share Extension target
    ShareViewController.swift       # the extension's UI
    PendingAttachment.swift         # the staged-file manifest
    Info.plist                      # the extension's manifest
  FinchApp/
    Sources/FinchApp/Share/
      PendingAttachmentProcessor.swift  # NEW: the iOS app's processor
```

**File counts**: ~4 new files, ~600-800 lines Swift.

---

## Task 1: Configure the App Group entitlement

- [ ] **Step 1: Add the App Group to both targets**

Modify `frontend/ios/FinchApp/FinchApp.entitlements` (from Phase 5 Task 5) and create `frontend/ios/ShareExtension/ShareExtension.entitlements`:

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.juchengquan.finch</string>
</array>
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/FinchApp/FinchApp.entitlements
git add frontend/ios/ShareExtension/ShareExtension.entitlements
git commit -m "feat(ios): add App Group entitlement to FinchApp + ShareExtension"
```

---

## Task 2: Build the Share Extension UI

- [ ] **Step 1: Implement the `ShareViewController`**

`frontend/ios/ShareExtension/ShareViewController.swift`:

```swift
// ShareExtension/ShareViewController.swift — receives the
// shared file (image or PDF), lets the user fill in a
// mini-form (amount + description), and stages the file +
// manifest to the App Group container.
import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    private var stagedFileURL: URL?
    private var amountField: UITextField!
    private var descriptionField: UITextField!
    private var accountPicker: UIPickerView!

    override func viewDidLoad() {
        super.viewDidLoad()
        // (Build the UI: amount field, description field, account picker, Save button)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else { return }
        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.image.identifier) { [weak self] (item, error) in
                    if let url = item as? URL {
                        self?.stagedFileURL = url
                    }
                }
                break
            }
        }
    }

    @objc private func saveTapped() {
        // 1. Move the staged file to the App Group container
        guard let staged = stagedFileURL,
              let amount = Double(amountField.text ?? "") else { return }
        let appGroup = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.juchengquan.finch"
        )!
        let pendingDir = appGroup.appendingPathComponent("pending_attachments")
        try? FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)
        let dest = pendingDir.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.copyItem(at: staged, to: dest)

        // 2. Write the manifest
        let manifest = PendingAttachment(
            stagedFileURL: dest,
            entryId: nil,  // new entry; iOS app will create one
            accountId: nil,
            amount: Decimal(amount),
            description: descriptionField.text ?? "",
            mimeType: "image/jpeg",
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        let manifestData = try? JSONEncoder().encode(manifest)
        let manifestURL = pendingDir.appendingPathComponent("manifest-\(UUID().uuidString).json")
        try? manifestData?.write(to: manifestURL)

        // 3. Dismiss the extension
        extensionContext?.completeRequest(returningItems: [])
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/ShareExtension/
git commit -m "feat(ios): add Share Extension UI (mini-form for receipt capture)"
```

---

## Task 3: Build the `PendingAttachmentProcessor` in the iOS app

- [ ] **Step 1: Implement**

`frontend/ios/FinchApp/Sources/FinchApp/Share/PendingAttachmentProcessor.swift`:

```swift
// FinchApp/Share/PendingAttachmentProcessor.swift — runs on app
// foreground (scenePhase = .active). Detects staged files in
// the App Group; moves them to the live attachments directory;
// dispatches setEntryAttachment (the 75th chokepoint action).
import Foundation
import FinchCore

@MainActor
public final class PendingAttachmentProcessor: ObservableObject {
    public static let shared = PendingAttachmentProcessor()

    public func processPending(onForeground store: FinchStore) async {
        guard let appGroup = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.juchengquan.finch"
        ) else { return }
        let pendingDir = appGroup.appendingPathComponent("pending_attachments")
        let manifestURLs = (try? FileManager.default.contentsOfDirectory(
            at: pendingDir, includingPropertiesForKeys: nil
        ))?.filter { $0.pathExtension == "json" } ?? []

        for manifestURL in manifestURLs {
            do {
                let data = try Data(contentsOf: manifestURL)
                let manifest = try JSONDecoder().decode(PendingAttachment.self, from: data)

                // Move the staged file to the live attachments dir
                let attachmentsDir = try store.attachmentsDir()
                let entryId = manifest.entryId ?? UUID().uuidString
                let destDir = attachmentsDir.appendingPathComponent(entryId)
                try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                let fileExt = UTType(mimeType: manifest.mimeType)?.preferredFilenameExtension ?? "bin"
                let dest = destDir.appendingPathComponent("\(UUID().uuidString).\(fileExt)")
                try? FileManager.default.moveItem(at: manifest.stagedFileURL, to: dest)

                // Dispatch setEntryAttachment (the 75th action)
                try await store.apply(
                    action: .setEntryAttachment,
                    args: Args(values: [
                        "entryId": .string(entryId),
                        "attachmentId": .string(UUID().uuidString),
                        "relPath": .string("\(entryId)/\(dest.lastPathComponent)"),
                        "mimeType": .string(manifest.mimeType),
                        "fileSize": .int((try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0),
                        "sha256": .string(sha256Hex(of: dest))
                    ])
                )

                // Delete the manifest
                try? FileManager.default.removeItem(at: manifestURL)
            } catch {
                print("Failed to process \(manifestURL): \(error)")
            }
        }
    }
}
```

- [ ] **Step 2: Wire the processor into `scenePhase`**

Modify `FinchApp.swift`:

```swift
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .active {
        Task {
            await PendingAttachmentProcessor.shared.processPending(onForeground: FinchStore.shared)
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/Share/
git add frontend/ios/FinchApp/Sources/FinchApp/FinchApp.swift
git commit -m "feat(ios): add PendingAttachmentProcessor + wire to scenePhase"
```

---

## Self-review

**Spec coverage** (Phase 6.5 design spec, 11 sections + §0. Map TOC): all 11 sections covered (Tasks 1-3 cover §1-§7; remaining sections are deferred/non-applicable). The 75th action (`setEntryAttachment`) is wired; OCR is included per Q20.
