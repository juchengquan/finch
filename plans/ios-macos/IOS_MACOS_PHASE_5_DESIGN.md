# finch for iOS & macOS — Phase 5 Implementation Design

> _Web facts verified against commit `22c9896` (SCHEMA_VERSION `2026-06-14T00:00:00Z`), 2026-06-13.
> See `_WEB_DRIFT_CHECKLIST.md`._

> **Status**: design spec — not yet an implementation plan. Once
> approved, this becomes the input to `writing-plans` to produce
> a step-by-step implementation plan for Phase 5.
>
> Companion documents:
>
> - `plans/ios-macos/IOS_MACOS_PLAN.md` — direction brief
> - `plans/ios-macos/IOS_MACOS_PHASE_1_DESIGN.md` — Phase 1.0 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_1_5_DESIGN.md` — Phase 1.5 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_2_DESIGN.md` — Phase 2 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_3_DESIGN.md` — Phase 3 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_4_DESIGN.md` — Phase 4 full design
> - `plans/ios-macos/IOS_MACOS_ROADMAP.md` — 8-phase arc
> - `plans/ios-macos/IOS_MACOS_PHASE_5_DESIGN.md` (this file)
>
> _Audience: the engineers who will build the iOS app. Assumes
> Phases 1.0-4 are complete; the 6 tabs + 7 write screens + 7
> power features are shipped; the chokepoint + 74 actions are
> the full write surface; the iCloud `Documents/finch/` folder
> exists but is not yet watched._

## See also

- `plans/ios-macos/IOS_MACOS_INDEX.md` §2.7, §2.14 — pack format + iCloud conflict
- `plans/ios-macos/IOS_MACOS_WIRE_FORMAT.md` §4 — the pack format (build + parse + extract + detectFileKind)
- `plans/ios-macos/IOS_MACOS_PHASE_1_DESIGN.md` §4 — the Phase 1.0 import pipeline
- `plans/ios-macos/IOS_MACOS_PHASE_2_DESIGN.md` — Phase 2 (chokepoint; pack entries dispatch through it)
- `plans/ios-macos/IOS_MACOS_PHASE_6_5_DESIGN.md` — Phase 6.5 (App Group is added here, not Phase 5)
- `plans/ios-macos/IOS_MACOS_PHASE_7_DESIGN.md` — Phase 7 (widgets + Watch; reuses App Group from Phase 6.5)
- `plans/ios-macos/IOS_MACOS_PLAN.md` §4.3 — the pack-based sync model

## §0. Map — 8-section template

The 8-section template maps to this spec's existing sections:

| Template section | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §2 (Auto-pack throttle) + §3 (iCloud folder-watcher) |
| §3. iOS UI surfaces | §4 (Conflict-copy UX) + §5 (Settings › Sync section) |
| §4. Cross-cutting concerns | §6 (Orphan attachment sweep — native-only) |
| §5. Wire contracts | §2 (auto-pack throttle — chokepoint dispatches write) + §3 (iCloud folder-watcher — pack import) |
| §6. CI / test infrastructure | §7 (CI changes) |
| §7. Out of scope (firm) | §9 |
| §8. Spec self-review + open questions | §10 + §8 |

## §1. Goal & non-goals

**Goal** — Implement the **iCloud Drive sync layer** on top of
the existing `.finch` pack engine (Phase 1.0) and chokepoint
(Phase 2):

1. **Auto-pack debounce** — after any write, wait a short idle
   window (a native debounce — see §2 for cadence), then build
   a fresh `.finch` and write it to the iCloud `Documents/finch/`
   folder
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
  tabs + 7 write screens + 7 power features are unchanged.
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
**short idle timer** (a native debounce — see §2.1 for the
chosen cadence). If another write happens within that window,
the timer resets. When the timer fires, the app builds a
fresh `.finch` and writes it to the iCloud `Documents/finch/`
folder.

The debounce window is **configurable** (the iOS app exposes
a `Settings › Sync › Auto-pack frequency` slider: 10s, 30s,
1min, 5min, 15min). Note this is **not** the web's
`backupConfig.frequencyMs` semantics: the web's `autoBackup`
is a **throttle** with a **1-hour** (`3,600,000 ms`) default
(`lib/db/state.ts:211`) that gates by age-since-the-newest-
backup (`server.ts:642`), not an idle debounce. The native
app deliberately chooses a much shorter, debounce-style
cadence because iCloud sync is interactive; that is a native
product choice, not the web's default.

