# Merchant detail screen — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tap a merchant in the Merchants admin to open a detail screen with its stats + transactions.

**Architecture:** An additive `merchantTransactions` selector (same id-or-name matching as `counterpartyTxCounts`); a new `CounterpartyDetailView` (stats + `TxRow` list → Edit); the admin row becomes a `NavigationLink`.

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-25-merchant-detail-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before app builds.
- Engine tests: `cd ios/FinchCore && swift test`. App builds: FinchApp (iOS) **and** FinchMac (macOS).
- Commits: **no `Co-Authored-By` trailer**. `merchantTransactions` is additive (parity-safe). PR targets `feat/frontend`.

---

### Task 1: Engine — `merchantTransactions` selector

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift`
- Test: `ios/FinchCore/Tests/FinchCoreTests/MerchantTransactionsTests.swift` (create)

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import FinchCore

final class MerchantTransactionsTests: XCTestCase {
    private let cps = [
        Counterparty(id: "cp1", ledgerId: "l1", name: "Starbucks", isVerified: false),
        Counterparty(id: "cp2", ledgerId: "l1", name: "Other", isVerified: false),
    ]
    private let txns = [
        Tx(id: "a", merchant: "Starbucks", amount: -5, account: "a1", date: "2026-06-01", ledgerId: "l1", counterpartyId: "cp1"), // linked
        Tx(id: "b", merchant: "starbucks", amount: -6, account: "a1", date: "2026-06-03", ledgerId: "l1"),                         // name match
        Tx(id: "c", merchant: "Starbucks", amount: -7, account: "a1", date: "2026-06-02", ledgerId: "l1", counterpartyId: "cp2"), // linked elsewhere
        Tx(id: "d", merchant: "Starbucks", amount: -8, account: "a1", date: "2026-06-04", ledgerId: "l2"),                         // other ledger
    ]

    func test_matchesByIdAndName_excludesOthers_newestFirst() {
        let out = Selectors.merchantTransactions(txns, cps, "cp1", "l1")
        XCTAssertEqual(out.map(\.id), ["b", "a"])   // date-desc: 06-03 then 06-01; c (cp2) + d (l2) excluded
    }
}
```

- [ ] **Step 2: Run — expect FAIL (no such function)**

Run: `cd ios/FinchCore && swift test --filter MerchantTransactionsTests 2>&1 | tail -15`
Expected: FAIL — `merchantTransactions` doesn't exist.

- [ ] **Step 3: Add the selector**

In `Selectors.swift`, after `counterpartyTxCounts`, add:

```swift
    /// A merchant's transactions: linked by counterpartyId, or matched by normalized
    /// merchant name (mirrors `counterpartyTxCounts`' resolution). Active-ledger,
    /// newest-first, INCLUDES pending.
    public static func merchantTransactions(_ txns: [Tx], _ counterparties: [Counterparty],
                                            _ counterpartyId: String, _ ledgerId: String) -> [Tx] {
        let idSet = Set(counterparties.map(\.id))
        var byName: [String: String] = [:]
        for c in counterparties {
            let n = c.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !n.isEmpty, byName[n] == nil { byName[n] = c.id }
        }
        let matched = txns.filter { t in
            guard ledgerOf(t) == ledgerId else { return false }
            let resolved: String?
            if let cid = t.counterpartyId, idSet.contains(cid) {
                resolved = cid
            } else {
                let n = t.merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                resolved = n.isEmpty ? nil : byName[n]
            }
            return resolved == counterpartyId
        }
        return matched.sorted { $0.date != $1.date ? $0.date > $1.date : ($0.time ?? "") > ($1.time ?? "") }
    }
```

- [ ] **Step 4: Run — expect PASS**

Run: `cd ios/FinchCore && swift test --filter MerchantTransactionsTests 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 5: Full engine suite incl. ParityTests**

Run: `cd ios/FinchCore && swift test 2>&1 | tail -8`
Expected: all pass (additive selector ⇒ ParityTests green).

- [ ] **Step 6: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift \
        ios/FinchCore/Tests/FinchCoreTests/MerchantTransactionsTests.swift
git commit -m "feat(ios): Selectors.merchantTransactions (id-or-name match)"
```

---

