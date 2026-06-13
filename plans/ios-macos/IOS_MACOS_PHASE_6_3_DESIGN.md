# finch for iOS & macOS — Phase 6.3 Implementation Design (Biometric lock)

> **Status**: design spec — not yet an implementation plan. Once
> approved, this becomes the input to `writing-plans` to produce a
> step-by-step implementation plan for Phase 6.3.
>
> Companion documents:
>
> - `plans/ios-macos/IOS_MACOS_PLAN.md` — direction brief
> - `plans/ios-macos/IOS_MACOS_PHASE_1_DESIGN.md` through `IOS_MACOS_PHASE_5_DESIGN.md` —
>   Phases 1.0 through 5 full designs
> - `plans/ios-macos/IOS_MACOS_PHASE_6_1_DESIGN.md` — Phase 6.1 (Spotlight)
> - `plans/ios-macos/IOS_MACOS_PHASE_6_2_DESIGN.md` — Phase 6.2 (Notifications)
> - `plans/ios-macos/IOS_MACOS_PHASE_7_DESIGN.md` — Phase 7 (widgets + Watch)
> - `plans/ios-macos/IOS_MACOS_ROADMAP.md` — 8-phase arc
> - `plans/ios-macos/IOS_MACOS_PHASE_6_3_DESIGN.md` (this file) — Phase 6.3
>
> Phase 6 is decomposed into 5 sub-specs (6.1-6.5). This is
> 6.3: biometric lock via `LocalAuthentication`. Phases 6.1
> and 6.2 are independently shipped. Phases 6.4-6.5 ship in
> any order.
>
> _Audience: the engineers who will build the iOS app. Assumes
> Phases 1.0-5 are complete._

## See also

- `plans/ios-macos/IOS_MACOS_INDEX.md` §2.13 — biometric / passcode fallback
- `plans/ios-macos/IOS_MACOS_PLAN.md` §10 — the biometric policy
- `plans/ios-macos/IOS_MACOS_PHASE_1_DESIGN.md` — Phase 1.0 (read-only shell; biometric gates the app)
- `plans/ios-macos/IOS_MACOS_PHASE_6_1_DESIGN.md` — Phase 6.1 (Spotlight; same Xcode project)
- `plans/ios-macos/IOS_MACOS_PHASE_6_2_DESIGN.md` — Phase 6.2 (Notifications; same Xcode project)
- `plans/ios-macos/IOS_MACOS_PHASE_6_4_DESIGN.md` — Phase 6.4 (App Intents; sensitive intents gated by biometric)

## §0. Map — 8-section template

The 8-section template maps to this spec's existing sections:

| Template section | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §3 (The `BiometricGate` class) |
| §3. iOS UI surfaces | §2 (The biometric policy — the 4 policies are the user-facing settings) |
| §4. Cross-cutting concerns | §5 (Data protection at rest) + §6 (Settings › Security section) |
| §5. Wire contracts | §4 (Sensitive-action gating — gates the chokepoint) |
| §6. CI / test infrastructure | §7 (CI changes) |
| §7. Out of scope (firm) | §9 |
| §8. Spec self-review + open questions | §10 + §8 |

## §1. Goal & non-goals

**Goal** — Add an **optional biometric lock** to the iOS
app:

- The user can choose to require **Face ID / Touch ID /
  Optic ID** to open the app, after a configurable idle
  timeout, or always
- The user can require biometric re-auth for **sensitive
  actions** (export, delete-all, change base currency)
- The data is protected at rest with
  `NSFileProtectionCompleteUnlessOpen` (per the plan's
  §10 resolved decision)
- The user can opt out entirely (the app opens
  immediately; the data is still encrypted at rest by
  iOS)

**Non-goals (firm)**:

- **No passcode fallback** — per the plan's §10, the
  proposal uses biometric only. The data is still
  encrypted at rest by iOS; if biometric fails repeatedly,
  iOS forces the user to use the device passcode (which
  iOS manages). We don't implement our own passcode
  fallback.
- **No new tabs / write screens / power features** — the 6
  tabs + 7 write screens + 7 power features are unchanged.
  Phase 6.3 adds a **lock surface** (a gate on app
  launch + a gate on sensitive actions).
