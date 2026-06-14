# Phase 8 Implementation Plan — CloudKit row-level sync

> _Web facts verified against commit `22c9896` (SCHEMA_VERSION `2026-06-14T00:00:00Z`), 2026-06-13.
> See `_WEB_DRIFT_CHECKLIST.md`._

> **For agentic workers:** Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add **row-level sync** via CloudKit. After Phase 8, when the user writes a transaction (via Phase 2's chokepoint), the iOS app immediately enqueues a `Mutation` record to CloudKit; the other device receives the record via a `CKQuerySubscription` and dispatches the same chokepoint action. Sub-second latency. Last-writer-wins on conflict (the audit gate is the safety net). Phase 8 is a **future roadmap item** after Phase 7 ships.

> **Schema prerequisite:** Phase 8 ADDS two new sync columns — `revision_id` and `device_id` — to `entries` and `postings`. These do **not** exist in the web schema today: the web's idempotency backstop is `dedup_hash` (unique index `idx_entry_dedup`, `entries-schema.ts:72`) plus `postEntry` being replay-idempotent keyed on `entry_id` alone (`entries.ts:258`). The `revisionId` / `deviceId` fields on `MutationEvent` (Task 1) and the CloudKit `Mutation` record map to these Phase-8-added columns, and the `(entry_id, revision_id)` last-writer-wins key depends on them.

> **Provisioning prerequisite — do this FIRST (see DESIGN §5.1):** CloudKit is a **paid-tier** capability. Before any of the live tasks below, join the **Apple Developer Program ($99/yr)** and create the `iCloud.com.juchengquan.finch` CloudKit container; a free Apple ID cannot. The pure mapping/conflict core (`CloudKitSync.swift`) is already built + CI-tested with no account, but the live push/pull/subscription loop can only be **run or verified after provisioning** — building it before then is coding blind. Don't pre-build the untestable live integration; provision, then execute Tasks 2–5 against a real container.

**Architecture:** A new `FinchCore/CloudKit/` module hosts the `CloudKitSyncDaemon` (the writer + the reader). The writer enqueues `Mutation` records to a private CloudKit database; the reader subscribes to `Mutation` records via `CKQuerySubscription` and dispatches each via `FinchStore.apply`. Per Q22, Phase 8 is **committed to building** (not deferred).

**Tech Stack:** Same as Phase 2 + `CloudKit` (`CKContainer`, `CKDatabase`, `CKRecord`, `CKQuerySubscription`).

**Input design spec:** `plans/ios-macos/IOS_MACOS_PHASE_8_DESIGN.md` (~570 lines, 9 sections + §0. Map TOC)

**Depends on:** Phases 1.0, 1.5, 2 + 6.5 (the 75th `setEntryAttachment` action).

**Estimated time:** 3-4 months.

---

## File structure

```
frontend/ios/FinchCore/
  Sources/FinchCore/CloudKit/
    CloudKitSyncDaemon.swift     # NEW: the writer + reader
    MutationEvent.swift            # NEW: the wire format for a mutation
    ConflictResolver.swift         # NEW: the LWW resolver
```

**File counts**: 3 new files, ~1,000-1,500 lines Swift.

---

## Task 1: Define the `MutationEvent` wire format

- [ ] **Step 1: Implement**

`frontend/ios/FinchCore/Sources/FinchCore/CloudKit/MutationEvent.swift`:

```swift
// CloudKit/MutationEvent.swift — the wire format for a single
// mutation. Mirrors the design spec §2.1.
import Foundation
import CloudKit

public struct MutationEvent: Codable, Equatable {
    public let id: String
    public let ledgerId: String
    public let action: String
    public let argsData: Data  // JSON-encoded
    public let occurredAt: Date
    public let deviceId: String
    public let revisionId: Int64
    public var applied: Bool

    public init(
        id: String = UUID().uuidString,
        ledgerId: String,
        action: String,
        argsData: Data,
        occurredAt: Date = Date(),
        deviceId: String = MutationEvent.currentDeviceId,
        revisionId: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        applied: Bool = false
    ) {
        self.id = id
        self.ledgerId = ledgerId
        self.action = action
        self.argsData = argsData
        self.occurredAt = occurredAt
        self.deviceId = deviceId
        self.revisionId = revisionId
        self.applied = applied
    }

    public static let currentDeviceId: String = {
        if let id = UIDevice.current.identifierForVendor?.uuidString {
            return id
        }
        return "unknown-device"
    }()
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/CloudKit/MutationEvent.swift
git commit -m "feat(ios): define MutationEvent wire format for CloudKit row sync"
```

---

## Task 2: Build the `CloudKitSyncDaemon` (writer)

- [ ] **Step 1: Implement the writer**

`frontend/ios/FinchCore/Sources/FinchCore/CloudKit/CloudKitSyncDaemon.swift`:

```swift
// CloudKit/CloudKitSyncDaemon.swift — the writer. Enqueues
// MutationEvent records to CloudKit when the chokepoint
// dispatches. The reader (Task 3) reads them.
import Foundation
import CloudKit
import GRDB

@MainActor
public final class CloudKitSyncDaemon: ObservableObject {
    public static let shared = CloudKitSyncDaemon()

    private let container = CKContainer(identifier: "iCloud.com.juchengquan.finch")
    private let database: CKDatabase
    private let zoneName = "MutationZone"
    private var subscriptionIDs: [String: CKSubscription.ID] = [:]

    public init() {
        self.database = container.privateCloudDatabase
    }

    public func enqueue(event: MutationEvent, dbPool: DatabasePool) async {
        // Create the per-ledger zone if it doesn't exist
        let zone = CKRecordZone(zoneName: zoneNameForLedger(event.ledgerId))
        _ = try? await database.save(zone)

        // Create the CKRecord
        let record = CKRecord(recordType: "Mutation", recordID: CKRecord.ID(recordName: event.id))
        record["ledgerId"] = event.ledgerId as CKRecordValue
        record["action"] = event.action as CKRecordValue
        record["argsData"] = event.argsData as CKRecordValue
        record["occurredAt"] = event.occurredAt as CKRecordValue
        record["deviceId"] = event.deviceId as CKRecordValue
        record["revisionId"] = event.revisionId as CKRecordValue
        record["applied"] = event.applied as CKRecordValue

        // Save (use CKAsset for large args, per grill pass #3 fix)
        if event.argsData.count > 1_000_000 {
            // Upload as CKAsset instead
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(event.id).json")
            try? event.argsData.write(to: tempURL)
            record["argsAsset"] = CKAsset(fileURL: tempURL)
        }

        _ = try? await database.save(record)
    }

    private func zoneNameForLedger(_ ledgerId: String) -> String {
        return "ledger-\(ledgerId)"
    }
}
```

- [ ] **Step 2: Wire the writer into `FinchStore.apply`**

```swift
public extension FinchStore {
    func apply(action: ActionName, args: Args) async throws {
        // (existing apply logic)

        // Enqueue the mutation to CloudKit (best-effort)
        let argsData = (try? JSONEncoder().encode(args.values)) ?? Data()
        let event = MutationEvent(
            ledgerId: activeLedgerId,
            action: action.rawValue,
            argsData: argsData
        )
        if let pool = dbPool {
            await CloudKitSyncDaemon.shared.enqueue(event: event, dbPool: pool)
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/CloudKit/CloudKitSyncDaemon.swift
git add frontend/ios/FinchApp/Sources/FinchApp/FinchStore.swift
git commit -m "feat(ios): implement CloudKitSyncDaemon writer + enqueue hook"
```

---

## Task 3: Build the `CloudKitSyncDaemon` (reader + subscription)

- [ ] **Step 1: Implement the subscription**

```swift
public extension CloudKitSyncDaemon {
    func subscribeToMutations(ledgerId: String) async {
        let subscriptionID = "ledger-\(ledgerId)"
        let subscription = CKQuerySubscription(
            recordType: "Mutation",
            predicate: NSPredicate(format: "TRUEPREDICATE"),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation]
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        _ = try? await database.save(subscription)
        subscriptionIDs[ledgerId] = subscriptionID
    }

    // Handle incoming notifications
    public func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async {
        // (extract MutationEvent from CKNotification, dispatch to FinchStore.apply)
    }
}
```

- [ ] **Step 2: Wire the iOS app's `AppDelegate`**

```swift
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        await CloudKitSyncDaemon.shared.handleRemoteNotification(userInfo)
        return .newData
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/CloudKit/CloudKitSyncDaemon.swift
git add frontend/ios/FinchApp/Sources/FinchApp/FinchApp.swift
git commit -m "feat(ios): implement CloudKit subscription + remote-notification handler"
```

---

## Task 4: Add the sync switch (Settings › Sync)

Per the §1 design decision: ONE switch, "Sync across devices (iCloud)",
CloudKit-backed. No mode picker, no "switch back to pack-based". Turning it on
runs a one-time bootstrap then subscribes; turning it off unsubscribes. The
`.finch` Export/Import (Phase 5) stays as a separate Backup section, unchanged.

Daemon API this view relies on (extend the `CloudKitSyncDaemon` from Tasks 2–3):
`bootstrap(ledgerId:)` (one-time full upload, Task 2), `subscribeToMutations(ledgerId:)`
/ `unsubscribe()` (Task 3), `resync(ledgerId:)` (forced re-upload + re-pull), and
the published status props `statusText` / `lastSyncText` / `pendingCount` /
`lastError`.

- [ ] **Step 1: Build the Sync settings view**

`frontend/ios/FinchApp/Sources/FinchApp/Settings/SyncSettingsView.swift`:

```swift
import SwiftUI
import FinchCore

struct SyncSettingsView: View {
    @EnvironmentObject private var store: FinchStore
    @StateObject private var sync = CloudKitSyncDaemon.shared
    @State private var enabled = AppState.syncEnabled   // persisted in app_state
    @State private var bootstrapping = false

    var body: some View {
        Form {
            Section {
                Toggle("Sync across devices (iCloud)", isOn: $enabled)
            } footer: {
                Text("Your data syncs through your iCloud account. Per-change merge across devices; the audit gate is the safety net.")
            }
            if enabled {
                Section("Status") {
                    LabeledContent("State", value: sync.statusText)        // "Subscribed to N ledgers" / "Setting up…"
                    LabeledContent("Last sync", value: sync.lastSyncText)
                    LabeledContent("Pending changes", value: "\(sync.pendingCount)")
                    if let err = sync.lastError { LabeledContent("Last error", value: err) }
                    Button("Resync ledger") { Task { await sync.resync(ledgerId: store.activeLedgerId) } }
                        .disabled(bootstrapping)
                }
            }
            // NOTE: the Backup (Export/Import .finch) section is the existing
            // Phase 5 UI — it is NOT a sync mode and is left exactly as-is.
        }
        .navigationTitle("Sync")
        .overlay { if bootstrapping { ProgressView("Setting up iCloud sync…") } }
        .onChange(of: enabled) { _, on in
            AppState.syncEnabled = on
            Task {
                if on {
                    bootstrapping = true
                    await sync.bootstrap(ledgerId: store.activeLedgerId)          // one-time full upload (Task 2)
                    await sync.subscribeToMutations(ledgerId: store.activeLedgerId) // Task 3
                    bootstrapping = false
                } else {
                    await sync.unsubscribe()
                }
            }
        }
    }
}
```

- [ ] **Step 2: Wire into `SettingsTab`** (single row, replacing any Phase 5
  "iCloud sync" auto-pack row — that automatic path is retired per §3.2):

```swift
NavigationLink {
    SyncSettingsView()
} label: {
    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
}
```

- [ ] **Step 3: Retire the Phase 5 auto-pack folder-watch** — disable the
  `AutoBackupManager`/`ICloudSync` *automatic* iCloud-Drive loop (the manual
  Export/Import stays). Leave a one-line note so it isn't re-enabled.

- [ ] **Step 4: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/Settings/SyncSettingsView.swift
git add frontend/ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift
git commit -m "feat(ios): single iCloud sync switch (CloudKit); retire auto-pack live sync"
```

---

## Task 5: Add the CloudKit capability

- [ ] **Step 1: Configure CloudKit in Xcode**

Open the project; target → Signing & Capabilities → "+ Capability" → CloudKit → enable "CloudKit" with the container `iCloud.com.juchengquan.finch`.

- [ ] **Step 2: Add the entitlement**

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.juchengquan.finch</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>
```

- [ ] **Step 3: Test on 2 real iCloud devices**

Build + run on 2 iPhones signed into the same iCloud account.
Turn on "Sync across devices (iCloud)" on both. Write a transaction
on device 1; it should appear on device 2 within ~1 second.

- [ ] **Step 4: Commit**

```bash
git add frontend/ios/FinchApp.xcodeproj/
git add frontend/ios/FinchApp/FinchApp.entitlements
git commit -m "feat(ios): configure CloudKit capability + entitlements"
```

---

## Self-review

**Spec coverage** (Phase 8 design spec, 9 sections + §0. Map TOC): all 9 sections covered (Tasks 1-5 cover §1-§5; remaining sections are deferred/non-applicable). Phase 8 is committed to building per Q22.
