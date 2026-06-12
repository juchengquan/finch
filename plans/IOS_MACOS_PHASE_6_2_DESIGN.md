# finch for iOS & macOS — Phase 6.2 Implementation Design (Notifications)

> **Status**: design spec — not yet an implementation plan. Once
> approved, this becomes the input to `writing-plans` to produce a
> step-by-step implementation plan for Phase 6.2.
>
> Companion documents:
>
> - `plans/IOS_MACOS_PLAN.md` — direction brief
> - `plans/IOS_MACOS_PHASE_1_DESIGN.md` through `IOS_MACOS_PHASE_5_DESIGN.md` —
>   Phases 1.0 through 5 full designs
> - `plans/IOS_MACOS_PHASE_6_1_DESIGN.md` — Phase 6.1 (Spotlight)
> - `plans/IOS_MACOS_PHASE_7_DESIGN.md` — Phase 7 (widgets + Watch)
> - `plans/IOS_MACOS_ROADMAP.md` — 8-phase arc
> - `plans/IOS_MACOS_PHASE_6_2_DESIGN.md` (this file) — Phase 6.2
>
> Phase 6 is decomposed into 5 sub-specs (6.1-6.5). This is
> 6.2: local notifications via `UNUserNotificationCenter`.
> Phase 6.1 (Spotlight) is independently shipped. Phases
> 6.3-6.5 ship in any order.
>
> _Audience: the engineers who will build the iOS app. Assumes
> Phases 1.0-5 are complete._

## §1. Goal & non-goals

**Goal** — Schedule **local notifications** for 4 categories
of events:

1. **Scheduled item due** — when a scheduled template's
   `dueDate` is within the next hour, fire a notification
   with a "Confirm now" action button