- **No new selectors** — the Phase 1.5 selectors are the
  full set. Biometric lock doesn't read.
- **No new chokepoint actions** — the chokepoint is
  unchanged. The biometric lock gates the UI; it doesn't
  gate the chokepoint (the chokepoint is internal to the
  app; the user can't call it without going through the
  UI).
- **No remote wipe** — if the user loses their device, the
  data is wiped via iOS's standard "Erase all content
  and settings" flow. We don't implement our own remote
  wipe.
- **No Touch ID / Face ID on Mac** — Mac's biometric
  integration is via Touch ID (built-in keyboards). The
  proposal works on Mac too (the `LAContext` API is
  cross-platform); the UX is the standard macOS Touch ID
  prompt.
- **No biometric auth for widgets + Watch** — the
  widgets (Phase 7) and Watch app don't show financial
  data without a tap-through to the iOS app (which is
  gated by biometric). The widget's data is the same
  data the iOS app shows; the widget itself doesn't need
  its own lock.

**Estimated scope**: ~400-500 lines Swift (the
`BiometricGate` + the policy model + the sensitive-action
gating) + ~150 lines SwiftUI (the Settings › Security
section) + ~150 lines tests. **1-2 weeks of full-time
work** for a small team. **Smallest of the 5 sub-specs**
after Phase 6.1.

## §2. The biometric policy

The biometric policy is a small set of user-configurable
options:

| Policy | Behavior |
|---|---|
| **Off** (default) | The app opens immediately; no biometric auth required |
| **On launch** | Every app launch requires biometric auth (from cold start AND from background) |
| **On background** | When the app is backgrounded for >N seconds, biometric auth is required to return |
| **On idle** | When the app is foreground but idle for >N seconds, biometric auth is required to interact |

The user picks one policy + the timeout (for "On
background" and "On idle" policies; the timeout is
configurable: 1, 5, 15, 30, 60 minutes; default 5).

### 2.1 — The policy data model

```swift
// ios/FinchApp/Security/BiometricPolicy.swift
public enum BiometricPolicy: String, Codable, Sendable, CaseIterable {
    case off
    case onLaunch
    case onBackground
    case onIdle

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .onLaunch: return "On launch"
        case .onBackground: return "On background"
        case .onIdle: return "On idle"
        }
    }
}

public struct BiometricSettings: Codable, Sendable {
    public var policy: BiometricPolicy = .off
    public var timeoutSeconds: Int = 300  // 5 minutes
    public var sensitiveActionsEnabled: Bool = true

    public static let defaultSettings = BiometricSettings()
}
```

The settings live in `app_state` (key:
`biometric_settings`, value: JSON-encoded
`BiometricSettings`). The web's `app_state` table is the
shared shape; the iOS port mirrors.

## §3. The `BiometricGate`

The `BiometricGate` is the iOS app's central lock
service. It hooks into the iOS app's lifecycle (app
launch, background → foreground, idle timer) and
prompts for biometric auth as needed.

### 3.1 — The gate

```swift
// ios/FinchApp/Security/BiometricGate.swift
@MainActor
@Observable
public final class BiometricGate {
    public static let shared = BiometricGate()

    public private(set) var isLocked: Bool = true
    public private(set) var lastUnlockAt: Date? = nil
    public private(set) var lastActivityAt: Date = Date()
    public private(set) var lastBackgroundedAt: Date? = nil
    public private(set) var settings: BiometricSettings = .defaultSettings

    private let context = LAContext()
    private var idleTimer: Timer?

    public func evaluateLockState() async {
        switch settings.policy {
        case .off:
            isLocked = false
        case .onLaunch:
            if lastUnlockAt == nil {
                isLocked = true
            } else {
                isLocked = false
            }
        case .onBackground:
            // Check if the app was backgrounded for more than
            // the timeout; if so, lock.
            if let lastBackgroundedAt = lastBackgroundedAt,
                   Date().timeIntervalSince(lastBackgroundedAt) > TimeInterval(settings.timeoutSeconds) {
                isLocked = true
            } else {
                isLocked = false
            }
        case .onIdle:
            // Check if the app was idle for more than the
            // timeout; if so, lock.
            if Date().timeIntervalSince(lastActivityAt) > TimeInterval(settings.timeoutSeconds) {
                isLocked = true
            } else {
                isLocked = false
            }
        }
    }

    public func recordActivity() {
        lastActivityAt = Date()
    }

    public func recordBackground() {
        lastBackgroundedAt = Date()
    }

    public func unlock() async throws {
        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock finch"
        )
        if success {
            isLocked = false
            lastUnlockAt = Date()
        } else {
            throw BiometricError.userCancelled
        }
    }

    public func authenticateForSensitiveAction(reason: String) async throws {
        guard settings.sensitiveActionsEnabled else { return }
        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: reason
        )
        if !success {
            throw BiometricError.userCancelled
        }
    }
}

public enum BiometricError: Error {
    case userCancelled
    case biometryNotAvailable
    case biometryNotEnrolled
    case biometryLockout
}
```

