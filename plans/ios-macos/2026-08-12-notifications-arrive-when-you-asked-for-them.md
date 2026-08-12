# A systematic notification policy — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notifications stop arriving at 3am and stop arriving in floods, and the ones that can be known in advance arrive on their date even if the app is never opened.

**Architecture:** `NotificationPlanner` keeps deciding **what is true**; a new pure `NotificationPolicy` decides **when it reaches you and how many**. Alerts split by whether they are predictable: scheduled-due and the weekly digest are handed to iOS ahead of time with calendar triggers, so the system delivers them with the app closed; budget and anomaly alerts stay write-driven and are held out of quiet hours.

**Tech Stack:** Swift, `UserNotifications` (`UNCalendarNotificationTrigger`, `UNTimeIntervalNotificationTrigger`), UIKit + SwiftUI settings screens, `UserDefaults` for preferences.

## Why there is no background task in this plan

The app has **no background execution at all** — no `BGTaskScheduler`, no background modes (verified: zero matches in the tree). It does not need any:

- **Predictable alerts** (a bill due on the 1st, the weekly digest) are registered with `UNCalendarNotificationTrigger`. iOS delivers those whether or not the app runs. The weekly digest already proves the pattern works.
- **Reactive alerts** (budget threshold, anomaly) only become true when data changes, and data only changes while someone is using the app. Evaluating on write is therefore complete, not a compromise.

Background refresh would only buy alerts that depend on **time passing rather than a write** — pace nudges, "you haven't logged anything in five days" — none of which exist today. It is also granted at Apple's discretion and may simply not run for days, so anything built to depend on it is unreliable by construction. **If pace-based alerts are ever wanted, background refresh becomes one more caller into the same planner and this design needs no rework.**

## Global Constraints

- Target `feat/frontend`. Never `main`. No `Co-Authored-By` trailer.
- `ios/scripts/ci-local.sh --ui` must print `gate passed` before pushing.
- New user-facing strings go through `String(localized:)`, need a `zh-manual.json` entry, and the regenerated catalog must be **committed** (guard 1 diffs against HEAD). Expect to re-run the key export — see the "i18n - extracted keys are current" step in `ci-local.sh`.
- **iOS allows 64 pending notifications per app.** Every scheduling decision here is bounded with that in mind.
- `NotificationPolicy` must be **pure** — no clock reads, no `UNUserNotificationCenter`. `now` is a parameter, exactly as `pendingSplit` takes `today`. It is the only way its rules are testable.

---

## The design, settled

| Alert | Delivery |
|---|---|
| `scheduledDue` | **Pre-scheduled** — calendar trigger on its `nextRun` date |
| `weeklyDigest` | Already pre-scheduled (Sunday morning, repeating) — unchanged |
| `budgetWarning`, `anomaly` | **Reactive** — planned on write, held if inside quiet hours |

**One pending notification per scheduled template**, for its next occurrence only. Bounded by template count rather than by time, so the 64 cap cannot be approached. When one fires or moves, the next plan emits the following occurrence.

**Two preferences:**
- **Quiet window** (default 22:00–08:00) — reactive alerts raised inside it are HELD to its end, not dropped.
- **Delivery hour** (default 09:00) — the time of day pre-scheduled alerts fire.

**The quiet window wins when they disagree.** A delivery hour of 07:00 with quiet hours ending at 08:00 fires at 08:00: `max(deliveryHour, quietEnd)`. The window is the promise the user made about being disturbed; the hour is a preference about when things land.

**Invalidation is already solved.** `NotificationPlanner.cancelIDs(planned:existing:)` removes anything pending or delivered that the current plan no longer contains, so a rescheduled bill corrects itself. **This imposes a hard requirement: the planner must emit future items on EVERY run.** Today `scheduledDue` is only emitted when `nextRun <= wallToday`, so a pre-scheduled alert would be cancelled by the very next write. Task 2 changes that, and Task 2's test is what proves it.

---

## File Structure

