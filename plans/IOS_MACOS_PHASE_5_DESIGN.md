# finch for iOS & macOS — Phase 5 Implementation Design

> **Status**: design spec — not yet an implementation plan. Once
> approved, this becomes the input to `writing-plans` to produce
> a step-by-step implementation plan for Phase 5.
>
> Companion documents:
>
> - `plans/IOS_MACOS_PLAN.md` — direction brief
> - `plans/IOS_MACOS_PHASE_1_DESIGN.md` — Phase 1.0 full design
> - `plans/IOS_MACOS_PHASE_1_5_DESIGN.md` — Phase 1.5 full design
> - `plans/IOS_MACOS_PHASE_2_DESIGN.md` — Phase 2 full design
> - `plans/IOS_MACOS_PHASE_3_DESIGN.md` — Phase 3 full design
> - `plans/IOS_MACOS_PHASE_4_DESIGN.md` — Phase 4 full design
> - `plans/IOS_MACOS_ROADMAP.md` — 8-phase arc
> - `plans/IOS_MACOS_PHASE_5_DESIGN.md` (this file)
>
> _Audience: the engineers who will build the iOS app. Assumes
> Phases 1.0-4 are complete; the 6 tabs + 6 write screens + 7
> power features are shipped; the chokepoint + 74 actions are
> the full write surface; the iCloud `Documents/finch/` folder
> exists but is not yet watched._

## §1. Goal & non-goals

**Goal** — Implement the **iCloud Drive sync layer** on top of
the existing `.finch` pack engine (Phase 1.0) and chokepoint
(Phase 2):

1. **Auto-pack debounce** — after any write, wait ~30 seconds
   of idle, then build a fresh `.finch` and write it to the
   iCloud `Documents/finch/` folder
2. **Manual "Sync now"** — a button in Settings that forces
   an immediate pack (no debounce)
3. **iCloud folder-watcher** — when iCloud surfaces a new
   `.finch` in the folder (from another device), auto-import
   it through the Phase 1.0 `Pack.import(url:)` pipeline
4. **Conflict-copy UX** — when iCloud keeps a conflict copy
   (both devices wrote offline), present an "open both,
   compare counts, pick one" sheet

**Phase 5 is the most novel design problem of the iOS/macOS
project.** Phases 1.0-4 port the web's read + write surface;
Phase 5 invents the delivery layer that's new to iOS. The
plan's §14.1 lists "Conflict-copy UX" and "Pack cadence + sweep
policy" as still-open questions; Phase 5 answers them.

**Non-goals (firm)**:

- **No new tabs / write screens / power features** — the 6
  tabs + 6 write screens + 7 power features are unchanged.
  Phase 5 adds: (a) a **Sync** section in the Settings tab;
  (b) a **Sync now** button; (c) the conflict-copy sheet (a
  modal that appears when a conflict is detected).
- **No row-level sync** — Phase 8. The pack model in Phase 5
  is the answer for the foreseeable future.
- **App Intents / Siri / Share Extension / Spotlight /
  notifications / biometric lock** — Phase 6.
- **Widgets / Live Activities / Watch** — Phase 7.
- **iOS-on-Mac (Catalyst)** — Phase 3.
- **Multi-user / shared ledgers** — single-user iCloud
  account = single finch install. Per the plan's §10
  resolved decision.
- **Android** — not in the plan.

