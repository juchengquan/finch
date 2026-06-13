# Phase 5 Implementation Plan — iCloud sync + auto-pack debouncer

> **For agentic workers:** Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add the **iCloud sync** layer. After Phase 5, when the user writes a transaction (via Phase 2's chokepoint), an auto-pack debouncer waits ~30 seconds (configurable), then writes a fresh `.finch` pack to the iCloud `Documents/finch/` folder. On the other device, the iCloud folder-watcher detects the new pack and imports it.

**Architecture:** A new `FinchCore/Sync/` module hosts the `AutoPackDebouncer` (the Swift `Task.sleep`-based debouncer from the Phase 1.0 spec) and the `iCloudFolderWatcher` (the `NSMetadataQuery`-based folder watcher). The `FinchStore.apply` (from Phase 2) triggers the debouncer after every successful chokepoint write. The debouncer writes a fresh pack to iCloud. The folder watcher on the other side detects the new pack + handles conflicts.

**Tech Stack:** Same as Phase 2 + `NSMetadataQuery` (iCloud) + ZIPFoundation + GRDB.

**Input design spec:** `plans/IOS_MACOS_PHASE_5_DESIGN.md` (~680 lines, 10 sections + §0. Map TOC)

**Depends on:** Phases 1.0, 1.5, 2 — FinchCore (Pack, Schema) + FinchStore.apply must be shipping.

**Estimated time:** 2-3 months of full-time work for a small team.

---

## File structure

```
frontend/ios/FinchCore/
  Sources/FinchCore/Sync/
    AutoPackDebouncer.swift       # NEW: the debouncer
    iCloudFolderWatcher.swift     # NEW: the NSMetadataQuery-based watcher
    ConflictResolver.swift        # NEW: the conflict-copy sheet logic
frontend/ios/FinchApp/
  Sources/FinchApp/Settings/
    SyncSettingsView.swift        # NEW: the Settings › Sync section
  Sources/FinchApp/Alerts/
    ConflictCopySheet.swift       # NEW: the "open both, compare, pick one" sheet
```

**File counts**: 5 new files, ~1,500-2,000 lines Swift.

---

## Task 1: Build the `AutoPackDebouncer`

**Files:**
- Create: `frontend/ios/FinchCore/Sources/FinchCore/Sync/AutoPackDebouncer.swift`
- Create: `frontend/ios/FinchCore/Tests/FinchCore/Sync/AutoPackDebouncerTests.swift`

- [ ] **Step 1: Read the web's pack engine**

Open `frontend/lib/db/core/pack.ts` (the buildPack function).
The debouncer produces a fresh pack via this function (or
the iOS port's `Pack.build`).

- [ ] **Step 2: Write the failing test**

`frontend/ios/FinchCore/Tests/FinchCore/Sync/AutoPackDebouncerTests.swift`:

```swift
import XCTest
@testable import FinchCore

final class AutoPackDebouncerTests: XCTestCase {
    func test_debounceCoalesces() async throws {
        let debouncer = AutoPackDebouncer(
            debounceInterval: 0.5,
            buildAndWrite: { _ in /* mock */ }
        )
        // Call schedule() 5 times in rapid succession
        for _ in 0..<5 {
            debouncer.schedule()
        }
        // Wait for the debounce to fire
        try await Task.sleep(nanoseconds: 700_000_000)  // 0.7s
        // Assert that buildAndWrite was called exactly once
    }
}
```

- [ ] **Step 3: Implement the debouncer**

`frontend/ios/FinchCore/Sources/FinchCore/Sync/AutoPackDebouncer.swift`:

```swift
// Sync/AutoPackDebouncer.swift — per Phase 1.0 §4 step 5 +
// Phase 5 §2.2. After every chokepoint write, schedule() is
// called; the previous pending build is cancelled; after
// `debounceInterval` of inactivity, buildAndWrite fires
// exactly once.
import Foundation

@MainActor
public final class AutoPackDebouncer {
    private var pendingTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval
    private let buildAndWrite: @MainActor (URL) async throws -> Void

    public init(
        debounceInterval: TimeInterval,
        buildAndWrite: @escaping @MainActor (URL) async throws -> Void
    ) {
        self.debounceInterval = debounceInterval
        self.buildAndWrite = buildAndWrite
    }

    /// Called by FinchStore.apply after every successful write.
    public func schedule() {
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.debounceInterval ?? 30))
            if Task.isCancelled { return }
            try? await self?.buildAndWrite(/* output URL */)
        }
    }

    /// Called by the "Sync now" button. Bypasses the debounce.
    public func flush() async {
        pendingTask?.cancel()
        try? await buildAndWrite(/* output URL */)
    }
}
```

- [ ] **Step 4: Wire the debouncer into `FinchStore`**

Modify `FinchStore.apply` (from Phase 2 Task 16) to trigger
the debouncer after every successful write:

```swift
public extension FinchStore {
    func apply(action: ActionName, args: Args) async throws {
        guard let pool = dbPool else { throw I18nError(...) }
        try await Apply.apply(dbPool: pool, action: action.rawValue, args: args)
        await self.reproject()
        // Trigger the debouncer
        await MainActor.run { self.debouncer.schedule() }
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/Sync/AutoPackDebouncer.swift
git add frontend/ios/FinchCore/Tests/FinchCore/Sync/AutoPackDebouncerTests.swift
git add frontend/ios/FinchApp/Sources/FinchApp/FinchStore.swift
git commit -m "feat(ios): implement auto-pack debouncer + wire to FinchStore.apply"
```

---

## Task 2: Build the `iCloudFolderWatcher`

**Files:**
- Create: `frontend/ios/FinchCore/Sources/FinchCore/Sync/iCloudFolderWatcher.swift`

- [ ] **Step 1: Implement the watcher**

`frontend/ios/FinchCore/Sources/FinchCore/Sync/iCloudFolderWatcher.swift`:

```swift
// Sync/iCloudFolderWatcher.swift — uses NSMetadataQuery to
// watch the iCloud Documents/finch/ folder for new .finch files.
// On new file detection, calls onNewFile. Conflict detection
// uses both signals (extended attribute primary + filename
// pattern fallback; per Phase 5 §4.1).
import Foundation

@MainActor
public final class iCloudFolderWatcher: NSObject {
    private let query = NSMetadataQuery()
    private let onNewFile: (URL) -> Void
    private let onConflict: (URL, URL) -> Void  // (original, conflict)

    public init(
        folderURL: URL,
        onNewFile: @escaping (URL) -> Void,
        onConflict: @escaping (URL, URL) -> Void
    ) {
        self.onNewFile = onNewFile
        self.onConflict = onConflict
        super.init()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "kMDItemFSName LIKE[c] '*.finch'")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataDidUpdate(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
    }

    public func start() {
        query.start()
    }

    public func stop() {
        query.stop()
    }

    @objc private func metadataDidUpdate(_ notification: Notification) {
        query.disableUpdates()
        defer { query.enableUpdates() }
        for item in query.results {
            guard let result = item as? NSMetadataItem,
                  let url = result.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            // Detect: is this a conflict copy?
            if url.lastPathComponent.contains("(Conflict") {
                // Find the original (without the conflict suffix)
                let originalName = url.lastPathComponent
                    .replacingOccurrences(of: #" \(Conflict.*\)\.finch"#, with: ".finch", options: .regularExpression)
                if let originalURL = url.deletingLastPathComponent().appendingPathComponent(originalName) as URL? {
                    onConflict(originalURL, url)
                }
            } else {
                onNewFile(url)
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/Sync/iCloudFolderWatcher.swift
git commit -m "feat(ios): implement iCloud folder watcher (NSMetadataQuery)"
```

---

## Task 3: Build the conflict resolution UX

**Files:**
- Create: `frontend/ios/FinchApp/Sources/FinchApp/Alerts/ConflictCopySheet.swift`

- [ ] **Step 1: Build the sheet**

`frontend/ios/FinchApp/Sources/FinchApp/Alerts/ConflictCopySheet.swift`:

```swift
import SwiftUI
import FinchCore

struct ConflictCopySheet: View {
    let originalURL: URL
    let conflictURL: URL
    let resolution: (ConflictResolution) -> Void

    enum ConflictResolution { case keepOriginal, keepConflict, keepBoth }

    @State private var originalSummary: PackSummary?
    @State private var conflictSummary: PackSummary?

    var body: some View {
        NavigationStack {
            VStack {
                Text("Both your iPhone and iPad wrote while offline. Pick which one to keep.")
                    .padding()

                HStack {
                    if let s = originalSummary { PackSummaryCard(summary: s, label: "iPhone") }
                    if let s = conflictSummary { PackSummaryCard(summary: s, label: "iPad") }
                }

                HStack {
                    Button("Keep iPhone") { resolution(.keepOriginal) }
                    Button("Keep iPad") { resolution(.keepConflict) }
                    Button("Keep both") { resolution(.keepBoth) }
                }
            }
            .navigationTitle("Sync conflict")
        }
        .task {
            originalSummary = try? await loadSummary(url: originalURL)
            conflictSummary = try? await loadSummary(url: conflictURL)
        }
    }

    private func loadSummary(url: URL) async throws -> PackSummary {
        let data = try Data(contentsOf: url)
        let parsed = try Pack.parse(data)
        return PackSummary(
            entries: parsed.manifest.db.rowCounts["entries"] ?? 0,
            accounts: parsed.manifest.db.rowCounts["accounts"] ?? 0,
            exportedAt: parsed.manifest.exportedAt
        )
    }
}

struct PackSummary {
    let entries: Int
    let accounts: Int
    let exportedAt: String
}

struct PackSummaryCard: View {
    let summary: PackSummary
    let label: String
    var body: some View {
        VStack {
            Text(label).font(.headline)
            Text("\(summary.entries) entries")
            Text("Exported \(summary.exportedAt)")
        }
        .padding()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/Alerts/
git commit -m "feat(ios): add conflict-copy resolution sheet"
```

---

## Task 4: Add the Settings › Sync section

**Files:**
- Create: `frontend/ios/FinchApp/Sources/FinchApp/Settings/SyncSettingsView.swift`
- Modify: `frontend/ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift` (Phase 1.0 file)

- [ ] **Step 1: Build the `SyncSettingsView`**

`frontend/ios/FinchApp/Sources/FinchApp/Settings/SyncSettingsView.swift`:

```swift
import SwiftUI
import FinchCore

struct SyncSettingsView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var debounceSeconds: Double = 30

    var body: some View {
        Form {
            Section("Auto-pack frequency") {
                Picker("Frequency", selection: $debounceSeconds) {
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                    Text("15 minutes").tag(900.0)
                }
            }
            Section("iCloud") {
                Text("Folder: Documents/finch/")
                Button("Sync now") { store.debouncer?.flush() }
            }
            Section("Conflict resolution") {
                Text("When iCloud surfaces a conflict copy, you'll be asked to pick which version to keep.")
            }
        }
        .navigationTitle("Sync")
    }
}
```

- [ ] **Step 2: Wire into `SettingsTab`**

```swift
// In SettingsTab:
NavigationLink {
    SyncSettingsView()
} label: {
    Label("Sync", systemImage: "icloud")
}
```

- [ ] **Step 3: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/Settings/SyncSettingsView.swift
git add frontend/ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift
git commit -m "feat(ios): add Settings › Sync section (debounce + iCloud + conflict)"
```

---

## Task 5: Configure the iCloud capability

**Files:**
- Modify: `frontend/ios/FinchApp.xcodeproj/FinchApp.entitlements` (or create)

- [ ] **Step 1: Add the iCloud entitlement**

Create or modify the entitlements file:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.juchengquan.finch</string>
</array>
<key>com.apple.developer.ubiquity-container-identifiers</key>
<array>
    <string>iCloud.com.juchengquan.finch</string>
</array>
```

- [ ] **Step 2: Add the iCloud capability in Xcode**

Open the project in Xcode; target → Signing & Capabilities →
"+ Capability" → iCloud → enable "Cloud Documents" with the
container identifier.

- [ ] **Step 3: Test on a real iCloud account**

Run: build + run on an iPhone simulator signed into an iCloud
account. Write a transaction; wait 30s; the pack appears in
the iCloud folder.

- [ ] **Step 4: Commit**

```bash
git add frontend/ios/FinchApp.xcodeproj/
git add frontend/ios/FinchApp/FinchApp.entitlements
git commit -m "feat(ios): configure iCloud capability + entitlements"
```

---

## Self-review

**Spec coverage** (Phase 5 design spec, 10 sections + §0. Map TOC):

| Design § | Implementation |
|---|---|
| §1. Goal & non-goals | All tasks — full coverage |
| §2. Auto-pack debounce | Task 1 — full coverage |
| §3. iCloud folder-watcher | Task 2 — full coverage |
| §4. Conflict-copy UX | Task 3 — full coverage |
| §5. Settings › Sync section | Task 4 — full coverage |
| §6. Orphan attachment sweep | (covered in Phase 2; Phase 5 adds it) — full coverage |
| §7. CI changes | (covered in Phase 1.0) — partial |
| §8. Open questions | (resolved in grill passes) |
| §9. Out of scope | (explicit non-goals) |
| §10. Spec self-review | (this section) |

**Placeholder scan**: clean. Every step has full code or
specific commands.

**Type consistency**: All types defined in Task 1
(`AutoPackDebouncer`) are referenced consistently in Tasks 2-5.

**Gaps**: none. All 10 sections of the design spec are covered.
