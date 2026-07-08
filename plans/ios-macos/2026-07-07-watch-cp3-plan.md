# Watch CP3 — on-wrist quick-add — Implementation Plan

> **Post-#417 addendum (2026-07-07).** The quick-add **templates** increment (#417, design record `2026-07-07-watch-quickadd-templates-design.md`) landed while this plan was in review and pre-delivered parts of it: Task 3's dedupe ring (`QuickAddDedupe`, exact key/semantics) + the `didReceiveUserInfo` receive path + the pending-status policy all exist. The composer implementation therefore **reuses `WatchQuickAddRequest` as the up-wire type** (gaining an optional `createdAt` for the tap date) instead of adding the parallel `WatchQuickAddPayload` below — one wire type, one receive path for templates + composer. Everything else (catalog §1, composer UI §4, staleness fallbacks §3) implemented as specced.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Log an expense from the watch: amount + category composer → `transferUserInfo` over the CP1 session → phone dedupes and applies it via `store.apply(.addTransaction)` as a **pending** transaction → the existing snapshot push updates the glance/complication as the ack.

**Architecture:** Two shared Foundation-only additions (`WatchQuickAddCatalog` on the snapshot payload, down; `WatchQuickAddPayload`, up). Phone: catalog built where the snapshot is already built (`WidgetSnapshotWriter`), receive + dedupe + apply in `PhoneWatchLink`. Watch: a `QuickAddView` reached from the glance toolbar.

**Tech Stack:** Swift / SwiftUI / WatchConnectivity; XcodeGen (`ios/project.yml`, no target changes expected); XCTest (`FinchAppTests`). Spec: `plans/ios-macos/2026-07-07-watch-cp3-spec.md`.

## Global Constraints

- Watch stays **FinchCore-free**; shared files (`ios/Shared/*`) stay Foundation-only (no SwiftUI/WidgetKit/WatchConnectivity imports) — they compile into FinchApp, FinchMac, FinchWatch, and FinchWatchComplication.
- All new phone-side WCSession code lives inside the existing `#if os(iOS)` guards (`PhoneWatchLink.swift` is already wrapped; keep it that way). Build FinchMac to prove it.
- `WatchSnapshotPayload.quickAdd` MUST be optional with no bespoke `init(from:)` — wire back-compat both directions relies on default Codable synthesis ignoring/omitting the key.
- Quick-adds apply with `status: "pending"` and `amount = -abs(...)` — wrist entries are provisional expenses; the phone's Pending review is the confirm/edit surface.
- Dedupe before apply — `transferUserInfo` can redeliver; a replayed `id` must be a no-op.
- Run from `ios/` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `xcodegen generate` after adding files. Builds: FinchApp (iOS sim), FinchMac (`-destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`), FinchWatch (`-destination 'generic/platform=watchOS Simulator'`).
- No new dependencies. No FinchCore schema/selector changes.

---

### Task 1: Shared wire types — catalog + quick-add payload

**Files:**
- Modify: `ios/Shared/WatchSnapshotPayload.swift` (add `WatchQuickAddCatalog` + optional `quickAdd` field)
- Create: `ios/Shared/WatchQuickAddPayload.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/WatchQuickAddPayloadTests.swift`

- [ ] **Step 1: Failing tests** — round-trip both types; **decode an OLD snapshot payload (no `quickAdd` key) → succeeds with `nil`**; decode garbage → nil:

