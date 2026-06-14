# CloudKit container setup — runbook (Phase 8)

> How to provision `iCloud.com.juchengquan.finch` and turn the **unverified**
> live-sync loop into a real, testable feature. Companion to
> `IOS_MACOS_PHASE_8_DESIGN.md` (the design + the §5.1 provisioning gate). Until
> these steps are done the CloudKit code is inert: every call guards on
> `accountAvailable()`, the "Sync across devices (iCloud)" switch defaults OFF,
> and the Phase 5 iCloud-Drive **file sync stays the only working live path**.

## What's already in the repo (don't redo these)

- **App entitlements** (`ios/FinchApp/FinchApp.entitlements`): app group
  `group.com.juchengquan.finch`, `icloud-container-identifiers` +
  `ubiquity-container-identifiers` = `iCloud.com.juchengquan.finch`,
  `icloud-services` = CloudKit (+ CloudDocuments).
- **Code** (`ios/FinchApp/Sources/FinchApp/Sync/`): `CloudKitSyncService`
  (push/pull/zones/subscription), `CloudKitSyncCoordinator` (switch + replay),
  `SyncMutation`/`SyncOutbox` (mutation log), wired into `FinchStore.apply`.
- **Settings › Sync** UI (the switch + status + Resync).

## What's missing (this runbook) + still-to-code (Step 5)

The container itself, real signing, the push/background plumbing, and three
deliberately-unbuilt code pieces (down-sync seed, APS→pull handler, conflict
revisioning). All flagged `PROVISIONING-GATED` in the source.

---

## Prerequisites

- **Apple Developer Program** membership ($99/yr) — a free Apple ID cannot
  create a CloudKit container or enable the capability.
- At least **two devices** (or two simulators) **signed into the same iCloud
  account** (Settings → iCloud), to verify multi-device convergence. CloudKit
  does nothing for a single device.
- Xcode with that developer account added (Settings → Accounts).

---

## Step 1 — App ID + capabilities (developer portal or Xcode)

Easiest path is **Xcode automatic signing**:

