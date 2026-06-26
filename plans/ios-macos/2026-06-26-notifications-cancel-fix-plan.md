# Notifications cancel-on-disable fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `NotificationService.refresh()` cancel stale notifications (fixes toggle-off / no-longer-relevant alerts still firing), with a test; verify the local-notification chain end-to-end on the sim.

**Architecture:** A pure `NotificationPlanner.cancelIDs(planned:existing:)` helper; `refresh()` reconciles pending + delivered against the current plan. App-layer only, no engine change.

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-26-notifications-cancel-fix-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS). Notification tests are in the **FinchApp test target** (`Tests/FinchAppTests/`), run via `xcodebuild test`.
- Commits: **no `Co-Authored-By` trailer**. No engine/parity changes. PR targets `feat/frontend`.

---

### Task 1: `cancelIDs` helper + reconcile in `refresh()` + test

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Notifications/NotificationPlanner.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/Notifications/NotificationService.swift`
- Modify: `ios/FinchApp/Tests/FinchAppTests/NotificationPlannerTests.swift`

- [ ] **Step 1: Add the failing test**

In `NotificationPlannerTests.swift`, add:

```swift
    func test_cancelIDs_dropsStaleKeepsPlanned() {
        let planned = [PlannedNotification(id: "budget:b1", kind: .budgetWarning, title: "", body: "", tab: nil, focusId: nil)]
        let existing: Set<String> = ["budget:b1", "scheduled:s1", "anomaly:t1"]
        XCTAssertEqual(NotificationPlanner.cancelIDs(planned: planned, existing: existing), ["anomaly:t1", "scheduled:s1"])
    }
```

- [ ] **Step 2: Add the `cancelIDs` helper**

In `NotificationPlanner.swift`, add a static method to the enum/type (next to `plan`):

```swift
    /// Ids currently scheduled or delivered that are no longer planned — a kind was
    /// disabled, a budget fell back under threshold, or a due item was confirmed — so
    /// they should be cancelled.
    public static func cancelIDs(planned: [PlannedNotification], existing: Set<String>) -> [String] {
        let keep = Set(planned.map(\.id))
        return existing.subtracting(keep).sorted()
    }
```

- [ ] **Step 3: Reconcile in `refresh()`**

In `NotificationService.swift`, in `refresh()`, immediately **after** these existing lines:

```swift
        let pending = Set(await center.pendingNotificationRequests().map(\.identifier))
        let delivered = Set(await center.deliveredNotifications().map(\.request.identifier))
        let existing = pending.union(delivered)
```
insert:

```swift
        let stalePending = NotificationPlanner.cancelIDs(planned: planned, existing: pending)
        if !stalePending.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stalePending) }
        let staleDelivered = NotificationPlanner.cancelIDs(planned: planned, existing: delivered)
        if !staleDelivered.isEmpty { center.removeDeliveredNotifications(withIdentifiers: staleDelivered) }
```
(The add loop below — `for p in planned where !existing.contains(p.id)` — is unchanged.)

- [ ] **Step 4: Run the notification tests**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:FinchAppTests/NotificationPlannerTests 2>&1 | grep -E "Test Suite|passed|failed|error:" | tail -15
```
Expected: `NotificationPlannerTests` all pass (incl. the new `test_cancelIDs_dropsStaleKeepsPlanned`).

- [ ] **Step 5: Build iOS + macOS**

```bash
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Notifications/NotificationPlanner.swift \
        ios/FinchApp/Sources/FinchApp/Notifications/NotificationService.swift \
        ios/FinchApp/Tests/FinchAppTests/NotificationPlannerTests.swift
git commit -m "fix(ios): notifications — cancel stale/disabled on refresh (reconcile)"
```

---

### Task 2: End-to-end sim verification + doc note (controller)

**Files:**
- Modify: `plans/ios-macos/IOS_MACOS_PHASE_6_2_DESIGN.md`

- [ ] **Step 1: Install + seed a due scheduled item**

Install the build; find the live DB (the `finch.sqlite3` with `entries`); locate the
scheduled/recurring table (`SELECT name FROM sqlite_master WHERE type='table' AND
(name LIKE '%recur%' OR name LIKE '%schedul%')`) and insert (or update an existing one
to) a template with `next_run <= today` (today = 2026-06-26) so the planner emits a
`scheduledDue` notification on launch.

- [ ] **Step 2: Launch, grant permission, observe the banner**
  - Launch; on the permission prompt, AXPress **Allow**.
  - `refresh()` runs at launch → schedules the due item with a ~3s trigger → a
    **notification banner** appears (foreground banner via the delegate). Screenshot it
    to `/tmp/notif.png`.
  - (Optional) AXPress the banner → app routes to the **Scheduled** tab.
  - If the banner doesn't surface under automation, note it; the planner + cancel logic
    are unit-tested and the scheduling glue is unchanged from the audited working path.

- [ ] **Step 3: Doc note**

Append a dated note to `plans/ios-macos/IOS_MACOS_PHASE_6_2_DESIGN.md`:
- `2026-06-26` — verified end-to-end on the simulator (permission → plan → schedule →
  fire → tap); **fixed** cancel-on-disable (`refresh()` now reconciles pending +
  delivered against the plan). By-design limits remain: no background refresh; reactive
  (already-due) scheduling; weekly-digest content captured at schedule time.

- [ ] **Step 4: Commit the doc + clean up the seed**

```bash
git add plans/ios-macos/IOS_MACOS_PHASE_6_2_DESIGN.md
git commit -m "docs(ios): note notifications verified end-to-end + cancel fix"
# then delete the seeded scheduled row from the sim DB
```

---

## Self-review notes
- Spec coverage: cancelIDs helper (T1 S2) + reconcile (T1 S3) + test (T1 S1/S4), build (T1 S5), end-to-end sim verify (T2 S1-2), doc note (T2 S3). ✓
- Type consistency: `cancelIDs(planned: [PlannedNotification], existing: Set<String>) -> [String]`, `PlannedNotification(id:kind:title:body:tab:focusId:)`, `removePendingNotificationRequests`/`removeDeliveredNotifications` consistent with the audited code. ✓
- App-layer only; no engine/parity change. ✓