```swift
import XCTest
@testable import FinchApp

final class WatchQuickAddPayloadTests: XCTestCase {
    func test_quickAddPayload_roundTrip() throws {
        let p = WatchQuickAddPayload(id: "u-1", ledgerId: "personal", accountId: "a1",
                                     categoryId: "c1", amount: 12.5,
                                     createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let back = try XCTUnwrap(WatchQuickAddPayload.decode(XCTUnwrap(p.encoded())))
        XCTAssertEqual(p, back)
    }

    func test_snapshotPayload_withCatalog_roundTrip() throws {
        var s = WatchSnapshotPayload(netWorth: 1, currency: "USD", budgetUsedPct: 1,
                                     weeklySpent: 1, generatedAt: .now)
        s.quickAdd = WatchQuickAddCatalog(ledgerId: "personal", accountId: "a1", accountName: "Checking",
                                          categories: [.init(id: "c1", name: "Food")])
        let back = try XCTUnwrap(WatchSnapshotPayload.decode(XCTUnwrap(s.encoded())))
        XCTAssertEqual(s, back)
    }

    func test_snapshotPayload_legacyWire_decodesWithNilCatalog() throws {
        // A CP1/CP2-era payload has no quickAdd key — must still decode.
        let legacy = WatchSnapshotPayload(netWorth: 2, currency: "USD", budgetUsedPct: 3,
                                          weeklySpent: 4, generatedAt: .now)
        let back = try XCTUnwrap(WatchSnapshotPayload.decode(XCTUnwrap(legacy.encoded())))
        XCTAssertNil(back.quickAdd)
    }

    func test_quickAddPayload_garbageReturnsNil() {
        XCTAssertNil(WatchQuickAddPayload.decode(Data([0x00, 0x01])))
    }
}
```

- [ ] **Step 2: Run to confirm compile failure** (types missing), same `-only-testing:` command shape as the CP1/CP2 plans.

- [ ] **Step 3: Implement the types** — `WatchQuickAddCatalog` (+ nested `Item`) and `var quickAdd: WatchQuickAddCatalog?` on the snapshot payload (spec §1); `ios/Shared/WatchQuickAddPayload.swift` per spec §2. Foundation only, synthesized Codable, `encoded()`/`decode` mirroring the existing payload.

- [ ] **Step 4: Tests green; build FinchWatch + FinchMac** (shared file compiles on all platforms).

- [ ] **Step 5: Commit** — `feat(ios): watch CP3 task 1 — shared quick-add wire types (catalog down, payload up)`

---

### Task 2: Phone — build the catalog into the snapshot push

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Widgets/WidgetSnapshot.swift` (build catalog in/next to `WidgetSnapshotWriter`)
- Modify: `ios/FinchApp/Sources/FinchApp/Watch/PhoneWatchLink.swift` (`WatchSnapshotPayload(widget:)` site gains the catalog — or move the mapping to the writer if cleaner)
- Test: `ios/FinchApp/Tests/FinchAppTests/WatchQuickAddCatalogTests.swift`

- [ ] **Step 1: Failing tests for the pure builder** — a static `WatchQuickAddCatalog.build(ledgerId:accounts:txns:categories:)`-shaped helper (exact signature per what `FinchStore` exposes — mirror how `WidgetSnapshot.netWorth`/`budgetUsedPct` take plain rows):
  - default account = most confirmed-expense-used account in the last 90 days; fallback first active account
  - categories = top ≤ 6 expense categories by 90-day confirmed-expense count; fallback first 6 expense categories
  - empty ledger → nil catalog (watch shows the disabled state)

- [ ] **Step 2: Implement the builder** (pure; lives in the app target next to `WidgetSnapshotWriter`, NOT in Shared — it consumes FinchCore row types).

- [ ] **Step 3: Wire it** — where `PhoneWatchLink.shared.push(WatchSnapshotPayload(widget: snap))` happens, attach `payload.quickAdd = builder(...)` (keep the `#if os(iOS)` guard; FinchMac must still build).

- [ ] **Step 4: Tests green; FinchApp + FinchMac build. Commit** — `feat(ios): watch CP3 task 2 — entry catalog rides the snapshot push`

---

