# ios/CLAUDE.md

The **native port of finch** — the SwiftUI app under `ios/`, shared by iOS, macOS
(`FinchMac`), watchOS, the Widget, and the Share extension. Active work happens here; the
root `CLAUDE.md` documents the web `frontend/`. Design docs: `plans/ios-macos/` (start at
`IOS_MACOS_INDEX.md`; gap matrix in `IOS_MACOS_UI_GAP_AUDIT.md`, build-out plan in
`IOS_MACOS_UI_REMEDIATION_PLAN.md`). Native may add features ahead of the web and feed
them back.

## Layout

- **`FinchCore/`** — SwiftPM package: read-side engine + write chokepoint. Swift port of
  `frontend/lib/db/`, kept at behavioral **parity** (see below). Sources in
  `FinchCore/Sources/FinchCore/`, tests in `FinchCore/Tests/` (`FinchCoreTests` + `ParityTests`).
- **`FinchApp/Sources/`** — the app layer, split three ways for the UIKit migration
  (`docs/uikit-migration-plan.md`):
  - **`FinchShared/`** — `FinchStore`, routing, notifications, sync, Spotlight, security,
    App Intents, pure logic, **and the string catalogs** (`Resources/*.xcstrings`).
    Compiled by **both** `FinchApp` and `FinchMac`.
  - **`FinchAppSwiftUI/`** — every SwiftUI view. iOS drops files via `excludes:` in
    `project.yml` as screens are converted; `FinchMac` keeps them all.
  - **`FinchAppUIKit/`** — UIKit code, **iOS only**.

  View-layer test: a file declaring `: View`, `: ViewModifier`, `-> some View`, `: App`
  or `: Scene` is view layer; everything else is shared.
- **`Shared/`** — `WatchSnapshotPayload*` (Foundation-only; compiled into phone + Watch so
  the Watch needs no `FinchCore`).
- **`FinchWidget/`, `FinchWatch/`, `FinchWatchComplication/`, `FinchShare/`** — extensions + Watch app.
- **`scripts/`** — localization tooling (Bun/TS). **`docs/`** — `simulator-ui-driving.md`.
- **`swiftui-vs-uikit.md`** — the SwiftUI-first rule; read before reaching for UIKit.

## Build & run

> **TWO XcodeGen projects, both git-ignored:** `FinchApp.xcodeproj` (iOS, extensions,
> Watch, tests) from `project.yml`; `FinchMac.xcodeproj` (macOS only) from
> `project-mac.yml`. Generate **both**: `xcodegen generate --spec project.yml,project-mac.yml`
> — before building, and again after adding any file under `FinchApp/Sources/` (new files
> enter a project only on regen; plain `xcodegen generate` does iOS only). Split so the
> iOS localization export cannot compile macOS — see `ios/project-mac.yml`'s header.

- **`swift build` / `swift test` build only `FinchCore`** (package rooted at
  `ios/Package.swift`; there is no `ios/FinchCore/Package.swift`). App targets build via
  the generated Xcode projects, not SwiftPM.
- **CLI:** if `xcode-select -p` says `CommandLineTools`, prefix xcodebuild with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- **iOS → Simulator:** scheme `FinchApp`, iPhone destination, bundle id
  `com.juchengquan.finch`. Prefer the **`ios-build-launch` skill**.
- **macOS → native window (no simulator):** `FinchMac.xcodeproj`, scheme `FinchMac`,
  "My Mac". Signs **ad-hoc** (`CODE_SIGN_IDENTITY = -`); its **App Group was dropped**
  from `FinchApp/FinchMac.entitlements` for team-less signing (no Mac widget;
  `AppGroup.containerURL` falls back to Application Support).