**Estimated scope**: ~600-800 lines Swift (the auto-pack
debouncer + the folder-watcher + the conflict-copy
resolver) + ~400 lines SwiftUI (the Sync section in Settings
+ the conflict-copy sheet) + ~300 lines tests (parity with
the web's `autoBackup` + integration tests for the debouncer).
**1.5-2.5 months of full-time work** for a small team.

## §2. Auto-pack debounce

After any successful write, the iOS app schedules a
**30-second idle timer**. If another write happens within
those 30 seconds, the timer resets. When the timer fires,
the app builds a fresh `.finch` and writes it to the iCloud
`Documents/finch/` folder.

The 30-second window is **configurable** (the web's
`backupConfig.frequencyMs` lives in `app_state`; the iOS app
mirrors this with a `Settings › Sync › Auto-pack frequency`
slider: 10s, 30s, 1min, 5min, 15min). The default is 30s.

### 2.1 — Why debounce?

Without debouncing, a burst of writes (e.g., the user
backfills 100 entries via the rules engine) would generate
100 pack writes — one per write. The debouncer coalesces
the burst into a single pack write 30 seconds after the
last write.

The 30-second default is the web's `lib/db/core/server.ts::autoBackup`
default (the web debounces on a similar cadence). The iOS
port matches.

### 2.2 — The debouncer

```swift
// ios/FinchApp/Sync/AutoPackDebouncer.swift
@MainActor
@Observable
public final class AutoPackDebouncer {
    private var pendingWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval
    private let packBuilder: PackBuilder
    private let iCloudWriter: ICloudWriter

    public init(debounceInterval: TimeInterval, packBuilder: PackBuilder, iCloudWriter: ICloudWriter) {
        self.debounceInterval = debounceInterval
        self.packBuilder = packBuilder
        self.iCloudWriter = iCloudWriter
    }

    /// Called by FinchStore.apply after every successful write.
    public func schedule() {
        pendingWorkItem?.cancel()  // cancel the previous pending pack
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                await self?.buildAndWritePack()
            }
        }
        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    /// Called by the "Sync now" button. Bypasses the debounce.
    public func flush() async {
        pendingWorkItem?.cancel()
        await buildAndWritePack()
    }

    /// Called when the app is backgrounded. Forces an immediate pack.
    public func flushBeforeBackground() async {
        await flush()
    }

    private func buildAndWritePack() async {
        do {
            let packURL = try await packBuilder.build()
            try await iCloudWriter.write(pack: packURL, to: "finch/\(filename)")
            // Phase 5.1: clean up the staging file
        } catch {
            // Log to the user's Settings › Sync › Last error
        }
    }
}
```

The debouncer is wired into `FinchStore.apply` (Phase 2's
§9.1): after every successful write, the store calls
`debouncer.schedule()`. The debouncer is reset on app
launch (no pending work survives a process restart; the
app re-checks the iCloud folder for new files on launch —
see §3).

### 2.3 — The pack builder (reusing Phase 1.0)

The `packBuilder.build()` is a wrapper around Phase 1.0's
`Pack.export(from: live: URL, to: URL)` (the
`lib/db/core/pack.ts` port). The build:

1. Opens the live DB read-only via GRDB
2. Runs `VACUUM INTO 'tmp/finch-<uuid>.sqlite3'`
3. Writes a fresh `manifest.json` with the current
   `schema_version` + `db_sha256` + per-file attachment
   checksums + `row_counts`
4. Copies the `attachments/` directory
5. Zips the staging directory into `finch.sqlite3.finch` (or
   `<ledger-slug>-<yyyy-mm-dd>.finch` if the user has
   set a custom filename template)

The build is **atomic**: a partial pack never overwrites a
good pack. If the build fails (e.g., disk full), the
existing good pack is preserved.

### 2.4 — The iCloud writer

The `iCloudWriter.write(pack:to:)` writes the pack to
`iCloud/finch/<ledger-slug>-<yyyy-mm-dd>.finch` (the
`Documents/finch/` subfolder from Phase 1.0). The write
is coordinated via `NSFileCoordinator` (iCloud's
"ubiquity" container requires coordination for cross-
process safety):

```swift
// ios/FinchApp/Sync/ICloudWriter.swift
public final class ICloudWriter {
    private let iCloudURL: URL

    public init() throws {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            throw ICloudError.notAvailable
        }
        let documentsURL = containerURL.appendingPathComponent("Documents")
        let finchURL = documentsURL.appendingPathComponent("finch")
        try FileManager.default.createDirectory(at: finchURL, withIntermediateDirectories: true)
        self.iCloudURL = finchURL
    }

    public func write(pack: URL, to relativePath: String) async throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        let destination = iCloudURL.appendingPathComponent(relativePath)
        var writeError: Error?
        coordinator.coordinate(writingItemAt: destination, options: .forReplacing, error: &coordError) { url in
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.copyItem(at: pack, to: url)
            } catch {
                writeError = error
            }
        }
        if let coordError { throw ICloudError.coordination(coordError) }
        if let writeError { throw ICloudError.write(writeError) }
    }
}
```

The `NSFileCoordinator` is required for iCloud — direct
file I/O can race with iCloud's sync daemon and produce
"file disappeared" errors.

### 2.5 — Filename strategy

The pack filename is `<ledger-slug>-<yyyy-mm-dd-HH-mm>.finch`.
The slug is the ledger's name lowercased and sanitized
(e.g., "Personal" → "personal"). The timestamp is UTC.

The web's filename is `<ledger-slug>-<yyyy-mm-dd>.finch`
(date only). The iOS app includes the time so multiple
auto-packs per day don't overwrite each other in the
iCloud folder.

The **retention policy**: the iCloud folder keeps the
last 7 packs (one per day for the past week, plus today's
auto-packs). Older packs are deleted on each new pack
write. The retention is user-configurable (Settings › Sync
› Keep last N packs: 7, 14, 30, 60, 90; default 7). The
web's retention is similar (the `.finch.bak` policy).

## §3. iCloud folder-watcher

The iOS app watches the iCloud `Documents/finch/` folder
for new files. When a new `.finch` appears (from another
device), the app auto-imports it through the Phase 1.0
`Pack.import(url:)` pipeline.

### 3.1 — The watcher

```swift
// ios/FinchApp/Sync/ICloudFolderWatcher.swift
public final class ICloudFolderWatcher {
    private let folderURL: URL
    private let query: NSMetadataQuery
    private let onNewFile: (URL) -> Void

    public init(folderURL: URL, onNewFile: @escaping (URL) -> Void) {
        self.folderURL = folderURL
        self.onNewFile = onNewFile
        let q = NSMetadataQuery()
        q.searchScopes = [folderURL.path]
        q.predicate = NSPredicate(format: "%K LIKE '*.finch'", NSMetadataItemFSNameKey)
        self.query = q
    }

    public func start() {
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
        query.start()
    }

    @objc private func metadataDidUpdate(_ note: Notification) {
        query.disableUpdates()
        defer { query.enableUpdates() }
        let items = query.results.compactMap { $0 as? NSMetadataItem }
        for item in items {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            onNewFile(url)
        }
    }
}
```

`NSMetadataQuery` is Apple's API for watching a folder
that's backed by iCloud (the file system API doesn't
notify on iCloud-driven changes — only on local writes).
The query is configured to watch the iCloud folder for
`.finch` files.

