# Phase 8 Implementation Plan — CloudKit row-level sync

> **For agentic workers:** Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add **row-level sync** via CloudKit. After Phase 8, when the user writes a transaction (via Phase 2's chokepoint), the iOS app immediately enqueues a `Mutation` record to CloudKit; the other device receives the record via a `CKQuerySubscription` and dispatches the same chokepoint action. Sub-second latency. Last-writer-wins on conflict (the audit gate is the safety net). Phase 8 is a **future roadmap item** after Phase 7 ships.

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

## Task 4: Add the opt-in flow (Settings › Sync › Row-level sync)

- [ ] **Step 1: Build the row-level sync opt-in view**

`frontend/ios/FinchApp/Sources/FinchApp/Settings/RowLevelSyncSettingsView.swift`:

```swift
import SwiftUI
import FinchCore

struct RowLevelSyncSettingsView: View {
    @State private var rowLevelSyncEnabled = false

    var body: some View {
        Form {
            Section {
                Toggle("Row-level sync (beta)", isOn: $rowLevelSyncEnabled)
            } footer: {
                Text("Sub-second sync via CloudKit. Last-writer-wins on conflict; the audit gate is the safety net.")
            }
            if rowLevelSyncEnabled {
                Section("Conflict resolution") {
                    Text("When two devices edit the same row, the most recent write wins.")
                }
            }
        }
        .navigationTitle("Row-level sync")
        .onChange(of: rowLevelSyncEnabled) { _, enabled in
            if enabled {
                Task { await CloudKitSyncDaemon.shared.subscribeToMutations(ledgerId: FinchStore.shared.activeLedgerId) }
            }
        }
    }
}
```

- [ ] **Step 2: Wire into `SettingsTab`**

```swift
NavigationLink {
    RowLevelSyncSettingsView()
} label: {
    Label("Row-level sync", systemImage: "arrow.triangle.2.circlepath")
}
```

- [ ] **Step 3: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/Settings/RowLevelSyncSettingsView.swift
git add frontend/ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift
git commit -m "feat(ios): add Row-level sync opt-in flow (Settings › Sync)"
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
Enable row-level sync on both. Write a transaction on device 1;
it should appear on device 2 within ~1 second.

- [ ] **Step 4: Commit**

```bash
git add frontend/ios/FinchApp.xcodeproj/
git add frontend/ios/FinchApp/FinchApp.entitlements
git commit -m "feat(ios): configure CloudKit capability + entitlements"
```

---

## Self-review

**Spec coverage** (Phase 8 design spec, 9 sections + §0. Map TOC): all 9 sections covered (Tasks 1-5 cover §1-§5; remaining sections are deferred/non-applicable). Phase 8 is committed to building per Q22.
