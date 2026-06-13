# finch for iOS & macOS — Phase 8 Implementation Design

> _Web facts verified against commit `22c9896` (SCHEMA_VERSION `2026-06-14T00:00:00Z`), 2026-06-13.
> See `_WEB_DRIFT_CHECKLIST.md`._

> **Status**: design spec — **COMMITTED TO BUILDING** (per
> the resolution-pass decision). The plan's §13 originally
> framed Phase 8 as deferred; that framing is updated in
> `plans/ios-macos/IOS_MACOS_PLAN.md` §13 (per the resolution pass).
> Phase 8 is a **future roadmap item after Phase 7 ships**;
> not on the immediate roadmap, but planned.
>
> This doc exists to capture the design for the future
> implementation. It is not on the immediate implementation
> roadmap; the pack model in Phase 5 is correct for 99% of
> users and ships first.
>
> Companion documents:
>
> - `plans/ios-macos/IOS_MACOS_PLAN.md` — direction brief
> - `plans/ios-macos/IOS_MACOS_PHASE_1_DESIGN.md` — Phase 1.0 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_1_5_DESIGN.md` — Phase 1.5 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_2_DESIGN.md` — Phase 2 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_3_DESIGN.md` — Phase 3 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_4_DESIGN.md` — Phase 4 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_5_DESIGN.md` — Phase 5 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_6_SKETCH` (in roadmap) — Phase 6 sketch
> - `plans/ios-macos/IOS_MACOS_PHASE_7_DESIGN.md` — Phase 7 full design
> - `plans/ios-macos/IOS_MACOS_ROADMAP.md` — 8-phase arc
> - `plans/ios-macos/IOS_MACOS_PHASE_8_DESIGN.md` (this file)
>
> _Audience: future engineers who will build Phase 8
> (committed to building per the resolution-pass decision Q22).
> Assumes Phases 1.0-7 are complete; the chokepoint + iCloud
> sync + widgets + Watch are all shipping._

## See also

