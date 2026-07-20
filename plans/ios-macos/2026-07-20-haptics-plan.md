# Haptic feedback + Settings toggle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add tasteful "key-moments-only" haptics (save success, save error/duplicate, destructive delete) with an on-by-default Settings toggle.

**Architecture:** A central `Haptics` helper (`UINotificationFeedbackGenerator`, `#if os(iOS)` no-op on macOS) called imperatively from the write screens; an `@AppStorage` toggle in Settings › Appearance gates it.

**Tech Stack:** Swift / SwiftUI / UIKit (iOS-only, one file).

## Global Constraints

- **UI-only.** No engine, projection, or `frontend/` changes; no Watch changes.
- **`Haptics` is the only new UIKit surface** (one `import UIKit`, `#if os(iOS)`); macOS is a compile no-op.
- Toggle key string is **`"finch.haptics.enabled"`**, default **true**; it must match `Haptics.enabledKey` exactly.
- Only `.success` / `.warning` notification types — no selection/impact/taps.
- Design doc: `plans/ios-macos/2026-07-20-haptics-design.md`.

---

### Task 1: `Haptics` helper + Settings toggle

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Common/Haptics.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/SettingsAppearanceView.swift`

**Interfaces:**
- Produces: `Haptics.success()`, `Haptics.warning()`, `Haptics.enabledKey` (used by later steps).

- [ ] **Step 1: Create the helper**

Create `ios/FinchApp/Sources/FinchApp/Common/Haptics.swift`:

```swift
import Foundation
#if os(iOS)
import UIKit
#endif

/// Central, opt-out haptic feedback for key confirmations. Imperative (fires
/// immediately) because these events save-then-dismiss — a SwiftUI
/// `.sensoryFeedback(trigger:)` change racing the dismissal is unreliable.
/// No-op on macOS. iOS also suppresses all haptics when System Haptics is off,
/// so this toggle is an additional app-level control.
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

- [ ] **Step 2: Add the toggle to Settings › Appearance**

In `SettingsAppearanceView.swift`, add the `@AppStorage` next to the others (after line ~31):

```swift
    @AppStorage(Haptics.enabledKey) private var hapticsEnabled = true
```

And add an iOS-only section after the existing `Section("Accounts") { … }` block:

```swift
            #if os(iOS)
            Section {
                Toggle("Haptic feedback", isOn: $hapticsEnabled)
            } footer: {
                Text("A gentle tap on saves, errors, and deletes. Also respects your device's System Haptics setting.")
            }
            #endif
```

- [ ] **Step 3: Build both platforms**

Run from `ios/` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`:
- `xcodegen generate`
- iOS: `xcodebuild -project FinchApp.xcodeproj -scheme FinchApp -destination 'generic/platform=iOS Simulator' build` → `BUILD SUCCEEDED`
- macOS: `xcodebuild -project FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' build` → `BUILD SUCCEEDED` (proves the `#else` no-op compiles)

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Common/Haptics.swift \
        ios/FinchApp/Sources/FinchApp/Tabs/SettingsAppearanceView.swift
git commit -m "feat(ios): Haptics helper + Settings toggle (default on)"
```

---

### Task 2: Wire the three fire points into the write screens

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AdjustBalanceSheet.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift`

**Interfaces:**
- Consumes: `Haptics.success()` / `Haptics.warning()` (Task 1).

Rule: `Haptics.success()` immediately before a success `dismiss()`; `Haptics.warning()` as the first statement of the matching `catch`, at the duplicate nudge, and on the success branch of each delete.

- [ ] **Step 1: AddTransactionSheet — dup nudge, success, error**

Duplicate nudge — replace:
```swift
            pendingDuplicate = m
            return
```
with:
```swift
            Haptics.warning()
            pendingDuplicate = m
            return
```

Success + error — replace:
```swift
            dismiss()
        } catch {
            errorMessage = i18nMessage(error)   // localizes I18nError (incl. zh), like every other write screen
        }
```
with:
```swift
            Haptics.success()
            dismiss()
        } catch {
            Haptics.warning()
            errorMessage = i18nMessage(error)   // localizes I18nError (incl. zh), like every other write screen
        }
```

- [ ] **Step 2: EditTransactionSheet — save, saveTransfer, delete**

`save()` success + error — replace (8-space `} catch`):
```swift
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
```
with:
```swift
            Haptics.success()
            dismiss()
        } catch { Haptics.warning(); errorMessage = i18nMessage(error) }
    }
```

`saveTransfer()` success + error — replace (12-space `} catch`):
```swift
                dismiss()
            } catch { errorMessage = i18nMessage(error) }
        }
```
with:
```swift
                Haptics.success()
                dismiss()
            } catch { Haptics.warning(); errorMessage = i18nMessage(error) }
        }
```

Delete transaction — replace:
```swift
                                do { try store.deleteTransaction(txn.id); dismiss() }   // also unlinks receipt files
```
with:
```swift
                                do { try store.deleteTransaction(txn.id); Haptics.warning(); dismiss() }   // also unlinks receipt files
```

- [ ] **Step 3: AdjustBalanceSheet — success, error**

Replace:
```swift
            try store.apply(.adjustAccountBalance, Args(args))
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
```
with:
```swift
            try store.apply(.adjustAccountBalance, Args(args))
            Haptics.success()
            dismiss()
        } catch { Haptics.warning(); errorMessage = i18nMessage(error) }
```

- [ ] **Step 4: AccountDetailView — delete transaction + delete account**

Delete transaction — replace:
```swift
        do { try store.deleteTransaction(txn.id) } catch { errorMessage = i18nMessage(error) }
```
with:
```swift
        do { try store.deleteTransaction(txn.id); Haptics.warning() } catch { errorMessage = i18nMessage(error) }
```

Delete account — replace:
```swift
        do { try store.apply(.deleteAccount, Args(["id": .string(a.id)])) }
        catch { errorMessage = i18nMessage(error) }   // engine rejects if it has transactions
```
with:
```swift
        do { try store.apply(.deleteAccount, Args(["id": .string(a.id)])); Haptics.warning() }
        catch { errorMessage = i18nMessage(error) }   // engine rejects if it has transactions
```

- [ ] **Step 5: Build both platforms**

Same commands as Task 1 Step 3 → both `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/AdjustBalanceSheet.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift
git commit -m "feat(ios): fire haptics on save success / error / duplicate / delete"
```

---

## Manual verification (for the PR body — needs a physical iPhone; the Simulator produces no haptics)

1. Save an expense → success tap. 2. Amount 0 / duplicate nudge → warning tap. 3. Delete a transaction / account → warning tap. 4. Settings › Appearance → **Haptic feedback** off → silent. 5. iOS System Haptics off → also silent. 6. macOS builds, no toggle, no-op.

## Self-Review

- **Spec coverage:** helper + toggle (Task 1); all three fire points across the four write screens (Task 2); default-on key `finch.haptics.enabled` = `Haptics.enabledKey`; iOS-only toggle; `.success`/`.warning` only; UI-only (Global Constraints). ✓
- **Type consistency:** `Haptics.success()` / `Haptics.warning()` / `Haptics.enabledKey` used exactly as produced by Task 1. ✓
- **Placeholders:** none — every edit shows concrete before/after. ✓
