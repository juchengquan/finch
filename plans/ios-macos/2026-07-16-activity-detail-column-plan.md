# Activity Detail Column (iPad/macOS) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Activity feed joins the iPad/macOS three-column shell — tap a row, see a read-only transaction detail (with Edit→sheet) in the third column; regular-width `tx:` deep links select in the column instead of being dropped.

**Architecture:** Task 1 builds the self-contained `TransactionDetailView` (new file; store-resolved, privacy-aware, Quick Look receipts, Edit→existing sheet). Task 2 threads the established `selection: Binding<String?>?` convention through `ActivityFeedView` (nil path byte-for-byte unchanged) and wires `.activity` into `SplitViewShell`'s `ThreeColumnShell` with deep-link consumption.

**Tech Stack:** Swift/SwiftUI; XcodeGen; XCTest regression only (SwiftUI views — no new unit-testable logic; consistent with sibling detail views). Spec: `plans/ios-macos/2026-07-16-activity-detail-column-spec.md`.

## Global Constraints

- **`ActivityFeedView`'s `selection == nil` path must be byte-for-byte behavior-identical** — it has 3 call sites (ActivityTab, Accounts' "All Transactions" push, LedgerDetailView) plus bulk-select mode. Only additive changes gated on `selection != nil`.
- Compact/iPhone: zero behavior change. `EditTransactionSheet` itself: untouched.
- All money via `store.displayMoney*` (privacy-aware); kind icon via `TxnKindIcon` with the feed's color convention (red/green by sign).
- Build BOTH `FinchApp` (iOS) and `FinchMac` (macOS) + full `FinchAppTests`. Watch for the macOS type-check-timeout trap: keep the detail view decomposed into small section funcs.
- Commands from `ios/` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `xcodegen generate` after adding the new file. Sim fallback: a booted device's `id=<udid>`.
- Row-tap flows can't be scripted — the PR ships a short manual checklist; scripted verification covers builds/tests + iPad placeholder screenshot.

---

### Task 1: `TransactionDetailView` (new, self-contained)

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/WriteScreens/TransactionDetailView.swift`

**Interfaces:**
- Consumes (existing): `store.txns`, `displayMoney(_:from:)`, `displayMoneyBase(_:)`, `categoryName(_:)`, `attachments(for:)` → `[AttachmentRow{id, kind, relPath, originalFilename}]`, `attachmentURL(for:)`, `TxnKindIcon.icon(for:)`, `EditTransactionSheet(txn:)`, `DetailPlaceholder(systemImage:label:)`.
- Produces (consumed by Task 2): `struct TransactionDetailView: View` with `init(txId: String)`.

- [ ] **Step 1: Create the view**

```swift
import SwiftUI
import FinchCore

/// Read-only transaction detail for the iPad/macOS third column (#414 CP1).
/// Resolves the transaction live from the store so it reflects edits; the Edit
/// button opens the existing EditTransactionSheet — the sheet stays the single
/// write path (no inline editing). Compact width never shows this view.
struct TransactionDetailView: View {
    @EnvironmentObject private var store: FinchStore
    let txId: String
    @State private var editing: Tx?
    @State private var previewURL: URL?

    private var txn: Tx? { store.txns.first { $0.id == txId } }