- **CI** builds the simulator unsigned (`CODE_SIGNING_ALLOWED: NO`). The **entire Apple
  suite runs post-merge only** — no Xcode work gates a PR (see Conventions); the
  pre-merge gate is `ci-local.sh` on your machine. Device builds need a local
  `DEVELOPMENT_TEAM` (don't commit it).

### Targets

`project.yml` → `FinchApp.xcodeproj`: `FinchApp`, `FinchWidget` / `FinchShare` (iOS
extensions), `FinchWatch` (watchOS app), `FinchWatchComplication`, plus `FinchAppTests` /
`FinchAppUITests` / `FinchCoreTests`.

`project-mac.yml` → `FinchMac.xcodeproj`: `FinchMac` alone (PRODUCT_NAME `finch`). It
compiles the **same SwiftUI sources** as `FinchApp` + `Shared/` — the split is of the
build, not the code — so iOS-only modifiers stay shimmed in `Common/PlatformCompat.swift`
(`#if os(macOS)`), and unguarded `Shared/` code must compile on macOS.

> **Localization caveat of the split:** keys are extracted from `FinchApp.xcodeproj` only,
> so a `String(localized:)` living only in macOS-only code never reaches the catalog and
> renders English. Verified lossless at split time (742 keys before and after); if macOS
> grows its own strings, add an export pass over `FinchMac.xcodeproj`.

> **Info.plist gotcha:** app/extension targets use hand-authored `INFOPLIST_FILE` with
> `GENERATE_INFOPLIST_FILE: NO`. Never switch to XcodeGen's `info:` block — it regenerates
> the plist and wipes the `.finch` UTI / document types / `finch://` scheme. Edit
> `Info.plist` directly.

## Test

- **`cd ios && swift build && swift test`** = `FinchCoreTests` + the four `ParityTests`
  gates. App-level tests run via the Xcode `FinchApp` scheme.
- **Regenerate parity fixtures:** `cd frontend && bun scripts/export-fixtures.ts`. Gotchas
  (also in `ios/README.md`):
  - After changing `WRITE_SEQUENCE`, keep only `writeparity/sequence.json` — the other
    fixtures churn by `datetime('now')` noise alone; **revert them**.
  - **No wall-clock-dated actions in `WRITE_SEQUENCE`** (e.g. `createAccount` with
    `openingBalance` stamps "today" → oracle fails the next day). `postScheduled` is fine —
    it takes an explicit date.

### The pre-merge iOS gate — `ios/scripts/ci-local.sh`

```bash
ios/scripts/ci-local.sh                        # the GATE — run before every push (~40 s warm · ~2.5 min cold)
ios/scripts/ci-local.sh --ui                   # + the iPhone UI tests (navigation work)
ios/scripts/ci-local.sh --full                 # cold full rehearsal of the post-merge CI job
ios/scripts/ci-local.sh --all                  # + the frontend job
ios/scripts/ci-local.sh --sim "ios-mysim"      # pin the simulator
```

**PRs run no Xcode at all** (2026-08-07; hosted `macos-26` queues were 10 min–12 h).
GitHub's PR check is ubuntu-only (frontend + cheap guards, ~2 min); the **full Apple
suite runs post-merge** as the safety net. **This script is what stands between a bug and
the base.**

- **The default run IS the gate**: seconds-cost checks + app build + `FinchAppTests` on
  **warm per-worktree DerivedData** (`ios/DerivedData/ci-local`, gitignored). It skips the
  33 UI tests (add via `--ui` for navigational changes), the duplicated `FinchCoreTests`
  (step 2's `swift test` already ran those 434 methods), and untouched platform builds. Skips are
  listed every run; all of them run post-merge in CI — deferred, not lost, coverage.
- **`--full`** = everything, cold `mktemp` DerivedData, mirroring the post-merge job
  fail-fast. A warm gate can pass on a stale product (has happened twice); acceptable now
  only because the cold post-merge run backstops every merge. Use `--full` — or the
  workflow's **`workflow_dispatch`** — before a risky merge. `FinchMac`/`FinchWatch`
  build non-gating (`FINCH_CI_PLATFORMS=1` to gate).
- **One run per machine** — two at once thrash (measured LA 28 on 12 cores); a second
  invocation waits and names the holder. A "slow" run is usually a queued run.
- **Worktree-named simulator**, created if needed; `--sim` / `$FINCH_CI_SIM` / `$SIM_NAME`
  override. Never a stock shared device — `xcodebuild test` installs app + demo seed onto
  whatever it's handed.
- `act` can't help (no macOS Docker container).

> **The one thing that makes local runs lie:** post-merge CI builds your branch **combined
> with the base**. Behind the base = green locally, red base after merge, on code you
> don't own. Step 0 refuses to run when behind: `git rebase origin/feat/frontend` first.
> Rule this out before calling any CI failure "environmental".

**The two i18n guards** (in CI too: guard 1 on every PR in the ubuntu `guards` job,
guard 2 post-merge — it needs a compile). `Localizable.xcstrings` is GENERATED;
hand-editing it destroys work:

| Guard | Catches | Fix |
|---|---|---|
| catalog reproducible from inputs | someone edited the generated catalog | translation goes in `scripts/zh-manual.json`, re-run `build-xcstrings.ts` |
| extracted keys current | a new UI string missing from `extracted-keys.json` → absent from catalog → renders English | re-run the pipeline atop `scripts/build-xcstrings.ts`; commit key set **and** rebuilt catalog |

Guard 2 compares the **key set**, not bytes. Regenerate `extracted-keys.json` only via
`bun run scripts/xliff-keys.ts > scripts/extracted-keys.json` — hand-writing it (even
identical) changes formatting and fails the guard.

**What the guards can't see:** strings that were never localizable —
`UNNotificationAction(title:)`, `Toggle(someString, …)`, any plain `String` — ship English
in every language with no check failing. Use `String(localized:)` at those sites. Avoid a
literal `%` inside an interpolated localized string (must round-trip as `%%`); pre-format
the value instead.

**What a green PR check means:** the required `ios-required` aggregate covers only
frontend + guards on a PR — no Swift, no Xcode. A red post-merge run files/updates a
**`post-merge-red` issue** (auto-closed by the next green push run) — check for it before
diagnosing. If `ci-local.sh` fails on strings you didn't touch, the base is probably
already red.

## Architecture

Two layers: the **`FinchCore` engine** (SwiftPM) and the **`FinchApp` shell**.

### FinchCore — the engine (parity port of `frontend/lib/db/`)

Behavioral mirror of the web DB layer, verified against fixtures the web exports
(`frontend/scripts/export-fixtures.ts`). Modules:

- **`Storage/`** — `Schema.swift`: the web `SCHEMA` DDL **byte-for-byte** (double-entry
  `entries`/`postings`, two-phase `sealed` write, balance/currency triggers, FTS5);
  `Schema.version` must equal web `SCHEMA_VERSION` (currently `2026-07-23T00:00:00Z`).
  `Migrations.swift` (fresh-DB init via `Migrations.runAll`), `Pack.swift` (`.finch` ZIP;
  snake_case manifest via explicit `CodingKeys`, **never** `.convertFromSnakeCase`),
  `Audit.swift` (10-code ledger sweep, verbatim; `jsNum()` matches JS `Number.toString`
  so `detail` strings compare byte-for-byte), `DownSync.swift` (CloudKit fresh-device
  seed; pure DB I/O).
- **`Store/`** — the **write chokepoint** (mirror of `lib/db/mutate.ts` + `domain/`).
  `ActionName.swift` = the web's actions **plus native-only** `setEntryAttachment` and
  native-first `setBudgetOrder` / `setTrackedCurrencies` (web ignores them).
  `Apply.apply` / `applyReturningId` dispatch to per-domain `handlers` in
  `Store/Domain/*.swift`; `JSONValue`/`Args` are the value types.
- **`Project/`** — read model (mirror of `projectState`). `Projection.run()` →
  `[Tx]` at **per-account-leg-posting grain** (one entry → several `Tx`; opening entries
  excluded), enriched with category/splits/tags/transfer/refund. `Money.swift` = currency
  core. `WidgetSnapshot.swift` also defines `enum AppGroup` (`group.com.juchengquan.finch`).
- **`Selectors/`** — pure selectors (`accountBalance`, `categorySpend`, `netWorth`,
  budget/forecast/insights/holdings/reconcile). Compute from these; don't store figures.
- **`Rules/`** (conditional rules), **`Export/`** (CSV).

**Don't hand-edit** `Schema.ddl`, `Pack`, or `Audit` — generated/verbatim from the TS
source; re-emit from the web side. Parity = four `ParityTests/` gates: selectors, audit,
projection, and a write round-trip replaying `WRITE_SEQUENCE` through Swift `Apply` with
an id-/timestamp-agnostic snapshot compare.

### FinchStore — the app store

`FinchStore` (`@MainActor`, `ObservableObject`, singleton `.shared`) = the zustand
equivalent: a **projection, not the source of truth** — `@Published` slices for the
**active ledger only**; SQLite is authoritative.

- **Mutation chokepoint:** every write → `store.apply(action, args)` /
  `applyReturningId` → `FinchCore.Apply` (may reject with `I18nError`) →
  `reprojectActiveLedger()` → republish. **No optimistic UI** — synchronous
  write-then-reproject, all-or-nothing (keeps last-good state, sets `dataError`).
  **Everything** — Siri, Watch, notification actions, seeds — funnels through it; nothing
  mutates the DB directly.
- **Write side-effects on every `apply`:** Spotlight re-index, notification re-plan,
  widget snapshot + timeline reload, debounced auto-backup, CloudKit outbox. Bulk seeds
  call `FinchCore.Apply.apply` directly to bypass them.
- **DB:** `Application Support/finch.sqlite3`, one GRDB `DatabaseQueue` (never a
  `DatabasePool`). **Relocates to a temp dir under XCTest** so import tests can't clobber
  dev data. App Group = cross-process scratch only (widget snapshot, Share receipts),
  never the main DB.
- **`store.today` is data-anchored** (`max(tx.date)`) for budget windows/forecasts (demo
  determinism). Literal-"today" surfaces (calendar, Today/Yesterday labels, next-run
  dates) must use **`store.wallToday`**. Mixing them is a real bug source.
- **`yyyy-MM-dd` are civil dates, not instants.** Parse/format with **`AppDate.isoDay`**,
  component math with **`AppDate.civil`** (Gregorian, device zone) — both ends in the
  **device** timezone. **Never hand-roll a hardcoded-UTC `Calendar` in the app layer**:
  local-parse + UTC-math shifts the day for any user off UTC (shipped twice, #570).
  `FinchCore` and `scheduledNextRun` are internally UTC and that's fine — zone is
  unobservable there; the bug lives only at the boundary. Guarded by
  `FinchAppTests/CivilDateTests` (fails in any non-UTC zone if a UTC pin returns).
- Per-device view prefs (active ledger, privacy mode, saved searches, appearance) live in
  **UserDefaults, never the DB or exports**.

### The adaptive shell & navigation

Chrome is **two renders**: `Shell/AdaptiveShell.swift` switches on `horizontalSizeClass` →
`TabBarShell` (compact) vs `SplitViewShell` (regular, master-detail via
`Shell/MasterDetailShell.swift`). Content views are single-render "one view, two layouts":
optional `selection: Binding<String?>?` — non-nil ⇒ selection mode, nil ⇒ push mode.

- **7 `AppTab`s ≠ 5 bottom slots.** `AppTab` lives in **`DeepLink/DeepLinkRouter.swift`**,
  not `Shell/`. Bottom bar: Accounts/Budgets/Scheduled/Insights/Settings; **Activity is
  hosted inside Accounts**; **Ledger is a top-left corner-push** (`LedgerBarButton`).
  Launch tab `.accounts`.
- **Routing is centralized in `DeepLinkRouter`** (`@MainActor` `.shared`) so App Intents /
  notifications / Spotlight drive the same state as the UI. Internal routes are
  `"<domain>:<id>"` strings (also the Spotlight item id).
- **⌘K palette:** `Shell/CommandPalette.swift` + `Shell/FinchCommands.swift` (⌘N add,
  ⌘1–6 tabs, ⌘⇧E export, ⌘⇧H hide amounts). Palette and add sheets present at **app
  root**; force-dismissed when the biometric lock engages.

### List rows & swipe actions — the 60pt rule

iOS picks the swipe-action style by **row height** (undocumented private behavior;
bisected on-device, boundary stable across text sizes and 390/402pt widths):

| row height | style |
|---|---|
| ≤ 59pt | wide capsule, icon + label inside the colour |
| ≥ 60pt | circular glyph, grey label below |

- **Height-driven, not label-driven** — `Label(_:systemImage:)` is correct in both cases;
  don't debug the label when styles disagree across pages.
- **`listRowInsets` is usually the lever** (default ~11pt/side vs the feed's
  `top: 2, bottom: 2` ≈ 13pt swing — the cause of #578). Check insets before content.
- **Accessibility sizes make everything circles** (smallest natural row ~63pt) — the
  circle+caption layout is the accessible fallback, not a regression.
- **Don't pay real costs to get under 60**: never truncate a row's name or shrink a
  sub-44pt tap target for a rendering detail. Budgets stays 75pt (circle) by choice.
  Tap-target floor: Categories' expand chevron is `Metrics.tapTargetMin` (44pt) square,
  guarded by `ExpandChevronTapTargetTests`. In UIKit, accessory `customView.frame` is
  **ignored** and constraints crash — `intrinsicContentSize` is the only working lever
  (see `AccessorySquare` in `CategoriesVC`).

Current heights: Accounts · `TxRow` · Merchants · Tags · Scheduled · Ledger · Categories
= 52pt (capsule — Categories dropped from 60 when its 26pt colour disc became the 18pt
`RowGlyphView` glyph); Budgets = 75pt (circle, by choice). **Measure with
`idb ui describe-all`**, not screenshots.

### Write screens (`WriteScreens/`)

Standard sheet = `NavigationStack { Form }`, `.inline` title, **icon toolbar buttons**:
`.cancellationAction` = ✕, `.confirmationAction` = ✓ (`confirmCheckmarkStyle()` in
`Common/ViewModifiers.swift`). Pickers are tap-to-open full-height sheets:
`SearchablePickerRow` (generic, stage-then-Confirm), `CategoryPickerRow` (tree),
`MerchantPickerRow` (free-text, **commits on tap** — deliberate: `.searchable` collapses
the nav bar and hides Confirm), `TagChipFlow`/`TagField` (chips via `FlowLayout`).
`AddTransactionSheet` is the flagship and the **layout blueprint** for the family (amount
is in the **account's own currency**).

- **Sheet layout is tokenized — don't hand-tune insets.** Apply **`finchSheetForm()`** to
  the `Form` — it sets `sectionSpacing` + `sheetTopMargin` from `Common/Metrics.swift`;
  without the explicit margin SwiftUI hands these sheets *different* default top insets
  (the old inconsistency). Headers go
  through **`finchSectionHeader(_:)`** — takes `LocalizedStringKey`; a `String` binds the
  non-localizing `Text` init and silently ships English.
- **No header on the first section after the type caption** (costs ~36pt of grey chrome
  for nothing; #563). Resist "Details"/"General"/"Info" openers.
- **Measure, don't eyeball:** `idb ui describe-all` gives frames in points; correct
  top-of-form reads type caption `y=138 h=48`, first row `y=198` (h≈50.3 —
  `Metrics.sheetRowMinHeight` floors short rows at 48; the style's own fixed
  vertical padding sets the rest, and its comment lists the measured dead
  knobs — don't re-try `listRowInsets`). Pixel-squinting
  produced wrong fixes twice (#554, #563).

### Money & currency (easy to get wrong — mirrors the web gotcha)

**Stored in the ledger's BASE currency; displayed in a per-ledger DISPLAY currency.**
Never format raw amounts; **never call `Money.format` in a view** (bypasses the privacy
mask). Use `FinchStore+ViewHelpers.swift`:

- **`displayMoneyBase(_:)`** — base amount → display currency, formatted.
- **`displayMoney(_:from:)`** — account-currency amount → base → display.
- **`displayNative(_:currency:)`** — format in that currency, **no conversion**.
- **`toBase(_:from:)`** — account → base; aggregates sum in base then format. `…forLedger:`
  variants exist for the two-layer Ledger detail.

`baseCurrency` = active ledger's `.base`; `displayCurrency` =
`displayCurrencyByLedger[activeLedgerId]` (DB-backed via `app_state`, defaults to base).
FX core in `Money.swift`: **hub USD**, `ExchangeRate.rate` = **USD-per-1-unit**;
`Money.convert` returns **`nil` for unrated currencies** and callers pass the amount
through **unconverted** — display-currency options are therefore restricted to rated
currencies. Privacy mode masks every `display*` helper with `"••••"`.

### Sync & data (mostly inert scaffold — read carefully)

- **CloudKit sync (`Sync/CloudKitSync*.swift`, `SyncMutation.swift`) is scaffold, not
  shipping** — built without a provisioned container, never two-device tested (loud
  `⚠️ UNVERIFIED AT RUNTIME` headers). Syncs **mutations, not rows**: each `apply` becomes
  a `SyncMutation` in a per-ledger zone; other devices replay through their own
  chokepoint. Trust the pure/tested pieces (`SyncOutbox`, mappers, `CloudKitConflict`,
  `DownSync`); treat the transport as unproven.
  **CloudKit *traps* (not throws) when unentitled** — never "simplify" the
  `hasCloudKitEntitlement` guard. Inert until provisioned
  (`plans/ios-macos/IOS_MACOS_PHASE_8_CLOUDKIT_SETUP.md`).
- **iCloud Drive pack sync (`Sync/ICloudSync.swift`)** — still alive: pushes auto-backup
  `.finch`s to iCloud Drive; surfaces newer packs for **manual** import (never silently
  swaps the live DB). Nil-safe without a ubiquity container.
- **`Sync/AutoBackupManager.swift`** — debounced (~5s) `.finch` snapshots: single local
  latest daily in `Application Support/Backups/` + keep-N archive in the designated folder.
- **`Sync/RateAutoUpdater.swift`** — the app's **only third-party network call**: daily
  ECB FX via `api.frankfurter.dev` (no key, ~20h throttle, silent offline). Stores the
  **inverse** of the quote (USD-per-unit).
- **Import/export (`FinchStore+ImportExport.swift`, `ImportExport/`)** — the `.finch`
  pipeline. **Import audits pre-swap**: on `PackError.auditFailed` the live DB is
  untouched (rejected pack retained for Face-ID-gated "Force import"). Export =
  `VACUUM INTO` clone + attachments. Export/delete/force-import are **biometric-gated**
  (`Security/BiometricGate`, **fails open** on a bare simulator).
- **Demo seed:** fresh DB on **simulator** → `SimulatorDemoSeed.seed` (~3-month dataset +
  EUR "Travel" ledger); otherwise `seedMinimalStarter` (one Personal/USD ledger). Account
  ids are a **global** PK, not per-ledger.

### OS integrations

- **Deep link:** only `finch://add` (`?account=<id>` pre-selects), via
  `DeepLinkRouter.handle`. Richer navigation is router state, not URLs.
- **App Intents:** 7 intents + 3 entities; writes via `store.apply`. **Biometric lock
  enforced**: locked ⇒ data actions refuse, entity queries return `[]`.
- **Widgets + Watch — two snapshots, two transports:** `WidgetSnapshot` (FinchCore) →
  App Group file → WidgetKit (same device). `WatchSnapshotPayload` (`Shared/`) → WCSession
  `updateApplicationContext` (App Groups don't cross devices). The Watch carries its own
  quick-add catalog; wrist adds land **pending** on the phone.
- **Spotlight:** full re-index on launch, every write, and import; **cleared while
  locked**, rebuilt on unlock.
- **Notifications:** 100% **local**. Content computed at plan-time with stable ids so
  re-planning is idempotent; `NotificationPlanner` is the pure/tested core.
- **`Security/`:** optional biometric lock (`LAPolicy.deviceOwnerAuthentication`,
  passcode fallback; off/onLaunch/onBackground/onIdle; **fails open** if the device can't
  evaluate).
- **`PowerTools/`** is reference-data admin UI (Categories, FX, Rules, Tags,
  Counterparties, statement import) — not an OS integration.

### i18n

**Generated, never hand-edited.** English is source; the only target is **`zh-Hans`**
(`FinchShared/Resources/Localizable.xcstrings` + `AppShortcuts.xcstrings`); untranslated
keys fall back to English. Pipeline (documented atop `scripts/build-xcstrings.ts`):
`xcodebuild -exportLocalizations` → `xliff-keys.ts` (→ `extracted-keys.json`, the
authoritative key set) → `build-xcstrings.ts` rebuilds with precedence
**`zh-manual.json` > web-derived map (`frontend/messages/{en,zh-CN}.json`) > English**.
Re-run all three after adding UI strings; hand edits go in `scripts/zh-manual.json`.

## Conventions

- **How a feature gets built:** brainstorm → design → plan → execution (one task at a
  time, reviewed between) → PR to `feat/frontend` → the user merges → delete worktree +
  branch. Each feature gets its **own worktree off `origin/feat/frontend`**
  (e.g. `/tmp/finch-<slug>`); the user edits the main tree concurrently — never
  `git stash` or `git checkout` there. **No `Co-Authored-By` trailer.**
- **No Xcode work gates a PR** (2026-08-07): PR check is ubuntu-only; the whole Apple
  suite (build, tests, UI tests, `FinchMac`, `FinchWatch`) runs post-merge or via
  `workflow_dispatch`. Pre-merge gate = `ci-local.sh`; macOS/watchOS breaks are warnings
  (`FINCH_CI_PLATFORMS=1` to gate). `FinchMac` must stay in its own project — inside
  `FinchApp.xcodeproj`, `-exportLocalizations` compiled it regardless of scheme/target/
  destination (see `ios/project-mac.yml`).
  **Still build `FinchMac` when touching `FinchShared`/`FinchAppSwiftUI`:** a macOS-only
  break passes the iOS build (`.topBarTrailing` doesn't exist on macOS), and `FinchMac`
  is the only target compiling `FinchAppSwiftUI/FinchApp.swift` plus every SwiftUI screen
  iOS `excludes:` — a surface that grows with each conversion.
- **SwiftUI-first** (`ios/swiftui-vs-uikit.md`): UIKit/AppKit only where SwiftUI can't,
  bridging the smallest piece behind a `Representable` in `Common/`. 4 sanctioned touches
  today (`Common/ActivityMonitor`, `FinchShare/ShareViewController`,
  `openSettingsURLString`, `NSMetadataQuery`). Deployment floor: **iOS 17 / macOS 14 /
  watchOS 10**.
- **Encapsulation boundary is the module, not the type**: `FinchStore` members shared
  with its `+Sync`/`+ImportExport`/`+ViewHelpers` extensions are intentionally
  `internal` — don't "tighten" them.
- **Driving the simulator:** `simctl` has no tap/swipe — use **`idb`**
  (`~/.local/idb-venv/bin/idb ui tap <x> <y> --udid <UDID>`; also `ui swipe`,
  `ui describe-all`). Install: `brew install facebook/fb/idb-companion` + `fb-idb` in a
  **Python 3.11** venv (3.12+ breaks on `asyncio.get_event_loop()`). `ui describe-all`
  returns frames **in points** — measure with it, don't eyeball screenshots.
  **AppleScript/AX is a dead end under tmux** (TCC attributes `osascript` to the detached
  tmux server). Fast jumps: DEBUG-only launch args `-initialTab <tab>`, `-openAdd YES`,
  `-resetStore`, `-disableNotifications` (all parsed in `LaunchSequence.run` —
  `FinchApp.swift` is excluded from iOS, so `App.init` parsing is macOS-only dead code on
  iOS), or `finch://add`. Longer recipe:
  `ios/docs/simulator-ui-driving.md`.

## Known OS issues (device-only)

- **iOS 26.5 Liquid Glass "resume shadows" under the chrome** — exaggerated shadows under
  nav pills / search / tab bar / FAB for ~2s after app-switch. **Not our code**:
  bisect-confirmed (Debug and Release, main thread idle, page-dependence uncorrelated
  with source); `scrollEdgeEffectStyle(.soft)` does NOT help, while
  `UIDesignRequiresCompatibility` removes it entirely — the conclusive attribution.
  Don't re-investigate chrome shadow glitches until Apple's compositor fixes land. The
  plist key is a livable local opt-out — **never commit it** (Apple will drop the key in
  a future SDK).
  The pushed-scroll-view variant does reproduce on the sim, but `simctl` screenshots
  don't capture glass layers. See `ios/docs/ios26-liquid-glass-artifacts.md` and
  `ios/docs/ios26-shadow-variant-matrix.md`.