| File | Change |
|---|---|
| `ios/FinchApp/Sources/FinchShared/Notifications/NotificationPlanner.swift` | `PlannedNotification.deliverOn: Date?`; emit future `scheduledDue` |
| `ios/FinchApp/Sources/FinchShared/Notifications/NotificationPolicy.swift` | **Create** — pure quiet-hours + cap rules |
| `ios/FinchApp/Sources/FinchShared/Notifications/NotificationPrefs.swift` | quiet window + delivery hour (find the existing prefs file; it holds `isOn(_:)`) |
| `ios/FinchApp/Sources/FinchShared/Notifications/NotificationService.swift` | use the policy; calendar trigger for dated items |
| `ios/FinchApp/Sources/FinchAppUIKit/NotificationsSettingsVC.swift` | a second section: quiet hours + delivery hour |
| `ios/FinchApp/Sources/FinchAppSwiftUI/...` the SwiftUI notifications settings | the same two rows (macOS + the `-uikitActivity NO` control build) |
| `ios/FinchCore/…` | **nothing** — this is app-layer policy, not engine |
| Tests | `NotificationPolicyTests.swift`, plus planner cases |

---

## Task 1: The policy, pure and tested

**Files:** create `NotificationPolicy.swift` and `NotificationPolicyTests.swift`.

**Interfaces — Produces:**

```swift
public struct QuietHours: Equatable, Sendable {
    public let startHour: Int   // 22
    public let endHour: Int     // 8
}

public enum NotificationPolicy {
    /// When may this alert be delivered, given the moment it was raised?
    /// Returns `now` when outside the window, otherwise the next window end.
    public static func deliveryTime(raisedAt now: Date, quiet: QuietHours, calendar: Calendar) -> Date

    /// Collapse an over-cap batch into the first `cap` plus one summary.
    public static func applyCap(_ planned: [PlannedNotification], cap: Int,
                                summary: (Int) -> PlannedNotification) -> [PlannedNotification]
}
```

- [ ] **Step 1: Write the failing tests**

Cases that must exist, each asserting a specific instant (build dates with `DateComponents`, never `Date()`):

1. Raised 14:12, quiet 22–08 → delivered **14:12** (untouched).
2. Raised 02:14, quiet 22–08 → delivered **08:00 the same day**.
3. Raised 23:30, quiet 22–08 → delivered **08:00 the NEXT day** (the window crosses midnight — this is the case that breaks a naive implementation).
4. Raised exactly 22:00 → held. Raised exactly 08:00 → delivered immediately. (Boundaries stated explicitly; `<` vs `<=` is the obvious slip.)
5. A window that does not cross midnight (e.g. 01:00–06:00) still holds correctly — do not assume the default.
6. `applyCap` with 2 items and cap 3 → returns the 2 unchanged, **no summary**.
7. `applyCap` with 10 items and cap 3 → returns 3 plus 1 summary, and the summary reports **7**.

