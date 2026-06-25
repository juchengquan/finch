# Reconcile badge + pending/confirmed split — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the reconcile checkpoint as a status badge in account detail, and split the account's transactions into "To confirm" (pending) vs confirmed.

**Architecture:** No engine/schema change. (1) FinchCore: add `lastReconciledAt`/`lastReconciledBalance` to `AccountRow` + the accounts projection (the columns + the `reconcileAccount` write already exist), and a pure `reconcileStatus` helper (35-day stale). (2) FinchApp: a badge + a pending/confirmed split in `AccountDetailView`.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), FinchCore, XcodeGen, XCTest.

## Global Constraints

- **No engine/schema/action change.** `accounts.last_reconciled_at`/`last_reconciled_balance` columns + the `reconcileAccount` write already exist; this surfaces them.
- Stale threshold **35 days** (boundary: 35 = fresh, 36 = stale). "days ago" measured against **`store.today`** (iOS max-tx-date anchor). Badge balance in the **account's native currency** (`Money.format(_:currency:)`).
- Pending/confirmed split via `Tx.pending` — pure UI; no change to confirmed-row layout.
- **Out of scope:** the guided reconcile session / quick-add (separate feature).
- **Must build iOS AND macOS (FinchMac).** Sim `iPhone 17 Pro Max`. New files → `xcodegen generate`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit; **no `Co-Authored-By` trailer**.

---

## File Structure

**Modify (FinchCore):** `ios/FinchCore/Sources/FinchCore/Project/Models.swift` (AccountRow), `ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift` (accounts projection).
**Create (FinchCore):** `ios/FinchCore/Sources/FinchCore/Selectors/ReconcileStatus.swift`.
**Create (tests):** `ios/FinchCore/Tests/FinchCoreTests/ReconcileStatusTests.swift`.
**Modify (FinchApp):** `ios/FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift`.

---

### Task 1: Surface lastReconciled on `AccountRow` + `reconcileStatus` helper

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Models.swift`
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift`
- Create: `ios/FinchCore/Sources/FinchCore/Selectors/ReconcileStatus.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests/ReconcileStatusTests.swift`

**Interfaces:**
- Produces: `AccountRow.lastReconciledAt: String?` + `lastReconciledBalance: Double?` (projected); `ReconcileStatus` enum + `Selectors.reconcileStatus(_:_:staleDays:) -> ReconcileStatus`.

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchCore/Tests/FinchCoreTests/ReconcileStatusTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class ReconcileStatusTests: XCTestCase {
    func test_reconcileStatus_never_fresh_stale_boundary() {
        XCTAssertEqual(Selectors.reconcileStatus(nil, "2026-06-26"), .never)
        XCTAssertEqual(Selectors.reconcileStatus("", "2026-06-26"), .never)
        XCTAssertEqual(Selectors.reconcileStatus("2026-06-26", "2026-06-26"), .fresh(days: 0))
        XCTAssertEqual(Selectors.reconcileStatus("2026-05-22", "2026-06-26"), .fresh(days: 35))   // exactly 35 → fresh
        XCTAssertEqual(Selectors.reconcileStatus("2026-05-21", "2026-06-26"), .stale(days: 36))   // 36 → stale
        XCTAssertEqual(Selectors.reconcileStatus("2026-07-01", "2026-06-26"), .fresh(days: 0))    // future → clamp 0
    }

    func test_accounts_projection_carries_last_reconciled() throws {
        let q = try TestSeed.base()   // l1 / a1 / c1
        try Apply.apply(dbQueue: q, action: "reconcileAccount", args: Args([
            "accountId": .string("a1"), "statementBalance": .double(1200), "statementDate": .string("2026-05-01")]))
        let a = try XCTUnwrap(Projection.accounts(dbQueue: q, ledgerId: "l1").first { $0.id == "a1" })
        XCTAssertEqual(a.lastReconciledAt, "2026-05-01")
        XCTAssertEqual(a.lastReconciledBalance, 1200)
        // a never-reconciled account projects nil (seed a 2nd account)
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "id": .string("a2"), "ledgerId": .string("l1"), "name": .string("Savings"), "type": .string("savings"), "currency": .string("USD")]))
        let a2 = try XCTUnwrap(Projection.accounts(dbQueue: q, ledgerId: "l1").first { $0.id == "a2" })
        XCTAssertNil(a2.lastReconciledAt)
        XCTAssertNil(a2.lastReconciledBalance)
    }
}
```
(If `createAccount`'s args differ, mirror an existing `AccountCrudTests` create call.)

- [ ] **Step 2: Run to verify failure**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter ReconcileStatusTests`
Expected: FAIL to compile — `AccountRow.lastReconciledAt`/`reconcileStatus`/`ReconcileStatus` undefined.