### Task 3: Phone — receive, dedupe, apply as pending

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Watch/PhoneWatchLink.swift`
- Create: `ios/FinchApp/Sources/FinchApp/Watch/QuickAddDedupe.swift` (pure ring)
- Test: `ios/FinchApp/Tests/FinchAppTests/QuickAddDedupeTests.swift`

- [ ] **Step 1: Failing tests for the dedupe ring** — `QuickAddDedupe` over an injected `UserDefaults` (suite name per-test): first-seen id passes and persists; replayed id rejected; ring evicts beyond 200; survives re-instantiation (persistence).

- [ ] **Step 2: Implement the ring** (key `finch.watch.processedQuickAddIds`, `[String]` in UserDefaults, append + trim to 200).

- [ ] **Step 3: Receive + apply** — in `PhoneWatchLink`:

```swift
func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    guard let data = userInfo["quickAdd"] as? Data,
          let p = WatchQuickAddPayload.decode(data),
          dedupe.firstSeen(p.id) else { return }
    Task { @MainActor in
        let store = FinchStore.shared
        // Catalog staleness guards: unknown ids fall back rather than dropping the spend.
        let accountId = store.accounts.contains(where: { $0.id == p.accountId }) ? p.accountId
            : (defaultAccountId(store) ?? p.accountId)
        let category = store.categoryNodes/first matching p.categoryId … fallback first expense category
        var args: [String: JSONValue] = [
            "ledgerId": .string(p.ledgerId), "accountId": .string(accountId),
            "amount": .double(-abs(p.amount)), "merchant": .string(categoryDisplayName),
            "categoryId": .string(categoryId),
            "date": .string(ymd(p.createdAt)), "time": .string(hm(p.createdAt)),
            "status": .string("pending"),
        ]
        try? store.apply(.addTransaction, Args(args))
        // No explicit ack: apply() already rewrites + pushes the watch snapshot.
    }
}
```
(Adjust category lookup to the store's actual API; the fallback rules are the spec's §3.3 guards. `try?` — a failed apply must not crash the session delegate; log in DEBUG.)

- [ ] **Step 4: Tests green; FinchApp + FinchMac build. Commit** — `feat(ios): watch CP3 task 3 — phone receives, dedupes, applies pending quick-adds`

---

### Task 4: Watch — QuickAddView + hand verification

**Files:**
- Modify: `ios/FinchWatch/FinchWatchApp.swift` (toolbar `+`, `QuickAddView`, send call)

- [ ] **Step 1: Composer per spec §4** — crown-driven amount (`.digitalCrownRotation`, 0…500 step 0.5, `.focusable()`) + quick-bump buttons (+1/+5/+10), category chip/picker from `snapshot.quickAdd.categories` (first preselected), currency label from `snapshot.currency`, Add disabled at 0 or when catalog is nil (with "Open finch on your iPhone" copy), on Add: build `WatchQuickAddPayload(id: UUID().uuidString, …, createdAt: Date())`, `WCSession.default.transferUserInfo(["quickAdd": data])`, checkmark confirmation "Added — syncs to iPhone", dismiss.

- [ ] **Step 2: Build FinchWatch** — green (app + complication both still build).

- [ ] **Step 3: Hand-verify on paired simulators** (screenshot both sides for the PR):
  1. Phone app running with demo data → watch glance shows figures and `+` enabled.
  2. Compose $12.50 in the first category → Add → confirmation shows.
  3. Phone: Pending review shows the new pending expense with the right amount/category/default account; the feed row's merchant reads as the category name.
  4. Confirm it on the phone → glance/complication figures update (snapshot push ack loop).
  5. Replay check (DEBUG): calling the delegate twice with the same payload books ONE transaction.

- [ ] **Step 4: Docs** — `2026-06-25-ios-handoff.md`: Watch row → "✅ CP1+CP2+CP3 done (#412, #415, #this) — sub-project complete"; session-log entry. `IOS_MACOS_ROADMAP.md` Phase 7 note if it lists the on-wrist quick-add as open.

- [ ] **Step 5: Commit** — `feat(ios): watch CP3 task 4 — on-wrist quick-add composer + docs`

---

## Acceptance criteria

- All three shared-payload tests + catalog-builder tests + dedupe-ring tests green in `FinchAppTests`; FinchCore `swift test`/ParityTests untouched and green.
- FinchApp, FinchMac, FinchWatch (app + complication) all build; no FinchCore import anywhere under `ios/FinchWatch*`/`ios/Shared`.
- A CP1/CP2-era persisted snapshot (no `quickAdd` key) still decodes on the watch (legacy-wire test is the guard).
- Hand-verified loop: wrist → pending on phone → confirm → wrist figures update; duplicate delivery books exactly one row.
- Quick-adds are `status: pending`, negative-signed, dated from the watch's `createdAt`.
