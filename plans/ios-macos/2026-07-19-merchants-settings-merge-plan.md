# Merchants Settings Page + Merge — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Merchants out of Power Tools to a Settings top-level page (restyled to the Categories/Tags conventions) and add merge (single + multi-select).

**Architecture:** Native-first merge actions (`mergeCounterparty` / `mergeCounterparties`) in `FinchCore` (mirroring `mergeCategory`, no web/parity), consumed by a renamed+restyled `MerchantsView` that reuses the existing `CounterpartyDetailView`, `CounterpartyNameSheet`, selectors, and the shared `SearchableModifier` + `mergeImpactMessage` helpers.

**Tech Stack:** Swift / SwiftUI, FinchCore (SwiftPM, GRDB), XcodeGen, XCTest.

**Reference spec:** `plans/ios-macos/2026-07-19-merchants-settings-merge-design.md`

## Global Constraints

- **Merge is native-first.** Add exactly two `ActionName` cases (`mergeCounterparty`, `mergeCounterparties`) + their `Counterparties` handlers. **No web change, no parity fixtures.** `ArgsTests.test_actionCount()` asserts the total — bump it **79 → 81** (and its comment).
- **Merge semantics:** reassign `entries.counterparty_id` source→target **by id only** (transactions that merely name-match are not rewritten); target keeps its own `is_verified`; then delete the source. Only `entries` references a counterparty.
- **Reuse, don't duplicate:** existing `createCounterparty`/`updateCounterparty`/`deleteCounterparty`/`verifyCounterparty`/`unverifyCounterparty`; `CounterpartyNameSheet`; `CounterpartyDetailView`; `Selectors.counterpartyTxCounts` / `merchantTransactions`; the shared `SearchableModifier`; and the free `mergeImpactMessage(txCount:)`.
- **SwiftUI-first**; deployment floor **iOS 17 / macOS 14**.
- **XcodeGen:** project is generated + git-ignored. After the file rename, run `xcodegen generate` (from `ios/`) before building. **Do NOT stage `ios/FinchApp.xcodeproj`** (git-ignored). Stage only source files.
- **xcodebuild** needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, run from `ios/`.
- Build **both iOS and macOS** before the PR (a macOS-only break can pass the iOS build).
- **Commits:** conventional prefixes; **no `Co-Authored-By` trailer**.
- Commands run from the worktree root `/private/tmp/finch-merch`; `swift test` / `xcodegen` run from `ios/`.

**Canonical app-build command** (UI-task verification gate):
```bash
cd ios && xcodegen generate && cd ..
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -scheme FinchApp -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/finchios-merch -quiet
```
(Run `xcodebuild` from `ios/`, or add `-project ios/FinchApp.xcodeproj`. Ignore spurious SourceKit "No such module 'FinchCore'".)

---

### Task 1: Merge engine — `mergeCounterparty` + `mergeCounterparties` (FinchCore)

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Store/ActionName.swift` (counterparties section, lines 30–35)
- Modify: `ios/FinchCore/Sources/FinchCore/Store/Domain/Counterparties.swift`
- Modify: `ios/FinchCore/Tests/FinchCoreTests/ArgsTests.swift` (count 79 → 81)
- Test: `ios/FinchCore/Tests/FinchCoreTests/CounterpartyMergeTests.swift` (create)

**Interfaces:**
- Produces actions `mergeCounterparty` (args `{sourceId, targetId}`) and `mergeCounterparties` (args `{sourceIds:[String], targetId}`), dispatched through `Apply`.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchCore/Tests/FinchCoreTests/CounterpartyMergeTests.swift`:

```swift
import XCTest
import GRDB
@testable import FinchCore

final class CounterpartyMergeTests: XCTestCase {
    /// Ledger, one account, two counterparties: cpSource (absorbed) and cpTarget (survivor).
    private func seeded() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L','USD',1,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('a1','l1','a1','cash','USD',0,0,1,1,datetime('now'),datetime('now'))")
            for c in ["cpSource", "cpTarget"] {
                try db.execute(sql: "INSERT INTO counterparties (id,ledger_id,name,is_verified,created_at,updated_at) VALUES (?,'l1',?,0,datetime('now'),datetime('now'))", arguments: [c, c])
            }
        }
        return q
    }

    /// Add an expense (merchant → entries.description) then link its entry to `cp`.
    private func addLinkedTx(_ q: DatabaseQueue, merchant: String, cp: String) throws {
        try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-5),
            "merchant": .string(merchant), "date": .string("2026-05-01"), "skipRules": .bool(true)]))
        try q.write { db in
            try db.execute(sql: "UPDATE entries SET counterparty_id = ? WHERE description = ?", arguments: [cp, merchant])
        }
    }

    private func merge(_ q: DatabaseQueue, _ source: String, _ target: String) throws {
        try Apply.apply(dbQueue: q, action: "mergeCounterparty", args: Args(["sourceId": .string(source), "targetId": .string(target)]))
    }

    func test_entries_repoint_and_source_deleted() throws {
        let q = try seeded()
        try addLinkedTx(q, merchant: "x", cp: "cpSource")
        try addLinkedTx(q, merchant: "z", cp: "cpTarget")
        try merge(q, "cpSource", "cpTarget")
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE counterparty_id = 'cpSource'"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE counterparty_id = 'cpTarget'"), 2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM counterparties WHERE id = 'cpSource'"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM counterparties WHERE id = 'cpTarget'"), 1)
        }
    }

    func test_merge_many_folds_all_sources() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO counterparties (id,ledger_id,name,is_verified,created_at,updated_at) VALUES ('cpSource2','l1','cpSource2',0,datetime('now'),datetime('now'))")
        }
        try addLinkedTx(q, merchant: "x", cp: "cpSource")
        try addLinkedTx(q, merchant: "y", cp: "cpSource2")
        try Apply.apply(dbQueue: q, action: "mergeCounterparties", args: Args([
            "sourceIds": .array([.string("cpSource"), .string("cpSource2")]),
            "targetId": .string("cpTarget")]))
        try q.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE counterparty_id = 'cpTarget'"), 2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM counterparties WHERE id IN ('cpSource','cpSource2')"), 0)
        }
    }

    func test_merge_into_self_rejected() throws {
        let q = try seeded()
        XCTAssertThrowsError(try merge(q, "cpSource", "cpSource"))
    }

    func test_missing_source_or_target_rejected() throws {
        let q = try seeded()
        XCTAssertThrowsError(try merge(q, "nope", "cpTarget"))
        XCTAssertThrowsError(try merge(q, "cpSource", "nope"))
    }

    func test_cross_ledger_merge_rejected() throws {
        let q = try seeded()
        try q.write { db in
            try db.execute(sql: "INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l2','L2','USD',0,datetime('now'),datetime('now'))")
            try db.execute(sql: "INSERT INTO counterparties (id,ledger_id,name,is_verified,created_at,updated_at) VALUES ('cpOther','l2','cpOther',0,datetime('now'),datetime('now'))")
        }
        XCTAssertThrowsError(try merge(q, "cpSource", "cpOther"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && swift test --filter CounterpartyMergeTests`
Expected: **FAIL** — `Apply.apply(action: "mergeCounterparty", …)` throws (unknown/unimplemented action).

- [ ] **Step 3: Implement — add the two actions + handlers, and fix the action count**

In `ios/FinchCore/Sources/FinchCore/Store/ActionName.swift`, replace the counterparties block:

```swift
    // --- counterparties (5) ---
    case createCounterparty
    case updateCounterparty
    case deleteCounterparty
    case verifyCounterparty
    case unverifyCounterparty
```

with:

```swift
    // --- counterparties (7) ---
    case createCounterparty
    case updateCounterparty
    case deleteCounterparty
    case verifyCounterparty
    case unverifyCounterparty
    case mergeCounterparty
    case mergeCounterparties
```

In `ios/FinchCore/Sources/FinchCore/Store/Domain/Counterparties.swift`, add the two handler entries to the `handlers` map (after `.unverifyCounterparty: unverify,`):

```swift
        .mergeCounterparty: merge,
        .mergeCounterparties: mergeMany,
```