    var body: some View {
        if let t = txn {
            List {
                headerSection(t)
                factsSection(t)
                statusSection(t)
                if let splits = t.splits, !splits.isEmpty { splitsSection(splits) }
                if let refunded = t.refundedTransactionId { refundSection(refunded) }
                receiptsSection(t)
            }
            .navigationTitle("Transaction")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = t } label: { Label("Edit", systemImage: "pencil") }
                }
            }
            .sheet(item: $editing) { EditTransactionSheet(txn: $0) }
            .quickLookPreview($previewURL)
        } else {
            // Deleted / ledger switched under us; the shell also guards.
            DetailPlaceholder(systemImage: "list.bullet", label: "Select a transaction")
        }
    }

    @ViewBuilder private func headerSection(_ t: Tx) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: TxnKindIcon.icon(for: t.kind))
                    .font(.title2)
                    .foregroundStyle(t.amount < 0 ? .red : .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.merchant).font(.headline)
                    Text(store.displayMoney(t.amount, from: t.currency))
                        .font(.title3).fontWeight(.semibold)
                        .foregroundStyle(t.amount < 0 ? .primary : Color.green)
                }
            }
        }
    }

    @ViewBuilder private func factsSection(_ t: Tx) -> some View {
        Section {
            LabeledContent("Date", value: t.time.map { "\(t.date) \($0)" } ?? t.date)
            if let cat = t.category {
                LabeledContent("Category", value: store.categoryName(cat) ?? cat)
            }
            if let acct = store.accounts.first(where: { $0.id == t.account }) {
                LabeledContent("Account", value: acct.name ?? t.account)
            }
            if let tags = t.tags, !tags.isEmpty {
                LabeledContent("Tags", value: tags.joined(separator: ", "))
            }
            if let note = t.note, !note.isEmpty {
                LabeledContent("Note", value: note)
            }
        }
    }

    @ViewBuilder private func statusSection(_ t: Tx) -> some View {
        Section {
            LabeledContent("Status", value: (t.pending ?? false) ? "Pending" : "Confirmed")
            if let cleared = t.clearedAt {
                LabeledContent("Cleared", value: String(cleared.prefix(10)))
            }
        }
    }

    @ViewBuilder private func splitsSection(_ splits: [TxSplit]) -> some View {
        Section("Splits") {
            ForEach(Array(splits.enumerated()), id: \.offset) { _, s in
                LabeledContent(store.categoryName(s.categoryId) ?? s.categoryId ?? "—",
                               value: store.displayMoneyBase(s.amountBase))
            }
        }
    }

    @ViewBuilder private func refundSection(_ refundedId: String) -> some View {
        Section {
            if let orig = store.txns.first(where: { $0.id == refundedId }) {
                LabeledContent("Refunds", value: "\(orig.merchant) · \(orig.date)")
            } else {
                LabeledContent("Refunds", value: "transaction \(refundedId)")
            }
        }
    }

    @ViewBuilder private func receiptsSection(_ t: Tx) -> some View {
        let atts = store.attachments(for: t.id)
        if !atts.isEmpty {
            Section("Receipts") {
                ForEach(atts) { att in
                    Button { previewURL = store.attachmentURL(for: att) } label: {
                        Label(att.originalFilename ?? "Receipt (\(att.kind))", systemImage: "paperclip")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build iOS (the view is unused yet — compilation is the gate)**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|reasonable time|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/TransactionDetailView.swift
git commit -m "feat(ios): TransactionDetailView — read-only inline detail for the iPad third column"
```

---

### Task 2: Feed selection mode + shell wiring + deep-link consumption

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift` (`ActivityFeedView`: new param + 3 gated changes)
- Modify: `ios/FinchApp/Sources/FinchApp/Shell/AdaptiveShell.swift` (`SplitViewShell`: `txSelection`, `.activity` branch, ledger-switch clear, focusedId consumption)

**Interfaces:**
- Consumes (Task 1): `TransactionDetailView(txId:)`. Existing: the `selection: Binding<String?>?` convention (`AccountsTab.swift:19`), `ThreeColumnShell`, `DetailPlaceholder`, `router.focusedId`/`selectedTab`.

- [ ] **Step 1: Add the selection param to `ActivityFeedView`**

After the `menuExtras` property declaration, add:
```swift
    /// Non-nil → three-column selection mode (rows select and the shell renders
    /// the detail column); nil → rows open the edit sheet. Same convention as
    /// `AccountsTab`/`BudgetsTab`/`LedgerListView` (#414/#23).
    var selection: Binding<String?>? = nil
```

- [ ] **Step 2: Bind the List to the provided binding in selection mode**

Change:
```swift
                List(selection: $kbSel) {
```
to:
```swift
                List(selection: selection ?? $kbSel) {
```

- [ ] **Step 3: Route row taps to selection in selection mode**

In `row(_:)`, change the Button action from:
```swift
        Button { isSelecting ? toggle(txn) : (editing = txn) } label: {
```
to:
```swift
        Button {
            if isSelecting { toggle(txn) }
            else if let selection { selection.wrappedValue = txn.id }
            else { editing = txn }
        } label: {
```
(Bulk-select `isSelecting` keeps priority; swipe/context menus untouched — Edit from the context menu still opens the sheet even in selection mode, which is fine and matches Accounts' rows keeping their actions.)

- [ ] **Step 4: Gate the macOS ↵-open to nil mode**

Change:
```swift
                .onKeyPress(.return) {
                    if !isSelecting, let id = kbSel, let txn = sections.flatMap({ $0.txns }).first(where: { $0.id == id }) { editing = txn; return .handled }
                    return .ignored
                }
```
to:
```swift
                .onKeyPress(.return) {
                    // In three-column selection mode the selection already drives
                    // the detail column — ↵ falls through (kbSel is unused there).
                    if !isSelecting, selection == nil, let id = kbSel,
                       let txn = sections.flatMap({ $0.txns }).first(where: { $0.id == id }) { editing = txn; return .handled }
                    return .ignored
                }
```

- [ ] **Step 5: Wire `.activity` into `SplitViewShell`**

Add the state (next to `budgetSelection`):
```swift
    @State private var txSelection: String?
```

Insert a `case .activity:` branch before `default:`:
```swift
            case .activity:
                ThreeColumnShell {
                    ActivityFeedView(consumesPendingFilter: true, selection: $txSelection)
                } detail: {
                    // Guard against a stale selection (deleted tx / ledger switch).
                    if let id = txSelection, store.txns.contains(where: { $0.id == id }) {
                        NavigationStack { TransactionDetailView(txId: id) }
                    } else {
                        DetailPlaceholder(systemImage: "list.bullet", label: "Select a transaction")
                    }
                }
```

Extend the ledger-switch invalidation:
```swift
        .onChange(of: store.activeLedgerId) { _, _ in
            accountSelection = nil
            budgetSelection = nil
            txSelection = nil
        }
```

Add regular-width deep-link consumption (a `tx:` route sets `.activity` + `focusedId`; compact consumes it in TabBarShell — mirror that here). On the same `Group` as the `onChange` above, add:
```swift
        // A `tx:` deep link (Spotlight / notification) on regular width: select
        // the transaction in the Activity detail column (compact shows the edit
        // sheet instead — see TabBarShell.focusedTx).
        .onChange(of: router.focusedId) { _, id in
            guard router.selectedTab == .activity, let id,
                  store.txns.contains(where: { $0.id == id }) else { return }
            txSelection = id
            router.focusedId = nil
        }
        .onAppear {
            if router.selectedTab == .activity, let id = router.focusedId,
               store.txns.contains(where: { $0.id == id }) {
                txSelection = id
                router.focusedId = nil
            }
        }
```

- [ ] **Step 6: Build both platforms + full FinchAppTests**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|reasonable time|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" -only-testing:FinchAppTests 2>&1 | grep -iE "Executed .* tests|TEST SUCCEEDED|TEST FAILED"
```
Expected: both builds SUCCEED; suite green (no behavior change on the nil path).

- [ ] **Step 7: iPad + iPhone simulator checks (scripted parts)**

- iPad (create/boot per the `ios-build-launch` skill; fresh sim per the #441 restoration-key gotcha): install, `xcrun simctl launch <pad> com.juchengquan.finch -initialTab activity`, screenshot → expect sidebar │ feed │ **"Select a transaction"** placeholder.
- iPhone (`finch-fresh-6` or similar): launch, Accounts → confirm nothing changed by inspection of the build (row-tap behavior is compile-gated on `selection == nil`); screenshot the feed for the record.
- Row-tap/detail/Edit flows: **manual checklist** (ships in the PR body):
  1. iPad: tap a feed row → detail fills the third column; tap another → updates.
  2. Edit → sheet → change amount → save → detail reflects it.
  3. Delete the selected row from the feed (swipe) → placeholder returns.
  4. iPhone: feed rows still open the edit sheet directly.
  5. (If Spotlight is populated) tap a transaction result on iPad → it selects in the column.

- [ ] **Step 8: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift \
        ios/FinchApp/Sources/FinchApp/Shell/AdaptiveShell.swift
git commit -m "feat(ios): Activity joins the three-column shell — selection mode + detail column + deep-link select"
```

---

## Self-Review

**1. Spec coverage:** detail view content/toolbar/fallback → Task 1 (all sections incl. splits/refund/receipts-QuickLook, Edit→sheet); selection convention + nil-path preservation (List binding, row action, ↵ gate — the ONLY three touch points, each gated on `selection`) → Task 2 Steps 1-4; shell branch + ledger-switch clear + placeholder guard → Task 2 Step 5; deep-link consumption (onChange + onAppear for the already-set case) → Task 2 Step 5; compact unchanged (all changes gated) → constraints; builds/tests/iPad screenshot + manual checklist → Task 2 Steps 6-7. ✅
**2. Placeholder scan:** none — full code everywhere.
**3. Type consistency:** `TransactionDetailView(txId:)` matches Task 2's usage; `selection ?? $kbSel` type-checks (`Binding<String?>`); `AttachmentRow.originalFilename/kind` and `TxSplit.categoryId/amountBase` verified against Models; `ActivityFeedView(consumesPendingFilter:selection:)` uses existing + new params (property-default init).