- [ ] **Step 2: Run them, confirm they fail** (`swift test` won't cover this — it is in the app target, so run the app test scheme).
- [ ] **Step 3: Implement.** No `Date()` anywhere in this file.
- [ ] **Step 4: Green.** **Step 5: Commit.**

---

## Task 2: The planner emits the future

**Files:** `NotificationPlanner.swift`

- [ ] **Step 1** Add `public let deliverOn: Date?` to `PlannedNotification` — `nil` means "as soon as policy allows". Adding a field to a `public struct` with a memberwise init breaks every construction site; add it **last with a default** (`deliverOn: Date? = nil`) so existing sites compile untouched.

- [ ] **Step 2** Change the `scheduledDue` loop. It currently reads:

```swift
for s in scheduled where !s.nextRun.isEmpty && s.nextRun <= wallToday {
```

It must now emit for **every** template with a non-empty `nextRun` — past-due AND future — because `cancelIDs` deletes anything absent from the plan. Past-due keeps `deliverOn: nil` (send now, subject to quiet hours); future carries `deliverOn` = its `nextRun` at the delivery hour.

**The date is a day string and the delivery hour is a preference.** Combine them in the planner, which already receives `wallToday`; pass the hour in as a parameter rather than reading prefs inside this pure type.

- [ ] **Step 3** Test: a template due next month produces a planned item with a `deliverOn`, and **two consecutive plans produce the same id** — that identity is what stops `cancelIDs` cancelling and re-adding it on every keystroke.

- [ ] **Step 4** Commit.

---

## Task 3: The service honours both

**Files:** `NotificationService.swift` (trigger choice is around line 116)

- [ ] **Step 1** Replace the trigger selection. Today: digest → calendar, everything else → `timeInterval: 3`. It becomes:

- `deliverOn != nil` → `UNCalendarNotificationTrigger` for that instant, `repeats: false`
- digest → unchanged (calendar, repeating)
- otherwise → `NotificationPolicy.deliveryTime(raisedAt: .now, …)`; if that is now, keep the 3-second trigger; if it is later, use a calendar trigger for it

- [ ] **Step 2** Apply `applyCap` before scheduling. **Cap = 3, and the summary is a real `PlannedNotification`** with a stable id (`"summary:<yyyy-MM-dd>"`) so re-planning replaces rather than duplicates it.

- [ ] **Step 3** Verify `cancelIDs` still behaves: it compares planned ids against pending AND delivered. The summary id must be in the plan whenever it is scheduled, or it cancels itself.

- [ ] **Step 4** Commit.

---

## Task 4: The two settings, on both screens

**Files:** `NotificationsSettingsVC.swift`, its SwiftUI counterpart, and the prefs store.

- [ ] **Step 1** Add the preferences beside the existing per-kind toggles. Defaults: quiet **22:00–08:00**, delivery hour **09:00**.
- [ ] **Step 2** A second section below the kind toggles: "Quiet hours" (start + end) and "Delivery time". Use the app's existing row idioms — **`ToggleAccessory` exists because UIKit has no toggle accessory; check what the codebase already does for a time picker in a list row before inventing one.**
- [ ] **Step 3** Both screens must match: macOS renders the SwiftUI one, and `NavigationUITests` runs its suite once per implementation.
- [ ] **Step 4** Commit.

---

## Task 5: Strings, gate, PR

- [ ] New keys ("Quiet hours", "Delivery time", the summary body) → `zh-manual.json` → re-export keys → `build-xcstrings.ts` → **commit the catalog**.
- [ ] Rebase, `./scripts/ci-local.sh --ui`, push, PR against `feat/frontend`.

---

## Two decisions left open, with recommendations

**The cap number.** I have written **3** throughout. It is a guess, not a measurement — the only evidence is that anomaly scoring runs over the 50 most recent purchases, so an import of unfamiliar merchants is the realistic burst. Change it in one place if 3 feels wrong; it is a constant, not a shape.

**The digest's Sunday-morning slot.** Left **fixed and unconfigurable**, so this change does not grow a third time setting. If the new Delivery time should also govern the digest, that is a one-line change in the digest's calendar trigger — but decide it deliberately rather than letting it drift.

## Deliberately out of scope

- **Any `FinchCore` change.** This is delivery policy; the engine has no opinion on when a human should be interrupted.
- **Background refresh** — see the top of this plan.
- **Per-budget muting and threshold tuning.** Real gaps in the four-toggle settings surface, but a settings-surface project rather than a delivery-policy one.

## Self-review notes

- Task 1 case 3 (raised 23:30 → next day 08:00) is the one a naive implementation fails, because the window crosses midnight. It is listed before the boundary cases on purpose.
- Task 2's "emit the future or `cancelIDs` deletes it" is the single non-obvious coupling in this plan. Its test asserts stable ids across two plans, which is what actually protects it.
- The `deliverOn` field must be added **last with a default**, or every existing `PlannedNotification(...)` call site fails to compile and the diff triples in size for no reason.