and add these methods to the `Counterparties` enum (e.g. after `setVerified`):

```swift
    static func merge(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let sourceId: String; let targetId: String }
        let a = try args.to(A.self)
        try validateMerge(db, source: a.sourceId, target: a.targetId)
        try mergeOne(db, source: a.sourceId, target: a.targetId)
        try db.execute(sql: "DELETE FROM counterparties WHERE id = ?", arguments: [a.sourceId])
    }

    /// Combine many `sourceIds` into `targetId` in one transaction (Apply wraps).
    /// All sources are validated up-front, so a bad one aborts the whole set.
    static func mergeMany(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let sourceIds: [String]; let targetId: String }
        let a = try args.to(A.self)
        if a.sourceIds.isEmpty {
            throw I18nError("error.invalidArgs", [:], "mergeCounterparties requires at least one source")
        }
        for source in a.sourceIds { try validateMerge(db, source: source, target: a.targetId) }
        for source in a.sourceIds { try mergeOne(db, source: source, target: a.targetId) }
        for source in a.sourceIds {
            try db.execute(sql: "DELETE FROM counterparties WHERE id = ?", arguments: [source])
        }
    }

    /// Repoint transactions linked to `source` (by counterparty_id) onto `target`.
    /// Does NOT validate or delete `source`. Runs inside the caller's transaction.
    private static func mergeOne(_ db: Database, source: String, target: String) throws {
        try db.execute(sql: "UPDATE entries SET counterparty_id = ? WHERE counterparty_id = ?", arguments: [target, source])
    }

    /// Guards for a single source→target merge: not-self, both exist, same ledger.
    private static func validateMerge(_ db: Database, source: String, target: String) throws {
        if source == target {
            throw I18nError("error.counterparty.mergeSelf", [:], "Cannot merge a merchant into itself")
        }
        guard let sLedger = try String.fetchOne(db, sql: "SELECT ledger_id FROM counterparties WHERE id = ?", arguments: [source]),
              let tLedger = try String.fetchOne(db, sql: "SELECT ledger_id FROM counterparties WHERE id = ?", arguments: [target]) else {
            throw I18nError("error.notFound.counterparty", [:], "Merchant does not exist")
        }
        if sLedger != tLedger {
            throw I18nError("error.counterparty.mergeLedger", [:], "Merchants must be in the same ledger to merge")
        }
    }
```

In `ios/FinchCore/Tests/FinchCoreTests/ArgsTests.swift`, update the count doc + assertion:

```swift
    /// The web's 74 actions + Phase 6.5's native-only `setEntryAttachment`
    /// + the native-first `setBudgetOrder` + `setTrackedCurrencies`
    /// + `mergeCategory` + `mergeCategories` (native-only) = 79
    /// + `mergeCounterparty` + `mergeCounterparties` (native-only) = 81.
    func test_actionCount() {
        XCTAssertEqual(ActionName.allCases.count, 81)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ios && swift test --filter CounterpartyMergeTests && swift test --filter ArgsTests`
Expected: **PASS** (5 merge tests + ArgsTests).

- [ ] **Step 5: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Store/ActionName.swift ios/FinchCore/Sources/FinchCore/Store/Domain/Counterparties.swift ios/FinchCore/Tests/FinchCoreTests/ArgsTests.swift ios/FinchCore/Tests/FinchCoreTests/CounterpartyMergeTests.swift
git commit -m "feat(ios): mergeCounterparty + mergeCounterparties (native-first, mirrors mergeCategory)"
```

---

### Task 2: `CounterpartyDetailView` — drop "See in Activity feed"

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/CounterpartyDetailView.swift`

- [ ] **Step 1: Remove the redundant section**

In `ios/FinchApp/Sources/FinchApp/PowerTools/CounterpartyDetailView.swift`, delete this block (the middle `Section`, consistent with the Categories redesign which removed the equivalent):

```swift
            if !txns.isEmpty {
                Section {
                    Button {
                        DeepLinkRouter.shared.pendingFilter = TxFilter(counterpartyId: counterparty.id)
                        DeepLinkRouter.shared.selectedTab = .activity
                    } label: {
                        Label("See in Activity feed", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
```