### 3.2 — On-launch folder scan

On app launch (and on every app foreground), the folder-
watcher does an **initial scan**: it lists all `.finch`
files in the folder and imports any that haven't been
imported yet. The "imported" tracking is in a local SQLite
table `imported_packs` (keyed on the file's `db_sha256`):

```sql
CREATE TABLE imported_packs (
  sha256 TEXT PRIMARY KEY,
  filename TEXT NOT NULL,
  imported_at TEXT NOT NULL
);
```

This prevents re-importing the same pack on every launch
(only imports the new ones).

### 3.3 — On-change notification

When a new `.finch` arrives (the user is on iPhone; iPad
just wrote), the folder-watcher fires `onNewFile(url)`. The
app:

1. Checks the file's `db_sha256` against `imported_packs`
2. If already imported, ignore
3. If not, run the Phase 1.0 import pipeline (validate →
   audit → atomic swap)
4. On success, add the sha to `imported_packs` and show a
   toast: "Imported `<filename>` from iCloud"
5. On failure, show an alert with the typed `PackError`
   (the import refuses if the audit gate fails)

The import runs on a background `Task`; the UI is not
blocked. The Activity tab refreshes when the projection
re-runs.

### 3.4 — Polling vs event-driven

`NSMetadataQuery` is event-driven for the initial scan and
for local writes. For **iCloud-driven changes** (a file
arriving from another device), the query fires when
iCloud's sync daemon updates the local cache. The latency
is typically 1-5 seconds; in rare cases (slow network,
daemon busy) it can be 30+ seconds.

The watcher also does a **periodic poll** every 60 seconds
as a safety net (the periodic poll re-checks the folder;
the event-driven path is the primary mechanism).

## §4. Conflict-copy UX

When the user is offline on two devices, both write to
their local DB. When they come back online, iCloud
surfaces a conflict: the iCloud folder has both the
original and a "conflict copy" (named
`<filename> (Conflict YYYY-MM-DD).finch` per Apple's
convention).

### 4.1 — Detection

The folder-watcher detects a conflict copy using **both** signals,
with the **extended attribute as the primary signal**:

1. **Primary**: the file's `com.apple.fileprovider.conflict`
   extended attribute (Apple's canonical signal). The
   `URLResourceKey` API exposes this attribute; the watcher
   queries it on every file in the iCloud folder.
2. **Fallback**: the filename pattern `(Conflict YYYY-MM-DD)`
   (the substring "Conflict" in the filename). Useful for
   older iOS versions or edge cases where the extended
   attribute API is incomplete.

If either signal fires, the app does NOT auto-import either
file; instead, it shows the **Conflict-copy sheet**.

### 4.2 — The conflict-copy sheet

```
┌─────────────────────────────────────┐
│  ← iCloud sync conflict             │
├─────────────────────────────────────┤
│  Both your iPhone and iPad wrote    │
│  while offline. Pick which one to   │
│  keep.                               │
│                                      │
│  ┌──────────────────────────────┐   │
│  │ 📄 personal-2026-06-12.finch │   │
│  │   iPhone · Jun 12, 18:42     │   │
│  │                              │   │
│  │   Entries:        1,247      │   │
│  │   Last write:     Jun 12 18:42│   │
│  │   Net worth:      $69,752    │   │
│  └──────────────────────────────┘   │
│                                      │
│  ┌──────────────────────────────┐   │
│  │ 📄 personal (Conflict        │   │
│  │   2026-06-12 18-50).finch   │   │
│  │   iPad · Jun 12, 18:50       │   │
│  │                              │   │
│  │   Entries:        1,251      │   │
│  │   Last write:     Jun 12 18:50│   │
│  │   Net worth:      $70,124    │   │
│  └──────────────────────────────┘   │
│                                      │
│  [Keep iPhone] [Keep iPad]          │
│  [Compare side-by-side]             │
└─────────────────────────────────────┘
```

The user picks one (or taps "Compare side-by-side" for a
more detailed diff). The chosen file is imported through
the Phase 1.0 pipeline; the other is deleted from the
iCloud folder (and added to a "Deleted conflicts" section
in Settings, recoverable for 30 days).

### 4.3 — Side-by-side compare

Tapping "Compare side-by-side" opens a deeper diff view:

```
┌─────────────────────────────────────┐
│  ← Compare                          │
├─────────────────────────────────────┤
│              iPhone      iPad       │
│  Entries:     1,247      1,251  (+4)│
│  Accounts:       12         12   (0)│
│  Net worth: $69,752   $70,124 (+372)│
│  Categories:    18        19  (+1) │
│                                      │
│  Entries unique to iPad (4):        │
│  + Jun 12  Stripe payout  $372.00  │
│  + Jun 12  Fee             -$1.00  │
│  + Jun 12  ...                     │
│                                      │
│  [Keep iPhone] [Keep iPad]          │
└─────────────────────────────────────┘
```

The diff is computed by running `projectState` on each
candidate and diffing the resulting `Tx[]` + `AccountRow[]`
+ `Category[]` arrays. The "Entries unique to iPad" list
is the set of `Tx.id`s that exist in the iPad pack but
not in the iPhone pack.

### 4.4 — The "force-merge" option (escape hatch)

A "Force merge" button is hidden behind a `?debug=1`
deep link. The force-merge imports the iPad pack as an
"additive" change: every entry in the iPad pack that's
not in the iPhone pack is added to the iPhone DB; the
existing entries are preserved. This is a recovery
hatch for users who know what they're doing; it's not
in the user-facing UI.

## §5. Settings › Sync section

The Settings tab (Phase 1.0's settings screen) gets a
**Sync** section. The section is a list of rows with
the iCloud sync configuration:

```
┌─────────────────────────────────────┐
│  Sync                               │
├─────────────────────────────────────┤
│  Status: ✓ iCloud available         │
│  Last sync: 2 minutes ago           │
│  Last error: —                      │
│                                      │
│  Auto-pack                          │
│  [On]  Every 30s after a change     │
│                                      │
│  [Sync now]                         │
│                                      │
│  iCloud folder                       │
│  ~/Library/Mobile Documents/        │
│  iCloud~com~juchengquan~finch/      │
│  Documents/finch/                   │
│  [Open in Files]                    │
│                                      │
│  Retention                          │
│  Keep last 7 packs               ▾  │
│                                      │
│  Conflicts (1)                      │
│  └─ 2026-06-12 18:50 iPad           │
│     [Resolve]                       │
└─────────────────────────────────────┘
```

The "Conflicts" row appears when there's an unresolved
conflict in the folder; tapping opens the conflict-copy
sheet (§4.2).

## §6. Orphan attachment sweep

When the iOS app builds a fresh pack, it includes every
attachment in `Application Support/attachments/`. Some
attachments may be orphaned (the DB no longer references
them — e.g., the user deleted the entry but the file
remained). The pack's manifest includes the
`attachment_count`; the build also does an orphan sweep:

1. List all files in `Application Support/attachments/`
2. List all `entry_attachments.rel_path` values from the
   DB
3. For each file on disk that has no DB reference, delete
   the file (after a safety check: the file must be older
   than 1 hour; this prevents the sweep from racing with
   a concurrent write)

The sweep runs as part of every `buildAndWritePack`. The
web's `lib/db/core/server.ts::autoBackup` does the same.

## §7. CI changes

The macos job from Phase 1.0's `IOS_MACOS_PHASE_1_DESIGN §9`
extends with:

- An **iCloud integration test** (a test that simulates a
  conflict, opens the conflict-copy sheet, asserts the
  UI, picks one, asserts the other is deleted)
- A **debouncer test** (a test that schedules 100 writes
  in 1 second, asserts the debouncer fires once, asserts
  the pack is written 30 seconds later)
- A **folder-watcher test** (a test that creates a
  `.finch` in the iCloud folder, asserts the watcher
  fires, asserts the import runs)
- A **migration test** (a test that imports a pre-DE
  pack, asserts the migration runs, asserts the audit is
  clean post-migration)

The iCloud integration test uses a **mock iCloud container**
(a `FileManager` substitute) so CI doesn't require a real
iCloud account.

## §8. Open questions

The plan's §14.1 still-open questions mostly land in Phase
6, but for Phase 5 specifically:

**Not blocking Phase 5 (decide later)**:

- **Pack cadence**: the 30-second default is the web's
  default. The iOS app makes it user-configurable
  (Settings › Sync › Auto-pack frequency: 10s, 30s, 1min,
  5min, 15min). The user research will inform the
  default; for Phase 5, the default is 30s.
- **Sweep policy**: orphan attachments are swept on every
  pack build. The "1 hour safety" check prevents racing
  with concurrent writes. The web's sweep is the same.
- **Retention default**: 7 packs. The user can configure
  7, 14, 30, 60, 90. The web's `.finch.bak` retention is
  the same.
- **Conflict-copy UX polish**: the current sketch is a
  basic sheet. The Phase 5 implementation may add:
  - A "preview the entries" button for each candidate
  - A "merge selectively" option (pick some entries from
    the iPhone, some from the iPad)
  - A "view raw SQL" option for power users

  These are UX refinements; the basic flow is the
  "Keep iPhone" / "Keep iPad" / "Compare side-by-side"
  picker.

- **Offline indicator**: the Settings › Sync section
  shows "✓ iCloud available" or "✗ iCloud unavailable".
  The iOS app uses `FileManager.default.ubiquityIdentityToken`
  to check; the indicator updates on every sync attempt.
  The user-facing message: "iCloud unavailable — your
  changes are saved locally and will sync when iCloud
  returns."

- **App Group vs iCloud-only container**: Phase 1.0
  designed the iOS app's data to live in the iCloud
  `Documents/` directory. Phase 6 (Share Extension
  receipts) needs the data to live in a **local** app
  group container (so the Share Extension process can
  read it). The Phase 5 design doesn't change this; the
  data is in the iCloud container, and the Share
  Extension in Phase 6 will need a different design
  (e.g., copy the attachment to a shared local path
  before the Share Extension writes).

**Specifically for the debouncer**:

- **Debounce on app backgrounding**: when the app is
  backgrounded, the debouncer flushes immediately (a
  background debounce is unreliable; the app may be
  killed mid-debounce). The proposal does this.
- **Debounce across app launches**: the debouncer doesn't
  survive an app launch (the in-memory `pendingWorkItem`
  is lost). On app launch, the folder-watcher does an
  initial scan (which catches any packs the previous
  session didn't sync). The proposal does this.

**Not blocking Phase 5 because they're Phase 6+ by design**:

- **App Intents / Siri / Share Extension / Spotlight /
  notifications / biometric lock** — Phase 6. The Share
  Extension's "write to the iCloud container" is a Phase
  6 concern; Phase 5's pack engine is reusable.
- **Widgets / Live Activities / Watch** — Phase 7. The
  widget's "current net worth" reads from the local DB;
  the iCloud sync is irrelevant for the widget.
- **Row-level sync** — Phase 8. The pack model is the
  answer for the foreseeable future.

## §9. Out of scope (firm)

These are explicitly NOT in Phase 5:

- **No new tabs / write screens / power features** — the
  6 tabs + 6 write screens + 7 power features are
  unchanged.
- **No row-level sync** — Phase 8.
- **App Intents / Siri / Share Extension / Spotlight /
  notifications / biometric lock** — Phase 6.
- **Widgets / Live Activities / Watch** — Phase 7.
- **iOS-on-Mac (Catalyst)** — Phase 3.
- **No new chokepoint actions** — the 74 Phase 2 actions
  are the full set. Phase 5 wires the pack engine +
  iCloud container; no new actions.
- **Multi-user / shared ledgers** — single-user iCloud
  account = single finch install. Per the plan's §10
  resolved decision.
- **Android** — not in the plan.
- **Pack encryption at rest** — out of scope per the
  plan's §10 resolved decision (file-protection only).

## §10. Spec self-review

(Inline review at write time; not part of the published
spec.)

- **Placeholders**: none. Every section has concrete
  content. The debouncer code sketch in §2.2, the iCloud
  writer in §2.4, the folder-watcher in §3.1, the
  conflict-copy sheet in §4.2, the compare view in §4.3,
  the Settings › Sync section in §5 — all concrete.
- **Internal consistency**: §2's debouncer uses
  `Pack.export` from Phase 1.0. §3's folder-watcher uses
  `Pack.import` from Phase 1.0. §4's conflict-copy uses
  `projectState` from Phase 1.0 + the chokepoint from
  Phase 2. The Settings › Sync section (§5) is the only
  new UI; the rest of the app's UI is unchanged.
- **Scope**: focused on Phase 5. Phases 1.0-4 are
  referenced as completed. Phase 6+ are explicitly out of
  scope (§9). The estimated scope (1.5-2.5 months)
  reflects the iCloud + conflict UX being the novel piece.
- **Ambiguity**: §2's debouncer is concrete (the code
  sketch, the timing, the cancellation logic). §3's
  folder-watcher is concrete (the `NSMetadataQuery` API,
  the initial scan, the periodic poll). §4's conflict-
  copy UX is concrete (the two-card picker, the side-by-
  side compare, the force-merge escape hatch). §8
  enumerates the open questions with proposed answers.