1. Open `ios/FinchApp.xcodeproj` (run `xcodegen generate` in `ios/` first).
2. For the **FinchApp** target → Signing & Capabilities:
   - Set your **Team**; let Xcode manage signing.
   - Confirm **iCloud** capability is on with **CloudKit** checked and the
     container `iCloud.com.juchengquan.finch` selected (Xcode creates it on first
     use if it doesn't exist — see Step 2).
   - Add the **Push Notifications** capability (CloudKit subscriptions deliver via
     APNs).
   - Add **Background Modes → Remote notifications** (so a subscription push can
     wake the app to `pull()`).
3. Repeat the iCloud (+ Push + Background) capabilities for **FinchMac**. Note:
   `ios/FinchApp/FinchMac.entitlements` currently has **no** iCloud keys — they
   must be added (mirror `FinchApp.entitlements`).
4. The extensions (`FinchWidget`, `FinchShare`, `FinchWatch`) use the **App
   Group**, not CloudKit — leave them as-is unless they later read CloudKit.

> The portal-equivalent: create/confirm App IDs for `com.juchengquan.finch` (+
> `.mac`), enable iCloud + CloudKit + Push, and create the container.

---

## Step 2 — Create the CloudKit container

In the [CloudKit Console](https://icloud.developer.apple.com) (or via Xcode's
iCloud capability picker → "+"):

- Container ID: **`iCloud.com.juchengquan.finch`** (must match the entitlement
  string exactly).
- It starts in the **Development** environment; you promote to Production before
  shipping (Step 7).

---

## Step 3 — Schema

finch uses **schema-on-write** in Development: the first time the app saves a
record of a given type/field, CloudKit creates it. So in Development you can just
run the app and let it define the schema. For reference, the code writes:

**Custom zones** — one per ledger, `zoneName = <ledger id>` (e.g. `personal`),
created by `CloudKitSyncService.ensureZones`. All records live in the **private**
database.

**Record type `Mutation`** (the live mutation log — `SyncMutationRecord`):

| field      | type   | notes                              |
|------------|--------|------------------------------------|
| `seq`      | Int64  | per-device monotonic replay order  |
| `deviceId` | String | origin device (skip own echoes)    |
| `ledgerId` | String | = the zone name                    |
| `action`   | String | `ActionName.rawValue`              |
| `argsJSON` | String | JSON-encoded `Args`                |
| `ts`       | String | ISO-8601                           |

**Row-mirror record types** (bootstrap upload — `CloudKitRecordMapper`): one type
per canonical table (`entries`, `postings`, `accounts`, `ledgers`, …; see
`CloudKitBootstrap.tables`), each column a String field, `recordName = row id`.

**Subscription**: a `CKDatabaseSubscription` with id `finch-mutations`
(`shouldSendContentAvailable = true`) — registered by `registerSubscription()`.

No **queryable** indexes are required: sync uses `recordZoneChanges` (zone-delta),
not `CKQuery`. (If you later add `CKQuery`-based lookups, mark those fields
queryable/sortable in the Console.)

---

## Step 4 — Build config (keep CI unsigned)

CI builds the **simulator** unsigned (`CODE_SIGNING_ALLOWED: NO` in
`ios/project.yml`) and must stay that way. For **device** builds, override locally
rather than committing a team id:

```bash
xcodebuild -project ios/FinchApp.xcodeproj -scheme FinchApp \
  -destination 'generic/platform=iOS' \
  DEVELOPMENT_TEAM=<YOUR_TEAM_ID> CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Automatic
```

If you prefer it in `project.yml`, add `DEVELOPMENT_TEAM` under the FinchApp /
FinchMac `settings.base` and flip `CODE_SIGNING_ALLOWED` to `YES` **only on a
local branch** — do not merge it, or CI's unsigned simulator build breaks.

---

## Step 5 — Finish the code (the `PROVISIONING-GATED` pieces)

These were intentionally not built without a runtime to test against:

1. **APS → `pull()` handler.** On the silent CloudKit push, call
   `CloudKitSyncCoordinator.shared.syncNow()` (or `service.pull(...)`). Wire it in
   `application(_:didReceiveRemoteNotification:)` / the SwiftUI
   `backgroundTask(.appRefresh)` or a `UNUserNotificationCenter` path. Until this
   exists, pulls only happen on launch / local write / Resync.
2. **Fresh-device down-sync seed.** A new install must re-hydrate from the
   row-mirror bootstrap records (Step 3) into an empty DB, then re-run the audit
   gate. This bypasses the chokepoint, so it needs care — it's the riskiest piece
   and was left unbuilt on purpose.
3. **Conflict revisioning.** The design (§2) keys field-level last-writer-wins on
   `(entry_id, revision_id)` and adds `revision_id`/`device_id` columns. The
   current loop relies on the chokepoint's `dedup_hash` + audit gate; add real
   revisioning once you observe actual conflict behavior.
4. **Reconsider `CKSyncEngine`.** The loop is operation-based for blind-compile
   stability; with a runtime you may prefer `CKSyncEngine` (handles tokens,
   retries, state). Migrate only after the operation-based path is proven.

---

## Step 6 — Test (Development environment)

1. Device A: sign into iCloud, run the signed build, Settings → **Sync across
   devices (iCloud)** ON. Watch `status` flip to "Subscribed to N ledgers".
2. In the CloudKit Console (Development) confirm the zones + `Mutation` records
   appear as you add transactions on A.
3. Device B (same iCloud account): enable sync; confirm A's changes replay (they
   flow through `applyRemote` → `FinchStore.apply`, so the audit gate runs).
4. **Conflict check**: edit the same entry on A and B while offline, reconnect,
   confirm both converge and the audit stays clean.
5. **Resync**: hit "Resync ledger" and confirm a full re-upload/re-pull recovers.

---

## Step 7 — Production + retiring file sync

- **Deploy schema** Development → Production in the CloudKit Console **before**
  any TestFlight/App Store build (Production starts empty; schema isn't
  auto-created there).
- Only once CloudKit is verified on two devices, **retire the Phase 5 auto file
  sync** per `IOS_MACOS_PHASE_8_DESIGN.md` §3.2 — stop the automatic
  `AutoBackupManager`→`ICloudSync` folder loop (keep the **manual** `.finch`
  export/import). This is a separate change; do not do it until row-level sync is
  trusted. The no-account guard means the two coexist safely until then.

---

## Costs (recap from the design)

CloudKit's free tier scales with your app's user base (Apple-funded), and each
user's data counts against **their** iCloud quota, not yours. No per-user cost to
you. Same privacy posture as the Phase 5 file sync (data in the user's private
iCloud).

## Gotchas

- Entitlement container string must match **exactly** (`iCloud.com.juchengquan.finch`).
- The simulator has **no iCloud account** by default — sign it in, or test on
  device. Without an account everything no-ops (by design).
- `recordZoneChanges` tokens are persisted per-zone in `UserDefaults`
  (`finch.sync.token.<zone>`); deleting the app or changing zones resets them.
- Don't commit `DEVELOPMENT_TEAM` / `CODE_SIGNING_ALLOWED: YES` — it breaks CI's
  unsigned simulator build.