### 2.1 — Why debounce?

Without debouncing, a burst of writes (e.g., the user
backfills 100 entries via the rules engine) would generate
100 pack writes — one per write. The debouncer coalesces
the burst into a single pack write a short interval after the
last write.

The native default cadence is a **native product choice**
(the design suggests a short, interactive window like ~30s).
The web's `lib/db/core/server.ts::autoBackup` does NOT do
this — it is an age-since-newest-backup **throttle** with a
**1-hour** default. The iOS port intentionally diverges to a
shorter, debounce-style cadence; do not describe this as
"matching the web's default."

### 2.2 — The debouncer

```swift
// ios/FinchApp/Sync/AutoPackDebouncer.swift
@MainActor
@Observable
public final class AutoPackDebouncer {
    private var pendingTask: Task<Void, Never>?
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
        pendingTask?.cancel()  // cancel the previous pending pack
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(debounceInterval))
            if Task.isCancelled { return }
            await self?.buildAndWritePack()
        }
    }

    /// Called by the "Sync now" button. Bypasses the debounce.
    public func flush() async {
        pendingTask?.cancel()
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
`buildPack(input) → { bytes, manifest }` (`pack.ts:99`),
orchestrated server-side by `exportPackBytes()` (`server.ts:714`)
— the `lib/db/core/pack.ts` port. (The parse/extract side is
`parsePack(zipBytes) → { manifest, zip }`, `extractPack`, and
`detectFileKind`.) The build:

1. Opens the live DB read-only via GRDB
2. Runs `VACUUM INTO 'tmp/finch-<uuid>.sqlite3'`
3. Writes a fresh `manifest.json` (nested, snake_case) with
   the current `schema_version` + `db.sha256` + per-file
   attachment checksums + `db.row_counts`
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
                // `replaceItemAt` is atomic and respects the
                // iCloud file-presenter coordination; the
                // two-step (remove + copy) leaves a window
                // where the file is absent.
                try FileManager.default.replaceItemAt(
                    url,
                    withItemAt: pack,
                    backupItemName: nil,
                    options: [],
                    resultingItemURL: nil
                )
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
last 14 packs. Older packs are deleted on each new pack
write. The retention is user-configurable (Settings › Sync
› Keep last N packs: 7, 14, 30, 60, 90; default 14). This
matches the web's default retention of **14** packs
(`lib/db/state.ts:216`, `backup-config.ts:16`).

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
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        // Filter on the filename key path (Spotlight metadata
        // key, not NSMetadataItem). Gate on the `.finch` UTI
        // (registered in Phase 1.0) for accurate matching.
        q.predicate = NSPredicate(format: "kMDItemFSName LIKE[c] '*.finch'")
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
table `imported_packs` (keyed on the manifest's `db.sha256`):

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

1. Checks the manifest's `db.sha256` against `imported_packs`
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
   watcher reads this via `getxattr(2)` directly (not
   via `URLResourceKey`, which doesn't expose the file-
   provider conflict attribute on iOS).
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
iCloud folder (and copied to `Application Support/
deleted_conflicts/` for 30 days — this is the **app's**
retention, not iCloud's, since iCloud Drive's conflict
copies are deleted locally the moment we removeItem).
The "Deleted conflicts" section in Settings lets the user
recover the file for 30 days.

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
│  [On]  ~30s after a change (native) │
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
│  Keep last 14 packs              ▾  │
│                                      │
│  Conflicts (1)                      │
│  └─ 2026-06-12 18:50 iPad           │
│     [Resolve]                       │
└─────────────────────────────────────┘
```

The "Conflicts" row appears when there's an unresolved
conflict in the folder; tapping opens the conflict-copy
sheet (§4.2).

## §6. Orphan attachment sweep (native-only)

When the iOS app builds a fresh pack, it includes every
attachment in `Application Support/attachments/`. Some
attachments may be orphaned (the DB no longer references
them — e.g., the user deleted the entry but the file
remained). The pack's manifest includes the
`attachments.count`; the build also does an orphan sweep:

1. List all files in `Application Support/attachments/`
2. List all `entry_attachments.rel_path` values from the
   DB
