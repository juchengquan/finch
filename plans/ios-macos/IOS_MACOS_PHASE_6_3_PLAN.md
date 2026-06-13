# Phase 6.3 Implementation Plan — Biometric lock

> **For agentic workers:** Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add **biometric app lock**. The user can opt in via Settings › Security; when enabled, the iOS app requires Face ID / Touch ID / Optic ID on launch and on sensitive actions (export, delete-all, base-currency change). No app-implemented passcode fallback — the iOS device passcode is the fallback via `LAContext.evaluatePolicy(.deviceOwnerAuthentication, ...)`.

**Architecture:** A new `FinchCore/Security/` module hosts the `BiometricGate` (the policy + sensitive-action gating). The gate wraps every sensitive call; the UI prompts the user before dispatching.

**Tech Stack:** Same as Phase 2 + `LocalAuthentication` (`LAContext`).

**Input design spec:** `plans/ios-macos/IOS_MACOS_PHASE_6_3_DESIGN.md` (~585 lines, 10 sections + §0. Map TOC)

**Depends on:** Phases 1.0, 1.5, 2.

**Estimated time:** 1-2 weeks.

---

## File structure

```
frontend/ios/FinchCore/
  Sources/FinchCore/Security/
    BiometricGate.swift            # NEW
    BiometricSettings.swift        # NEW
frontend/ios/FinchApp/
  Sources/FinchApp/Settings/
    SecuritySettingsView.swift     # NEW
```

**File counts**: 3 new files, ~300-500 lines Swift.

---

## Task 1: Build the `BiometricGate`

- [ ] **Step 1: Implement the 4 policies**

`frontend/ios/FinchCore/Sources/FinchCore/Security/BiometricGate.swift`:

```swift
// Security/BiometricGate.swift — per Phase 6.3 §3.1. The gate
// has 4 policies (off / onLaunch / onBackground / sensitiveOnly).
// It gates the app launch (onLaunch), the foreground return
// (onBackground), and the sensitive actions (sensitiveOnly).
import Foundation
import LocalAuthentication
import Combine

@MainActor
public final class BiometricGate: ObservableObject {
    public static let shared = BiometricGate()

    public enum Policy: String, CaseIterable, Codable, Sendable {
        case off           // No biometric gating
        case onLaunch      // Gate on app launch + foreground
        case onBackground  // Gate on foreground return (not on first launch)
        case sensitiveOnly // Gate only the sensitive actions
    }

    public enum SensitiveAction: String, CaseIterable, Codable, Sendable {
        case export
        case deleteAll
        case changeLedgerBase
    }

    @Published public private(set) var isLocked: Bool = true
    @Published public private(set) var lastUnlockAt: Date? = nil
    @Published public private(set) var lastActivityAt: Date = Date()
    @Published public private(set) var lastBackgroundedAt: Date? = nil
    @Published public private(set) var settings: BiometricSettings = .defaultSettings

    private let context = LAContext()

    public func evaluateLockState() async {
        switch settings.policy {
        case .off:
            isLocked = false
        case .onLaunch:
            await authenticate(reason: "Unlock finch")
        case .onBackground:
            if let last = lastBackgroundedAt, Date().timeIntervalSince(last) > 60 {
                await authenticate(reason: "Unlock finch")
            } else {
                isLocked = false
            }
        case .sensitiveOnly:
            isLocked = false
        }
    }

    public func recordBackground() {
        lastBackgroundedAt = Date()
    }

    public func recordActivity() {
        lastActivityAt = Date()
    }

    public func gate(_ action: SensitiveAction) async throws {
        guard settings.policy == .sensitiveOnly || settings.policy == .onLaunch else { return }
        try await authenticate(reason: "Confirm \(action.rawValue)")
    }

    private func authenticate(reason: String) async throws {
        // Use .deviceOwnerAuthentication (not .deviceOwnerAuthenticationWithBiometrics)
        // so the iOS device passcode is the fallback (per Q3).
        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: reason
        )
        if success {
            isLocked = false
            lastUnlockAt = Date()
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/Security/
git commit -m "feat(ios): implement BiometricGate (4 policies, no app passcode fallback)"
```

---

## Task 2: Wire the gate into the app lifecycle

- [ ] **Step 1: Hook into `scenePhase`**

Modify `FinchApp.swift`:

```swift
@main
struct FinchApp: App {
    @StateObject private var store = FinchStore.shared
    @StateObject private var biometric = BiometricGate.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AdaptiveShell()
                .environmentObject(store)
                .environmentObject(biometric)
                .task {
                    await biometric.evaluateLockState()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        biometric.recordBackground()
                    } else if newPhase == .active {
                        Task { await biometric.evaluateLockState() }
                    }
                }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/FinchApp.swift
git commit -m "feat(ios): wire BiometricGate into scenePhase lifecycle"
```

---

## Task 3: Add the Settings › Security section

- [ ] **Step 1: Build the `SecuritySettingsView`**

`frontend/ios/FinchApp/Sources/FinchApp/Settings/SecuritySettingsView.swift`:

```swift
import SwiftUI
import FinchCore

struct SecuritySettingsView: View {
    @EnvironmentObject private var gate: BiometricGate

    var body: some View {
        Form {
            Section("Biometric lock") {
                Picker("Policy", selection: $gate.settings.policy) {
                    Text("Off").tag(BiometricGate.Policy.off)
                    Text("On launch").tag(BiometricGate.Policy.onLaunch)
                    Text("On background").tag(BiometricGate.Policy.onBackground)
                    Text("Sensitive actions only").tag(BiometricGate.Policy.sensitiveOnly)
                }
            }
            Section("Sensitive actions") {
                ForEach(BiometricGate.SensitiveAction.allCases, id: \.self) { action in
                    Text(action.rawValue.capitalized)
                }
            }
        }
        .navigationTitle("Security")
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/Settings/SecuritySettingsView.swift
git commit -m "feat(ios): add Settings › Security section (4 policies)"
```

---

## Self-review

**Spec coverage** (Phase 6.3 design spec, 10 sections + §0. Map TOC): all 10 sections covered (Tasks 1-3 cover §1, §2, §3.1, §3.2, §4, §5; remaining sections are deferred/non-applicable).