### Task 2: `CounterpartyDetailView` + navigation from the admin

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/PowerTools/CounterpartyDetailView.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/CounterpartyAdminView.swift`

- [ ] **Step 1: Create the detail screen**

```swift
import SwiftUI
import FinchCore

/// A merchant's transactions + aggregate stats. Pushed from the Merchants admin.
struct CounterpartyDetailView: View {
    @EnvironmentObject private var store: FinchStore
    let counterparty: Counterparty
    @State private var editing: Tx?

    private var txns: [Tx] {
        Selectors.merchantTransactions(store.txns, store.merchants, counterparty.id, store.activeLedgerId)
    }
    private var total: Double { txns.reduce(0) { $0 + $1.amount } }

    var body: some View {
        List {
            Section {
                LabeledContent("Transactions", value: "\(txns.count)")
                LabeledContent("Total", value: store.displayMoneyBase(total))
                if !txns.isEmpty {
                    LabeledContent("Average", value: store.displayMoneyBase(total / Double(txns.count)))
                }
            }
            if !txns.isEmpty {
                Section("Transactions") {
                    ForEach(txns) { tx in
                        Button { editing = tx } label: { TxRow(txn: tx).contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(counterparty.name)
        .sheet(item: $editing) { EditTransactionSheet(txn: $0) }
    }
}
```
(No `navigationBarTitleDisplayMode` — it's unavailable on macOS; `navigationTitle` alone is cross-platform. `TxRow` reads `store` from the environment.)

- [ ] **Step 2: Make the admin row a NavigationLink**

In `CounterpartyAdminView.swift`, replace the row's `HStack { … }` (name / seal / count / Spacer / inline Verify button):

```swift
                        HStack {
                            Text(cp.name)
                            if cp.isVerified {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(.tint)
                                    .accessibilityLabel("Verified")
                            }
                            if let n = counts[cp.id], n > 0 {
                                Text("\(n)×").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    .accessibilityLabel("\(n) transactions")
                            }
                            Spacer()
                            Button(cp.isVerified ? "Unverify" : "Verify") { toggleVerify(cp) }
                                .font(.caption).buttonStyle(.bordered)
                        }
```
with:

```swift
                        NavigationLink {
                            CounterpartyDetailView(counterparty: cp)
                        } label: {
                            HStack {
                                Text(cp.name)
                                if cp.isVerified {
                                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.tint)
                                        .accessibilityLabel("Verified")
                                }
                                if let n = counts[cp.id], n > 0 {
                                    Text("\(n)×").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                        .accessibilityLabel("\(n) transactions")
                                }
                            }
                        }
```
(The `.swipeActions { … }` and `.contextMenu { … }` that follow are unchanged — Verify/Rename/Delete stay there. `toggleVerify` keeps its other callers.)

- [ ] **Step 3: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`. (If `toggleVerify` is now unused anywhere, it still has the swipe/context callers, so no warning. If `displayMoneyBase` differs, match `TxRow`'s usage.)

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/PowerTools/CounterpartyDetailView.swift \
        ios/FinchApp/Sources/FinchApp/PowerTools/CounterpartyAdminView.swift
git commit -m "feat(ios): merchant detail screen (stats + transactions)"
```

---

### Task 3: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Install + launch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"; xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```
(Merchants appear once transactions have merchants / counterparties. Settings → Power Tools → Merchants.)

- [ ] **Step 2: Verify**
  - Settings → Power Tools → **Merchants** → each row is tappable (chevron) → opens the detail.
  - Detail shows **Transactions / Total / Average** and a date-desc list of that merchant's transactions; tap one → **Edit** opens.
  - Rename / Verify / Delete still available via the row's **swipe** and **context menu**.
  - Screenshot evidence to `/tmp/merchantdetail.png`.

- [ ] **Step 3 (no commit):** report; if a check fails, return to the relevant task.

---

## Self-review notes
- Spec coverage: selector + test + parity (T1), detail screen stats+list+Edit (T2 S1), admin NavigationLink replacing inline Verify (T2 S2), cross-platform build (T2 S3), manual (T3). ✓
- Type consistency: `merchantTransactions(_:_:_:_:)`, `CounterpartyDetailView(counterparty:)`, `store.merchants`, `TxRow`, `displayMoneyBase` consistent. ✓
- Additive engine selector; Verify/Rename/Delete preserved in swipe/context. ✓