3. For each file on disk that has no DB reference, delete
   the file (after a safety check: the file must be older
   than 1 hour; this prevents the sweep from racing with
   a concurrent write)

The sweep runs as part of every `buildAndWritePack`.

**This is a native-only feature.** The web's `autoBackup`
does **NO** orphan sweep — there is no disk-scan + DB-diff +
1-hour safety window in the web. The web's only attachment-
file cleanup is the per-mutation best-effort
`unlinkAttachmentFiles` (`_shared/attachment-cleanup.ts`),
which deletes the files for attachments removed within that
one mutation — not a periodic disk reconciliation. The iOS
sweep is a deliberate native addition; do not describe it as
"the web does the same."

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
- A **schema-version-replay test** (a test that imports a
  pack stamped at an older `schema_version`, asserts
  `migrate(exec, { fresh: false })` replays every MIGRATIONS
  entry that sorts after the recorded version, asserts the
  audit is clean post-replay). Note there is **no** pre-DE
  migration codepath — the double-entry cutover data-move is
  dead code in git history only; `MIGRATIONS` replays by
  version, so this is a generic schema-version-replay test,
  not a double-entry-cutover migration.

The iCloud integration test uses a **mock iCloud container**
(a `FileManager` substitute) so CI doesn't require a real
iCloud account.

## §8. Open questions

The plan's §14.1 still-open questions mostly land in Phase
6, but for Phase 5 specifically:

**Not blocking Phase 5 (decide later)**:

- **Pack cadence**: the native default is a short,
  interactive debounce window (the design suggests ~30s) —
  a **native product choice**, NOT the web's default. The web
  `autoBackup` is an age-since-newest-backup **throttle** with
  a **1-hour** (`3,600,000 ms`) default (`lib/db/state.ts:211`,
  `server.ts:642`). The iOS app makes the window user-
  configurable (Settings › Sync › Auto-pack frequency: 10s,
  30s, 1min, 5min, 15min). User research will inform the
  native default.
- **Sweep policy**: orphan attachments are swept on every
  pack build. The "1 hour safety" check prevents racing
  with concurrent writes. This is **native-only** — the web
  does no orphan sweep (its only cleanup is per-mutation
  best-effort `unlinkAttachmentFiles`).
- **Retention default**: 14 packs (matches the web default,
  `lib/db/state.ts:216`). The user can configure 7, 14, 30,
  60, 90.
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

- **App Group vs iCloud-only container** (resolved in
  Phase 6.5 §2.2): the iOS app's data lives in the
  iCloud `Documents/finch/` directory (for iCloud Drive
  sync). The App Group is a separate local container
  (added in Phase 6.5's Xcode setup) that the Share
  Extension + widgets + Watch app use as a shared
  scratch space — the App Group holds
  `pending_attachments/manifests/` (staged Share
  Extension files), `widget_snapshot.json` (the
  widget's read-side data), and any other cross-
  process artifacts. The live DB + attachments are
  NOT in the App Group; they're in the iCloud
  container. The two coexist: iCloud container for
  user data, App Group for cross-process state.

**Specifically for the debouncer**:

- **Debounce on app backgrounding**: when the app is
  backgrounded, the debouncer flushes immediately (a
  background debounce is unreliable; the app may be
  killed mid-debounce). The proposal does this.
- **Debounce across app launches**: the debouncer doesn't
  survive an app launch (the in-memory `pendingTask`
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
  6 tabs + 7 write screens + 7 power features are
  unchanged.
- **No row-level sync** — Phase 8.
- **App Intents / Siri / Share Extension / Spotlight /
  notifications / biometric lock** — Phase 6.
- **Widgets / Live Activities / Watch** — Phase 7.
- **iOS-on-Mac (Catalyst)** — Phase 3.
- **No new chokepoint actions** — the 74 Phase 2 actions
  are the full set (Phase 6.5's `setEntryAttachment` brings
  the running total to 75; Phase 5 doesn't add more).
  Phase 5 wires the pack engine + iCloud container;
  no new actions.
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
  `buildPack` / `exportPackBytes` from Phase 1.0. §3's
  folder-watcher uses the `parsePack` / import pipeline from
  Phase 1.0. §4's conflict-copy uses
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
