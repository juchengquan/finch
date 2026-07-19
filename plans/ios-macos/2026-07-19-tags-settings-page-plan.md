# Tags Settings Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Tags admin out of Power Tools to a Settings top-level page and restyle it to match the Categories page (search, color-swatch rows with a tx-count pill, tap→transactions detail, swipe Edit/Delete, + to add).

**Architecture:** One new read-only `FinchCore` selector (`tagTransactions`) powers a new `TagDetailView`; the renamed `TagsView` (was `TagAdminView`) mirrors `CategoriesView`'s layout and reuses the existing `TagEditSheet` + the three existing tag write-actions; `SettingsTab` gains a top-level row and drops the Power Tools one. No new mutations, schema, wire, or web change.

**Tech Stack:** Swift / SwiftUI, FinchCore (SwiftPM, GRDB), XcodeGen-generated app project, XCTest.

**Reference spec:** `plans/ios-macos/2026-07-19-tags-settings-page-design.md`

## Global Constraints

- **No engine actions/schema/wire change.** The only `FinchCore` change is the pure read-only `tagTransactions` selector. All writes reuse existing chokepoints: `createTag`, `updateTag`, `deleteTag` (via `store.apply(...)`). No parity fixtures.
- **SwiftUI-first**; deployment floor **iOS 17 / macOS 14** (no newer-only APIs).
- **Tags are flat / color-only / name-ordered** (`TagRow { id, name, color }`) — no hierarchy, kind, icon, or `sortOrder`. Out of scope: merge, reorder, icons, kind split.
- **XcodeGen:** the app project is generated + git-ignored. After adding/renaming any file under `FinchApp/Sources/`, run `xcodegen generate` (in `ios/`) before building.
- **xcodebuild** needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (local `xcode-select` points at CommandLineTools).
- **Cross-platform:** `SettingsRootList` is shared with the macOS Preferences window — no Mac-specific work needed.
- **Commits:** conventional `feat(ios):` / `refactor(ios):` / `test(ios):`; **no `Co-Authored-By` trailer**.
- **All commands run from the worktree root** (`/private/tmp/finch-tagspage`); `swift test` / `xcodegen` run from `ios/`.

**Canonical app-build command** (used as the verification gate for UI tasks):
```bash
cd ios && xcodegen generate && cd ..
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -scheme FinchApp -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/finchios-tags -quiet
```

---

### Task 1: `tagTransactions` selector (FinchCore)

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift` (add after `categoryTransactions`, ~line 249)
- Test: `ios/FinchCore/Tests/FinchCoreTests/TagTransactionsTests.swift` (create)

**Interfaces:**
- Consumes: existing `Selectors.tagTxCounts(_:_:)`, `Selectors.ledgerOf(_:)`, `Tx` (has `tags: [String]?`, `ledgerId`, `pending`, `date`, `time`).
- Produces: `Selectors.tagTransactions(_ txns: [Tx], _ tagId: String, _ ledgerId: String) -> [Tx]` — non-pending, in-ledger, `tags` contains `tagId`; date-desc (time-desc tiebreak). Agrees with `tagTxCounts[tagId]` by construction.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchCore/Tests/FinchCoreTests/TagTransactionsTests.swift`:

```swift
import XCTest
@testable import FinchCore

final class TagTransactionsTests: XCTestCase {
    private func tx(_ id: String, tags: [String]? = nil, date: String = "2026-05-01",
                    pending: Bool = false, ledger: String = "l1") -> Tx {
        Tx(id: id, merchant: "m", amount: -5, account: "a1", date: date,
           pending: pending, ledgerId: ledger, tags: tags)
    }

    func test_matches_tagged_newest_first() {
        let out = Selectors.tagTransactions(
            [tx("a", tags: ["tagA"], date: "2026-06-01"),
             tx("b", tags: ["tagA"], date: "2026-06-03"),
             tx("c", tags: ["tagB"], date: "2026-06-02")], "tagA", "l1")
        XCTAssertEqual(out.map(\.id), ["b", "a"])   // date-desc; tagB excluded
    }

    func test_multi_tag_txn_matched() {
        let out = Selectors.tagTransactions([tx("t1", tags: ["tagA", "tagB"])], "tagB", "l1")
        XCTAssertEqual(out.map(\.id), ["t1"])
    }

    func test_excludes_pending_and_other_ledger() {
        let out = Selectors.tagTransactions(
            [tx("t1", tags: ["tagA"]),
             tx("t2", tags: ["tagA"], pending: true),
             tx("t3", tags: ["tagA"], ledger: "l2")], "tagA", "l1")
        XCTAssertEqual(out.map(\.id), ["t1"])
    }

    func test_untagged_absent() {
        XCTAssertTrue(Selectors.tagTransactions([tx("t1")], "tagA", "l1").isEmpty)
    }

    func test_agrees_with_tagTxCounts() {
        let txns = [tx("t1", tags: ["tagA"]), tx("t2", tags: ["tagA", "tagB"]),
                    tx("t3", tags: ["tagA"], pending: true), tx("t4", tags: ["tagB"], ledger: "l2")]
        let counts = Selectors.tagTxCounts(txns, "l1")
        XCTAssertEqual(Selectors.tagTransactions(txns, "tagA", "l1").count, counts["tagA"] ?? 0)
        XCTAssertEqual(Selectors.tagTransactions(txns, "tagB", "l1").count, counts["tagB"] ?? 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && swift test --filter TagTransactionsTests`
Expected: **build failure** — `type 'Selectors' has no member 'tagTransactions'`.

- [ ] **Step 3: Write minimal implementation**

In `ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift`, immediately after the `categoryTransactions(...)` function (ends ~line 249), add:

```swift
    /// Transactions in `ledgerId` tagged with `tagId`, matched the SAME way as
    /// `tagTxCounts` (non-pending; `tx.tags` holds tag ids), so this list agrees
    /// with the count badge. Date-desc sorted (time-desc tiebreak).
    public static func tagTransactions(_ txns: [Tx], _ tagId: String, _ ledgerId: String) -> [Tx] {
        let matched = txns.filter { t in
            guard ledgerOf(t) == ledgerId else { return false }
            if (t.pending ?? false) { return false }
            return (t.tags ?? []).contains(tagId)
        }
        return matched.sorted { $0.date != $1.date ? $0.date > $1.date : ($0.time ?? "") > ($1.time ?? "") }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ios && swift test --filter TagTransactionsTests`
