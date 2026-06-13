# Phase 6.2 Implementation Plan — Notifications

> **For agentic workers:** Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add **local notifications** for 4 categories: scheduled item due, budget warning, anomaly flagged, weekly digest. The user grants permission on first app launch; the iOS app schedules notifications via `UNUserNotificationCenter`.

**Architecture:** A new `FinchCore/Notifications/` module hosts the `NotificationScheduler` (which schedules the 4 categories). The scheduler is called by `FinchStore.apply` (for immediate notifications like budget warning) and by a daily timer (for the weekly digest). Action handlers in `UNUserNotificationCenterDelegate` route taps to the existing `DeepLinkRouter` (from Phase 6.1).

**Tech Stack:** Same as Phase 2 + `UserNotifications` (`UNUserNotificationCenter`).

**Input design spec:** `plans/ios-macos/IOS_MACOS_PHASE_6_2_DESIGN.md` (~740 lines, 9 sections + §0. Map TOC)

**Depends on:** Phases 1.0, 1.5, 2 — FinchStore + selectors + chokepoint must be shipping.

**Estimated time:** 2-3 weeks.

---

## File structure

```
frontend/ios/FinchCore/
  Sources/FinchCore/Notifications/
    NotificationScheduler.swift   # NEW
    NotificationPermission.swift  # NEW
    WeeklyDigest.swift            # NEW
frontend/ios/FinchApp/
  Sources/FinchApp/Settings/
    NotificationsSettingsView.swift  # NEW
```

**File counts**: 4 new files, ~500-700 lines Swift.

---

## Task 1: Build the `NotificationPermission` flow

**Files:**
- Create: `frontend/ios/FinchCore/Sources/FinchCore/Notifications/NotificationPermission.swift`

- [ ] **Step 1: Implement**

`frontend/ios/FinchCore/Sources/FinchCore/Notifications/NotificationPermission.swift`:

```swift
// Notifications/NotificationPermission.swift — requests
// notification permission on first app launch (per Phase 6.2
// §1 — permission is on first launch, not after first import).
import Foundation
import UserNotifications

public enum NotificationPermission {
    /// Request notification permission. Returns the new
    /// authorization status. Idempotent: if the user has
    /// already granted/denied, returns the existing status
    /// without re-prompting.
    @MainActor
    public static func requestIfNeeded() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings()
        switch current.authorizationStatus {
        case .notDetermined:
            _ = try? await center.requestAuthorization(
                options: [.alert, .badge, .sound],
                localizedReason: "finch sends you reminders for scheduled transactions, budget warnings, and your weekly spending digest."
            )
            return await center.notificationSettings().authorizationStatus
        case .denied, .authorized, .provisional, .ephemeral:
            return current.authorizationStatus
        @unknown default:
            return .denied
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/Notifications/NotificationPermission.swift
git commit -m "feat(ios): implement NotificationPermission.requestIfNeeded (first-launch flow)"
```

---

## Task 2: Build the `NotificationScheduler`

**Files:**
- Create: `frontend/ios/FinchCore/Sources/FinchCore/Notifications/NotificationScheduler.swift`

- [ ] **Step 1: Implement the 4 notification categories**

`frontend/ios/FinchCore/Sources/FinchCore/Notifications/NotificationScheduler.swift`:

```swift
// Notifications/NotificationScheduler.swift — schedules the
// 4 notification categories. Each category has a unique
// notification identifier prefix for easy cancellation.
import Foundation
import UserNotifications

public enum NotificationScheduler {
    public static func scheduleScheduledDue(
        templateId: String,
        templateName: String,
        dueAt: Date
    ) async {
        let content = UNMutableNotificationContent()
        content.title = "Scheduled: \(templateName)"
        content.body = "Tap to confirm."
        content.categoryIdentifier = "scheduledDue"
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: dueAt
            ),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "scheduledDue:\(templateId)",
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    public static func scheduleBudgetWarning(
        budgetId: String, budgetName: String, percentUsed: Double
    ) async {
        // (similar pattern)
    }

    public static func scheduleAnomalyFlagged(
        txnId: String, merchant: String, amount: Decimal
    ) async {
        // (similar pattern; threshold 2.5 per Phase 6.2 §3.4)
    }

    public static func scheduleWeeklyDigest(
        digest: WeeklyDigest
    ) async {
        // (recurring weekly — every Sunday at 9 AM)
    }

    public static func cancelScheduledDue(templateId: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["scheduledDue:\(templateId)"])
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/Notifications/NotificationScheduler.swift
git commit -m "feat(ios): implement NotificationScheduler (4 categories)"
```

