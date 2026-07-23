# Swipe-action reset on navigation — design

**Status:** design, 2026-07-22. Grounded in an on-device prototype (throwaway `SwipeResetLab`,
iPhone simulator, iOS 17) and a full inventory of `.swipeActions` sites under
`ios/FinchApp/Sources/FinchApp/`.

## The bug

Swipe a `List` row open (revealing Delete / Edit / etc.), then navigate away via a control that
does **not** touch the list — switch tabs, or push a detail — and come back. The row is **still
swiped open**. The user expects it to close, the way it already does when you tap elsewhere on the
same screen. Reported across "most swipe actions".

Confirmed root behaviour on-device: this is standard SwiftUI. Tapping a *different row* already
closes the swipe correctly (iOS eats that tap); the bug is specifically navigation that leaves the
list mounted but off-screen, then returns to it.

## Findings from the prototype (what the design is grounded in, not guessed)

A DEBUG harness with switchable strategies, driven on the simulator:

| Finding | Evidence |
|---|---|
| **A list rebuild (`.id` change) is the *only* thing that closes a swiped-open row.** SwiftUI exposes no API to close a swipe. | `rebuild` strategy closed it; baseline stayed open. |
| **A programmatic `scrollTo` does NOT close a swipe** (unlike UIKit tables), and it moves scroll position for nothing. | `nudge` strategy: list scrolled, swipe stayed wide open. |
| **`.onDisappear` fires on navigate-away (while off-screen), `.onAppear` on return.** So the rebuild can happen off-screen → the close itself is flicker-free. | Lifecycle counters: `disappear` incremented on push, `appear` on pop. |
| **Rebuild is memory-flat — no leak.** Warmup aside, RSS plateaus across many rebuilds. | 20 cycles @ 40 rows: 278.2→278.5 MB. 15 cycles @ 5 000 rows: 417.6→418.0 MB (even dipped). Off-screen, so no dropped frames; 30 rapid navigations on a 5 000-row list stayed fully responsive. |
| **Rebuild's only real cost is scroll position resetting to the top** — invisible on short lists, jarring on long feeds. | `rebuild` on a bottom-scrolled list snapped back to row 0. |
| **Manual "top-visible-row" capture + async `scrollTo` on return restores scroll position** cleanly. | `keepScroll` strategy: left at row 17, returned to row 17, `token` bumped (swipe closed). |
| **iOS 17 `.scrollPosition(id:)` does NOT solve this on `List`.** It compiles at the iOS 17 floor but does not reliably track/restore the top row — restore snapped to row 0. | `scrollAPI` strategy failed; `token` bumped but position lost. → we use manual tracking, not the API. |

## What this builds — and what it deliberately does not

**Builds:** every `List` carrying `.swipeActions` closes any open swipe when the user navigates away
and returns, via an off-screen `.id()` rebuild wrapped in one shared modifier. The long transaction
feeds additionally preserve scroll position across that rebuild.

**Does not:**
- **Touch `EditTransactionSheet`** (`WriteScreens/EditTransactionSheet.swift:241`). Its receipt list
  is a `Form` inside a **modal sheet** — dismissed, not returned-to — so "reset on return" has no
  meaning. Out of scope.
- **Try to detect whether a swipe is actually open.** SwiftUI gives no signal. We always rebuild on
  navigate-away; the prototype proved this is free (memory-flat, off-screen, no jank), so gating it
  on "was something swiped" buys nothing.
- **Use `.scrollPosition(id:)`.** Disproven above.
- **Change the visuals, the actions, or `txnSwipeActions`' behaviour.** Only navigation-reset and
  scroll-restoration are added.

## Scope inventory

**Deployment floor: iOS 17.0 / macOS 14.0** (`ios/project.yml:4-7`, `ios/Package.swift:9`). The
`FinchMac` target shares these SwiftUI sources — **every new modifier must compile on macOS** (mind
the existing `#if os(iOS)` shims). No `ScrollViewReader` and no `.id()` on any `List` exist today —
green field.

### SHORT lists — base reset only (Phase 1)

Row count bounded by a *configuration set* the user maintains, so scroll-reset-to-top is a non-issue.
Inline `.swipeActions`, one screen each:

| Screen | File:line | Selection mode? |
|---|---|---|
| Accounts | `Tabs/AccountsTab.swift:191,192,210,211` | yes (`List(selection:)` + split) |
| Budgets | `Tabs/BudgetsTab.swift:171,172,190,191` | yes (mirrors Accounts) |
| Scheduled list | `Tabs/ScheduledTab.swift:79,85` | yes (`List(selection:)`) |
| Scheduled calendar | `Tabs/ScheduledCalendarView.swift:272,276` | no |
| Backups | `Tabs/SettingsBackupsView.swift:174,179` | no |
| Holdings | `WriteScreens/HoldingsView.swift:34` | no |
| Ledgers | `WriteScreens/LedgerManagementView.swift:65` | yes (`List(selection:)`) |
| Merchants | `PowerTools/MerchantsView.swift:131` | yes (`isSelecting`) |
| Rules | `PowerTools/RulesManagerView.swift:39,43` | no |
| FX history | `PowerTools/ExchangeRateHistoryView.swift:39` | no |
| Categories | `PowerTools/CategoriesView.swift:281` | no (reorder branch has no swipes) |
| Tags | `PowerTools/TagsView.swift:188` | yes (`isSelecting`) |

### LONG feeds — base reset **+ scroll preservation** (Phase 2)

Row count driven by *transaction volume* (paginated or unbounded). All five share the same shape:
`List` of a pinned "To confirm" `Section` + month `Section`s, rows are `TxRow` + the shared
`txnSwipeActions` helper (`Common/TxnSwipeActions.swift`, applied at each call site below). Row id =
`Tx.id` (`String`); month-section id = `MonthGrouping.Section.id` (`"yyyy-MM"` `String`) — both
`scrollTo`-suitable.

| Feed | Helper call | Notes |
|---|---|---|
| Activity feed | `Tabs/ActivityTab.swift:335` | `List(selection:)`, paginated 50/page, **multi-select + split-view selection** |
| Account detail | `WriteScreens/AccountDetailView.swift:226` | plain `List`, no selection — the simple case |
| Category detail | `PowerTools/CategoryDetailView.swift:78` | plain `List`, unbounded |
| Tag detail | `PowerTools/TagDetailView.swift:77` | plain `List`, unbounded |
| Merchant detail | `PowerTools/CounterpartyDetailView.swift:75` | plain `List`, unbounded |

## Design

### Component 1 — `resetsSwipeOnNavigation(enabled:)` (new, `Common/SwipeReset.swift`)

A `ViewModifier` applied to a `List`. Owns its rebuild token; bumps it off-screen on navigate-away:

```swift
extension View {
    /// Closes any open swipe-action row when the view leaves and returns, by rebuilding the
    /// List's identity while it is off-screen. Pass `enabled: false` to suppress the rebuild
    /// while an in-list selection/edit mode is active (a rebuild would drop that selection).
    func resetsSwipeOnNavigation(enabled: Bool = true) -> some View
}

private struct SwipeResetModifier: ViewModifier {
    let enabled: Bool
    @State private var token = 0
    func body(content: Content) -> some View {
        content
            .id(token)
            .onDisappear { if enabled { token &+= 1 } }
    }
}
```

- `.id(token)` gives the List an identity that changes when `token` bumps → fresh List, swipes
  closed. `&+=` (wrapping) is defensive against a theoretical overflow; harmless.
- The bump fires in `.onDisappear` — the list is off-screen (covered by the pushed page / hidden
  tab), so the fresh identity is built before the user sees it again. Flicker-free.
- **`enabled:`** lets a screen with an active in-list selection suppress the rebuild, which would
  otherwise reset `selected` / `kbSel` / the split-view detail column. Callers with a selection
  mode pass `enabled: !isSelecting` (and, for split lists, `&& selection == nil`); callers without
  one omit it (defaults to `true`).
- Compiles unchanged on macOS (pure SwiftUI).

Applied to all 12 short-list `List`s and all 5 feed `List`s.

### Component 2 — scroll preservation for the five feeds (`Common/SwipeReset.swift`)

The base modifier alone would reset a feed to the top on every navigation. To preserve position we
add, per feed:

1. **Wrap the feed's `List` in a `ScrollViewReader`** (none exists today) to get a `scrollTo` proxy.
2. **Track the top-visible row.** Each `TxRow` reports visibility into a `Set<String>` of visible
   `Tx.id`s (`.onAppear`/`.onDisappear`). The **topmost** visible id = the first id in the feed's
   already-known display order (`sections.flatMap { pending + $0.txns }`) that is in the set.
   Maintain a `topAnchor: String?` updated on row **appear only** (not on disappear) so teardown's
   disappear events don't clobber it — the anchor survives navigate-away holding the last on-screen
   top. *(This is the proven `keepScroll` mechanism, adapted from flat-Int order to id-in-display-
   order because the feeds are sectioned.)*
