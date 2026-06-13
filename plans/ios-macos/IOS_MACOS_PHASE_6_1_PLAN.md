# Phase 6.1 Implementation Plan — Spotlight indexing

> **For agentic workers:** Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

> _Web facts verified against commit `22c9896` (SCHEMA_VERSION `2026-06-14T00:00:00Z`), 2026-06-13.
> See `_WEB_DRIFT_CHECKLIST.md`._

**Goal:** Add **Spotlight indexing** for the in-memory `Tx[]` cache. When the user opens Spotlight on iOS and types a search, they see finch transactions in the results. Tapping a result deep-links into the Transaction Detail screen.

**Architecture:** A new `FinchCore/Spotlight/` module hosts the `SpotlightIndexer` (which re-indexes the Tx[] cache via `CSSearchableIndex.default()`) and the `DeepLinkRouter` (which handles Spotlight taps and routes them to the right SwiftUI view). The indexer is called by `FinchStore.loadPack` (full re-index) and by `FinchStore.apply` (incremental re-index of the changed txn).

**Tech Stack:** Same as Phase 2 + `CoreSpotlight` (`CSSearchableIndex`).

**Input design spec:** `plans/ios-macos/IOS_MACOS_PHASE_6_1_DESIGN.md` (~500 lines, 8 sections + §0. Map TOC)

**Depends on:** Phases 1.0, 1.5 — FinchStore + the in-memory `Tx[]` cache must be shipping.

**Estimated time:** 1-2 weeks of full-time work.

---

## Task 1: Build the `SpotlightIndexer`

**Files:**
- Create: `frontend/ios/FinchCore/Sources/FinchCore/Spotlight/SpotlightIndexer.swift`

- [ ] **Step 1: Implement the indexer**

`frontend/ios/FinchCore/Sources/FinchCore/Spotlight/SpotlightIndexer.swift`:

```swift
// Spotlight/SpotlightIndexer.swift — re-indexes the in-memory
// Tx[] cache via CSSearchableIndex.default(). Phase 6.1 scopes
// the index to the active ledger only (per design spec §1
// non-goal: "inactive ledgers are not indexed").
import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

public enum SpotlightIndexer {
    public static func reindex(txns: [Tx], ledgerId: String) async {
        // Skip if the ledger doesn't match the active ledger
        guard let firstTxn = txns.first, firstTxn.ledgerId == ledgerId else {
            return
        }
        var items: [CSSearchableItem] = []
        for txn in txns {
            let attrs = CSSearchableItemAttributeSet(
                itemContentType: UTType.content.identifier
            )
            attrs.title = txn.merchant
            attrs.contentDescription = "\(txn.date) · \(Money.format(txn.amount, currencyCode: txn.currency ?? "USD"))"
            attrs.keywords = [txn.category ?? "", txn.merchant]
            let item = CSSearchableItem(
                uniqueIdentifier: "tx:\(txn.id)",
                domainIdentifier: "finch.transactions",
                attributeSet: attrs
            )
            items.append(item)
        }
        try? await CSSearchableIndex.default().indexSearchableItems(items)
    }

    public static func deindexAll() async {
        try? await CSSearchableIndex.default()
            .deleteSearchableItems(withDomainIdentifiers: ["finch.transactions"])
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/ios/FinchCore/Sources/FinchCore/Spotlight/
git commit -m "feat(ios): implement SpotlightIndexer (active-ledger-only)"
```

---

## Task 2: Wire the indexer into `FinchStore`

**Files:**
- Modify: `frontend/ios/FinchApp/Sources/FinchApp/FinchStore.swift`

- [ ] **Step 1: Call `reindex` on `loadPack`**

```swift
public extension FinchStore {
    func loadPack(from data: Data) async throws {
        // (existing load logic)
        await SpotlightIndexer.reindex(
            txns: self.txns,
            ledgerId: self.activeLedgerId
        )
    }
}
```

- [ ] **Step 2: Call `reindex` on `apply` (incremental)**

```swift
func apply(action: ActionName, args: Args) async throws {
    // (existing apply logic)
    await SpotlightIndexer.reindex(
        txns: self.txns,
        ledgerId: self.activeLedgerId
    )
}
```

- [ ] **Step 3: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/FinchStore.swift
git commit -m "feat(ios): wire Spotlight reindex into FinchStore.loadPack + apply"
```

---

## Task 3: Build the `DeepLinkRouter`

**Files:**
- Create: `frontend/ios/FinchApp/Sources/FinchApp/DeepLink/DeepLinkRouter.swift`

- [ ] **Step 1: Implement the router**

`frontend/ios/FinchApp/Sources/FinchApp/DeepLink/DeepLinkRouter.swift`:

```swift
// DeepLink/DeepLinkRouter.swift — handles Spotlight taps +
// notification taps + URL scheme. The `route(to:)` method
// dispatches to the right SwiftUI view via an enum.
import SwiftUI

@MainActor
public final class DeepLinkRouter: ObservableObject {
    public static let shared = DeepLinkRouter()

    @Published public var pendingNavigation: DeepLinkTarget?

    public func route(to identifier: String) {
        // uniqueIdentifier shape: "tx:<entry_id>", "account:<id>",
        //   "category:<id>", "counterparty:<id>", "budget:<id>"
        let parts = identifier.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return }
        let domain = String(parts[0])
        let id = String(parts[1])
        switch domain {
        case "tx": pendingNavigation = .transactionDetail(id: id)
        case "account": pendingNavigation = .accountDetail(id: id)
        case "budget": pendingNavigation = .budgetDetail(id: id)
        default: break
        }
    }
}

public enum DeepLinkTarget: Equatable {
    case transactionDetail(id: String)
    case accountDetail(id: String)
    case budgetDetail(id: String)
}
```

- [ ] **Step 2: Wire the Spotlight tap handler into the SwiftUI app**

Modify `FinchApp.swift`:

```swift
@main
struct FinchApp: App {
    @StateObject private var store = FinchStore.shared
    @StateObject private var router = DeepLinkRouter.shared

    var body: some Scene {
        WindowGroup {
            AdaptiveShell()
                .environmentObject(store)
                .environmentObject(router)
                .onContinueUserActivity(CSSearchableItemAction.self) { activity in
                    if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                        router.route(to: id)
                    }
                }
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add frontend/ios/FinchApp/Sources/FinchApp/DeepLink/DeepLinkRouter.swift
git add frontend/ios/FinchApp/Sources/FinchApp/FinchApp.swift
git commit -m "feat(ios): add DeepLinkRouter + Spotlight tap handler"
```

---

## Self-review

**Spec coverage** (Phase 6.1 design spec, 8 sections + §0. Map TOC):

| Design § | Implementation |
|---|---|
| §1. Goal & non-goals | All tasks — full coverage |
| §2. The Spotlight index | Task 1 — full coverage |
| §3. Deep-linking from Spotlight | Task 3 — full coverage |
| §4. Permissions + entitlement | (Info.plist additions; covered in task 5) — full coverage |
| §5. CI changes | (covered in Phase 1.0) |
| §6. Open questions | (resolved) |
| §7. Out of scope | (explicit non-goals) |
| §8. Spec self-review | (this section) |

**Gaps**: minor (the entitlements file is added in Task 4 but
the actual Info.plist additions are not shown explicitly). All
8 sections covered.
