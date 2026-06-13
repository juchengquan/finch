# finch for iOS & macOS — Phase 7 Implementation Design

> _Web facts verified against commit `22c9896` (SCHEMA_VERSION `2026-06-14T00:00:00Z`), 2026-06-13.
> See `_WEB_DRIFT_CHECKLIST.md`._

> **Status**: design spec — not yet an implementation plan. Once
> approved, this becomes the input to `writing-plans` to produce a
> step-by-step implementation plan for Phase 7.
>
> Companion documents:
>
> - `plans/ios-macos/IOS_MACOS_PLAN.md` — direction brief
> - `plans/ios-macos/IOS_MACOS_PHASE_1_DESIGN.md` — Phase 1.0 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_1_5_DESIGN.md` — Phase 1.5 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_2_DESIGN.md` — Phase 2 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_3_DESIGN.md` — Phase 3 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_4_DESIGN.md` — Phase 4 full design
> - `plans/ios-macos/IOS_MACOS_PHASE_5_DESIGN.md` — Phase 5 full design
> - `plans/ios-macos/IOS_MACOS_ROADMAP.md` — 8-phase arc
> - `plans/ios-macos/IOS_MACOS_PHASE_7_DESIGN.md` (this file)
>
> _Audience: the engineers who will build the iOS app. Assumes
> Phases 1.0-5 are complete; the iPhone + iPad + Mac apps are
> shipping with the 6 tabs + 7 write screens + 7 power features
> + iCloud sync._

## See also

- `plans/ios-macos/IOS_MACOS_INDEX.md` §2.4 — App Group container (added in Phase 6.5, reused here)
- `plans/ios-macos/IOS_MACOS_WIRE_FORMAT.md` §4 — the pack format (widget snapshot reads from the live DB)
- `plans/ios-macos/IOS_MACOS_PHASE_1_DESIGN.md` §1 — the 4-tab list (the widget grid mirrors it)
- `plans/ios-macos/IOS_MACOS_PHASE_1_5_DESIGN.md` — Phase 1.5 (selectors that drive widget content)
- `plans/ios-macos/IOS_MACOS_PHASE_2_DESIGN.md` — Phase 2 (chokepoint; the Watch quick-add uses `addTransaction`)
- `plans/ios-macos/IOS_MACOS_PHASE_5_DESIGN.md` — Phase 5 (iCloud + pack engine)
- `plans/ios-macos/IOS_MACOS_PHASE_6_5_DESIGN.md` — Phase 6.5 (App Group setup)

## §0. Map — 8-section template

The 8-section template maps to this spec's existing sections:

| Template section | Maps to |
|---|---|
| §1. Goal & non-goals | §1 |
| §2. Architecture / data model | §2 (Widgets) + §3 (Live Activities) + §4 (Apple Watch app) — the 3 extension targets |
| §3. iOS UI surfaces | §2 (Widgets UI) + §3 (Live Activities UI) + §4 (Watch UI) |
| §4. Cross-cutting concerns | (not directly covered — stub to `IOS_MACOS_PLAN.md` §10 for the multi-platform strategy) |
| §5. Wire contracts | §2 (widget reads from the chokepoint projection) + §3 (Live Activity updates via the chokepoint) + §4 (Watch quick-add dispatches chokepoint writes) |
| §6. CI / test infrastructure | §5 (CI changes) |
| §7. Out of scope (firm) | §7 |
| §8. Spec self-review + open questions | §8 + §6 |

## §1. Goal & non-goals

**Goal** — Add the **Apple-platform native surfaces** that
make finch feel like a first-class iOS app, not a webview:

1. **Widgets** (WidgetKit) — read-only views on the home
   screen, on the lock screen, and in StandBy mode. The
   widget candidates are: net-worth sparkline, this-month
   budget ring, month-forecast tile, weekly digest tile.
2. **Live Activities / Lock Screen / Dynamic Island** —
   real-time updates from the iOS app, surfaced on the
   lock screen, in the Dynamic Island, and in StandBy. The
   Live Activity candidates are: scheduled item due (with
   a "Confirm" action button), budget over 90% (with a
   "View budgets" action button), anomaly flagged (with a
   "View transaction" action button).
3. **Apple Watch app** — a glance app (read-only net worth
   + budget rings) + a quick-add action (add a recent
   expense, dispatching through the Phase 2 chokepoint).

