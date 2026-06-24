# Merchant transaction counts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a live `N×` usage count next to each merchant in Power Tools › Merchants — the number of non-pending transactions attributed to that merchant.

**Architecture:** A new pure FinchCore selector counts non-pending txns per counterparty (by `counterpartyId` when set & known, else by normalized merchant name), and `CounterpartyAdminView` renders `N×` per row from it. No engine/schema/model/projection change.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), FinchCore, XcodeGen, XCTest. FinchCore tests via `swift test`; FinchApp via `xcodebuild … -only-testing:FinchAppTests/…`.

## Global Constraints

- **No engine/schema/model/projection change** — derived live from `store.txns` + `store.merchants`.
- **Count = all non-pending txns** for the merchant (decision A; all kinds, no expense-only filter).
- **Attribution:** by `counterpartyId` when set AND it matches a known counterparty; otherwise by normalized name (`merchant.trimmed.lowercased == counterparty.name.trimmed.lowercased`); first counterparty wins on duplicate names.
- Count the dict **once per render** (not per row).
- **Must build iOS AND macOS (FinchMac).** Sim: `iPhone 17 Pro Max`. New files → `xcodegen generate`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit messages; **no `Co-Authored-By` trailer**.

---

## File Structure

**Modify (FinchCore):**
- `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift` — add `counterpartyTxCounts` (after `merchantStats`/`anomalyScore`).

**Create (tests):**
- `ios/FinchCore/Tests/FinchCoreTests/CounterpartyTxCountsTests.swift`

**Modify (FinchApp):**
- `ios/FinchApp/Sources/FinchApp/PowerTools/CounterpartyAdminView.swift` — compute counts once + render `N×` per row.

**Common run commands:**
```bash
cd /Users/blackmount8/_repository/finch/ios
swift test --filter <ClassName>                       # FinchCore
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:FinchAppTests/<ClassName>
```

---

### Task 1: `Selectors.counterpartyTxCounts` (pure)

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift` (add a static func; the `ledgerOf` helper + 2-space indentation conventions are already in this file)
- Test: `ios/FinchCore/Tests/FinchCoreTests/CounterpartyTxCountsTests.swift` (create)

**Interfaces:**
- Produces: `static func counterpartyTxCounts(_ txns: [Tx], _ counterparties: [Counterparty], _ ledgerId: String) -> [String: Int]` — keyed by counterparty id; non-pending txns in `ledgerId` attributed by `counterpartyId` (when known) else normalized name; absent for unused.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchCore/Tests/FinchCoreTests/CounterpartyTxCountsTests.swift`:

```swift
import XCTest
@testable import FinchCore

final class CounterpartyTxCountsTests: XCTestCase {
    private func cp(_ id: String, _ name: String) -> Counterparty {
        Counterparty(id: id, ledgerId: "l1", name: name)
    }
    private func tx(_ id: String, merchant: String = "", cp: String? = nil,
                    pending: Bool = false, ledger: String = "l1") -> Tx {
        Tx(id: id, merchant: merchant, amount: -5, account: "a1", date: "2026-05-01",
           pending: pending, ledgerId: ledger, counterpartyId: cp)
    }

    func test_counts_by_counterpartyId() {
        let r = Selectors.counterpartyTxCounts([tx("t1", cp: "cp1"), tx("t2", cp: "cp1")], [cp("cp1", "Starbucks")], "l1")
        XCTAssertEqual(r, ["cp1": 2])
    }

    func test_name_fallback_is_case_and_whitespace_insensitive() {
        let r = Selectors.counterpartyTxCounts(
            [tx("t1", merchant: "starbucks"), tx("t2", merchant: "  STARBUCKS ")],
            [cp("cp1", "Starbucks")], "l1")
        XCTAssertEqual(r, ["cp1": 2])
    }

    func test_unknown_counterpartyId_falls_back_to_name() {
        // counterpartyId points at an unknown id, but the merchant name matches
        let r = Selectors.counterpartyTxCounts([tx("t1", merchant: "Starbucks", cp: "ghost")], [cp("cp1", "Starbucks")], "l1")
        XCTAssertEqual(r, ["cp1": 1])
    }

    func test_excludes_pending() {
        let r = Selectors.counterpartyTxCounts([tx("t1", cp: "cp1"), tx("t2", cp: "cp1", pending: true)], [cp("cp1", "Starbucks")], "l1")
        XCTAssertEqual(r, ["cp1": 1])
    }

    func test_excludes_other_ledger() {
        let r = Selectors.counterpartyTxCounts([tx("t1", cp: "cp1"), tx("t2", cp: "cp1", ledger: "l2")], [cp("cp1", "Starbucks")], "l1")
        XCTAssertEqual(r, ["cp1": 1])
    }

    func test_unused_merchant_is_absent() {
        let r = Selectors.counterpartyTxCounts([tx("t1", cp: "cp1")], [cp("cp1", "Starbucks"), cp("cp2", "Shell")], "l1")
        XCTAssertEqual(r["cp1"], 1)
        XCTAssertNil(r["cp2"])
    }

    func test_unmatched_txn_is_uncounted() {
        // merchant name matches nothing, no counterpartyId → not counted
        let r = Selectors.counterpartyTxCounts([tx("t1", merchant: "Nowhere")], [cp("cp1", "Starbucks")], "l1")
        XCTAssertTrue(r.isEmpty)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter CounterpartyTxCountsTests`
Expected: FAIL to compile — `counterpartyTxCounts` undefined.

- [ ] **Step 3: Implement the selector**

In `Selectors.swift`, add (inside the `Selectors` enum/struct, after the `anomalyScore` function, matching the file's 2-space indentation):

```swift
  /// Per-counterparty usage count: non-pending txns in `ledgerId` attributed to a
  /// counterparty by `counterpartyId` (when set & known) else by normalized name.
  /// Keyed by counterparty id; absent for unused merchants. Counts all kinds.
  public static func counterpartyTxCounts(_ txns: [Tx], _ counterparties: [Counterparty], _ ledgerId: String) -> [String: Int] {
      let idSet = Set(counterparties.map(\.id))
      var byName: [String: String] = [:]   // normalized name → counterparty id (first wins)
      for c in counterparties {
          let n = c.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
          if !n.isEmpty, byName[n] == nil { byName[n] = c.id }
      }
      var out: [String: Int] = [:]
      for t in txns {
          if ledgerOf(t) != ledgerId { continue }
          if (t.pending ?? false) { continue }
          let cpId: String?
          if let cid = t.counterpartyId, idSet.contains(cid) {
              cpId = cid
          } else {
              let n = t.merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
              cpId = n.isEmpty ? nil : byName[n]
          }
          if let id = cpId { out[id, default: 0] += 1 }
      }
      return out
  }
```

(Verify the indentation/brace style matches the surrounding functions in `Selectors.swift` — adjust whitespace only if needed.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter CounterpartyTxCountsTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Run the full FinchCore suite (no regressions)**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift \
        ios/FinchCore/Tests/FinchCoreTests/CounterpartyTxCountsTests.swift
git commit -m "feat(ios): Selectors.counterpartyTxCounts (per-merchant usage count)"
```

---

### Task 2: Show `N×` per merchant row

**Files:**
- Modify (full rewrite): `ios/FinchApp/Sources/FinchApp/PowerTools/CounterpartyAdminView.swift`

**Interfaces:**
- Consumes: `Selectors.counterpartyTxCounts` (Task 1); `store.txns`, `store.merchants`, `store.activeLedgerId`.
- Produces: the `N×` row display. No new public symbols.

- [ ] **Step 1: Replace the view file**

Replace the entire contents of `ios/FinchApp/Sources/FinchApp/PowerTools/CounterpartyAdminView.swift` with (current view + a once-per-render `counts` dict + the `N×` text; `CounterpartyNameSheet` unchanged):

```swift
import SwiftUI
import FinchCore

/// Merchants / counterparties admin — list (with usage counts), search, add,
/// rename, verify/unverify, delete. Routes FinchStore.apply.
struct CounterpartyAdminView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var search = ""
    @State private var showingAdd = false
    @State private var editing: Counterparty?
    @State private var errorMessage: String?

    private var filtered: [Counterparty] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? store.merchants : store.merchants.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        // Computed once per render, not per row.
        let counts = Selectors.counterpartyTxCounts(store.txns, store.merchants, store.activeLedgerId)
        return Group {
            if store.merchants.isEmpty {
                ContentUnavailableView("No merchants", systemImage: "person.crop.circle",
                                       description: Text("Merchants appear as you add transactions, or add one with +."))
            } else {
                List {
                    ForEach(filtered) { cp in
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
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(cp) } label: { Label("Delete", systemImage: "trash") }
                            Button { editing = cp } label: { Label("Rename", systemImage: "pencil") }.tint(.blue)
                        }
                        .contextMenu {
                            Button { editing = cp } label: { Label("Rename", systemImage: "pencil") }
                            Button { toggleVerify(cp) } label: { Label(cp.isVerified ? "Unverify" : "Verify", systemImage: "checkmark.seal") }
                            Button(role: .destructive) { delete(cp) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                .searchable(text: $search)
            }
        }
        .navigationTitle("Merchants")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add Merchant")
            }
        }
        .sheet(isPresented: $showingAdd) { CounterpartyNameSheet(counterparty: nil) }
        .sheet(item: $editing) { CounterpartyNameSheet(counterparty: $0) }
        .errorAlert($errorMessage)
    }

    private func toggleVerify(_ cp: Counterparty) {
        do { try store.apply(cp.isVerified ? .unverifyCounterparty : .verifyCounterparty, Args(["id": .string(cp.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func delete(_ cp: Counterparty) {
        do { try store.apply(.deleteCounterparty, Args(["id": .string(cp.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
}

/// Add or rename a counterparty (name only).
struct CounterpartyNameSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let counterparty: Counterparty?
    @State private var name: String
    @State private var errorMessage: String?

    init(counterparty: Counterparty?) {
        self.counterparty = counterparty
        _name = State(initialValue: counterparty?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(counterparty == nil ? "Add Merchant" : "Rename Merchant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save").bold()
                }
            }
        }
    }

    private func save() {
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorMessage = "Enter a name."; return }
        do {
            if let counterparty {
                try store.apply(.updateCounterparty, Args(["id": .string(counterparty.id), "patch": .object(["name": .string(trimmed)])]))
            } else {
                try store.apply(.createCounterparty, Args(["ledgerId": .string(store.activeLedgerId), "name": .string(trimmed)]))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
```

- [ ] **Step 2: Build iOS + run the full FinchApp suite**

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

- [ ] **Step 3: Build macOS (FinchMac) — CI gate**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verification on the simulator**

Launch to Merchants (Settings › Power Tools › Merchants). With the seeded data, a merchant referenced by transactions shows `N×` (e.g. `2×`); a freshly-added, unused merchant shows no count. Add a transaction for a merchant and confirm its count increments.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch -initialTab settings
```

- [ ] **Step 5: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/PowerTools/CounterpartyAdminView.swift
git commit -m "feat(ios): show per-merchant transaction count (N×)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-24-ios-merchant-txcounts-design.md`):
- New `counterpartyTxCounts` selector (all non-pending, id-or-name attribution, keyed by cp id) → Task 1. ✓
- Row `N×` (muted, monospaced, hidden when 0), counts computed once per render → Task 2. ✓
- No engine/model/projection change; build iOS+macOS; full tests green → Task 2 steps 2-3. ✓

**Placeholder scan:** No TBD/TODO; full code in every code step; sim step has concrete checks. The two "verify indentation/build-settings" notes carry concrete actions, not vague placeholders. ✓

**Type consistency:** `counterpartyTxCounts(_:_:_:) -> [String: Int]` signature matches Task 2's call; `counts[cp.id]` is `Int?`, guarded `if let n …, n > 0`. `Counterparty`/`Tx` constructions in the test match their real inits (`Tx(id:merchant:amount:account:date:pending:ledgerId:counterpartyId:)`, `Counterparty(id:ledgerId:name:)`). ✓

---

## Out of scope

Merchant color/badge; merge; sort-by-usage; any non-merchant screen.