- [ ] **Step 2: Build to verify**

Run the canonical app-build command (see Global Constraints).
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 3: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/PowerTools/CounterpartyDetailView.swift
git commit -m "feat(ios): drop 'See in Activity feed' from merchant detail (redundant with inline list)"
```

---

### Task 3: `MerchantsView` (rename + restyle + merge UI) and Settings wiring

**Files:**
- Rename: `ios/FinchApp/Sources/FinchApp/PowerTools/CounterpartyAdminView.swift` → `ios/FinchApp/Sources/FinchApp/PowerTools/MerchantsView.swift`
- Modify (in the renamed file): replace `struct CounterpartyAdminView` with `struct MerchantsView` (+ a private `MerchantMergePair`); **keep `struct CounterpartyNameSheet` unchanged**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift`

**Interfaces:**
- Consumes: `mergeCounterparty`/`mergeCounterparties` (Task 1), `CounterpartyDetailView` (Task 2), `CounterpartyNameSheet` (kept), `Selectors.counterpartyTxCounts`/`merchantTransactions`, shared `SearchableModifier`, `mergeImpactMessage(txCount:)`, `store.merchants`, `Args`, `i18nMessage`.
- Produces: `struct MerchantsView` (no-arg init), referenced by `SettingsRootList`.

- [ ] **Step 1: Rename the file**

```bash
git mv ios/FinchApp/Sources/FinchApp/PowerTools/CounterpartyAdminView.swift ios/FinchApp/Sources/FinchApp/PowerTools/MerchantsView.swift
```

- [ ] **Step 2: Replace the `CounterpartyAdminView` struct with `MerchantsView`**

In `ios/FinchApp/Sources/FinchApp/PowerTools/MerchantsView.swift`, replace the entire `struct CounterpartyAdminView: View { … }` (the top struct, ending just before `struct CounterpartyNameSheet`) with the following. **Leave `struct CounterpartyNameSheet` below it untouched.**