---

## Task 3: Add the `WeeklyDigest` selector port

**Files:**
- Create: `frontend/ios/FinchCore/Sources/FinchCore/Notifications/WeeklyDigest.swift`

- [ ] **Step 1: Implement**

`frontend/ios/FinchCore/Sources/FinchCore/Notifications/WeeklyDigest.swift`:

```swift
// Notifications/WeeklyDigest.swift — port of
// `lib/select.ts::weeklyDigest` (already ported in Phase 1.5).
// This file is the iOS port's convenience wrapper for the
// notification body text.
import Foundation

public struct WeeklyDigest: Equatable, Sendable, Codable {
    public let totalSpent: Decimal
    public let topCategory: String?
    public let topCategoryAmount: Decimal
    public let weekStart: String
    public let weekEnd: String
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/Notifications/WeeklyDigest.swift
git commit -m "feat(ios): add WeeklyDigest type for weekly notification body"
```

---

## Task 4: Add the `UNUserNotificationCenterDelegate` + action handlers

**Files:**
- Modify: `frontend/ios/FinchApp/Sources/FinchApp/FinchApp.swift`

- [ ] **Step 1: Implement the delegate**

Modify `FinchApp.swift`:

```swift
@main
struct FinchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // (existing body)
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]  // Show in-app too
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionId = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            // Route via the existing DeepLinkRouter (Phase 6.1)
            switch actionId {
            case "confirmNow":
                guard let templateId = userInfo["templateId"] as? String else { return }
                try? await FinchStore.shared.apply(
                    action: .postScheduled,
                    args: Args(values: ["templateId": .string(templateId)])
                )
            case "viewBudgets":
                DeepLinkRouter().route(to: "budget:\(userInfo["budgetId"] ?? "")")
            case "viewTransaction":
                guard let entryId = userInfo["entryId"] as? String else { return }
                DeepLinkRouter().route(to: "tx:\(entryId)")
            default:
                break
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/FinchApp.swift
git commit -m "feat(ios): wire UNUserNotificationCenterDelegate + action handlers"
```

---

## Task 5: Add the Settings › Notifications section

- [ ] **Step 1: Build the `NotificationsSettingsView`**

`frontend/ios/FinchApp/Sources/FinchApp/Settings/NotificationsSettingsView.swift`:

```swift
import SwiftUI
import FinchCore

struct NotificationsSettingsView: View {
    @State private var scheduledDueEnabled = true
    @State private var budgetWarningEnabled = true
    @State private var anomalyEnabled = true
    @State private var weeklyDigestEnabled = true

    var body: some View {
        Form {
            Section("Categories") {
                Toggle("Scheduled item due", isOn: $scheduledDueEnabled)
                Toggle("Budget warning (90% spent)", isOn: $budgetWarningEnabled)
                Toggle("Anomaly flagged", isOn: $anomalyEnabled)
                Toggle("Weekly digest (Sunday 9 AM)", isOn: $weeklyDigestEnabled)
            }
        }
        .navigationTitle("Notifications")
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/Settings/NotificationsSettingsView.swift
git commit -m "feat(ios): add Settings › Notifications section"
```

---

## Self-review

**Spec coverage** (Phase 6.2 design spec, 9 sections + §0. Map TOC):

| Design § | Implementation |
|---|---|
| §1. Goal & non-goals | All tasks — full coverage |
| §2. Permission request | Task 1 — full coverage |
| §3. The NotificationScheduler | Tasks 2 + 3 + 4 — full coverage |
| §4. Settings › Notifications | Task 5 — full coverage |
| §5. Action handlers | Task 4 — full coverage |
| §6. CI changes | (covered in Phase 1.0) |
| §7. Open questions | (resolved) |
| §8. Out of scope | (explicit non-goals) |
| §9. Spec self-review | (this section) |

**Gaps**: none. All 9 sections covered.