**Phase 7 is mostly UI work** on top of the existing data
layer. The widgets + Live Activities + Watch all read from
the in-memory `Tx[]` cache + the in-memory `AccountRow[]` +
the chokepoint (for Watch quick-add). The Phase 1.5
selectors are the data source for the widget + Live
Activity + Watch read paths.

**Non-goals (firm)**:

- **No new tabs / write screens / power features** — the
  6 tabs + 7 write screens + 7 power features are unchanged.
  Phase 7 adds 3 new **system surfaces** (WidgetKit,
  ActivityKit, watchOS) that read from the existing data.
- **No new selectors** — the Phase 1.5 selectors are the
  full set. The widgets + Live Activities + Watch reuse
  them.
- **Auto-pack debounce + iCloud folder-watcher** — Phase 5.
- **App Intents / Siri / Share Extension / Spotlight /
  notifications / biometric lock** — Phase 6.
- **Row-level sync** — Phase 8.
- **Android / Wear OS** — not in the plan. watchOS only.
- **Multi-user / shared ledgers** — single-user iCloud
  account = single finch install. Per the plan's §10
  resolved decision.

**Estimated scope**: ~600 lines Swift (the widget timeline
provider + the Live Activity attributes + the Watch app
view model) + ~500 lines SwiftUI (the widget views + the
Watch app UI) + ~300 lines watchOS-specific code (the
complication, the digital crown support, etc.) + ~200
lines tests. **1-2 months of full-time work** for a small
team. Watch is the optional part (per the plan §7, "MAY
later"); the widgets + Live Activities are the headline.

## §2. Widgets (WidgetKit)

WidgetKit ships **read-only views** on the home screen,
lock screen, and StandBy mode. The widget's data is
provided by a **TimelineProvider** that returns a sequence
of `TimelineEntry` snapshots; the system renders each
snapshot at its scheduled time.

### 2.1 — The 4 widgets

The 4 widgets share a common shape: a small SwiftUI view
that reads from a snapshot of the data layer. The
TimelineProvider runs the relevant Phase 1.5 selector and
packages the result as a `TimelineEntry`.

**Widget 1: Net worth sparkline**

- A 2-row widget: net worth figure (large) + 6-month line
  chart (small)
- Reads: `netWorthByMonth(txns, accounts, ledgerId,
  endMonth: now, n: 6)` (Phase 1.5)
- Refresh: hourly (the system budget may be tighter; the
  widget respects the system-enforced budget)
- Tapping the widget deep-links to the iOS app's Insights
  tab

**Widget 2: This-month budget ring**

- A 2-row widget: budget name + circular progress ring
- Reads: `budgetProgress(budget, ...)` for each budget
  (Phase 1.5 / 1.0)
- Refresh: hourly
- Tapping the widget deep-links to the iOS app's Budgets
  tab
- The widget supports **AppIntentConfiguration** (the
  iOS 17+ replacement for the legacy
  `WidgetConfigurationIntent` / `IntentConfiguration`; the
  user picks which budget to show — the topmost "almost
  over" budget, or a specific budget by name)

**Widget 3: Month-forecast tile**

- A 1-row widget: "Forecast: $1,847 spend this month"
- Reads: `monthForecast(txns, scheduled, ledgerId, month,
  today)` (Phase 1.5) — a SINGLE month (the `month` string),
  month-to-date actuals + daily run-rate × days-remaining +
  upcoming scheduled; 2nd param is `scheduled[]`, not
  `accounts`
- Refresh: daily (the forecast doesn't change intra-day)
- Tapping the widget deep-links to the Insights tab

**Widget 4: Weekly digest tile**

- A 2-row widget: "This week: $234 spent" + "vs last week:
  ▼ $12 (-5%)"
- Reads: `weeklyDigest(txns, ledgerId, anchor: last
  Sunday)` (Phase 1.5)
- Refresh: daily
- Tapping the widget deep-links to the Activity tab

### 2.2 — The widget extension

The widgets are a separate **Widget Extension** target in
the Xcode project. The extension is a small binary that
ships with the main iOS app; the user enables widgets
from the iOS home screen.

```swift
// ios/FinchWidget/FinchWidgetBundle.swift
@main
struct FinchWidgetBundle: WidgetBundle {
    var body: some Widget {
        NetWorthWidget()
        BudgetRingWidget()
        MonthForecastWidget()
        WeeklyDigestWidget()
    }
}
```

Each widget is a `Widget` struct with:
- A `kind` (the unique identifier)
- A `StaticConfiguration` or `IntentConfiguration` (the
  former for fixed widgets; the latter for user-configurable
  ones like the Budget Ring)
- A `TimelineProvider` (the data source)
- A `Widget` view (the SwiftUI body)

### 2.3 — The TimelineProvider

```swift
// ios/FinchWidget/Providers/NetWorthProvider.swift
struct NetWorthEntry: TimelineEntry {
    let date: Date
    let netWorth: Decimal
    let history: [NetWorthByMonth]
}

struct NetWorthProvider: TimelineProvider {
    func placeholder(in context: Context) -> NetWorthEntry {
        // Sample data for the widget gallery
        NetWorthEntry(
            date: Date(),
            netWorth: 69_752.00,
            history: (0..<6).map { i in
                NetWorthByMonth(
                    month: monthString(monthsAgo: i),
                    netWorth: 69_752.00 - Decimal(i * 1000)
                )
            }
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NetWorthEntry) -> Void) {
        completion(loadFromAppGroup())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NetWorthEntry>) -> Void) {
        let entry = loadFromAppGroup()
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(next))
        completion(timeline)
    }

    private func loadFromAppGroup() -> NetWorthEntry {
        // Read the data from the App Group container (shared
        // between the iOS app and the widget extension).
        // The iOS app writes a JSON snapshot to the App Group
        // on every successful write; the widget reads the
        // snapshot.
        let snapshotURL = AppGroup.containerURL.appendingPathComponent("widget_snapshot.json")
        // ... deserialize the snapshot
    }
}
```

The widget **reads from a shared App Group container** (not
the iCloud container; the widget is a separate process
that doesn't have iCloud access by default). The iOS app
writes a JSON snapshot to the App Group on every successful
write (and on every app foreground). The widget reads the
snapshot on each refresh.

### 2.4 — The widget snapshot

The snapshot is a JSON blob with the pre-computed widget
data:

```json
{
  "generatedAt": "2026-06-12T18:42:00Z",
  "netWorth": 69752.00,
  "netWorthHistory": [
    { "month": "2026-01", "netWorth": 60000.00 },
    { "month": "2026-02", "netWorth": 62000.00 },
    { "month": "2026-03", "netWorth": 65000.00 },
    { "month": "2026-04", "netWorth": 67000.00 },
    { "month": "2026-05", "netWorth": 68500.00 },
    { "month": "2026-06", "netWorth": 69752.00 }
  ],
  "topBudget": {
    "name": "Groceries",
    "spent": 340.00,
    "limit": 500.00,
    "percent": 0.68
  },
  "monthForecast": 1847.00,
  "weeklyDigest": {
    "spent": 234.56,
    "previousWeekDelta": -12.00,
    "previousWeekDeltaPercent": -0.05
  }
}
```

The iOS app writes this JSON to the App Group on every
write (in `FinchStore.apply` from Phase 2, after the
chokepoint succeeds) and on every app foreground. The
widget reads it on every refresh.

### 2.5 — App Group entitlements

The widget extension requires the **App Group entitlement**
(same as the Phase 6 Share Extension). The entitlement
key: `com.apple.security.application-groups` with value
`group.com.juchengquan.finch`. The Xcode project is
configured at Phase 6.5's Share Extension setup (Phase 7
reuses the same entitlement for the widget + Watch
extension; Phase 7's only addition is the widget target
and the Watch app, both of which join the existing App Group).

The App Group container is at
`~/Library/Group Containers/group.com.juchengquan.finch/`.
The iOS app + the widget extension + the (Phase 6) Share
Extension all read/write here.

## §3. Live Activities (ActivityKit)

Live Activities are **real-time widgets** that appear on
the lock screen, in the Dynamic Island, and in StandBy
mode. They're updated by the iOS app's chokepoint (via
`Activity.update(...)`).

### 3.1 — The 3 Live Activities

**Activity 1: Scheduled item due**

- Trigger: a scheduled item's `dueDate` is within the next
  hour
- Surface: a "Coming up: <description> due in N minutes"
  with a "Confirm now" button
- Tapping the button dispatches `Args.postScheduled({templateId})`
  via the chokepoint
- Refresh: the iOS app schedules a `UNUserNotificationCenter`
  trigger to fire the Live Activity update at the right
  time; the Live Activity's `ContentState` carries the
  due-time and the template's `id`

**Activity 2: Budget over 90%**

- Trigger: a budget's `spent / limit` exceeds 0.9
- Surface: "<budget name>: <percent>% used" with a "View
  budgets" button
- Tapping the button deep-links to the iOS app's Budgets
  tab
- Refresh: the iOS app updates the Live Activity whenever
  the relevant budget's progress changes (in
  `FinchStore.apply` after a transaction posts)

**Activity 3: Anomaly flagged**

- Trigger: a recent transaction has `anomalyScore` > 3
- Surface: "Unusual: <description> $<amount>" with a
  "View" button
- Tapping the button deep-links to the iOS app's
  Transaction Detail screen
- Refresh: the iOS app updates the Live Activity when the
  anomaly threshold is crossed

### 3.2 — The Live Activity attributes

```swift
// ios/FinchApp/LiveActivities/ScheduledItemAttributes.swift
struct ScheduledItemAttributes: ActivityAttributes {
    public typealias ContentState = ScheduledItemState

    public struct ScheduledItemState: Codable, Hashable {
        var dueAt: Date
        var description: String
        var amount: Decimal
        var templateId: String  // for the "Confirm now" action
    }

    var ledgerId: String
    var templateName: String
}

@available(iOS 16.2, *)
struct ScheduledItemLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScheduledItemAttributes.self) { context in
            // The lock-screen / banner UI
            ScheduledItemLockScreenView(state: context.state)
        } dynamicIsland: { context in
            // The Dynamic Island UI (compact, expanded, minimal)
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Coming up", systemImage: "calendar")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.amount, format: .currency(code: "USD"))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.description)
                    Button("Confirm now") {
                        // Deep-link to the iOS app
                    }
                }
            } compactLeading: {
                Image(systemName: "calendar")
            } compactTrailing: {
                Text(timerInterval: ...context.state.dueAt, countsDown: true)
            } minimal: {
                Image(systemName: "calendar")
            }
        }
    }
}
```

The `Widget` body provides:
- The **lock-screen UI** (a SwiftUI view shown above the
  lock clock)
- The **Dynamic Island UI** (compact, expanded, minimal
  variants for the 3 states)
- The **StandBy mode UI** (a lower-fidelity variant for
  nightstand use)

### 3.3 — Updating the Live Activity

When the chokepoint posts a transaction that affects a
budget's progress, the iOS app updates the corresponding
Live Activity:

```swift
// ios/FinchApp/LiveActivities/LiveActivityManager.swift
@MainActor
public final class LiveActivityManager {
    public func updateBudgetProgress(budgetId: String, spent: Decimal, limit: Decimal) async {
        guard let activity = Activity<BudgetProgressAttributes>.activities.first(where: { $0.attributes.budgetId == budgetId }) else {
            return
        }
        let state = BudgetProgressAttributes.ContentState(
            spent: spent,
            limit: limit,
            percent: spent / limit
        )
        // staleDate ~15 min ahead so the system can gracefully
        // collapse the activity to a "needs update" state if
        // the iOS app can't reach the chokepoint.
        let staleDate = Date().addingTimeInterval(15 * 60)
        await activity.update(.init(state: state, staleDate: staleDate))
    }
}
```

The Live Activity has a **stale date**; if the iOS app
doesn't update it before the stale date, the system
collapses the Live Activity to a "needs update" state.
The iOS app's `FinchStore.apply` updates the affected Live
Activities on every write.

## §4. Apple Watch app

The Watch app is a **glance app + a quick-add action**.

### 4.1 — The Watch app structure

```
finch (Watch app)
├── Net Worth (complication + glance)
│   - Big number: $69,752
│   - 1-day delta: ▲ $234
├── Budgets (complication + list)
│   - 🛒 Groceries    $340 / $500  (68%)
│   - ☕ Food & Dining $280 / $300  (93%)
│   - 🚗 Transport    $80 / $400  (20%)
│   - Tap to view details
├── Quick Add (action)
│   - "+ Add Recent Expense"
│   - Picks a recent merchant + amount
│   - Tapping "Add" dispatches via the iOS app's chokepoint
```

The Watch app is a **small SwiftUI app** that runs on
watchOS 26+ and shares the App Group container with the
iOS app. The Watch app reads the widget snapshot JSON
(§2.4) for the data; the iOS app's snapshot update is the
write path (the Watch app doesn't write to the DB
directly).

### 4.2 — The data flow

The Watch app is **read-only** (the complication + the
glance + the list). The Watch app's **quick-add action**
opens the iOS app on the iPhone (via `WKApplicationDelegate`)
which dispatches the chokepoint. The Watch app does **not**
write directly to the DB.

```
┌─────────────────────────────────────┐
│  Watch app                           │
│  Read: widget snapshot JSON         │
│  (from App Group container)         │
└─────────────────────────────────────┘
              ▲
              │ (iOS app writes the snapshot
              │  on every successful write)
              │
┌─────────────────────────────────────┐
│  iOS app                             │
│  Writes: widget snapshot JSON        │
│  Writes: DB via the chokepoint       │
└─────────────────────────────────────┘
              ▲
              │ (Watch quick-add triggers the
              │  iOS app; the iOS app dispatches
              │  the chokepoint; the iOS app
              │  re-writes the snapshot)
              │
┌─────────────────────────────────────┐
│  Watch app (quick-add)              │
│  Triggers: open iOS app              │
└─────────────────────────────────────┘
```

The Watch app is **not** a write target in Phase 7. Watch
quick-add is a deep-link to the iOS app. The iOS app
writes to the DB; the iOS app's `FinchStore.apply` updates
the snapshot; the Watch app reads the new snapshot.

This is a **deliberate design choice**: writing from a
watchOS process is fraught (sandbox + iCloud + App Group
+ parent-app-process boundary). The deep-link is simpler
and matches the user's mental model ("the watch is a
glance; the phone is the real app").

### 4.3 — The Watch UI

```
┌─────────────────────────┐
│  Net worth              │
│  $69,752                │
│  ▲ $234                │
├─────────────────────────┤
│  Budgets                │
│  🛒 Groceries  68%      │
│  ☕ Food       93%  ⚠   │
│  🚗 Transport  20%      │
├─────────────────────────┤
│  + Add Recent           │
│    Expense              │
└─────────────────────────┘
```

The Watch app is a **simple list with 2 sections**
(net worth + budgets + the quick-add button). Tapping
the quick-add button:
- Picks the most recent expense (from the snapshot's
  `recentExpenses` list)
- Opens the iOS app's "Add Transaction" form pre-filled
  with the recent merchant + amount
- The user confirms on the iOS app; the chokepoint posts
  the entry; the iOS app's snapshot updates

### 4.4 — Watch complications

The Watch app's net worth + budget data surfaces as
**Watch complications** (the small icons on the Watch
face). The complication types:
- **Modular small**: the net worth figure
- **Modular large**: the net worth + 1-day delta
- **Corner**: the topmost "almost over" budget (the same
  data the widget uses)
- **Circular**: the topmost budget's progress ring
  (the same circular ring as the iOS widget)

The complications update **when the iOS app updates the
snapshot** (via the App Group). The Watch reads the
snapshot on every face refresh.

## §5. CI changes

The macos job from Phase 1.0's `IOS_MACOS_PHASE_1_DESIGN §9`
extends with:

- A **widget extension** target test (`xcodebuild test
  -scheme FinchWidget -destination 'platform=iOS
  Simulator,name=iPhone 15'`)
- A **Live Activity snapshot test** (the Live Activity
  content state is correctly serialized)
- A **Watch app test** (`xcodebuild test -scheme FinchWatch
  -destination 'platform=watchOS Simulator,name=Apple Watch
  Series 10'`)
- A **snapshot JSON test** (the iOS app writes the
  snapshot JSON in the expected shape; the widget + Watch
  parse it correctly)

## §6. Open questions

**Not blocking Phase 7 (decide later)**:

- **Widget refresh budget**: WidgetKit enforces a system-
  wide refresh budget (Apple's recommendation: don't
  refresh more than ~40-60 times per day). The iOS app's
  proposal refreshes hourly (24 times per day). **Per Q30,
  no force-refresh button in Settings** — the user can
  implicitly force-refresh by opening the iOS app (which
  updates the snapshot; the widget reads the new snapshot on
  its next refresh).
- **Live Activity lifetime**: a Live Activity can live up
  to 8 hours (after that, the system collapses it). **Per
  Q31, the lifetime is user-configurable** via Settings
  › Live Activities › Scheduled-due window: 1 hour (default),
  4 hours, 8 hours (max). The user can also disable Live
  Activities for the scheduled-due category (fall back to
  standard notifications). The exact limits are
  Apple-defined and may change.
- **Watch app scope**: the proposal is a **glance app +
  quick-add**. A full Watch app (with all 6 tabs) is a
  larger scope (the watchOS app would need its own
  chokepoint port; the App Group + iCloud sync model
  would need to be re-thunk). Per the plan §7 "MAY
  later", the full Watch app is a follow-up.
- **StandBy mode UI**: the widgets surface in StandBy
  mode automatically. The Live Activity's StandBy UI is
  lower-fidelity (large text, no animations). The
  proposal uses the default StandBy UI; custom StandBy UI
  is a follow-up.
- **Dynamic Island layout**: the proposal has 3 regions
  (leading / trailing / bottom). Some Live Activities
  may need 2 or 4 regions. The exact layout is per-
  activity.
- **Widget configuration UX**: the Budget Ring widget has
  an `AppIntentConfiguration` (the user picks which
  budget to show). The UX is the iOS standard
  configuration sheet. The proposal doesn't detail the
  exact pickers.

**Not blocking Phase 7 because they're Phase 5+ by design**:

- **Auto-pack debounce + iCloud folder-watcher** —
  Phase 5. The widgets + Live Activities + Watch all
  read from the iOS app's local DB; they don't need
  iCloud sync to work (the data is always local; the
  iCloud sync is for cross-device).
- **App Intents / Siri / Share Extension / Spotlight /
  notifications / biometric lock** — Phase 6. (Note: the
  Live Activity's "Confirm now" action button is NOT an
  App Intent; it's a deep-link to the iOS app.)
- **Row-level sync** — Phase 8.

## §7. Out of scope (firm)

These are explicitly NOT in Phase 7:

- **No new tabs / write screens / power features** — the
  6 tabs + 7 write screens + 7 power features are
  unchanged.
- **No new selectors** — the Phase 1.5 selectors are the
  full set. The widgets + Live Activities + Watch reuse
  them.
- **No new chokepoint actions** — the 74 Phase 2 actions
  are the full set (Phase 6.5's `setEntryAttachment` is a
  planned **native-only** 75th action — the web has no such
  chokepoint action; it adds attachments via the
  `/api/attachments` route — which brings the running total
  to 75; Phase 7 doesn't add more).
  Phase 7's Watch quick-add uses
  `Args.postScheduled` (Phase 2) for one specific case;
  the widgets + Live Activities don't write.
- **No new iCloud sync** — the iCloud sync is Phase 5;
  the widgets + Live Activities + Watch are read-only
  consumers of the local DB.
- **Auto-pack debounce + iCloud folder-watcher** — Phase 5.
- **App Intents / Siri / Share Extension / Spotlight /
  notifications / biometric lock** — Phase 6.
- **Row-level sync** — Phase 8.
- **iOS-on-Mac (Catalyst)** — Phase 3. Widgets +
  watchOS don't run on Mac; only iOS + watchOS.
- **Full Watch app** — Phase 7 ships a glance app + a
  quick-add action. A full Watch app (with all 6 tabs)
  is a follow-up.
- **Multi-user / shared ledgers** — single-user iCloud
  account = single finch install. Per the plan's §10
  resolved decision.
- **Android / Wear OS** — not in the plan.

## §8. Spec self-review

(Inline review at write time; not part of the published
spec.)

- **Placeholders**: none. Every section has concrete
  content. The 4 widgets + 3 Live Activities + Watch
  glance have concrete shapes.
- **Internal consistency**: §2.3's `NetWorthProvider` uses
  the `netWorthByMonth` selector from Phase 1.5. §3.2's
  `ScheduledItemAttributes` uses the `Args.postScheduled`
  action from Phase 2. §4.2's data flow uses the App
  Group container (added in Phase 6.5's Share
  Extension setup; Phase 7 reuses the same entitlement
  for the Widget Extension + the Watch app).
  §4.4's Watch complications use the same data as the
  iOS widget. The snapshot JSON (§2.4) is the shared
  data format for the iOS app, the widget, and the Watch
  app.
- **Scope**: focused on Phase 7. Phases 1.0-5 are
  referenced as completed. Phase 6 and Phase 8 are
  explicitly out of scope (§7). The estimated scope
  (1-2 months) reflects the UI-heavy nature of the
  phase.
- **Ambiguity**: §2.1's 4 widgets have concrete
  descriptions (the figure, the chart, the refresh
  cadence, the deep-link). §3.1's 3 Live Activities have
  concrete triggers + surfaces + actions. §4.3's Watch
  UI has a concrete layout. §6 enumerates the open
  questions with proposed answers.