2. **Budget over threshold** — when a budget's `spent /
   limit` exceeds its `warning_pct` (default 90%), fire a
   notification with a "View budgets" action button
3. **Anomaly flagged** — when a recent transaction has
   `anomalyScore` > 2.5 (the web's `anomalyScore` threshold
   in `lib/select.ts`), fire
   a notification with a "View transaction" action button
4. **Weekly digest** — every Sunday morning at the user's
   configured time (default 9 AM), fire a notification
   summarizing the week's spending (the `weeklyDigest`
   selector from Phase 1.5)

**All notifications are LOCAL** (no push notifications; per
the plan's §10 "no data collected" privacy stance). The
notification **content is generated at schedule time, not
at fire time** (avoids running the chokepoint in a
background context).

**Non-goals (firm)**:

- **No push notifications** — the plan's §10 is explicit:
  no server-side push. Local notifications only.
- **No new tabs / write screens / power features** — the 6
  tabs + 6 write screens + 7 power features are unchanged.
  Phase 6.2 adds a **notification surface** that the user
  sees in the iOS Notification Center.
- **No new selectors** — the Phase 1.5 selectors are the
  full set. The notification content uses
  `weeklyDigest` (Phase 1.5) and the chokepoint's
  post-write data.
- **No new chokepoint actions** — the chokepoint is
  unchanged. Phase 6.2 hooks into the existing
  `FinchStore.apply` (Phase 2) to schedule notifications
  on writes.
- **No notification customization UI** — the 4
  notification categories are user-toggleable (on/off in
  Settings) but not deeply configurable. Threshold
  tuning (e.g., "alert me at 80% not 90%") is a future
  phase.
- **No per-transaction notifications** — only the 4
  categories above. (Per-transaction alerts would
  overwhelm the user.)
- **No iOS Lock Screen / banner UI changes** — the standard
  iOS notification UI is used.
- **No Critical Alerts** (the special iOS entitlement for
  high-priority notifications that bypass Do Not Disturb
  and silent mode) — Phase 6.2 doesn't use them.
- **No per-ledger notification preferences** — the
  notification settings are global. Per-ledger
  preferences are a future phase.

**Estimated scope**: ~600-800 lines Swift (the
`NotificationScheduler` + the 4 notification types + the
permission request + the action handlers) + ~200 lines
SwiftUI (the Settings › Notifications section) + ~300
lines tests. **2-3 weeks of full-time work** for a small
team.

## §2. Permission request

iOS requires explicit user permission for local
notifications. **The iOS app requests permission on first
app launch** (the standard iOS pattern; predictable moment
for the user). The request is the standard iOS prompt; the
user can grant or decline.

### 2.1 — The permission request

```swift
// ios/FinchApp/Notifications/NotificationPermission.swift
public final class NotificationPermission {
    public static func requestIfNeeded() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings()
        switch current.authorizationStatus {
        case .notDetermined:
            // First time — request permission.
            // requestAuthorization returns Bool, so re-fetch
            // notificationSettings() to get the new status.
            _ = try? await center.requestAuthorization(
                options: [.alert, .badge, .sound],
                localizedReason: "finch sends you reminders for scheduled transactions, budget warnings, and your weekly spending digest."
            )
            return await center.notificationSettings().authorizationStatus
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return current.authorizationStatus
        @unknown default:
            return .denied
        }
    }
}
```

The permission is requested **on first app launch** (the
standard iOS pattern; the user sees the prompt predictably).
If the user declines, the Settings › Notifications section
has a "Request permission" button (which deep-links to
`UIApplication.openSettingsURLString`) for users who want
to retry after fixing iOS Settings.

No `Info.plist` key is required for `UNUserNotificationCenter` —
the system uses the `localizedReason:` argument passed to
`center.requestAuthorization(options:)` for the permission
prompt's body text (and there's no legacy
`NSUserNotificationsUsageDescription` key for the modern
`UNUserNotificationCenter` API on iOS 17+).

### 2.2 — The 4 notification categories

Each notification has a **`UNNotificationCategory`** that
defines its action buttons. The categories are registered
on app launch:

```swift
// ios/FinchApp/Notifications/NotificationCategories.swift
public final class NotificationCategories {
    public static func register() {
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([
            // 1. Scheduled item due
            UNNotificationCategory(
                identifier: "scheduledDue",
                actions: [
                    UNNotificationAction(
                        identifier: "confirmNow",
                        title: "Confirm now",
                        options: [.foreground]  // opens the app
                    ),
                    UNNotificationAction(
                        identifier: "snooze1h",
                        title: "Snooze 1 hour",
                        options: []
                    )
                ],
                intentIdentifiers: [],
                options: []
            ),
            // 2. Budget over threshold
            UNNotificationCategory(
                identifier: "budgetWarning",
                actions: [
                    UNNotificationAction(
                        identifier: "viewBudgets",
                        title: "View budgets",
                        options: [.foreground]
                    )
                ],
                intentIdentifiers: [],
                options: []
            ),
            // 3. Anomaly flagged
            UNNotificationCategory(
                identifier: "anomalyFlagged",
                actions: [
                    UNNotificationAction(
                        identifier: "viewTransaction",
                        title: "View",
                        options: [.foreground]
                    )
                ],
                intentIdentifiers: [],
                options: []
            ),
            // 4. Weekly digest
            UNNotificationCategory(
                identifier: "weeklyDigest",
                actions: [
                    UNNotificationAction(
                        identifier: "openActivity",
                        title: "Open Activity",
                        options: [.foreground]
                    )
                ],
                intentIdentifiers: [],
                options: []
            )
        ])
    }
}
```

Each category has at least one action; the action handler
is in §5.

## §3. The `NotificationScheduler`

The `NotificationScheduler` is the iOS app's central
notification-scheduling service. It hooks into the existing
`FinchStore.apply` (Phase 2) to schedule notifications on
writes.

### 3.1 — The scheduler's data model

```swift
// ios/FinchApp/Notifications/NotificationScheduler.swift
@MainActor
public final class NotificationScheduler {
    public static let shared = NotificationScheduler()

    /// Called on app launch + foreground (in the scenePhase
    /// handler that Phase 6.3 already has). Re-schedules the
    /// weekly digest so the body content reflects the
    /// latest digest (captured at schedule time by
    /// UNUserNotificationCenter; the body would otherwise
    /// be stale once a `repeats: true` digest is scheduled).
    public func evaluateOnLaunch(currentState: FinchStore) async {
        await rescheduleAll(newState: currentState)
    }