- [ ] **Step 3: Extend `AccountRow`**

In `Models.swift`, in the `AccountRow` struct after `public var openingBalanceBase: Double?`:
```swift
    public var lastReconciledAt: String?
    public var lastReconciledBalance: Double?
```
Extend the `init` signature (append, defaulted): `…, openingBalanceBase: Double? = nil, lastReconciledAt: String? = nil, lastReconciledBalance: Double? = nil)` and add to the body: `self.lastReconciledAt = lastReconciledAt; self.lastReconciledBalance = lastReconciledBalance`.

- [ ] **Step 4: Project the columns**

In `Projections+State.swift` `accountRows(...)`:
- SELECT — add to the column list: `a.last_reconciled_at AS lastReconciledAt, a.last_reconciled_balance AS lastReconciledBalance` (e.g. right after `a.is_active AS isActive`).
- map — add to the `AccountRow(...)` init call: `lastReconciledAt: r["lastReconciledAt"], lastReconciledBalance: r["lastReconciledBalance"]`.

- [ ] **Step 5: Create `ReconcileStatus.swift`**

Create `ios/FinchCore/Sources/FinchCore/Selectors/ReconcileStatus.swift`:
```swift
import Foundation

/// Reconcile freshness for an account's last checkpoint.
public enum ReconcileStatus: Equatable, Sendable {
    case never
    case fresh(days: Int)
    case stale(days: Int)
}

extension Selectors {
    private static let utcDayFmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")!
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// `.never` when never reconciled; else whole-days `today − lastReconciledAt`
    /// (clamped ≥ 0): `> staleDays` ⇒ `.stale`, else `.fresh`. Dates are YYYY-MM-DD.
    public static func reconcileStatus(_ lastReconciledAt: String?, _ today: String, staleDays: Int = 35) -> ReconcileStatus {
        guard let iso = lastReconciledAt, !iso.isEmpty,
              let last = utcDayFmt.date(from: String(iso.prefix(10))),
              let now = utcDayFmt.date(from: String(today.prefix(10))) else {
            return .never
        }
        let days = max(0, Int((now.timeIntervalSince(last) / 86_400).rounded()))
        return days > staleDays ? .stale(days: days) : .fresh(days: days)
    }
}
```
(The `guard`'s `else` returns `.never` for nil/empty/unparseable — simple + safe.)

- [ ] **Step 6: Run tests**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter ReconcileStatusTests`
Expected: PASS (2 tests).

- [ ] **Step 7: Full FinchCore suite**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test`
Expected: all pass (defaulted `AccountRow` init params keep other call sites valid).

- [ ] **Step 8: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchCore/Sources/FinchCore/Project/Models.swift \
        ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift \
        ios/FinchCore/Sources/FinchCore/Selectors/ReconcileStatus.swift \
        ios/FinchCore/Tests/FinchCoreTests/ReconcileStatusTests.swift
git commit -m "feat(ios): surface lastReconciled on AccountRow + reconcileStatus helper"
```

---

### Task 2: Badge + pending/confirmed split in `AccountDetailView`

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift`

**Interfaces:**
- Consumes: `AccountRow.lastReconciledAt`/`lastReconciledBalance`, `Selectors.reconcileStatus`, `ReconcileStatus` (Task 1); `store.today`, `store.baseCurrency`, `Money.format`, `store.transactions(for:)`, `Tx.pending`.

- [ ] **Step 1: Add the badge to the header Section**

In `AccountDetailView.body`, replace:
```swift
                    Section { header(account) }
```
with:
```swift
                    Section {
                        header(account)
                        reconcileBadge(account)
                    }
```

- [ ] **Step 2: Add the `reconcileBadge` view**

Add this method to `AccountDetailView` (e.g. near `header`):
```swift
    @ViewBuilder private func reconcileBadge(_ a: AccountRow) -> some View {
        let status = Selectors.reconcileStatus(a.lastReconciledAt, store.today)
        let bal = Money.format(a.lastReconciledBalance ?? 0, currency: a.currency ?? store.baseCurrency)
        HStack(spacing: 6) {
            switch status {
            case .never:
                Image(systemName: "checkmark.seal").foregroundStyle(.secondary)
                Text("Never reconciled").foregroundStyle(.secondary)
            case .fresh(let d):
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("Reconciled to \(bal) · \(agoLabel(d))").foregroundStyle(.green)
            case .stale(let d):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Reconciled to \(bal) · \(agoLabel(d))").foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
    }

    private func agoLabel(_ d: Int) -> String { d == 0 ? "today" : d == 1 ? "1 day ago" : "\(d) days ago" }
```

- [ ] **Step 3: Split transactions into pending / confirmed**

Replace `transactionsSection(_:)` with:
```swift
    @ViewBuilder private func transactionsSection(_ a: AccountRow) -> some View {
        let txns = store.transactions(for: a.id)
        let pending = txns.filter { $0.pending == true }
        let confirmed = txns.filter { $0.pending != true }
        if !pending.isEmpty {
            Section("To confirm (\(pending.count))") {
                ForEach(pending, id: \.id) { t in txRow(t) }
            }
        }
        Section("Transactions") {
            if confirmed.isEmpty {
                Text("No transactions").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(confirmed, id: \.id) { t in txRow(t) }
            }
        }
    }

    @ViewBuilder private func txRow(_ t: Tx) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.merchant).lineLimit(1)
                Text(t.date).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(store.displayMoneyBase(t.amount)).fontWeight(.medium)
        }
    }
```

- [ ] **Step 4: Build iOS + full FinchApp suite**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Full FinchCore suite**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test 2>&1 | grep -iE "error:|Test Suite 'All tests'"`
Expected: all pass.

- [ ] **Step 6: Build macOS (FinchMac)**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Manual verification on the simulator**

Open an account's detail:
- **Never reconciled:** badge reads "Never reconciled" (grey).
- **Reconcile it** (the existing Reconcile action → statement balance + date) → the badge turns green "Reconciled to $X · today"; an old checkpoint (>35 days) shows the amber ⚠ variant.
- An account with **pending** txns shows a **"To confirm (N)"** section above "Transactions"; an account with none shows only "Transactions".

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch -initialTab accounts
```

- [ ] **Step 8: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift
git commit -m "feat(ios): reconcile status badge + pending/confirmed split in account detail"
```

---

## Self-Review

**Spec coverage** (against `2026-06-26-ios-reconcile-badge-split-design.md`):
- `AccountRow.lastReconciledAt`/`Balance` + projection → Task 1 steps 3-4. ✓
- `reconcileStatus` (never/fresh/stale, 35-day boundary, store.today anchor) → Task 1 step 5. ✓
- Badge (native-currency balance, green/amber/neutral, "N days ago") → Task 2 steps 1-2. ✓
- Pending/confirmed split ("To confirm (N)" above Transactions) → Task 2 step 3. ✓
- No engine change; build iOS+macOS; full tests → Task 2 steps 4-6. ✓

**Placeholder scan:** No TBD/TODO; full code in every step; sim step concrete. ✓

**Type consistency:** `reconcileStatus(_ String?, _ String, staleDays:) -> ReconcileStatus` used by the badge; `AccountRow(... lastReconciledAt:lastReconciledBalance:)` defaulted init keeps call sites valid; projection aliases (`lastReconciledAt`/`lastReconciledBalance`) match the `r[...]` reads; `Money.format(_:currency:)`, `store.today`, `store.baseCurrency`, `store.transactions(for:)`, `Tx.pending` all exist; `txRow` shared by both sections. ✓

---

## Out of scope

The guided reconcile session (tick cleared / cleared-vs-target / quick-add-missing / confirm-and-clear); engine/schema/action changes; an accounts-list-row badge.