```swift
/// A chosen (initiating A, picked B) pair for a merge; the alert decides which survives.
private struct MerchantMergePair: Identifiable {
    let a: Counterparty
    let b: Counterparty
    var id: String { a.id + "|" + b.id }
}

/// Merchants admin — a flat, name-only list (Settings top-level). Mirrors the
/// Categories/Tags pages: search, a transaction-count pill, tap → the merchant's
/// transactions, swipe Rename/Delete/Merge, + to add. Plus verify/unverify
/// (merchant-only) and merge (single + multi-select). All via FinchStore.apply.
struct MerchantsView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var selectedMerchantId: String?
    @State private var showingAdd = false
    @State private var editing: Counterparty?
    @State private var pendingDelete: Counterparty?
    @State private var search = ""
    @State private var errorMessage: String?
    // merge state (mirrors CategoriesView)
    @State private var mergingFrom: Counterparty?
    @State private var pendingMerge: MerchantMergePair?
    @State private var mergeChoice: MerchantMergePair?
    @State private var isSelecting = false
    @State private var selected: Set<String> = []
    @State private var mergeManySurvivorChoice: [Counterparty]?

    private var filtered: [Counterparty] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? store.merchants : store.merchants.filter { $0.name.lowercased().contains(q) }
    }
    private var byId: [String: Counterparty] { Dictionary(uniqueKeysWithValues: store.merchants.map { ($0.id, $0) }) }

    var body: some View {
        let counts = Selectors.counterpartyTxCounts(store.txns, store.merchants, store.activeLedgerId)
        return Group {
            if store.merchants.isEmpty {
                ContentUnavailableView("No merchants", systemImage: "storefront",
                                       description: Text("Merchants appear as you add transactions, or add one with +."))
            } else {
                List { ForEach(filtered) { cp in row(cp, counts) } }
                    .modifier(SearchableModifier(text: $search))
            }
        }
        .navigationTitle("Merchants")
        .errorAlert($errorMessage)
        .toolbar { toolbarContent }
        .navigationDestination(item: $selectedMerchantId) { id in
            if let cp = store.merchants.first(where: { $0.id == id }) { CounterpartyDetailView(counterparty: cp) }
        }
        .sheet(isPresented: $showingAdd) { CounterpartyNameSheet(counterparty: nil) }
        .sheet(item: $editing) { CounterpartyNameSheet(counterparty: $0) }
        // Single-merge target picker; present keep-name alert only after it dismisses.
        .sheet(item: $mergingFrom, onDismiss: {
            if let p = pendingMerge { mergeChoice = p; pendingMerge = nil }
        }) { a in mergeTargetSheet(a) }
        .alert("Keep which name?", isPresented: Binding(
            get: { mergeChoice != nil }, set: { if !$0 { mergeChoice = nil } }),
            presenting: mergeChoice) { pair in
            Button("Keep \"\(pair.a.name)\"") { merge(source: pair.b, target: pair.a) }
            Button("Keep \"\(pair.b.name)\"") { merge(source: pair.a, target: pair.b) }
            Button("Cancel", role: .cancel) {}
        } message: { pair in
            if let msg = mergeImpactMessage(txCount: mergeTxCount(pair.a, pair.b)) { Text(msg) }
        }
        .alert("Keep which name?", isPresented: Binding(
            get: { mergeManySurvivorChoice != nil }, set: { if !$0 { mergeManySurvivorChoice = nil } }),
            presenting: mergeManySurvivorChoice) { picks in
            ForEach(picks) { survivor in
                Button("Keep \"\(survivor.name)\"") { mergeMany(keeping: survivor, from: picks) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { picks in
            if let msg = mergeImpactMessage(txCount: mergeManyTxCount(picks)) { Text(msg) }
        }
        .alert("Delete \(pendingDelete?.name ?? "")?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete) { cp in
            Button("Delete", role: .destructive) { delete(cp) }
            Button("Cancel", role: .cancel) {}
        } message: { cp in
            let n = counts[cp.id] ?? 0
            if n > 0 { Text("\(cp.name) — \(n) transactions keep the name but lose the merchant link.") }
            else { Text("This permanently deletes \(cp.name).") }
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .confirmationAction) {
                Button("Merge (\(selected.count))") {
                    mergeManySurvivorChoice = selected.compactMap { byId[$0] }
                        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }.disabled(selected.count < 2)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button { isSelecting = false; selected = [] } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Cancel")
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add Merchant")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { isSelecting = true; selected = [] } label: { Label("Merge…", systemImage: "arrow.triangle.merge") }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("More")
            }
        }
    }

    @ViewBuilder private func row(_ cp: Counterparty, _ counts: [String: Int]) -> some View {
        if isSelecting {
            Button {
                if selected.contains(cp.id) { selected.remove(cp.id) } else { selected.insert(cp.id) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: selected.contains(cp.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(selected.contains(cp.id) ? Color.accentColor : .secondary)
                    rowLabel(cp, counts, chevron: false)
                }
            }
            .buttonStyle(.plain)
        } else {
            Button { selectedMerchantId = cp.id } label: { rowLabel(cp, counts, chevron: true) }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    // Rename first ⇒ outer edge / full-swipe default (never delete).
                    Button { editing = cp } label: { Label("Rename", systemImage: "pencil") }.tint(.accentColor)
                    Button { pendingDelete = cp } label: { Label("Delete", systemImage: "trash") }.tint(.red)
                    Button { mergingFrom = cp } label: { Label("Merge…", systemImage: "arrow.triangle.merge") }.tint(.orange)
                }
                .contextMenu {
                    Button { editing = cp } label: { Label("Rename", systemImage: "pencil") }
                    Button { toggleVerify(cp) } label: { Label(cp.isVerified ? "Unverify" : "Verify", systemImage: "checkmark.seal") }
                    Button { mergingFrom = cp } label: { Label("Merge…", systemImage: "arrow.triangle.merge") }
                    Button(role: .destructive) { pendingDelete = cp } label: { Label("Delete", systemImage: "trash") }
                }
        }
    }

    @ViewBuilder private func rowLabel(_ cp: Counterparty, _ counts: [String: Int], chevron: Bool) -> some View {
        HStack(spacing: 8) {
            Text(cp.name).foregroundStyle(.primary)
            if cp.isVerified {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.tint).accessibilityLabel("Verified")
            }
            Spacer(minLength: 8)
            if let n = counts[cp.id], n > 0 {
                Text("\(n)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .accessibilityLabel("\(n) transactions")
            }
            if chevron { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
        }
        .contentShape(Rectangle())
    }

    private func mergeTargetSheet(_ a: Counterparty) -> some View {
        NavigationStack {
            List {
                let targets = store.merchants.filter { $0.id != a.id }
                if targets.isEmpty {
                    ContentUnavailableView("No other merchants", systemImage: "arrow.triangle.merge",
                                           description: Text("There's nothing to merge \(a.name) with yet."))
                } else {
                    ForEach(targets) { t in
                        Button {
                            pendingMerge = MerchantMergePair(a: a, b: t)
                            mergingFrom = nil
                        } label: { Text(t.name).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Merge \(a.name) with…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { mergingFrom = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
            }
        }
    }

    // MARK: actions
    private func toggleVerify(_ cp: Counterparty) {
        do { try store.apply(cp.isVerified ? .unverifyCounterparty : .verifyCounterparty, Args(["id": .string(cp.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func delete(_ cp: Counterparty) {
        errorMessage = nil
        do { try store.apply(.deleteCounterparty, Args(["id": .string(cp.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func merge(source: Counterparty, target: Counterparty) {
        errorMessage = nil; mergeChoice = nil
        do { try store.apply(.mergeCounterparty, Args(["sourceId": .string(source.id), "targetId": .string(target.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
    private func mergeMany(keeping survivor: Counterparty, from all: [Counterparty]) {
        errorMessage = nil; mergeManySurvivorChoice = nil
        let sources = all.filter { $0.id != survivor.id }.map(\.id)
        do {
            try store.apply(.mergeCounterparties, Args([
                "sourceIds": .array(sources.map(JSONValue.string)),
                "targetId": .string(survivor.id)]))
            isSelecting = false; selected = []
        } catch { errorMessage = i18nMessage(error) }
    }
    /// Choice-independent union of transactions referencing either merchant.
    private func mergeTxCount(_ a: Counterparty, _ b: Counterparty) -> Int {
        let ledger = store.activeLedgerId
        let ids = Set(Selectors.merchantTransactions(store.txns, store.merchants, a.id, ledger).map(\.id))
            .union(Selectors.merchantTransactions(store.txns, store.merchants, b.id, ledger).map(\.id))
        return ids.count
    }
    private func mergeManyTxCount(_ cps: [Counterparty]) -> Int {
        let ledger = store.activeLedgerId
        var ids = Set<String>()
        for c in cps { ids.formUnion(Selectors.merchantTransactions(store.txns, store.merchants, c.id, ledger).map(\.id)) }
        return ids.count
    }
}
```