    private let center = UNUserNotificationCenter.current()
    private var enabledCategories: Set<NotificationCategory> = []

    public init() {
        // Read the user's enabled-category preferences from
        // app_state (key: "notification_enabled_categories")
        self.enabledCategories = loadEnabledCategories()
    }

    /// Called by FinchStore.apply after every successful write.
    public func onWrite(action: String, args: [String: Any], newState: FinchStore) async {
        // 1. Scheduled item due: re-schedule notifications for
        //    scheduled templates that will be due in the next
        //    24 hours.
        // 2. Budget over threshold: re-evaluate the affected
        //    budget's progress; if over warning_pct, schedule
        //    a notification (with a 1-hour dedup).
        // 3. Anomaly flagged: re-evaluate recent transactions
        //    (last 24h) with high anomalyScore; schedule
        //    notifications (with a 1-hour dedup).
        await rescheduleAll(newState: newState)
    }

    public func rescheduleAll(newState: FinchStore) async {
        await scheduleScheduledDueNotifications(newState: newState)
        await scheduleBudgetWarningNotifications(newState: newState)
        await scheduleAnomalyNotifications(newState: newState)
        await scheduleWeeklyDigestNotification()
    }

    // ... 4 private functions, one per category
}

public enum NotificationCategory: String, Codable, CaseIterable {
    case scheduledDue
    case budgetWarning
    case anomalyFlagged
    case weeklyDigest
}
```

### 3.2 — Scheduled item due

For each scheduled template that will be due in the next
24 hours, schedule a notification at the template's
`dueDate`:

```swift
private func scheduleScheduledDueNotifications(newState: FinchStore) async {
    guard enabledCategories.contains(.scheduledDue) else { return }
    let upcoming = newState.scheduled.filter { $0.dueDate <= Date().addingTimeInterval(24 * 3600) }
    for template in upcoming {
        let content = UNMutableNotificationContent()
        content.title = "Coming up: \(template.name)"
        content.body = "$\(template.amount) due \(formatRelative(template.dueDate))"
        content.categoryIdentifier = "scheduledDue"
        content.userInfo = ["templateId": template.id, "entryId": nil]
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: template.dueDate),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "scheduled-\(template.id)",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
}
```

Each scheduled template gets **one notification** with a
unique identifier (`scheduled-<template_id>`). The
notification is scheduled at the template's `dueDate`; it
fires once.

### 3.3 — Budget over threshold

After every write that affects a budget's progress, re-
evaluate the budget's `spent / limit` against its
`warning_pct`. If over the threshold and no notification has
fired in the last hour, schedule one:

```swift
private func scheduleBudgetWarningNotifications(newState: FinchStore) async {
    guard enabledCategories.contains(.budgetWarning) else { return }
    for budget in newState.budgets {
        let progress = try? Selectors.budgetProgress(budget, txns: newState.txns, accounts: newState.accounts, ...)
        guard let progress = progress else { continue }
        let pct = progress.spent / progress.limit
        guard pct >= budget.warningPct else { continue }

        let content = UNMutableNotificationContent()
        content.title = "Budget: \(budget.name)"
        content.body = "\(Int(pct * 100))% used ($\(progress.spent) / $\(progress.limit))"
        content.categoryIdentifier = "budgetWarning"
        content.userInfo = ["budgetId": budget.id]
        content.sound = .default

        // Fire 1 second after scheduling (immediate notification;
        // the user is in the app, the notification shows in the
        // banner; the user can tap to view)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "budget-\(budget.id)",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
        // The "add" call replaces an existing notification with
        // the same identifier; no dedup needed beyond this.
    }
}
```

The unique identifier `budget-<budget_id>` ensures that
re-scheduling replaces the existing notification (no
duplicate banners if the user opens the app multiple
times).

### 3.4 — Anomaly flagged

For each transaction in the last 24 hours with
`anomalyScore > 2.5` (the web's `anomalyScore` threshold
in `lib/select.ts`), schedule a notification:

```swift
private func scheduleAnomalyNotifications(newState: FinchStore) async {
    guard enabledCategories.contains(.anomalyFlagged) else { return }
    let recent = newState.txns.filter { $0.date >= ISO8601DateFormatter().string(from: Date().addingTimeInterval(-24 * 3600)) }
    for tx in recent {
        let score = try? Selectors.anomalyScore(tx, stats: merchantStats(newState.txns))
        guard let score = score, abs(score) > 2.5 else { continue }

        let content = UNMutableNotificationContent()
        content.title = "Unusual: \(tx.merchant)"
        content.body = "$\(tx.amount) on \(formatDate(tx.date))"
        content.categoryIdentifier = "anomalyFlagged"
        content.userInfo = ["entryId": tx.id]
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "anomaly-\(tx.id)",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
}
```

The unique identifier `anomaly-<entry_id>` ensures no
duplicate banners for the same transaction.

### 3.5 — Weekly digest

The weekly digest notification is scheduled **once per
week** (every Sunday at the user's configured time,
default 9 AM). The content is generated at schedule time
using the `weeklyDigest` selector from Phase 1.5:

```swift
private func scheduleWeeklyDigestNotification() async {
    guard enabledCategories.contains(.weeklyDigest) else { return }

    // The notification is scheduled 7 days from now, repeating weekly.
    // The content is generated NOW (at schedule time) — but since the
    // content is "next week's digest", we need to RE-schedule it every
    // week.
    //
    // Implementation: schedule the next digest for next Sunday; the
    // notification fires; the user opens the app; FinchStore.apply
    // (or app foreground) re-schedules the next digest for the
    // following Sunday.

    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 1  // Pin Sunday-first (locale-independent)
    let now = Date()
    let nextSunday = calendar.nextDate(
        after: now,
        matching: DateComponents(hour: 9, weekday: 1),  // Sunday at 9 AM
        matchingPolicy: .nextTime
    ) ?? now.addingTimeInterval(7 * 24 * 3600)

    let store = FinchStore.shared
    let digest = try? Selectors.weeklyDigest(txns: store.txns, ledgerId: store.activeLedgerId, anchor: ISO8601DateFormatter().string(from: nextSunday))

    let content = UNMutableNotificationContent()
    content.title = "Your week: $\(digest?.totalSpent ?? 0)"
    content.body = digest.map {
        let cat = $0.topCategory ?? "(none)"
        return "Top category: \(cat) ($\($0.topCategoryAmount))"
    } ?? "Open finch to see your weekly digest"
    content.categoryIdentifier = "weeklyDigest"
    content.sound = .default
    content.userInfo = ["type": "weeklyDigest"]

    let trigger = UNCalendarNotificationTrigger(
        dateMatching: DateComponents(hour: 9, weekday: 1),
        repeats: true
    )
    let request = UNNotificationRequest(
        identifier: "weekly-digest",
        content: content,
        trigger: trigger
    )
    try? await center.add(request)
}
```

The weekly digest is **the one notification that uses
`.repeats: true`** (the user wants it every Sunday at 9
AM, not just once). The content is generated once and
reused; the content reflects the digest at the time of
scheduling. If the user opens the app between digests, the
content is updated on the next scheduling cycle.

The trade-off: the digest content shown when the
notification fires is the **content at scheduling time**,
not the content at the time the notification is delivered.
If the user's spending changes between scheduling and
delivery (e.g., they log a transaction on Sunday afternoon
and the digest fires Sunday at 9 AM with stale content),
the content is slightly stale. This is an acceptable
trade-off (the user can open the app for fresh data; the
notification is a "reminder to check in" rather than a
real-time digest).

A more sophisticated approach would re-schedule the
weekly digest **at fire time** (a background fetch or a
silent push). Per the plan's §10, push notifications are
out of scope, so the at-schedule-time content is the
proposal.

## §4. Settings › Notifications section

The Settings tab (Phase 1.0's settings screen) gets a
**Notifications** section:

```
┌─────────────────────────────────────┐
│  Notifications                       │
├─────────────────────────────────────┤
│  Status: ✓ Permission granted        │
│                                      │
│  ☑ Scheduled item due                │
│  ☑ Budget over threshold            │
│  ☑ Anomaly flagged                   │
│  ☑ Weekly digest (Sundays at 9 AM)  │
│                                      │
│  [Open System Settings]              │
└─────────────────────────────────────┘
```

The 4 toggles control the `NotificationCategory` set
(§3.1). The "Open System Settings" button deep-links to
`UIApplication.openSettingsURLString` for users who want
to manage notification settings at the iOS level.

## §5. Action handlers

When the user taps a notification's action button, iOS
launches the iOS app (with the `foreground` option) and
delivers the action to `UNUserNotificationCenterDelegate`.
The `FinchApp` scene receives the action and routes to
the right screen.

### 5.1 — The `FinchApp` notification handler

```swift
@main
struct FinchApp: App {
    @State private var store = FinchStore.shared
    @State private var router = DeepLinkRouter()

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            AdaptiveShell()
                .environment(store)
                .environment(router)
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    handleSpotlightTap(activity)
                }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionId = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        handleNotificationAction(actionId: actionId, userInfo: userInfo)
        completionHandler()
    }

    private func handleNotificationAction(actionId: String, userInfo: [AnyHashable: Any]) {
        switch actionId {
        case "confirmNow":
            // Scheduled item due: dispatch the chokepoint
            guard let templateId = userInfo["templateId"] as? String else { return }
            Task { @MainActor in
                try? await store.apply(action: "postScheduled", args: ["id": templateId])
            }
        case "snooze1h":
            // Reschedule the notification for 1 hour from now
            guard let templateId = userInfo["templateId"] as? String else { return }
            Task { @MainActor in
                await NotificationScheduler.shared.snoozeScheduledDue(templateId: templateId, hours: 1)
            }
        case "viewBudgets":
            // Deep-link to the Budgets tab
            router.route(to: "budget:\(userInfo["budgetId"] ?? "")")
        case "viewTransaction":
            // Deep-link to the Transaction Detail screen
            guard let entryId = userInfo["entryId"] as? String else { return }
            router.route(to: "tx:\(entryId)")
        case "openActivity":
            // Deep-link to the Activity tab
            router.route(to: "activity")
        default:
            // Tapping the notification body (no specific action)
            // — switch to the corresponding tab
            if let entryId = userInfo["entryId"] as? String {
                router.route(to: "tx:\(entryId)")
            } else if let budgetId = userInfo["budgetId"] as? String {
                router.route(to: "budget:\(budgetId)")
            } else {
                router.route(to: "activity")
            }
        }
    }
}
```

Each action dispatches the right behavior:
- **Confirm now** → the chokepoint (Phase 2's
  `postScheduled` action posts the entry)
- **Snooze 1h** → reschedule the notification for 1
  hour from now
- **View budgets / View transaction / Open Activity** →
  the deep-link router (Phase 6.1's `DeepLinkRouter`)
- **Default (tap body)** → similar to the action, but
  without the specific intent

The "Confirm now" action is the only one that writes
through the chokepoint. The deep-link actions are
read-side.

## §6. CI changes

The macos job from Phase 1.0's `IOS_MACOS_PHASE_1_DESIGN §9`
extends with:

- A **scheduling test**: build a DB with a scheduled template
  due in 1 hour; call `NotificationScheduler.onWrite`;
  assert the notification is scheduled with the right
  trigger time
- A **budget warning test**: write enough transactions to
  push a budget past 90%; assert the notification is
  scheduled
- A **dedup test**: write the same budget-warning event
  twice; assert only one notification is scheduled
  (the second `add` replaces the first, same identifier)
- A **weekly digest test**: schedule the weekly digest;
  assert it's scheduled for the next Sunday at 9 AM
- An **action handler test**: simulate a
  `UNNotificationResponse` with `actionId: "confirmNow"`;
  assert the chokepoint's `postScheduled` was dispatched

The notification tests use a **mock `UNUserNotificationCenter`**
that captures the scheduled requests without firing real
notifications.

## §7. Open questions

**Not blocking Phase 6.2 (decide later)**:

- **Threshold tuning**: the proposal uses the defaults
  (90% for budget warning, 2.5 for anomaly, 1 hour for
  scheduled due). User-configurable thresholds are a
  future phase.
- **Per-ledger notification preferences**: the proposal
  uses global preferences. Per-ledger preferences (e.g.,
  "alert me for the Personal ledger but not Business") is
  a future phase.
- **Notification content staleness**: the weekly digest
  content is generated at schedule time (not at fire time).
  This is an acceptable trade-off; a more sophisticated
  approach (background fetch + at-fire-time content) is
  out of scope.
- **Critical Alerts**: the proposal doesn't use Critical
  Alerts (which require an Apple-granted entitlement). If
  the user wants high-priority notifications that bypass
  Do Not Disturb, that's a separate Apple approval
  process.
- **Notification grouping**: iOS 26 supports notification
  grouping (multiple notifications collapsed into one).
  The proposal doesn't group; the user sees each
  notification separately. A future enhancement could
  group budget warnings by ledger, or anomaly
  notifications by category.

**Specifically for the scheduling**:

- **Schedule at write time vs schedule at app launch**:
  the proposal schedules on every write (so the
  notifications are always up-to-date even if the app
  isn't launched). The trade-off: scheduling is a small
  per-write cost (~10ms for the budget warning check).
  The cost is acceptable.
- **App launch re-schedule**: the proposal also
  re-schedules on app launch (to catch any notifications
  that were dropped while the app was uninstalled /
  reinstalled). The unique identifiers ensure no
  duplicates.

**Not blocking Phase 6.2 because they're Phase 6.3+ by design**:

- **Biometric lock** — Phase 6.3 (notifications can
  contain sensitive financial data; the biometric lock
  gates access to the app's screens)
- **App Intents / Siri** — Phase 6.4
- **Share Extension receipts** — Phase 6.5
- **Widgets / Live Activities / Watch** — Phase 7
- **Row-level sync** — Phase 8

## §8. Out of scope (firm)

These are explicitly NOT in Phase 6.2:

- **No push notifications** — local notifications only
  (per the plan's §10)
- **No new tabs / write screens / power features** — the 6
  tabs + 6 write screens + 7 power features are unchanged
- **No new selectors** — the Phase 1.5 selectors are the
  full set (the weekly digest uses `weeklyDigest` from
  Phase 1.5)
- **No new chokepoint actions** — the chokepoint is
  unchanged; the "Confirm now" action dispatches the
  existing `postScheduled` action
- **No notification customization UI** — the 4 categories
  are user-toggleable (on/off) but not deeply configurable
- **No per-transaction notifications** — only the 4
  categories
- **No iOS Lock Screen / banner UI changes** — standard
  iOS notification UI
- **No Critical Alerts** (the special iOS entitlement)
- **No per-ledger notification preferences**
- **No notification grouping** (iOS 26's notification
  grouping)
- **No background-fetched at-fire-time content** (the
  weekly digest content is generated at schedule time)
- **No scheduled template snooze UI** — the "Snooze 1h"
  action is the only snooze; UI for snooze-from-X is a
  future phase

## §9. Spec self-review

(Inline review at write time; not part of the published
spec.)

- **Placeholders**: none. Every section has concrete
  content. The 4 notification categories (§3.2-§3.5) each
  have a code sketch. The Settings UI (§4) is concrete. The
  action handlers (§5.1) are concrete.
- **Internal consistency**: §3.1's `NotificationScheduler`
  uses `Selectors.budgetProgress` (Phase 1.5) and
  `Selectors.anomalyScore` (Phase 1.0/1.5) and
  `Selectors.weeklyDigest` (Phase 1.5). §5.1's
  `confirmNow` action dispatches `postScheduled` (Phase 2).
  The `DeepLinkRouter` is from Phase 6.1.
- **Scope**: focused on Phase 6.2 only. Phases 6.1, 6.3-6.5
  are referenced as separate specs. Phase 7+ are
  explicitly out of scope (§8). The estimated scope
  (2-3 weeks) reflects the 4 notification categories.
- **Ambiguity**: §2's permission request is concrete (the
  `UNUserNotificationCenter` API). §3's 4 notification
  types have concrete code sketches. §4's Settings UI is
  concrete. §5's action handlers are concrete. §6
  enumerates the CI test cases. §7 enumerates the open
  questions with proposed answers.