The `LAContext.evaluatePolicy` API handles all the
platform-specific UX (Face ID prompt, Touch ID prompt,
fallback to device passcode, lockout after repeated
failures).

### 3.2 — The lock screen

When `isLocked == true`, the iOS app shows a full-screen
lock screen:

```
┌─────────────────────────────────────┐
│                                      │
│                                      │
│           [finch icon]               │
│                                      │
│           finch is locked            │
│                                      │
│         ┌──────────────┐             │
│         │   Unlock     │             │
│         └──────────────┘             │
│                                      │
│                                      │
└─────────────────────────────────────┘
```

Tapping "Unlock" calls `BiometricGate.unlock()`. The
Face ID / Touch ID prompt appears (the system prompt; not
the iOS app's UI). On success, `isLocked = false` and the
iOS app's normal UI re-renders.

The lock screen is implemented as a SwiftUI view in
`ios/FinchApp/Security/LockScreenView.swift`. The
`AdaptiveShell` (Phase 3) checks `BiometricGate.shared.isLocked`
and shows the lock screen instead of the normal tabs.

### 3.3 — App lifecycle integration

The lock state is evaluated at 3 lifecycle points:

```swift
@main
struct FinchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var gate = BiometricGate.shared

    var body: some Scene {
        WindowGroup {
            AdaptiveShell()
                .environment(gate)
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhase(newPhase)
                }
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            gate.recordBackground()
        case .active:
            Task { await gate.evaluateLockState() }
        case .inactive:
            break  // transient; do nothing
        @unknown default:
            break
        }
    }
}
```

`scenePhase` is iOS's standard lifecycle signal. The iOS
app records the background time on `.background`, then
re-evaluates the lock state on `.active` (the user
returns to the app).

The idle timer (for the "On idle" policy) is a
`Timer.scheduledTimer` that fires every 30 seconds and
calls `gate.evaluateLockState()`. The timer is started
on app launch and stopped on app background.

## §4. Sensitive-action gating

The user can require biometric re-auth for **sensitive
actions**:

- **Export .finch** (Phase 1.0's export — the user is
  moving their data off the device)
- **Delete all data** (a destructive action that wipes the
  local DB; the iOS app's "Settings › Database › Delete
  all" button)
- **Change base currency** (Phase 4's FX tools — re-rates
  historic entries; destructive)

Each sensitive action calls
`BiometricGate.authenticateForSensitiveAction(reason:)`
before dispatching the chokepoint:

```swift
// ios/FinchApp/FinchStore.swift (Phase 2 + Phase 6.3)
public func apply(action: String, args: [String: Any], sensitive: Bool = false) async throws {
    if sensitive {
        try await BiometricGate.shared.authenticateForSensitiveAction(
            reason: "Confirm: \(action)"
        )
    }
    try await Store.applyMutation(db, action: action, args: args)
    // ... existing post-write logic
}
```

The `sensitive: true` flag is set by the calling view
(e.g., the Export button sets it; the Add Transaction form
does not).

The action handler at the iOS UI level:

```swift
// ios/FinchApp/Export/ExportButton.swift
Button("Export .finch") {
    Task {
        do {
            // Phase 1.0's export is a direct Pack.export(from:to:)
            // call, NOT a chokepoint action. The export
            // sensitive-action gating is a thin wrapper
            // around the chokepoint, so the biometric check
            // happens before the export, not via
            // store.apply(action: "exportDbBytes", ...).
            try await biometricGate.authenticate(reason: "Export your finch data")
            let pack = try await Pack.export(from: store.db)
            // Show the share sheet
        } catch BiometricError.userCancelled {
            // User cancelled the biometric prompt
            // — no export
        } catch {
            // Other error — show alert
        }
    }
}
```

If the user cancels the biometric prompt, the action is
aborted and no error alert is shown (cancellation is a
normal user action).

## §5. Data protection at rest

The proposal uses
`NSFileProtectionCompleteUnlessOpen` (per the plan's
§10 resolved decision). The iOS app's local data
(`Application Support/finch.sqlite3` +
`Application Support/attachments/`) is written with this
protection class:

```swift
// ios/FinchApp/Security/FileProtection.swift
public func setFileProtection(at url: URL) throws {
    try (url as NSURL).setResourceValue(
        URLFileProtection.completeUnlessOpen,
        forKey: .fileProtectionKey
    )
}
```

`completeUnlessOpen` means:
- The file is unreadable when the device is locked
- The file is readable while the app is running
- The file is protected by the device passcode (and
  biometric, if enabled) when the device is locked

This is a system-level data protection; the iOS app
doesn't implement the encryption itself. The data is
encrypted by iOS using the device's hardware key.

The iOS app applies `setFileProtection` to:
- The live DB (`Application Support/finch.sqlite3`)
- The WAL file (`Application Support/finch.sqlite3-wal`)
- The attachments directory (recursively, every file
  inside)
- **NOT** the iCloud container's `Documents/finch/`
  directory — iCloud's encryption is Apple's responsibility
  (E2E with Advanced Data Protection), and setting
  `completeUnlessOpen` on the iCloud pack would break the
  iCloud daemon's ability to sync the file to other devices
  when the originating device is locked. iCloud's encryption
  also covers the data in transit
  and at rest by Apple's iCloud infrastructure)

## §6. Settings › Security section

The Settings tab gets a **Security** section:

```
┌─────────────────────────────────────┐
│  Security                            │
├─────────────────────────────────────┤
│  Biometric lock                      │
│  ( ) Off                            │
│  (•) On launch                      │
│  ( ) On background                  │
│  ( ) On idle                        │
│                                      │
│  Idle timeout (for "On background" / "On idle") │
│  5 minutes                       ▾   │
│                                      │
│  ☑ Require biometric for sensitive actions │
│                                      │
│  ────────────                        │
│  Data protection at rest            │
│  ✓ Protected (iOS file protection)   │
└─────────────────────────────────────┘
```

The 4 radio buttons control the policy; the dropdown sets
the timeout; the checkbox toggles the sensitive-action
gating. The "Data protection at rest" row is
informational (always ✓, since the protection is on by
default and the user can't disable it).

## §7. CI changes

The macos job from Phase 1.0's `IOS_MACOS_PHASE_1_DESIGN §9`
extends with:

- A **lock state test**: configure `BiometricSettings.policy
  = .onLaunch`; verify `isLocked = true` on app launch;
  call `BiometricGate.unlock()` (mocked to succeed);
  assert `isLocked = false`
- A **policy test**: configure `.onBackground`; record
  a background event 10 minutes ago; verify
  `isLocked = true`
- A **sensitive-action test**: configure
  `sensitiveActionsEnabled = true`; call
  `biometricGate.authenticate(reason: "Export...")`
  (the export-gated code path from §4.2); assert
  the biometric prompt was requested (mocked) and
  the export was dispatched
- A **user-cancel test**: configure biometric to
  fail-on-cancel; call `unlock()`; assert the error
  is `BiometricError.userCancelled` and `isLocked` is
  still `true`

The biometric tests use a **mock `LAContext`** that
captures the policy evaluation request without invoking
real biometric hardware.

## §8. Open questions

**Not blocking Phase 6.3 (decide later)**:

- **Passcode fallback**: the proposal uses biometric
  only. If the user has biometric disabled in iOS Settings,
  the `LAContext.evaluatePolicy(.deviceOwnerAuthentication,
  ...)` falls back to the device passcode. We don't
  implement our own passcode fallback; iOS handles it.
- **Biometric on Mac**: Mac's biometric is Touch ID
  (built-in keyboards). The proposal uses
  `LAContext.evaluatePolicy` which is cross-platform; the
  Touch ID prompt appears automatically on Mac.
- **Per-ledger sensitive actions**: the proposal uses
  global sensitive actions. Per-ledger gating (e.g.,
  "require biometric for the Business ledger but not
  Personal") is a future phase.
- **Failed-attempt cooldown**: iOS automatically locks
  out biometric after repeated failures (configurable
  in iOS Settings). We don't implement our own
  cooldown.
- **Biometric re-auth for Spotlight deep-links**: the
  proposal doesn't require biometric re-auth when a
  Spotlight result opens a specific Transaction Detail
  screen. The biometric lock is on app launch; if the
  app is unlocked, the Spotlight deep-link works without
  re-auth. (Alternative: require re-auth for every
  Spotlight deep-link. A future phase.)

**Specifically for the policy**:

- **"On background" vs "On idle"**: the proposal has both
  policies. The user research (not in scope for Phase 6.3)
  may favor one over the other. The default is "Off";
  the user can pick any of the 3 active policies.
- **Idle timeout range**: the proposal supports 1, 5, 15,
  30, 60 minutes. The 1-minute option may be too
  aggressive (the user is constantly prompted); the
  60-minute option may be too lax. The user can pick.

**Not blocking Phase 6.3 because they're Phase 6.4+ by design**:

- **App Intents / Siri** — Phase 6.4 (Siri can trigger
  sensitive actions like "Add a transaction"; the
  biometric prompt appears before the chokepoint dispatches)
- **Share Extension receipts** — Phase 6.5
- **Widgets / Live Activities / Watch** — Phase 7 (the
  widgets don't trigger sensitive actions; the Watch
  quick-add is gated by the iOS app's biometric, not the
  Watch's)
- **Row-level sync** — Phase 8

## §9. Out of scope (firm)

These are explicitly NOT in Phase 6.3:

- **No passcode fallback** — biometric only (iOS handles
  fallback to device passcode via `LAContext`)
- **No new tabs / write screens / power features** — the 6
  tabs + 7 write screens + 7 power features are unchanged
- **No new selectors** — the Phase 1.5 selectors are the
  full set
- **No new chokepoint actions** — the chokepoint is
  unchanged; biometric lock gates the UI
- **No remote wipe** — iOS's "Erase all content and settings"
  handles this
- **No biometric for widgets + Watch** — the widgets +
  Watch don't show financial data without a tap-through
  to the iOS app (which is gated by biometric)
- **No failed-attempt cooldown** — iOS's built-in
  cooldown
- **No per-ledger sensitive actions** — global gating
  only
- **No biometric re-auth for Spotlight deep-links** —
  the biometric lock is on app launch; Spotlight
  deep-links work without re-auth if the app is
  unlocked

## §10. Spec self-review

(Inline review at write time; not part of the published
spec.)

- **Placeholders**: none. Every section has concrete
  content. The 4 policies (§2), the `BiometricGate` API
  (§3.1), the lock screen UI (§3.2), the lifecycle
  integration (§3.3), the sensitive-action gating (§4),
  the file protection (§5), the Settings UI (§6) are
  all concrete.
- **Internal consistency**: §3's `BiometricGate` uses
  `LAContext.evaluatePolicy` (the standard iOS API).
  §4's sensitive-action gating hooks into
  `FinchStore.apply` from Phase 2. §5's
  `NSFileProtection.completeUnlessOpen` is the standard
  iOS data protection API. The `AdaptiveShell` is from
  Phase 3.
- **Scope**: focused on Phase 6.3 only. Phases 6.1, 6.2
  are referenced as separate specs (independently
  shipped). Phases 6.4-6.5 are referenced as separate
  specs. Phase 7+ are explicitly out of scope (§9). The
  estimated scope (1-2 weeks) reflects biometric being
  the second-smallest of the 5 sub-features.
- **Ambiguity**: §2's 4 policies are a concrete table.
  §3.1's `BiometricGate` has concrete API. §3.2's lock
  screen has a concrete layout. §4's sensitive-action
  gating has concrete code. §5's file protection has
  concrete iOS API usage. §6's Settings UI is concrete.
  §7 enumerates the CI test cases. §8 enumerates the
  open questions with proposed answers.