3. **On the List's `.onDisappear`:** capture `savedAnchor = topAnchor`, then bump the rebuild token
   (Component 1's job — the feed uses the same token).
4. **On the List's `.onAppear`:** if `savedAnchor != nil`, `DispatchQueue.main.async { proxy.scrollTo(savedAnchor, anchor: .top) }`. The `async` lets the rebuilt list lay out first.

Packaged so the feed's row and List opt in with minimal surface — a small companion modifier
(e.g. `.tracksTopRow(id:in:)` on the row and `.preservesScrollAcrossReset(order:anchor:)` on the
List) rather than open-coding the four steps in each of the five files. Exact API finalised in the
plan; the four behaviours above are the contract.

### ActivityTab selection gating (the one real risk)

`ActivityTab` (`ActivityFeedView`) has an in-list **multi-select** (`isSelecting`, `selected:
Set<String>`, bottom action bar) and a **split-view / keyboard selection** (`selection`, `kbSel`).
It already resets multi-select on disappear (`ActivityTab.swift:159`). Its swipe-reset must pass
`enabled: !isSelecting && selection == nil` so a rebuild never fires mid-selection. The other four
feeds have no selection mode; Account/Category/Tag/Merchant detail are the clean case.

## Phasing

Two phases, each independently shippable; **Phase 1 can merge on its own.**

- **Phase 1 — short lists (12 screens).** Apply `resetsSwipeOnNavigation(...)` to each. No scroll
  concern; pass `enabled: !isSelecting`/`selection == nil` on the six with a selection mode. Trivial,
  low-risk, covers most swipe screens.
- **Phase 2 — long feeds (5 screens).** Base reset + Component 2 scroll preservation + ActivityTab
  gating. Delicate; **acceptance requires eyeballing the real Activity feed on a device** to confirm
  the async restore shows no top-of-list flash and that multi-select / split-view are undisturbed.

## Decisions

| decision | value | rationale |
|---|---|---|
| Close mechanism | `.id()` rebuild | Only thing that closes a SwiftUI swipe (prototype). |
| Rebuild trigger | `.onDisappear` bump | Fires off-screen → flicker-free; proven to fire on push/tab-switch. |
| Always rebuild vs detect-open | always | No open-state signal exists; rebuild is free (memory-flat, off-screen). |
| Scroll restore | manual top-row capture + async `scrollTo` | Proven; `.scrollPosition(id:)` unreliable on iOS 17 `List`. |
| Scroll restore scope | 5 long feeds only | Short lists have nothing to scroll. |
| Selection safety | `enabled:` gate | Rebuild would drop `selected`/`kbSel`/split-view selection. |
| Packaging | one shared modifier (+ feed companion) | DRY across 17 `List`s; no per-screen ad-hoc `.id` juggling. |
| `EditTransactionSheet` | excluded | Modal `Form`, dismissed not returned-to. |

## Testing

- **Unit:** extract the topmost-visible computation as a pure helper —
  `topVisibleID(order: [String], visible: Set<String>) -> String?` (first of `order` present in
  `visible`) — and unit-test it (empty set → nil; respects order; ignores stale ids). This is the
  only non-trivial pure logic; the rest is view wiring.
- **Manual / UI:** per screen — swipe a row, navigate away (tab switch and push where applicable),
  return, assert the row is closed. For the five feeds additionally assert scroll position is
  preserved. For ActivityTab, repeat while in multi-select and split-view and assert selection is
  intact and no rebuild-to-top occurs.
- **Device:** Phase 2 acceptance — watch the Activity feed restore for a top-of-list flash.

## Rejected alternatives

- **Scroll-nudge** (programmatic `scrollTo` to close the swipe) — disproven on-device; scrolling
  doesn't close SwiftUI swipes.
- **`.scrollPosition(id:)`** for scroll preservation — compiles at iOS 17 but doesn't reliably
  track/restore on `List`; disproven on-device.
- **Per-screen inline `.id` + `.onDisappear`** — not DRY across 17 lists; a shared modifier is one
  place to fix and reason about.
- **Detecting an open swipe to rebuild only when needed** — no SwiftUI signal, and rebuild is free.

## Files

- **New:** `ios/FinchApp/Sources/FinchApp/Common/SwipeReset.swift` (Component 1 + 2 + pure helper),
  `ios/FinchApp/Tests/.../SwipeResetTests.swift` (helper unit tests).
- **Modify (Phase 1, 12):** `Tabs/AccountsTab.swift`, `Tabs/BudgetsTab.swift`, `Tabs/ScheduledTab.swift`,
  `Tabs/ScheduledCalendarView.swift`, `Tabs/SettingsBackupsView.swift`, `WriteScreens/HoldingsView.swift`,
  `WriteScreens/LedgerManagementView.swift`, `PowerTools/MerchantsView.swift`, `PowerTools/RulesManagerView.swift`,
  `PowerTools/ExchangeRateHistoryView.swift`, `PowerTools/CategoriesView.swift`, `PowerTools/TagsView.swift`.
- **Modify (Phase 2, 5):** `Tabs/ActivityTab.swift`, `WriteScreens/AccountDetailView.swift`,
  `PowerTools/CategoryDetailView.swift`, `PowerTools/TagDetailView.swift`, `PowerTools/CounterpartyDetailView.swift`.