Expected: **PASS** (5 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/FinchCore/Sources/FinchCore/Selectors/Selectors.swift ios/FinchCore/Tests/FinchCoreTests/TagTransactionsTests.swift
git commit -m "feat(ios): tagTransactions selector (mirrors categoryTransactions/tagTxCounts)"
```

---

### Task 2: Promote `SearchableModifier` to a shared file

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Common/SearchableModifier.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift` (remove the private `SearchableModifier`, ~lines 555–566)

**Interfaces:**
- Produces: `struct SearchableModifier: ViewModifier` (internal) with `init(text: Binding<String>)`, usable as `.modifier(SearchableModifier(text: $search))` from both Categories and Tags.

- [ ] **Step 1: Create the shared modifier**

Create `ios/FinchApp/Sources/FinchApp/Common/SearchableModifier.swift`:

```swift
import SwiftUI

/// Cross-platform searchable placement: on iOS the search bar stays visible
/// (`.navigationBarDrawer(displayMode: .always)`); default placement on macOS.
/// Shared by the Categories and Tags admin pages.
struct SearchableModifier: ViewModifier {
    @Binding var text: String
    func body(content: Content) -> some View {
        #if os(iOS)
        content.searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always))
        #else
        content.searchable(text: $text)
        #endif
    }
}
```

- [ ] **Step 2: Remove the duplicate from `CategoriesView.swift`**

Delete this block at the bottom of `ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift` (the private copy — `CategoriesView` keeps calling `.modifier(SearchableModifier(text: $search))`, now resolving to the shared one):

```swift
/// Cross-platform search: uses `.navigationBarDrawer(displayMode:.always)` on iOS
/// (keeps search bar always visible) and the default placement on macOS.
private struct SearchableModifier: ViewModifier {
    @Binding var text: String
    func body(content: Content) -> some View {
        #if os(iOS)
        content.searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always))
        #else
        content.searchable(text: $text)
        #endif
    }
}
```

- [ ] **Step 3: Build to verify (regen + compile)**

Run the canonical app-build command (see Global Constraints).
Expected: **BUILD SUCCEEDED** (Categories search still compiles against the shared modifier).

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Common/SearchableModifier.swift ios/FinchApp/Sources/FinchApp/PowerTools/CategoriesView.swift ios/FinchApp.xcodeproj
git commit -m "refactor(ios): promote SearchableModifier to a shared Common/ file"
```

---

### Task 3: `TagDetailView` (a tag's transactions)

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/PowerTools/TagDetailView.swift`

**Interfaces:**
- Consumes: `Selectors.tagTransactions` (Task 1), `TagRow`, `TxRow`, `EditTransactionSheet(txn:)`, `AddTransactionSheet(prefill:)`, `store.displayMoneyBase(_:)`.
- Produces: `struct TagDetailView { init(tag: TagRow) }` — pushed by `TagsView` (Task 4).

- [ ] **Step 1: Create the view**

Create `ios/FinchApp/Sources/FinchApp/PowerTools/TagDetailView.swift`:

```swift
import SwiftUI
import FinchCore

/// A tag's transactions + aggregate stats. Pushed from the Tags page when a row
/// is tapped. Mirrors `CategoryDetailView`: membership matches the row's count
/// badge (`tagTransactions` ≙ `tagTxCounts`, i.e. non-pending, tagged in this ledger).
struct TagDetailView: View {
    @EnvironmentObject private var store: FinchStore
    let tag: TagRow
    @State private var editing: Tx?
    @State private var duplicating: Tx?   // Duplicate → Add sheet pre-filled

    private var txns: [Tx] {
        Selectors.tagTransactions(store.txns, tag.id, store.activeLedgerId)
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
                        Button { editing = tx } label: { TxRow(txn: tx, showRunningBalance: false).contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                            .swipeActions(edge: .leading) {
                                if ["expense", "income"].contains(tx.kind ?? "") {
                                    Button { duplicating = tx } label: { Label("Duplicate", systemImage: "plus.square.on.square") }.tint(.indigo)
                                }
                            }
                            .contextMenu {
                                Button { editing = tx } label: { Label("Edit", systemImage: "pencil") }
                                if ["expense", "income"].contains(tx.kind ?? "") {
                                    Button { duplicating = tx } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle(tag.name)
        .sheet(item: $editing) { EditTransactionSheet(txn: $0) }
        .sheet(item: $duplicating) { AddTransactionSheet(prefill: $0) }
    }
}
```

- [ ] **Step 2: Build to verify (regen + compile)**

Run the canonical app-build command (see Global Constraints).
Expected: **BUILD SUCCEEDED** (view compiles; not yet referenced anywhere).

- [ ] **Step 3: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/PowerTools/TagDetailView.swift ios/FinchApp.xcodeproj
git commit -m "feat(ios): TagDetailView — a tag's transactions + stats (mirrors CategoryDetailView)"
```

---

### Task 4: `TagsView` (rename + restyle) and Settings wiring

**Files:**
- Rename: `ios/FinchApp/Sources/FinchApp/PowerTools/TagAdminView.swift` → `ios/FinchApp/Sources/FinchApp/PowerTools/TagsView.swift`
- Modify (in the renamed file): `struct TagAdminView` → `struct TagsView`, new list body; **keep `TagEditSheet` unchanged**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift` (add top-level row at ~line 38; remove Power Tools Tags row at ~line 136)

**Interfaces:**
- Consumes: `SearchableModifier` (Task 2), `TagDetailView` (Task 3), `TagEditSheet` (kept), `Selectors.tagTxCounts`, `store.tags`, `store.apply(.deleteTag, ...)`, `Color(hex:)`, `Args`, `i18nMessage`.
- Produces: `struct TagsView` (no-arg init), referenced by `SettingsRootList`.

- [ ] **Step 1: Rename the file (preserve history)**

```bash
git mv ios/FinchApp/Sources/FinchApp/PowerTools/TagAdminView.swift ios/FinchApp/Sources/FinchApp/PowerTools/TagsView.swift
```

- [ ] **Step 2: Replace the `TagAdminView` struct with `TagsView`**

In `ios/FinchApp/Sources/FinchApp/PowerTools/TagsView.swift`, replace the entire `struct TagAdminView: View { … }` (the top struct, ending just before `struct TagEditSheet`) with the following. **Leave `struct TagEditSheet` below it untouched.**

```swift
/// Tags admin — a flat, color-only list (Settings top-level). Mirrors the
/// Categories page: search, color-swatch rows with a transaction-count pill,
/// tap → the tag's transactions, swipe Edit/Delete, + to add. All through the
/// existing chokepoints (create / update / deleteTag). Tags have no hierarchy,
/// kind, icon, or order — so no tree, kind picker, reorder, or merge here.
struct TagsView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var selectedTagId: String?          // tapped row → transactions
    @State private var creating = false
    @State private var editing: TagRow?
    @State private var deleting: TagRow?
    @State private var search = ""
    @State private var errorMessage: String?

    private var rows: [TagRow] {
        guard !search.isEmpty else { return store.tags }
        return store.tags.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        let counts = Selectors.tagTxCounts(store.txns, store.activeLedgerId)
        return List {
            if store.tags.isEmpty {
                emptyState
            } else {
                ForEach(rows) { tag in row(tag, counts) }
            }
        }
        .modifier(SearchableModifier(text: $search))
        .navigationTitle("Tags")
        .errorAlert($errorMessage)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New tag")
            }
        }
        .navigationDestination(item: $selectedTagId) { id in
            if let t = store.tags.first(where: { $0.id == id }) { TagDetailView(tag: t) }
        }
        .sheet(isPresented: $creating) { TagEditSheet(tag: nil) }
        .sheet(item: $editing) { TagEditSheet(tag: $0) }
        // Centered window-level alert (matches Categories/Activity deletes).
        .alert("Delete \(deleting?.name ?? "")?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting) { t in
            Button("Delete", role: .destructive) { delete(t) }
            Button("Cancel", role: .cancel) {}
        } message: { t in
            let n = counts[t.id] ?? 0
            if n > 0 { Text("\(t.name) is removed from \(n) transactions.") }
        }
    }

    /// A tag row: color swatch + name + count pill + a trailing chevron (every
    /// row navigates to its detail). Tap opens transactions; Edit/Delete are on
    /// the swipe (Edit is the full-swipe default) and context menu.
    @ViewBuilder private func row(_ tag: TagRow, _ counts: [String: Int]) -> some View {
        Button { selectedTagId = tag.id } label: {
            HStack(spacing: 10) {
                Circle().fill(Color(hex: tag.color ?? "") ?? .secondary).frame(width: 26, height: 26)
                Text(tag.name).foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let n = counts[tag.id], n > 0 {
                    Text("\(n)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .accessibilityLabel("\(n) transactions")
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            // Edit declared first ⇒ outer edge / full-swipe default (never delete).
            Button { editing = tag } label: { Label("Edit", systemImage: "pencil") }.tint(.accentColor)
            // Not role: .destructive — the alert confirms; matches Categories.
            Button { deleting = tag } label: { Label("Delete", systemImage: "trash") }.tint(.red)
        }
        .contextMenu {
            Button { editing = tag } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { deleting = tag } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tag").font(.largeTitle).foregroundStyle(.secondary)
            Text("No tags yet").font(.headline)
            Text("Tap + to add one.").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func delete(_ t: TagRow) {
        errorMessage = nil
        do { try store.apply(.deleteTag, Args(["id": .string(t.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
}
```

- [ ] **Step 3: Wire Settings — add top-level row, drop the Power Tools row**

In `ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift`, in `SettingsRootList`, add the Tags link right after the Categories link:

```swift
                NavigationLink { CategoriesView() } label: { Label("Categories", systemImage: "square.grid.2x2") }
                NavigationLink { TagsView() } label: { Label("Tags", systemImage: "tag") }
```

Then in `SettingsPowerToolsView`, remove the Tags row (leaving Rules + Merchants):

```swift
        List {
            NavigationLink("Rules") { RulesManagerView() }
            NavigationLink("Merchants") { CounterpartyAdminView() }
        }
```

- [ ] **Step 4: Build to verify (regen + compile)**

Run the canonical app-build command (see Global Constraints).
Expected: **BUILD SUCCEEDED** (no remaining reference to `TagAdminView`; `TagsView` resolves `SearchableModifier`, `TagDetailView`, `TagEditSheet`).

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/PowerTools/TagsView.swift ios/FinchApp/Sources/FinchApp/Tabs/SettingsTab.swift ios/FinchApp.xcodeproj
git commit -m "feat(ios): Tags → Settings top-level with a Categories-style page (rename TagAdminView→TagsView)"
```

---

### Task 5: Localization + full verification

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Resources/Localizable.xcstrings` (regenerated)
- Modify (if needed): `ios/scripts/zh-manual.json` (zh-Hans for any new key the web map doesn't cover)

**Interfaces:** none (mechanical + manual verification).

- [ ] **Step 1: Run the full FinchCore test suite**

Run: `cd ios && swift test`
Expected: **PASS** (all `FinchCoreTests` + `ParityTests`, incl. `TagTransactionsTests`; parity unaffected — no new actions).

- [ ] **Step 2: Regenerate the zh-Hans string catalog**

Follow the 3-step pipeline documented atop `ios/scripts/build-xcstrings.ts` (export → `xliff-keys.ts` → `build-xcstrings.ts`). New user-facing keys introduced by this feature: `"Tags"`, `"New tag"`, `"No tags yet"`, `"Tap + to add one."`, `"%@ is removed from %lld transactions."`, and (reused, already localized) `"Transactions"`, `"Total"`, `"Average"`, `"Delete %@?"`, `"Edit"`, `"Delete"`, `"Duplicate"`.

Run: `cd ios && bun scripts/build-xcstrings.ts`
Then confirm the new keys have `zh-Hans` values (add them to `ios/scripts/zh-manual.json` and re-run if the web map didn't cover them — keep the tag term **标签**).

- [ ] **Step 3: Manual simulator verification**

Build/install/launch on the session sim (use the `ios-build-launch` skill), then verify:
- Settings shows **Tags** as a top-level row (after Categories) and **Power Tools** now shows only **Rules, Merchants**.
- Tags list: color swatches + names + count pills + chevrons; **search** filters by name; empty state reads "No tags yet".
- **Tap** a tag → `TagDetailView` (stats header + its transactions); tapping a tx opens Edit.
- **Swipe** a row: full-swipe → Edit sheet; Delete → centered alert with "…removed from N transactions." → tag gone; the count matches the badge.
- **+** → new-tag sheet; save adds it.
- (Optional) macOS Preferences window shows the Tags row.

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Resources/Localizable.xcstrings ios/scripts/zh-manual.json
git commit -m "i18n(ios): zh-Hans for the Tags Settings page"
```

---

## Self-Review

**Spec coverage** (each design decision → task):
- Decision 1 (move to Settings top-level, rename, drop Power Tools link, macOS via shared list) → Task 4.
- Decision 2 (Categories-style rows, search, swatch/name/count pill, chevron divergence) → Task 4 (+ shared `SearchableModifier` Task 2).
- Decision 3 (tap → `TagDetailView`) → Tasks 3 (+ 4 wiring); data via `tagTransactions` Task 1.
- Decision 4 (swipe/context Edit+Delete; reuse `TagEditSheet`; + toolbar) → Task 4.
- Decision 5 (delete-impact count alert) → Task 4.
- Decision 6 (toolbar +) → Task 4.
- Decision 7 (empty state) → Task 4.
- `Selectors.tagTransactions` (only engine change) → Task 1. i18n → Task 5. Testing → Tasks 1 & 5.

**Placeholder scan:** none — every code step shows complete code; every run step shows a command + expected result.

**Type consistency:** `tagTransactions(_ txns:[Tx], _ tagId:String, _ ledgerId:String) -> [Tx]` defined in Task 1 and consumed in Task 3; `TagsView` (Task 4) consumes `TagDetailView` (Task 3), `SearchableModifier` (Task 2), and the kept `TagEditSheet`; `SettingsRootList` consumes `TagsView`. `TagRow` fields (`id`, `name`, `color`) and actions (`.deleteTag`) match the codebase.

## Out of scope (future phases, mirroring Categories)
Tag merge (`mergeTag`/`mergeTags` engine + parity), drag-reorder (tag `sortOrder` column + action), icons, kind split, hierarchy.
