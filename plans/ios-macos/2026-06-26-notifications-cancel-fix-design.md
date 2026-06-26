# Notifications end-to-end check + cancel-on-disable fix

**Date:** 2026-06-26
**Status:** Design approved, pending implementation
**Scope:** Verify the local-notification chain end-to-end on the simulator, and fix the one real bug found (disabling a kind / a no-longer-relevant alert doesn't cancel already-scheduled notifications). Small App-layer change + test + sim verification + doc note.

## Audit summary

The subsystem is **wired and mostly functional**, not a stub:
- Permission requested at launch (`FinchApp.swift:65` → `requestPermissionIfNeeded`); delegate set → foreground banners shown.
- `NotificationPlanner.plan(...)` builds notifications for 4 kinds (budgetWarning, scheduledDue, anomaly, weeklyDigest) from store state + enabled prefs — pure, unit-tested.
- `NotificationService.refresh()` actually schedules via `UNUserNotificationCenter.add(...)`; re-run on app launch, **every store mutation** (`FinchStore.swift:150`), and Settings toggles.
- Taps route via `DeepLinkRouter` to the right tab/entity.

**The one real bug:** `refresh()` only **adds** — it never removes. So when a kind is toggled **off** (or a budget falls back under threshold, or a due item is confirmed), the already-scheduled notification stays pending and still fires. By-design limits (no background refresh; reactive/already-due scheduling; weekly-digest content captured at schedule time) are documented in `IOS_MACOS_PHASE_6_2_DESIGN.md` and out of scope.

## Design

### 1. `NotificationPlanner.cancelIDs` — pure reconcile helper

```swift
/// Ids currently scheduled or delivered that are no longer planned — a kind was
/// disabled, a budget fell back under threshold, or a due item was confirmed — so
/// they should be cancelled. (`refresh()` plans the *current* set; anything pending
/// or delivered that isn't in it is stale.)
public static func cancelIDs(planned: [PlannedNotification], existing: Set<String>) -> [String] {
    let keep = Set(planned.map(\.id))
    return existing.subtracting(keep).sorted()
}
```

### 2. `NotificationService.refresh()` — cancel stale before adding

After computing `planned`, `pending`, `delivered` (existing code), and **before** the
add loop, reconcile:

```swift
        let stalePending = NotificationPlanner.cancelIDs(planned: planned, existing: pending)
        if !stalePending.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stalePending) }
        let staleDelivered = NotificationPlanner.cancelIDs(planned: planned, existing: delivered)
        if !staleDelivered.isEmpty { center.removeDeliveredNotifications(withIdentifiers: staleDelivered) }
```
The existing add loop (`for p in planned where !existing.contains(p.id)`) is unchanged —
together this makes `refresh()` a full reconcile: the live notification set always
matches the current plan. Cancels **both** pending (won't fire) and delivered (cleared
from Notification Center) for now-stale ids.

### 3. Test

In `NotificationPlannerTests` (FinchApp test target):

```swift
    func test_cancelIDs_dropsStaleKeepsPlanned() {
        let planned = [PlannedNotification(id: "budget:b1", kind: .budgetWarning, title: "", body: "", tab: nil, focusId: nil)]
        let existing: Set<String> = ["budget:b1", "scheduled:s1", "anomaly:t1"]
        XCTAssertEqual(NotificationPlanner.cancelIDs(planned: planned, existing: existing), ["anomaly:t1", "scheduled:s1"])
    }
```
(`budget:b1` is still planned → kept; the disabled/stale `scheduled:s1` + `anomaly:t1` → cancelled.)

### 4. End-to-end sim verification

Local notifications fire on the simulator. Seed a **scheduled item due today**
(`nextRun <= today`), launch, **grant the permission prompt**, and confirm a
notification **banner actually fires** (foreground banner via the delegate) and tapping
it routes to the Scheduled tab. This exercises permission → plan → schedule → fire → tap.

### 5. Doc note

Append a dated note to `IOS_MACOS_PHASE_6_2_DESIGN.md`: verified end-to-end on the sim;
cancel-on-disable fixed (`refresh()` now reconciles); restate the by-design limits (no
background refresh, reactive scheduling) so they aren't re-filed as bugs.

## Out of scope
- Background refresh (`BGTaskScheduler`); proactive future-due reminders; digest content
  freshness; anomaly scan window. All documented non-goals.
- Any engine/`FinchCore` change — this is App-layer (`NotificationPlanner`/`Service`).

## Testing
- **Unit:** `cancelIDs` test (above) in the FinchApp test target.
- **Build:** FinchApp (iOS) + FinchMac (macOS).
- **Manual (sim):** the end-to-end banner-fires verification (§4).

## Notes
- `cancelIDs` lives on `NotificationPlanner` (the pure-logic home) so it's testable
  without mocking `UNUserNotificationCenter`.
- PR targets `feat/frontend`.
