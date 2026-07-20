# Haptic feedback + Settings toggle — design

**Date:** 2026-07-20
**Status:** approved (brainstormed with user)
**Scope:** iOS/macOS app only (`ios/`), UI-only. No engine, projection, or web changes.

## Problem

The app produces **no haptic feedback** anywhere on iPhone/iPad — there is no
`UIFeedbackGenerator`, `.sensoryFeedback`, or CoreHaptics usage in `FinchApp`
(the only haptic in the codebase is the Watch app's Digital Crown detent). Key
confirmations (a transaction saving, an error, a delete) have no tactile signal.
Add tasteful, "key-moments-only" haptics with a Settings toggle to disable them.

## Decision

A small central **`Haptics`** helper, called imperatively from the write
screens on three kinds of event, gated by an on-by-default Settings toggle.
Deliberately minimal — no haptics on ordinary taps/toggles/selections (avoids
the "buzzy finance app" annoyance).

## Architecture

### `FinchApp/Sources/FinchApp/Common/Haptics.swift`

An imperative helper wrapping `UINotificationFeedbackGenerator`, guarded
`#if os(iOS)` so it's a no-op on macOS (which has no `UINotificationFeedbackGenerator`).

```swift
import Foundation
#if os(iOS)
import UIKit
#endif

/// Central, opt-out haptic feedback for key confirmations. Imperative (fires
/// immediately) because these events save-then-dismiss — a SwiftUI
/// `.sensoryFeedback(trigger:)` change racing the dismissal is unreliable.
/// No-op on macOS. iOS also suppresses all haptics when the user turns off
/// System Haptics, so this toggle is an additional app-level control.
enum Haptics {
    static let enabledKey = "finch.haptics.enabled"

    /// Default ON; an unset key reads as enabled.
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func success() { fire(.success) }
    static func warning() { fire(.warning) }

    #if os(iOS)
    private static func fire(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
    #else
    private enum Kind { case success, warning }
    private static func fire(_ type: Kind) {}   // no-op on macOS
    #endif
}
```

**Why imperative / UIKit:** these fire on save-then-`dismiss()`; a declarative
`.sensoryFeedback` trigger can be torn down with the view before it plays.
`UINotificationFeedbackGenerator` fires synchronously. This is a justified
minimal UIKit touch (the SwiftUI-first rule's "when SwiftUI can't express it
well"), and the only new UIKit surface is one `import UIKit` in this file.

### The three fire points ("key moments")

- **`Haptics.success()`** — a successful save, immediately before `dismiss()`:
  - `AddTransactionSheet.save()` (the success `dismiss()` after the write)
  - `EditTransactionSheet.save()` and `saveTransfer()` (their success `dismiss()`)
  - `AdjustBalanceSheet.save()` (success `dismiss()`)
- **`Haptics.warning()`** — a save failed or a soft block:
  - the `catch { errorMessage = i18nMessage(error) }` paths in those same save
    methods
  - the **duplicate nudge** in `AddTransactionSheet.save()` (where
    `pendingDuplicate = m; return`)
- **`Haptics.warning()`** — a **destructive confirm** completes:
  - delete transaction (`EditTransactionSheet` delete-confirm action;
    `AccountDetailView` `store.deleteTransaction`)
  - delete account (`AccountDetailView` `.deleteAccount` apply)

  Fire on the **success** branch of each delete (after the delete call succeeds,
  before/with dismiss), not in its `catch` (which already gets the save-error
  warning rule).

### The setting

- **`@AppStorage("finch.haptics.enabled")`, default `true`**, a **"Haptic
  feedback"** `Toggle` in `SettingsAppearanceView`, **iOS-only** (`#if os(iOS)`
  — hidden on macOS), placed with the other interface toggles.
- Footer: *"Also respects your device's System Haptics setting."*
- The key string must match `Haptics.enabledKey` exactly.

## Non-goals (explicit)

- No haptics on ordinary taps, toggles, selections, swipes, pull-to-refresh, or
  tab switches (the user chose "key moments only").
- No selection/impact styles — only the `.success` / `.warning` notification
  types.
- No engine, projection, or web changes. No change to the Watch app.

## Testing

Haptics are hardware and **do not fire in the iOS Simulator**, so on-device is
the only real verification. Automated coverage:

- `xcodebuild` FinchApp (iOS Simulator) **and** FinchMac — both `BUILD SUCCEEDED`
  (proves the `#if os(iOS)` guard compiles on both).

**Manual checklist (PR body — requires a physical iPhone):**
1. Save an expense → a success tap.
2. Trigger a save error (e.g. amount 0) / the duplicate nudge → a warning tap.
3. Delete a transaction / an account → a warning tap.
4. Settings › Appearance → toggle **Haptic feedback** off → none of the above buzz.
5. Turning off iOS System Haptics also silences them (toggle on).
6. macOS build has no toggle and no haptics (no-op).