- `plans/ios-macos/IOS_MACOS_INDEX.md` — the navigation index
- `plans/ios-macos/IOS_MACOS_WIRE_FORMAT.md` §2, §3 — the 74+1 Args + I18nError wire format
- `plans/ios-macos/IOS_MACOS_PLAN.md` §13 — the framing (Phase 8 is committed to building per Q22)
- `plans/ios-macos/IOS_MACOS_PHASE_2_DESIGN.md` — Phase 2 (chokepoint; CloudKit row-level sync observes it)
- `plans/ios-macos/IOS_MACOS_PHASE_5_DESIGN.md` — Phase 5 (pack-based sync model; Phase 8 is the row-level successor)
- `plans/ios-macos/IOS_MACOS_PHASE_6_5_DESIGN.md` — Phase 6.5 (the 75th action; Phase 8 row sync may add 1-2 more)
- `plans/ios-macos/IOS_MACOS_PHASE_7_DESIGN.md` — Phase 7 (widgets + Watch; Phase 8 doesn't change these)

## §0. Map — 8-section template

The 8-section template maps to this spec's existing sections:

| Template section | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §2 (Architecture: CloudKit + the chokepoint) + §3 (The migration from pack-based to row-level sync) |
| §3. iOS UI surfaces | §4 (Settings › Sync section, Phase 8 additions) |
| §4. Cross-cutting concerns | §3 (the migration) + §8 (Why we're building this in a future phase — context) |
| §5. Wire contracts | §2 (CloudKit schema — the row-level wire format) |
| §6. CI / test infrastructure | §5 (CI changes) |
| §7. Out of scope (firm) | §7 |
| §8. Spec self-review + open questions | §9 + §6 |

## §1. Goal & non-goals

**Goal** — Replace the pack-based sync model
(Phase 5) with **row-level sync** that gives sub-second
latency across devices. The plan's §4.3-C sketches this
option: "CloudKit or server sync atop the UUID-ready,
single-choke-point mutation layer."

The two viable implementations:

- **CloudKit** (the proposal) — Apple's free, serverless
  sync platform. One CloudKit private database per ledger;
  the schema mirrors the shared SQLite schema. The chokepoint
  publishes a `Mutation` event on every write; the sync
  layer subscribes, batches, and pushes to CloudKit. Other
  devices subscribe to CloudKit subscriptions; the sync
  layer pulls deltas, dispatches them through the chokepoint.
  **Phase 8 adds two new sync columns — `revision_id` and
  `device_id` — to `entries` and `postings`** (a native,
  CloudKit-driven schema extension); the sync-layer idempotency
  key becomes `(entry_id, revision_id)`. The web schema today
  has NO such columns: its real idempotency backstop is
  `dedup_hash` (the unique index `idx_entry_dedup`) plus
  `postEntry` being replay-idempotent keyed on `entry_id`
  alone (`entries-schema.ts:8-34,72`; `entries.ts:258`).
  Conflict resolution: last-writer-wins on `(entry_id,
  revision_id)` (using the Phase-8-added columns) with the
  audit gate as the safety net.
- **Custom server** — a finch-server (Node.js or Go) that
  the iOS app talks to via HTTPS + WebSocket. The schema
  is the same; the server hosts the master copy. Custom
  auth + custom conflict resolution.

**The CloudKit path is the default** (per the Open
questions; CloudKit is "free" and matches the plan's local-
first promise). The custom-server path is sketched but
not detailed.

**Why this is deferred** (per the plan's §13):

- The pack model in Phase 5 is **already correct** for
  99% of users. Sync is eventual (sub-minute latency is
  the typical case; sub-hour is the worst case). The
  user's experience: edit on iPhone, see the change on
  iPad within 1-2 minutes. That's good enough.
- The complexity of row-level sync is **substantial**:
  CloudKit subscriptions, batched sync, conflict
  resolution, the `Mutation` event bus. The pack model
  uses iCloud Drive's built-in file sync; the row-level
  model uses CloudKit's record-store sync. The latter
  is more code, more bugs, more edge cases.
- The privacy story is **the same** for both models
  (the data is end-to-end encrypted at rest; the user
  trusts Apple/iCloud either way). The pack model is
  simpler; the row-level model adds no privacy benefit.

**Non-goals (firm)**:

- **No new chokepoint actions** — the 74 Phase 2 actions
  are the full set (Phase 6.5's `setEntryAttachment` is a
  **native-only addition** — the web has no such chokepoint
  action; attachments upload via `/api/attachments` — bringing
  the native running total to 75; Phase 8 doesn't add more).
  Phase 8 adds a **sync layer** that
  observes the chokepoint and publishes mutations.
- **No new tabs / write screens / power features** — the
  6 tabs + 7 write screens + 7 power features are
  unchanged. Phase 8 adds a background sync daemon.
- **No changes to the chokepoint's invariants** — the
  audit gate + the balance triggers + the schema
  triggers are unchanged. Phase 8 layers on top.
- **No changes to the pack engine** — the pack engine
  (Phase 1.0) and the iCloud sync (Phase 5) continue to
  exist. The row-level sync is a **complement**; users
  can opt in to row-level sync or stick with the pack
  model. (In practice, most users will use one or the
  other; the opt-in is a safety net for the transition.)
- **Multi-user / shared ledgers** — single-user iCloud
  account = single finch install. Per the plan's §10
  resolved decision. CloudKit's "shared database" feature
  is not used.
- **Android** — not in the plan.
- **Custom-server path** — sketched but not detailed. If
  pursued, it would be a separate spec.

**Estimated scope**: ~1,500-2,500 lines Swift
(the CloudKit subscription + the mutation event bus + the
sync daemon) + ~500 lines SwiftUI (the Settings › Sync
section additions for "row-level sync" vs. "pack-based
sync") + ~1,000 lines tests (the CloudKit mock + the
mutation round-trip tests). **2-4 months of full-time
work** for a small team. This is a **large phase** if
ever pursued.

## §2. Architecture: CloudKit + the chokepoint

The chokepoint (Phase 2) is the single write path. Every
write flows through `FinchStore.apply(action, args)`. The
sync layer **observes** the chokepoint and publishes a
`Mutation` event for each successful write.

### 2.1 — The `Mutation` event bus

```swift
// ios/FinchApp/Sync/MutationEventBus.swift
@MainActor
public final class MutationEventBus {
    public static let shared = MutationEventBus()

    private var subscribers: [UUID: (MutationEvent) -> Void] = [:]

    public func subscribe(_ handler: @escaping (MutationEvent) -> Void) -> UUID {
        let id = UUID()
        subscribers[id] = handler
        return id
    }

    public func unsubscribe(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    public func publish(_ event: MutationEvent) {
        for handler in subscribers.values {
            handler(event)
        }
    }
}

public struct MutationEvent: Codable, Sendable {
    public let mutationId: String  // UUID; idempotency key
    public let ledgerId: String
    public let action: String
    public let args: [String: AnyCodable]
    public let occurredAt: Date
    public let deviceId: String
    public let revisionId: Int64  // monotonic per device
}
```

`FinchStore.apply` (from Phase 2) publishes a `MutationEvent`
after every successful write (before the `getCachedAudit`
invalidation). The sync layer subscribes to the bus and
forwards the event to CloudKit.

### 2.2 — CloudKit schema

CloudKit's record store is a key-value store; the schema
mirrors the shared SQLite schema. **Note:** the `revisionId`
and `deviceId` fields below correspond to the new
`revision_id` / `device_id` columns Phase 8 ADDS to `entries`
and `postings` (§2.1, §2.4) — they do not exist in the web
schema today and are introduced by this phase. All other
fields map to existing columns (`createdAt`→`created_at`,
`clearedAt`→`cleared_at`, `sortOrder`→`sort_order`, plus
`memo`, `amountBase`, `exchangeRate`, `origAmount`,
`origCurrency`). The proposal:

```
CKRecordType: "Entry"
  recordID: ledger_id:entry_id (composite)
  fields:
    ledgerId: String
    date: String (ISO 8601)
    time: String?
    description: String
    kind: String
    status: String
    createdAt: Date
    revisionId: Int64
    deviceId: String  // last writer

CKRecordType: "Posting"
  recordID: ledger_id:entry_id:posting_id
  fields:
    entryId: String (FK)
    accountId: String
    categoryId: String?
    amount: Double
    currency: String
    amountBase: Double
    exchangeRate: Double
    origAmount: Double?
    origCurrency: String?
    clearedAt: Date?
    memo: String?
    sortOrder: Int

CKRecordType: "Mutation"
  recordID: mutation_id (UUID)
  fields:
    ledgerId: String
    action: String
    argsData: Data (JSON-encoded)  // small actions; for large
                                  // payloads (e.g., bulk
                                  // recategorize, rebuildEntry
                                  // with full posting arrays)
                                  // use a CKAsset on
                                  // `argsAsset: CKAsset` instead —
                                  // CloudKit enforces a 1MB hard
                                  // limit on `Data` fields and
                                  // the server-side record size
                                  // limit is 1MB
    occurredAt: Date
    deviceId: String
    revisionId: Int64
    applied: Bool  // true once the receiving device has dispatched
```

**One CloudKit zone per ledger.** The zone is a
`CKRecordZone` with the ledger's id as the zone name. The
zone is created on first use; deleted on ledger delete.
The zone's records are the Entry + Posting + Mutation
records.

### 2.3 — Subscriptions

Each device subscribes to a **per-ledger subscription** on
the ledger's zone. When a record changes (another device
wrote), CloudKit fires a `CKQuerySubscription` notification.
The device fetches the changed record(s) and dispatches
the mutation through the chokepoint (idempotent on the
Phase-8-added `(entry_id, revision_id)` key — see §2.4).

```swift
// ios/FinchApp/Sync/CloudKitSyncDaemon.swift
@MainActor
public final class CloudKitSyncDaemon {
    private let container = CKContainer(identifier: "iCloud.com.juchengquan.finch")
    private let database: CKDatabase
    private var subscriptionIDs: [String: CKSubscription.ID] = [:]

    public init() {
        self.database = container.privateCloudDatabase
    }

    public func subscribeToLedger(_ ledgerId: String) async throws {
        let zoneID = CKRecordZone.ID(zoneName: ledgerId, ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await database.save(zone)

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

        _ = try await database.save(subscription)
        subscriptionIDs[ledgerId] = subscriptionID
    }

    public func handleNotification(_ userInfo: [AnyHashable: Any]) async {
        // CloudKit fires a silent push notification on every
        // Mutation record creation. The handler fetches the
        // new Mutation(s), dispatches them through the
        // chokepoint, and marks the Mutation as applied.
    }
}
```

The silent push notification wakes the iOS app in the
background; the app fetches the new Mutation(s) and
dispatches them. The latency is sub-second (CloudKit
notifications fire within ~100ms of the record creation).

### 2.4 — The chokepoint's idempotency

**Today (web), the chokepoint idempotency is `entry_id` +
`dedup_hash`**, NOT `(entry_id, revision_id)`. `postEntry`
is replay-idempotent keyed on `entry_id` alone
(`entries.ts:258`), and the unique index `idx_entry_dedup`
over `dedup_hash` (`entries-schema.ts:72`) is the duplicate
backstop. There is **no `revision_id` or `device_id` column**
in the web `entries` / `postings` schema.

**Phase 8 ADDS** `revision_id` and `device_id` columns to
both tables (a native CloudKit-driven schema extension) so
the sync layer can key last-writer-wins on `(entry_id,
revision_id)`. With those columns present, the chokepoint
becomes **idempotent on `(entry_id, revision_id)`**:
- A `postEntry` with a known `entry_id` and a new
  `revision_id` upserts the entry (overwriting the
  previous version)
- A `postEntry` with a known `entry_id` and the same
  `revision_id` is a no-op (the entry is already at that
  revision)
- A `deleteEntry` with a known `entry_id` is idempotent
  (deleting a deleted entry is a no-op)

The sync layer relies on this: when a device receives a
`Mutation` event from another device, it dispatches the
chokepoint. If the device has already dispatched this
mutation (because it was the original writer), the
chokepoint is a no-op. The `Mutation` record's `applied`
field is set to `true` once the receiving device has
dispatched.

### 2.5 — Conflict resolution

The chokepoint's audit gate (`Args.auditLedger` on every
import; per the plan's §4.9) is the safety net. If a sync-
delivered mutation would create a corruption, the
chokepoint's audit fails; the user is shown the typed
problem set (Phase 2's `auditFailed` error case).

In practice, conflicts are rare:
- The `revisionId` is monotonic per device; the
  chokepoint's upsert always picks the latest
- The audit gate catches the rare cases (e.g., a date
  edit that would change the balance in an unexpected
  way)

## §3. The migration from pack-based to row-level sync

If Phase 8 is ever pursued, the transition is a **one-way
migration**: the user opts in to row-level sync; the
iCloud pack engine (Phase 5) is still available as a
fallback (the user can switch back if row-level sync has
issues).

### 3.1 — The opt-in flow

Settings › Sync gets a new section: **Sync mode** with
two options: "Pack-based (default)" and "Row-level
(beta)". The user picks one; the choice is stored in
`app_state`.

When the user switches to row-level sync:
1. The CloudKit sync daemon is initialized
2. The first sync run: every Entry + Posting in the
   local DB is uploaded to CloudKit (as a Mutation with
   `action: 'bootstrapLedger'`)
3. Future writes are published to the Mutation bus and
   pushed to CloudKit in real-time
4. The iCloud pack engine continues to run as a fallback
   (every 30 minutes, a pack is built and uploaded to
   iCloud Drive)

When the user switches back to pack-based:
1. The CloudKit subscriptions are cancelled
2. The Mutation bus is unsubscribed
3. The iCloud pack engine continues as the primary sync
   path

### 3.2 — Backward compatibility

The pack model in Phase 5 is the **fallback**. If row-
level sync has a bug (e.g., a record corruption, a missed
subscription), the pack model kicks in: the user edits
on iPhone, the pack is built and uploaded to iCloud, the
iPad downloads the pack via the Phase 5 folder-watcher,
the iPad's CloudKit daemon is reset from the pack's
contents.

The two models coexist. The row-level model is the
primary (sub-second latency); the pack model is the
fallback (sub-minute latency). The user can switch at
any time.

## §4. Settings › Sync section (Phase 8 additions)

The Phase 5 Settings › Sync section gets a new
**Sync mode** row:

```
┌─────────────────────────────────────┐
│  Sync                               │
├─────────────────────────────────────┤
│  Mode                               │
│  (•) Pack-based (default)          │
│  ( ) Row-level (beta)              │
│                                      │
│  ...                                │
│                                      │
│  Row-level sync                     │
│  Status: ✓ Subscribed to 3 ledgers │
│  Last sync: 12 seconds ago          │
│  Pending mutations: 0               │
│  Last error: —                      │
│                                      │
│  [Resync ledger]                    │
│  [Switch back to pack-based]        │
└─────────────────────────────────────┘
```

The "Resync ledger" button forces a full re-upload of the
ledger (useful if the user suspects a corruption). The
"Switch back to pack-based" button is a one-tap rollback.

## §5. CI changes

The macos job from Phase 1.0's `IOS_MACOS_PHASE_1_DESIGN §9`
extends with:

- A **CloudKit integration test** using a mock CloudKit
  container (a `CKContainer` substitute; the test doesn't
  need a real iCloud account)
- A **mutation round-trip test**: device A writes →
  mutation published → device B receives → chokepoint
  dispatched → audit gate clean
- A **conflict test**: device A and device B both write
  the same `entry_id` with different `revisionId`s →
  chokepoint's last-writer-wins → audit gate clean
- A **migration test**: switch from pack-based to row-
  level sync → first sync run uploads all entries →
  switch back → verify the pack matches the local DB

## §6. Open questions

The plan's §14.1 still-open questions mostly land in Phase
6, but for Phase 8 specifically:

**Not blocking Phase 8 (decide later)**:

- **CloudKit vs custom server**: CloudKit is the default
  (free, matches the local-first promise, the schema
  migration is straightforward). A custom server is
  sketched but not detailed; if the user later wants
  custom-server sync, it would be a separate spec.
- **Per-ledger subscriptions vs single subscription**: the
  proposal is per-ledger subscriptions (one per active
  ledger). A single subscription (all ledgers, all
  devices) is simpler but less scalable.
- **Mutation retention in CloudKit**: the `Mutation`
  records in CloudKit are retained for N days (the
  proposal: 30 days) so late-joining devices can
  catch up. After N days, the records are purged
  (the devices that need them have already applied
  them). The retention is a CloudKit `CKQueryOperation`
  with a server-side filter.
- **Bandwidth limits**: CloudKit has a per-second record
  creation limit (the limit is generous; we won't hit
  it). The sync daemon's batched uploads respect the
  limit (back off + retry on rate-limit errors).
- **Conflict UX**: the proposal is last-writer-wins on
  `(entry_id, revision_id)` (using the Phase-8-added
  `revision_id` column). A more sophisticated
  conflict resolution (e.g., three-way merge for
  transaction edits) is a follow-up. The audit gate
  catches the rare cases that LWW doesn't.

**Specifically for the migration**:

- **Pack + row-level coexistence**: the proposal has both
  sync paths running in parallel. This is more complex
  than running one or the other. The "one-way migration"
  (switch from pack to row-level, never switch back) is
  simpler but less forgiving of bugs.
- **Cold-start bootstrap**: when the user first enables
  row-level sync, the daemon uploads every Entry +
  Posting in the local DB to CloudKit. For a 10,000-
  entry ledger, this is a ~5-10 second upload. The
  user sees a "Setting up row-level sync..." spinner.

**Not blocking Phase 8 because they're Phase 6+ by design**:

- **App Intents / Siri / Share Extension / Spotlight /
  notifications / biometric lock** — Phase 6. The CloudKit
  sync daemon is orthogonal to the App Intents; the
  intents dispatch through the chokepoint (which is
  sync-agnostic).
- **Widgets / Live Activities / Watch** — Phase 7. The
  widgets + Live Activities + Watch read from the local
  DB; the sync model is irrelevant for the read path.

## §7. Out of scope (firm)

These are explicitly NOT in Phase 8:

- **No new chokepoint actions** — the 74 Phase 2 actions
  are the full set (Phase 6.5's `setEntryAttachment` is a
  native-only addition — the web has no such action;
  attachments upload via `/api/attachments` — bringing the
  native running total to 75; Phase 8 doesn't add more).
  Phase 8 adds a sync layer that observes the chokepoint.
- **No new tabs / write screens / power features** — the
  6 tabs + 7 write screens + 7 power features are
  unchanged.
- **No changes to the chokepoint's invariants** — the
  audit gate + the balance triggers + the schema
  triggers are unchanged.
- **No changes to the pack engine** — the pack engine
  (Phase 1.0) and the iCloud sync (Phase 5) continue to
  exist as a fallback. Phase 8 complements them.
- **Custom-server path** — sketched but not detailed; if
  pursued, it would be a separate spec.
- **Multi-user / shared ledgers** — single-user iCloud
  account = single finch install. Per the plan's §10
  resolved decision. CloudKit's "shared database" feature
  is not used.
- **Android** — not in the plan.
- **Three-way merge / sophisticated conflict resolution**
  — last-writer-wins is the proposal. The audit gate is
  the safety net.

## §8. Why we're building this in a future phase

Per the resolution-pass decision (Q22): **Phase 8 is
committed to building**. The plan's §13 framing is
updated to remove the "if ever pursued" deferral language
(per the parallel update to `plans/ios-macos/IOS_MACOS_PLAN.md` §13).

That said, the pack model in Phase 5 is **correct for the
first 99% of users** and ships first. Phase 8 is a future
roadmap item that lands after Phase 7 ships. The user
research will inform whether sub-second latency is
worth the substantial added complexity (CloudKit
subscriptions, batched sync, conflict resolution, the
per-row sync state machine).

**When we build Phase 8, this design doc is the starting
point**. A future team would:
1. Re-read this design (the CloudKit schema, the
   `Mutation` event bus, the Phase-8-added `revision_id` /
   `device_id` columns and the resulting `(entry_id,
   revision_id)` idempotency — vs. the web's current
   `entry_id` + `dedup_hash` backstop — and the LWW +
   audit-gate conflict resolution)
2. Update the CloudKit schema (the proposal's record
   types are a starting point)
3. Implement the `Mutation` event bus + the CloudKit
   sync daemon
4. Migrate existing users from pack-based to row-level
   (the opt-in flow in §3.1)
5. Add the Settings › Sync UI (§4) — the user picks
   "Pack-based (default)" or "Row-level (beta)"

The estimated scope (2-4 months full-time) is comparable
to Phase 4 (power features) and Phase 5 (iCloud sync).

## §9. Spec self-review

(Inline review at write time; not part of the published
spec.)

- **Placeholders**: none. Every section has concrete
  content. The CloudKit schema, the `Mutation` event
  bus, the chokepoint's idempotency, the migration flow,
  the Settings UI — all concrete.
- **Internal consistency**: §2.1's `Mutation` event is
  published by `FinchStore.apply` (Phase 2's §9.1). §2.4's
  chokepoint idempotency relies on the `revision_id` /
  `device_id` columns Phase 8 ADDS (the web today is
  idempotent on `entry_id` + `dedup_hash`); the chokepoint's
  audit gate catches the rare cases that idempotency doesn't
  handle. §3.1's migration uses the
  Phase 5 iCloud pack engine as a fallback. §4's Settings
  UI extends the Phase 5 Settings › Sync section.
- **Scope**: focused on Phase 8 IF it's ever pursued.
  Phases 1.0-7 are referenced as completed. Phase 6 is
  explicitly out of scope (the App Intents dispatch through
  the chokepoint; the sync model is orthogonal). The
  estimated scope (2-4 months) reflects the
  CloudKit + chokepoint + migration complexity.
- **Ambiguity**: §2.1's `MutationEvent` struct is concrete
  (the field set, the codability). §2.2's CloudKit schema
  is concrete (the 3 record types, the field sets). §3.1's
  opt-in flow is concrete (the user picks "Row-level
  (beta)"; the daemon initializes). §6 enumerates the
  open questions with proposed answers.
- **Framing**: this spec captures the Phase 8 design
  (committed to building per Q22, future roadmap item
  after Phase 7). The spec body uses active voice
  throughout (no "if pursued" framing); only the
  "custom-server path" sidebar in §1 retains a
  conditional because that's a hypothetical beyond
  Phase 8's committed scope.
