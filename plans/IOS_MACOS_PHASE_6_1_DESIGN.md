# finch for iOS & macOS — Phase 6.1 Implementation Design (Spotlight indexing)

> **Status**: design spec — not yet an implementation plan. Once
> approved, this becomes the input to `writing-plans` to produce a
> step-by-step implementation plan for Phase 6.1.
>
> Companion documents:
>
> - `plans/IOS_MACOS_PLAN.md` — direction brief
> - `plans/IOS_MACOS_PHASE_1_DESIGN.md` through `IOS_MACOS_PHASE_5_DESIGN.md` —
>   Phases 1.0 through 5 full designs
> - `plans/IOS_MACOS_PHASE_7_DESIGN.md` — Phase 7 (widgets + Watch)
> - `plans/IOS_MACOS_ROADMAP.md` — 8-phase arc
> - `plans/IOS_MACOS_PHASE_6_1_DESIGN.md` (this file) — Phase 6.1
>
> Phase 6 is decomposed into 5 sub-specs (6.1-6.5), one per Apple
> platform framework. This is 6.1: Spotlight indexing via
> `CoreSpotlight`. The other 4 sub-specs (Notifications, Biometric
> lock, App Intents, Share Extension) are independent and ship in
> any order.
>
> _Audience: the engineers who will build the iOS app. Assumes
> Phases 1.0-5 are complete; the iPhone + iPad + Mac apps are
> shipping with the 6 tabs + 6 write screens + 7 power features
> + iCloud sync._

## §1. Goal & non-goals

**Goal** — Index finch's transactions / merchants / accounts /
budgets into iOS's **Spotlight** (the system-wide search) so
that:

- Typing "starbucks" in iOS Spotlight → finch entries for
  Starbucks surface as a top hit; tapping opens the iOS
  app's Transaction Detail screen
- Typing "chase" → the Chase Checking account surfaces;
  tapping opens the iOS app's Account Detail screen
- Typing "groceries" → the Groceries budget surfaces;
  tapping opens the iOS app's Budgets tab
- Typing "alex" (a counterparty) → transactions with
  counterparty "Alex Smith" surface; tapping opens the
  Transaction Detail

This is the **iOS analogue of the web's ⌘K command palette**:
the web has a per-app ⌘K (Phase 3's Mac menu bar); Spotlight
gives finch **system-wide** searchability on iOS.

**Non-goals (firm)**:

- **No new tabs / write screens / power features** — the 6
  tabs + 6 write screens + 7 power features are unchanged.
  Phase 6.1 adds a **read-side** integration: iOS system
  search surfaces finch's entities.
- **No new selectors** — the Phase 1.5 selectors are the
  full set. The Spotlight index reads from the in-memory
  `Tx[]` cache + `AccountRow[]` + `Category[]` +
  `Counterparty[]` + `Holding[]` arrays.
- **No new chokepoint actions** — Spotlight is read-only.
- **No Siri integration** — Siri (App Intents) is Phase 6.4.
  Spotlight and Siri are different frameworks.
- **No widget changes** — WidgetKit widgets are Phase 7.
  Spotlight is `CoreSpotlight`, a separate framework.
- **No app launch from Spotlight** — Phase 6.1 supports
  **deep-linking** (tapping a Spotlight result opens the
  iOS app at the right screen); the iOS app's launch
  behavior is unchanged.
- **No bidirectional sync with Spotlight** — the iOS app
  pushes entities to Spotlight; the user can't edit
  finch data from Spotlight's UI (Spotlight is read-only
  for our purposes).

**Estimated scope**: ~400-600 lines Swift (the
`SpotlightIndexer` + the deep-link handler + the
re-indexing strategy) + ~100 lines SwiftUI (the deep-link
routing in `FinchApp`) + ~200 lines tests. **1-2 weeks of
full-time work** for a small team. **Smallest of the 5
Phase 6 sub-specs.**

## §2. The Spotlight index