- [ ] **Step 3: Wire Settings — add top-level row, drop the Power Tools row**

In `ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift`, in `SettingsRootList`, add the Merchants link right after the Tags link:

```swift
                NavigationLink { TagsView() } label: { Label("Tags", systemImage: "tag") }
                NavigationLink { MerchantsView() } label: { Label("Merchants", systemImage: "storefront") }
```

Then in `SettingsPowerToolsView`, remove the Merchants row (leaving Rules):

```swift
        List {
            NavigationLink("Rules") { RulesManagerView() }
        }
```

- [ ] **Step 4: Build to verify**

Run the canonical app-build command. Expected: **BUILD SUCCEEDED** (no remaining `CounterpartyAdminView` reference; grep to confirm: `grep -rn CounterpartyAdminView ios/FinchApp/Sources` → no matches).

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/PowerTools/MerchantsView.swift ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift
git commit -m "feat(ios): Merchants → Settings top-level with a Categories-style page + merge (rename CounterpartyAdminView→MerchantsView)"
```

---

### Task 4: Localization + full verification

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Resources/Localizable.xcstrings`
- Modify: `ios/scripts/zh-manual.json`

- [ ] **Step 1: Full FinchCore test suite**

Run: `cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: **all pass** (incl. `CounterpartyMergeTests`, `ArgsTests` count 81, `ParityTests` unaffected — no new parity actions).

- [ ] **Step 2: macOS build**

Run: `cd ios && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"`
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 3: Surgical zh-Hans for the new strings**