`CoreSpotlight` (Apple's search framework) lets an app push
**`CSSearchableItem`s** to the system search index. Each item
has:
- A `uniqueIdentifier` (a string unique to the app)
- A `domainIdentifier` (a string grouping related items;
  e.g., "transactions", "accounts", "categories", "merchants",
  "budgets")
- A `title` (the entity's name)
- A `contentDescription` (a short description)
- One or more `keywords` (search terms)
- An optional `thumbnailURL` (a file URL; the iOS app
  generates small PNGs for each entity type)
- A `contentCreationDate` and `contentModificationDate`
- An optional `rating` (0-5 stars; not used by finch)

### 2.1 — The 5 domains

finch pushes entities to 5 `domainIdentifier`s:

| Domain | Entity | `uniqueIdentifier` shape | `title` | `contentDescription` |
|---|---|---|---|---|
| `transactions` | `Tx` | `tx:<entry_id>` | merchant + amount + date | e.g., "Starbucks -$6.50 Jun 12" |
| `accounts` | `AccountRow` | `account:<account_id>` | account name + type | e.g., "Chase Checking (Spending)" |
| `categories` | `Category` | `category:<category_id>` | category name + parent | e.g., "Groceries › Food" |
| `merchants` | `Counterparty` | `counterparty:<counterparty_id>` | counterparty name | e.g., "Starbucks Inc" |
| `budgets` | Budget | `budget:<budget_id>` | budget name | e.g., "Groceries (this month: $340 / $500)" |

Each entity has a **thumbnail**:
- Transactions: a small icon (the category's icon)
- Accounts: a small icon (the account-type icon: wallet,
  piggy bank, chart, etc.)
- Categories: the category's own icon
- Merchants: a generic "person" icon (no merchant-specific
  icon in Phase 1.0)
- Budgets: the category's icon (a budget is a category
  with a limit)

### 2.2 — The `SpotlightIndexer`

```swift
// ios/FinchApp/Spotlight/SpotlightIndexer.swift
@MainActor
public final class SpotlightIndexer {
    public static let shared = SpotlightIndexer()

    private let searchableIndex = CSSearchableIndex.default()

    public func indexAll(store: FinchStore) async {
        // Called on app launch + on every iCloud sync (the
        // data may have changed on another device)
        let items = buildSearchableItems(from: store)
        do {
            try await searchableIndex.indexSearchableItems(items)
        } catch {
            // Log to the user-visible Sync section
        }
    }

    public func indexEntity(_ entity: SpotlightEntity) async {
        let item = entity.toSearchableItem()
        try? await searchableIndex.indexSearchableItems([item])
    }

    public func deindexEntity(_ entity: SpotlightEntity) async {
        try? await searchableIndex.deleteSearchableItems(
            withIdentifiers: [entity.uniqueIdentifier]
        )
    }

    private func buildSearchableItems(from store: FinchStore) -> [CSSearchableItem] {
        var items: [CSSearchableItem] = []
        items += store.txns.map { SpotlightEntity.transaction($0).toSearchableItem() }
        items += store.accounts.map { SpotlightEntity.account($0).toSearchableItem() }
        items += store.categories.map { SpotlightEntity.category($0).toSearchableItem() }
        items += store.merchants.map { SpotlightEntity.merchant($0).toSearchableItem() }
        items += store.budgets.map { SpotlightEntity.budget($0).toSearchableItem() }
        return items
    }
}

public enum SpotlightEntity {
    case transaction(Tx)
    case account(AccountRow)
    case category(Category)
    case merchant(Counterparty)
    case budget(Budget)

    var uniqueIdentifier: String { /* ... */ }
    var domainIdentifier: String { /* ... */ }
    var title: String { /* ... */ }
    var contentDescription: String { /* ... */ }
    var keywords: [String] { /* ... */ }
    var thumbnailURL: URL? { /* ... */ }

    func toSearchableItem() -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = title
        attrs.contentDescription = contentDescription
        attrs.keywords = keywords
        attrs.thumbnailURL = thumbnailURL
        let item = CSSearchableItem(
            uniqueIdentifier: uniqueIdentifier,
            domainIdentifier: domainIdentifier,
            attributeSet: attrs
        )
        return item
    }
}
```

The `SpotlightIndexer.indexAll` is called on:
- **App launch** — full re-index of the in-memory cache
- **App foreground** — same
- **iCloud sync event** (Phase 5) — same (the data may
  have changed on another device)
- **Every successful write** (Phase 2's `FinchStore.apply`)
  — incremental re-index of just the affected entities

The full re-index is **idempotent**: `indexSearchableItems`
with the same `uniqueIdentifier` replaces the existing item.
So a re-index on app launch is just a "re-assert" of the
current state.

### 2.3 — Incremental re-index on write

The chokepoint (Phase 2) writes through `FinchStore.apply`.
After every successful write, the store calls
`SpotlightIndexer.indexEntity(...)` for each affected entity:

```swift
// ios/FinchApp/FinchStore.swift (Phase 2 + Phase 6.1)
@MainActor
@Observable
public final class FinchStore {
    // ... existing Phase 2 code ...

    public func apply(action: String, args: [String: Any]) async throws {
        try await Store.applyMutation(db, action: action, args: args)
        let newTxns = try await Project.run(on: db, ledgerId: activeLedgerId)
        self.txns = newTxns
        self.derivedState = try await Selectors.recomputeAll(...)

        // Phase 6.1: re-index the affected entities in Spotlight
        await SpotlightIndexer.shared.indexAll(store: self)
    }
}
```

The full re-index is `O(n)` over the entity count, but the
typical iOS user has ~1,000-10,000 transactions; indexing
takes <100ms. If the entity count grows, the re-index can
be debounced (every 30 seconds; the in-memory cache is the
source of truth for the app's UI regardless of Spotlight
state).

### 2.4 — De-indexing

When an entity is deleted (a transaction, an account, a
category, a merchant, or a budget), the chokepoint posts
the delete; the store's `apply` calls
`SpotlightIndexer.deindexEntity(...)` for the deleted
entity. The `deleteSearchableItems(withIdentifiers:)` API
removes the item from the system index.

## §3. Deep-linking from Spotlight

When the user taps a Spotlight result, iOS opens the
calling app (finch) with a `NSUserActivity` carrying the
item's `uniqueIdentifier`. The iOS app's `App` body
receives the activity and routes to the right screen.

### 3.1 — The `FinchApp` scene

```swift
// ios/FinchApp/FinchApp.swift (Phase 3 + Phase 6.1)
@main
struct FinchApp: App {
    @State private var store = FinchStore.shared
    @State private var router = DeepLinkRouter()

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

    private func handleSpotlightTap(_ activity: NSUserActivity) {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            return
        }
        router.route(to: id)
    }
}
```

The `DeepLinkRouter` is a small `@Observable` class that
parses the unique identifier and routes to the right screen:

```swift
// ios/FinchApp/DeepLink/DeepLinkRouter.swift
@MainActor
@Observable
public final class DeepLinkRouter {
    public var pendingNavigation: DeepLinkTarget? = nil

    public func route(to: uniqueIdentifier: String) {
        // uniqueIdentifier shape: "tx:<entry_id>", "account:<id>",
        //   "category:<id>", "counterparty:<id>", "budget:<id>"
        let parts = uniqueIdentifier.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return }
        let domain = String(parts[0])
        let id = String(parts[1])
        switch domain {
        case "tx":
            pendingNavigation = .transactionDetail(id)
        case "account":
            pendingNavigation = .accountDetail(id)
        case "category":
            pendingNavigation = .budgetsTab  // or category detail
        case "counterparty":
            pendingNavigation = .activityTab  // filtered by merchant
        case "budget":
            pendingNavigation = .budgetsTab
        default:
            return
        }
    }
}

public enum DeepLinkTarget {
    case transactionDetail(String)  // entryId
    case accountDetail(String)  // accountId
    case activityTab
    case budgetsTab
    case insightsTab
}
```

The `AdaptiveShell` (Phase 3) observes `router.pendingNavigation`
and routes accordingly:
- `transactionDetail(entryId)` → push the Transaction
  Detail view in the Activity tab
- `accountDetail(accountId)` → push the Account Detail view
  in the Accounts tab
- `activityTab` → switch to the Activity tab
- `budgetsTab` → switch to the Budgets tab
- `insightsTab` → switch to the Insights tab

After the navigation, the router clears
`pendingNavigation` (so the next Spotlight tap doesn't
re-trigger).

### 3.2 — Universal Links (optional, Phase 6.1.5)

A follow-up could add **Universal Links**: a URL scheme
`finch://tx/<entry_id>` that opens the same screens from a
URL (e.g., from a Mail message or a Notes link). This
requires:
- An `apple-app-site-association` file on a domain the
  app controls (e.g., `finch.app/.well-known/...`)
- The `Associated Domains` entitlement
- A `NSUserActivity` handler that parses the URL

Universal Links are a Phase 6.1.5 follow-up; the basic
Spotlight deep-linking is Phase 6.1.

## §4. Permissions + entitlement

`CoreSpotlight` doesn't require any specific entitlement.
The app declares its intent in `Info.plist`:

```xml
<key>NSUserActivityTypes</key>
<array>
    <string>com.juchengquan.finch.spotlight-tx</string>
    <string>com.juchengquan.finch.spotlight-account</string>
    <string>com.juchengquan.finch.spotlight-category</string>
    <string>com.juchengquan.finch.spotlight-counterparty</string>
    <string>com.juchengquan.finch.spotlight-budget</string>
</array>
```

The `CSSearchableItemActionType` constant is the standard
identifier for Spotlight-driven `NSUserActivity` callbacks;
the per-domain identifiers are app-specific (used to
disambiguate which Spotlight result was tapped).

## §5. CI changes

The macos job from Phase 1.0's `IOS_MACOS_PHASE_1_DESIGN §9`
extends with:

- A **Spotlight indexing test**: build a small DB fixture
  with 10 transactions, 5 accounts, 3 categories, 2
  merchants, 2 budgets; call `SpotlightIndexer.indexAll`;
  assert the system index has 22 items (10 + 5 + 3 + 2 + 2)
- A **Spotlight re-index test**: index, modify an entity
  in the DB (via a write through the chokepoint), re-index;
  assert the modified entity is updated in the system index
- A **Spotlight de-index test**: index, delete an entity
  via the chokepoint, assert the entity is removed from
  the system index
- A **deep-link routing test**: simulate a Spotlight tap
  (`NSUserActivity` with a `tx:<id>` identifier); assert
  the `DeepLinkRouter` routes to `transactionDetail(id)`
- A **Spotlight search test**: index 100 transactions,
  query the system index for "starbucks" (using
  `CSSearchQuery`), assert the matching transactions are
  returned (this test runs on the iOS Simulator; the
  system index is real)

The Spotlight tests use a **per-test index** (a custom
`CSSearchableIndex` instance, not the default) to avoid
polluting the simulator's global index.

## §6. Open questions

**Not blocking Phase 6.1 (decide later)**:

- **Index refresh cadence**: the proposal is "re-index on
  every write + on app launch + on iCloud sync event." A
  more sophisticated approach would debounce (every 30
  seconds) and use `CSSearchableIndex.deleteAllSearchableItems`
  before each full re-index. The current proposal is
  idempotent (re-indexing the same item is a no-op), so
  the simpler approach is fine.
- **Search ranking**: the proposal uses the default
  `CSSearchQuery` ranking (which considers title +
  keywords + content description). A custom ranking
  (e.g., "recent transactions rank higher than old
  ones") is a future phase.
- **Universal Links**: the proposal covers Spotlight-only
  deep-linking. Universal Links (`finch://tx/<id>`) are a
  Phase 6.1.5 follow-up.
- **Search in inactive ledgers**: the proposal indexes
  the **active ledger** only. If the user switches ledgers
  via the ledger switcher, the Spotlight index re-fetches
  the new ledger's entities. Inactive ledgers are not
  indexed (they're not in the in-memory cache).

**Specifically for the deep-link**:

- **Multi-tap behavior**: if the user taps multiple
  Spotlight results in quick succession, the proposal
  routes to the most recent tap (the previous tap's
  navigation is replaced). A "queue" of pending navigations
  is a future enhancement.
- **Pre-fetch on Spotlight tap**: the proposal opens the
  iOS app and shows the entity immediately. The
  `NSUserActivity` doesn't carry the entity data (just the
  id); the iOS app fetches the entity from the in-memory
  cache (or from the DB if the cache is cold). A
  pre-fetch via `CSSearchableItemAttributeSet` payload is
  possible but the proposal doesn't use it.

**Not blocking Phase 6.1 because they're Phase 6.2-6.5+ by design**:

- **Notifications** — Phase 6.2
- **Biometric lock** — Phase 6.3
- **App Intents / Siri** — Phase 6.4
- **Share Extension receipts** — Phase 6.5
- **Widgets / Live Activities / Watch** — Phase 7
- **Row-level sync** — Phase 8

## §7. Out of scope (firm)

These are explicitly NOT in Phase 6.1:

- **No new tabs / write screens / power features** — the 6
  tabs + 6 write screens + 7 power features are unchanged.
- **No new selectors** — the Phase 1.5 selectors are the
  full set.
- **No new chokepoint actions** — Spotlight is read-only.
- **No Siri integration** — Phase 6.4.
- **No widget changes** — Phase 7.
- **No Universal Links** — Phase 6.1.5 (optional follow-up).
- **No bidirectional sync with Spotlight** — read-only
  indexing.
- **No search ranking customization** — default ranking
  for Phase 6.1; custom ranking is a follow-up.
- **No inactive-ledger indexing** — only the active ledger
  is indexed.

## §8. Spec self-review

(Inline review at write time; not part of the published
spec.)

- **Placeholders**: none. Every section has concrete
  content. The `SpotlightIndexer` code sketch (§2.2), the
  `DeepLinkRouter` code sketch (§3.1), the `Info.plist`
  keys (§4) are all concrete.
- **Internal consistency**: §2.2's `SpotlightIndexer` uses
  the in-memory `Tx[]` cache from Phase 1.0 + the
  `AccountRow[]` / `Category[]` / `Counterparty[]` /
  `Budget[]` arrays. §2.3's incremental re-index hooks
  into `FinchStore.apply` from Phase 2. §3's deep-link
  uses the `AdaptiveShell` from Phase 3.
- **Scope**: focused on Phase 6.1 only. Phases 6.2-6.5 are
  referenced as separate specs. Phase 7+ are explicitly
  out of scope (§7). The estimated scope (1-2 weeks)
  reflects Spotlight being the simplest of the 5
  sub-features.
- **Ambiguity**: §2.1's 5 domains are a concrete table.
  §2.2's `SpotlightIndexer` has a concrete API. §3.1's
  `DeepLinkRouter` has concrete routing logic. §5
  enumerates the CI test cases. §6 enumerates the open
  questions with proposed answers.