Add zh-Hans for the new user-facing strings introduced by this feature to `Localizable.xcstrings` (mirror the existing entry shape: `"KEY": { "localizations": { "zh-Hans": { "stringUnit": { "state": "translated", "value": "…" } } } }`) and to `scripts/zh-manual.json` (`"KEY": "…"`). Do NOT run the full `build-xcstrings.ts` pipeline (the stale-`extracted-keys.json` gap would regress unrelated strings — a separate follow-up). New keys (skip any already present, e.g. "Merchants", "Cancel", "Delete %@?"):

| Key | zh-Hans |
|---|---|
| `Merge…` | `合并…` |
| `Merge %@ with…` | `将 %@ 合并到…` |
| `Keep which name?` | `保留哪个名称？` |
| `Keep "%@"` | `保留“%@”` |
| `Merge (%lld)` | `合并（%lld）` |
| `No other merchants` | `没有其他商户` |
| `There's nothing to merge %@ with yet.` | `目前没有可与 %@ 合并的商户。` |
| `%@ — %lld transactions keep the name but lose the merchant link.` | `%@ —— %lld 笔交易保留名称，但将失去商户关联。` |
| `%lld transactions will be combined` | (already present from Categories merge — verify; if missing, `将合并 %lld 笔交易`) |
| `1 transaction will be combined` | (already present — verify) |

Validate JSON after editing: `python3 -m json.tool ios/FinchApp/Sources/FinchApp/Resources/Localizable.xcstrings >/dev/null && python3 -m json.tool ios/scripts/zh-manual.json >/dev/null`.

- [ ] **Step 4: Build (validates the catalog) + manual sim pass**

Run the canonical app-build command; expect **BUILD SUCCEEDED**. Then (via the `ios-build-launch` skill, on this session's sim) verify: Settings shows **Merchants** as a top-level row (Power Tools now Rules only); rows show count pill + verified seal; search; tap → merchant detail; swipe Rename/Delete/Merge; single merge (target picker → keep-name) folds counts into the survivor; `⋯` → multi-select → Merge (N); delete shows the impact count.

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Resources/Localizable.xcstrings ios/scripts/zh-manual.json
git commit -m "i18n(ios): zh-Hans for the Merchants page + merge"
```

---

## Self-Review

**Spec coverage:**
- Decision 1 (move to top-level, rename, drop from Power Tools) → Task 3.
- Decision 2 (name-only rows, count pill, verified seal, search) → Task 3.
- Decision 3 (Rename-first swipe, verify/unverify menu, `+` and `⋯` Merge) → Task 3.
- Decision 4 (single + multi merge UI) → Task 3 (engine: Task 1).
- Decision 5 (merge semantics — id-only reassignment, target keeps verified) → Task 1.
- Decision 6 (delete-impact count) → Task 3.
- Decision 7 (drop "See in Activity feed") → Task 2.
- i18n → Task 4; testing (merge unit tests, iOS+macOS build) → Tasks 1 & 4.

**Placeholder scan:** none — complete code per code step; commands + expected results per run step. (The i18n table lists exact keys/values; two rows are marked "verify already present" with a fallback value, not a placeholder.)

**Type consistency:** `mergeCounterparty`/`mergeCounterparties` defined in Task 1 and consumed in Task 3's `merge`/`mergeMany`; `MerchantsView` (Task 3) consumes `CounterpartyDetailView` (Task 2), `CounterpartyNameSheet` (kept), `SearchableModifier`, and `mergeImpactMessage(txCount:)`; `SettingsRootList` consumes `MerchantsView`. `Counterparty` fields (`id`, `name`, `isVerified`, `ledgerId`) match the model.

## Out of scope (per spec)
Drag-reorder; dissolving Power Tools; rewriting free-text/name-matched or rule-JSON references during merge; any web/parity change.
