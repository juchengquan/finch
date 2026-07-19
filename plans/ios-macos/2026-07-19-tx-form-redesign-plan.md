# Add/Edit transaction form redesign — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Reorder the expense/income Add+Edit fields (Account · Amount · Category · Date & time first; Merchant+Note last), turn the shared single-select picker into a bottom sheet, replace the tag checklist with wrapping toggle chips (+ show-all cap), and make the Add sheet's top translucent on scroll.

**Architecture:** UI-only in `ios/FinchApp`. Two new small components (`FlowLayout`, `TagChipFlow`) + one converted component (`SearchablePickerRow`). Engine untouched. Spec: `plans/ios-macos/2026-07-19-tx-form-redesign-design.md`.

## Global Constraints

- Build **both** FinchApp (iOS) and FinchMac per task; run FinchAppTests per task.
- `xcodegen generate` after adding files (Tasks 1). Commits: no `Co-Authored-By`.
- Session sim resolved by name (`ios-finch`); `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- No engine changes; save-arg shapes and merchant auto-categorization unchanged.

**Shared build/test block (from worktree root):**
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
UDID=$(xcrun simctl list devices | grep "ios-finch (" | grep -oE '[0-9A-F-]{36}')
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp -destination "id=$UDID" 2>&1 | grep -E "error: |BUILD (SUCCEEDED|FAILED)"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error: |BUILD (SUCCEEDED|FAILED)"
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination "id=$UDID" -only-testing:FinchAppTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed .* tests"
```

---

### Task 1: `FlowLayout` + `TagChipFlow` (+ TDD'd show-all partition)

**Files:**
- Create `ios/FinchApp/Sources/FinchApp/WriteScreens/FlowLayout.swift`
- Create `ios/FinchApp/Sources/FinchApp/WriteScreens/TagChipFlow.swift`
- Create `ios/FinchApp/Tests/FinchAppTests/TagChipFlowTests.swift`

**Interfaces produced:** `TagChipFlow(tags: [TagRow], selected: Binding<Set<String>>)`; `TagChipFlow.collapsedVisible(tags:selected:cap:) -> [TagRow]` (pure, tested).

- [ ] **Step 1: failing test** — `TagChipFlowTests.swift`:

```swift
import XCTest
@testable import FinchApp
import FinchCore

final class TagChipFlowTests: XCTestCase {
    private func tags(_ ids: [String]) -> [TagRow] { ids.map { TagRow(id: $0, name: $0, color: nil) } }

    func test_underCap_showsAll() {
        let all = tags(["a","b","c"])
        let vis = TagChipFlow.collapsedVisible(tags: all, selected: [], cap: 10)
        XCTAssertEqual(vis.map(\.id), ["a","b","c"])
    }

    func test_overCap_truncatesToCap_preservingOrder() {
        let all = tags((1...15).map { "t\($0)" })
        let vis = TagChipFlow.collapsedVisible(tags: all, selected: [], cap: 10)
        XCTAssertEqual(vis.count, 10)
        XCTAssertEqual(vis.first?.id, "t1")
    }

    func test_selectedAlwaysVisible_evenBeyondCap() {
        let all = tags((1...15).map { "t\($0)" })
        // t14 is selected but sits past the cap — must still appear.
        let vis = TagChipFlow.collapsedVisible(tags: all, selected: ["t14"], cap: 10)
        XCTAssertTrue(vis.contains { $0.id == "t14" })
        XCTAssertLessThanOrEqual(vis.count, 11)   // cap unselected + the pulled-in selected
        // No duplicates.
        XCTAssertEqual(Set(vis.map(\.id)).count, vis.count)
    }

    func test_manySelected_allSelectedShown() {
        let all = tags((1...15).map { "t\($0)" })
        let sel = Set((11...15).map { "t\($0)" })
        let vis = TagChipFlow.collapsedVisible(tags: all, selected: sel, cap: 10)
        for id in sel { XCTAssertTrue(vis.contains { $0.id == id }, "\(id) missing") }
    }
}
```

- [ ] **Step 2: run — fails** (undefined). Shared block's test line.

- [ ] **Step 3: `FlowLayout.swift`**:

```swift
import SwiftUI

/// A wrapping layout: places subviews left-to-right, breaking to a new row when
/// the next subview would overflow the proposed width. iOS 17 `Layout`.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0, rowHeight: CGFloat = 0, totalHeight: CGFloat = 0, totalWidth: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + s.width > maxWidth {
                totalHeight += rowHeight + rowSpacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = s.width; rowHeight = s.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + s.width
                rowHeight = max(rowHeight, s.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxX = bounds.maxX
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > maxX {
                x = bounds.minX; y += rowHeight + rowSpacing; rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
```

- [ ] **Step 4: `TagChipFlow.swift`**:

```swift
import SwiftUI
import FinchCore

/// Multi-select tag picker rendered as wrapping toggle chips (replaces the
/// one-tag-per-row checklist). Selected chips fill in the tag's color; tapping
/// toggles. A "Show all (N)" / "Show less" control caps the collapsed height for
/// large tag sets — but every SELECTED tag is always visible (never hidden).
struct TagChipFlow: View {
    let tags: [TagRow]
    @Binding var selected: Set<String>
    var cap: Int = 10
    @State private var expanded = false

    /// Collapsed visible set: every selected tag, plus unselected tags in order
    /// up to `cap`, preserving original order and without duplicates.
    static func collapsedVisible(tags: [TagRow], selected: Set<String>, cap: Int) -> [TagRow] {
        var unselectedBudget = cap
        var out: [TagRow] = []
        for t in tags {
            if selected.contains(t.id) { out.append(t) }
            else if unselectedBudget > 0 { out.append(t); unselectedBudget -= 1 }
        }
        return out
    }

    private var visible: [TagRow] { expanded ? tags : Self.collapsedVisible(tags: tags, selected: selected, cap: cap) }
    private var hiddenCount: Int { tags.count - visible.count }

    var body: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(visible) { tag in
                chip(tag)
            }
            if !expanded, hiddenCount > 0 {
                Button { expanded = true } label: { pill("Show all (\(tags.count))", filled: false, tint: .secondary) }
                    .buttonStyle(.plain)
            } else if expanded, tags.count > cap {
                Button { expanded = false } label: { pill("Show less", filled: false, tint: .secondary) }
                    .buttonStyle(.plain)
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private func chip(_ tag: TagRow) -> some View {
        let isOn = selected.contains(tag.id)
        let tint = Color(hex: tag.color ?? "") ?? .accentColor
        return Button {
            if isOn { selected.remove(tag.id) } else { selected.insert(tag.id) }
        } label: {
            pill(tag.name, filled: isOn, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func pill(_ text: String, filled: Bool, tint: Color) -> some View {
        Text(text)
            .font(.callout)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(filled ? Color.white : tint)
            .background(filled ? tint : tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(filled ? 0 : 0.4)))
    }
}
```

- [ ] **Step 5: run shared block** — both builds green, tests pass (4 new).
- [ ] **Step 6: commit** — `feat(ios): FlowLayout + TagChipFlow (wrapping tag chips w/ show-all cap)`

---

### Task 2: `SearchablePickerRow` → bottom sheet

**Files:** Modify `ios/FinchApp/Sources/FinchApp/WriteScreens/SearchablePickerRow.swift`

- [ ] **Step 1** — replace the whole file with:

```swift
import SwiftUI

/// One option in a `SearchablePickerRow` — an id + its display name.
struct PickerOption: Identifiable, Hashable {
    let id: String
    let name: String
}

/// A form row that shows the current selection and opens a full-height BOTTOM
/// SHEET (slides up from the bottom) with a searchable single-select list —
/// replacing the older pushed nav list. Drop-in: same (title, options,
/// selection) API, so every call site upgrades at once.
struct SearchablePickerRow: View {
    let title: String
    let options: [PickerOption]
    @Binding var selection: String
    @State private var presented = false

    private var selectedName: String { options.first { $0.id == selection }?.name ?? "—" }

    var body: some View {
        Button { presented = true } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(selectedName).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $presented) {
            SearchablePickerSheet(title: title, options: options, selection: $selection)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }
}

/// The sheet body: searchable, single-select, dismisses on choose or Cancel.
private struct SearchablePickerSheet: View {
    let title: String
    let options: [PickerOption]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [PickerOption] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? options : options.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { opt in
                Button {
                    selection = opt.id
                    dismiss()
                } label: {
                    HStack {
                        Text(opt.name)
                        Spacer()
                        if opt.id == selection { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $query)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
```

- [ ] **Step 2: run shared block** — both builds green; tests still pass.
- [ ] **Step 3: sim check** — install; open Add sheet (`finch://add`); tap Category → confirm a sheet slides up from the bottom (screenshot). Commit — `feat(ios): SearchablePickerRow opens a bottom sheet instead of a pushed list`

---

### Task 3: Add sheet — field reorder + tag chips

**Files:** Modify `ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift`

- [ ] **Step 1: reorder `expenseIncomeFields(for:)`.** Replace the current body (Amount, Merchant, Category, Split, Account, Refund) with a primary section holding Account, Amount, Category — plus keep Split/Refund here, and move Merchant out:

```swift
    @ViewBuilder private func expenseIncomeFields(for k: Kind) -> some View {
        Section {
            SearchablePickerRow(title: "Account",
                options: accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $accountId)
            amountField
            if pendingSplits == nil {
                SearchablePickerRow(title: "Category",
                    options: categories(for: k).map { PickerOption(id: $0.id, name: $0.name) }, selection: $categoryId)
            }
            DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .environment(\.locale, AppDate.h24Locale)
            if k != .refund, DecimalInput.parse(amount) ?? 0 != 0 {
                Button {
                    showingSplit = true
                } label: {
                    HStack {
                        Text(pendingSplits == nil ? "Split…" : "Split across \(pendingSplits!.count) categories")
                        Spacer()
                        if pendingSplits != nil { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if k == .refund {
                Button { showingRefundPicker = true } label: {
                    HStack {
                        Text("Refunds")
                        Spacer()
                        Text(refundedSummary).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Merchant/Source + Note — optional free-text, shown as the LAST section.
    @ViewBuilder private func detailsSection(for k: Kind) -> some View {
        Section("Details") {
            HStack {
                Text(k == .income ? "Source" : "Merchant"); Spacer()
                TextField("", text: $merchant).multilineTextAlignment(.trailing)
            }
            merchantSuggestionRows
            HStack {
                Text("Note"); Spacer()
                TextField("Optional", text: $note, axis: .vertical).multilineTextAlignment(.trailing)
            }
        }
    }
```

- [ ] **Step 2: rework `formPage(_:)`** — the Date/Note section that currently sits after the fields must drop its Date row (now in the primary section) and its Note (now in Details); the Tags section becomes the chip flow; add the Details section at the very bottom. In `formPage`, replace:

```swift
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, AppDate.h24Locale)   // 24-hour time wheel regardless of device setting
                    HStack {
                        Text("Note"); Spacer()
                        TextField("Optional", text: $note, axis: .vertical).multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    Picker("Status", selection: $status) {
```
with (Date+Note section removed; Status kept):
```swift
                Section {
                    Picker("Status", selection: $status) {
```

- [ ] **Step 3** — replace the inline Tags section:
```swift
                if !store.tags.isEmpty {
                    Section("Tags") {
                        ForEach(store.tags) { tag in
                            Button { toggleTag(tag.id) } label: {
                                HStack {
                                    Text(tag.name).foregroundStyle(.primary)
                                    Spacer()
                                    if selectedTags.contains(tag.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                            }
                        }
                    }
                }
```
with:
```swift
                if !store.tags.isEmpty {
                    Section("Tags") { TagChipFlow(tags: store.tags, selected: $selectedTags) }
                }
```

- [ ] **Step 4** — add the Details section at the very bottom of `formPage`, immediately AFTER the Receipt section's closing brace and BEFORE the `if let errorMessage` section:
```swift
                if k == .expense || k == .income || k == .refund {
                    detailsSection(for: k)
                }
```
(Transfer has no merchant field today — keep it out for `.transfer`.)

- [ ] **Step 5** — `toggleTag` is now unused in this file; if the compiler warns unused, leave it (Edit still uses its own). Confirm no other reference broke. Run the shared block — both builds green, tests pass.
- [ ] **Step 6: sim check + commit** — install, screenshot the expense Add form shows Account/Amount/Category/Date then Tags chips then Details last. Commit — `feat(ios): Add sheet — reorder fields + wrapping tag chips`

---

### Task 4: Edit sheet — field reorder + tag chips

**Files:** Modify `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift`

The Edit sheet interleaves split/transfer branches. Only the **line-item** (`else`) branch reorders; split and transfer branches keep their structure. Target line-item order: primary section (Account, Amount+currency, Category, Date), then Split button, then Refund/Tags/Receipts, then Details (Merchant/Note) last.

- [ ] **Step 1** — the first `Section` (Merchant, Note, Date) loses Merchant+Note+Date. Replace the first section (lines ~157–169) with nothing for line items (its rows move); but split/transfer branches still need Date. Simplest correct approach: keep a top section that holds ONLY the Date for split/transfer, and build the full primary section inside the line-item branch. Replace the first `Section { Merchant, Note, Date }` with:

```swift
                // Line items build their own primary section (Account/Amount/
                // Category/Date) below; split & transfer keep Date here.
                if isSplit || transferLegs != nil {
                    Section {
                        DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .environment(\.locale, AppDate.h24Locale)
                    }
                }
```

- [ ] **Step 2** — in the line-item `else` branch, replace the `Section("Amount & category")` with the reordered primary section that also folds in Account + Date (and remove the separate `if txn.kind != "transfer" { Section("Account") … }` block, since Account now lives in the primary section for line items; transfer already excludes it, and split needs Account too — see note):

Replace:
```swift
                } else {
                    Section("Amount & category") {
                        HStack {
                            Text("Amount")
                            Spacer()
                            TextField("0.00", text: $amountText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            // Currency lives inline with the amount, always visible.
                            Picker("", selection: $currencyCode) {
                                ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu).labelsHidden().fixedSize()
                        }
                        SearchablePickerRow(title: "Category",
                            options: categories.map { PickerOption(id: $0.id, name: $0.name) }, selection: $categoryId)
                        Button("Split across categories…") { showingSplit = true }
                    }
                }

                if txn.kind != "transfer" {
                    Section("Account") {
                        SearchablePickerRow(title: "Account",
                            options: store.accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $accountId)
                    }
                }
```
with:
```swift
                } else {
                    Section {
                        SearchablePickerRow(title: "Account",
                            options: store.accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $accountId)
                        HStack {
                            Text("Amount")
                            Spacer()
                            TextField("0.00", text: $amountText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            Picker("", selection: $currencyCode) {
                                ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu).labelsHidden().fixedSize()
                        }
                        SearchablePickerRow(title: "Category",
                            options: categories.map { PickerOption(id: $0.id, name: $0.name) }, selection: $categoryId)
                        DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .environment(\.locale, AppDate.h24Locale)
                        Button("Split across categories…") { showingSplit = true }
                    }
                }

                // Split still needs an Account row (line items have it above; transfer doesn't).
                if isSplit {
                    Section("Account") {
                        SearchablePickerRow(title: "Account",
                            options: store.accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $accountId)
                    }
                }
```

- [ ] **Step 3** — replace the inline Edit Tags section (the `ForEach(store.tags)` checklist, lines ~235–247) with:
```swift
                if !store.tags.isEmpty {
                    Section("Tags") { TagChipFlow(tags: store.tags, selected: $selectedTags) }
                }
```

- [ ] **Step 4** — add a Details section (Merchant/Source + Note) at the very bottom, immediately before the `if let errorMessage` section. Use the sheet's existing `merchant`/`note`/`merchantSuggestionRows` and the effective source label:
```swift
                if txn.kind != "transfer", txn.kind != "adjustment", txn.kind != "opening" {
                    Section("Details") {
                        HStack {
                            Text(effectiveKind == "income" ? "Source" : "Merchant"); Spacer()
                            TextField("", text: $merchant).multilineTextAlignment(.trailing)
                        }
                        merchantSuggestionRows
                        HStack {
                            Text("Note"); Spacer()
                            TextField("Optional", text: $note, axis: .vertical).multilineTextAlignment(.trailing)
                        }
                    }
                }
```
(Transfer legs and adjustment/opening keep Note in their own top Date section — leave that; for those kinds Note stays where Step 1 puts the Date section. If Note is needed for transfer, add it to the Step 1 section. Implementer: verify transfer edit still exposes Note — if it did before and now doesn't, add a Note row to the Step 1 branch.)

- [ ] **Step 5: run shared block** — both builds green, tests pass. **Sim check** the Edit sheet for an expense: primary section reads Account/Amount/Category/Date; Tags are chips; Merchant+Note last. Also open a transfer edit and a split edit — confirm they still render correctly (Date present, no broken/missing Account).
- [ ] **Step 6: commit** — `feat(ios): Edit sheet — reorder fields + wrapping tag chips`

---

### Task 5: Translucent scroll-edge top (Add sheet) — visual acceptance

**Files:** Modify `ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift`

This is a **visual-acceptance** task (spec §4): the opaque `.background(Color(uiColor: .systemGroupedBackground))` on the paged `TabView` (line ~111) defeats the translucent scroll-edge top. Make the top translucent (scrolled content blurs faintly under the toolbar, like Accounts) WHILE keeping the pager pages visually uniform.

- [ ] **Step 1** — try: move the grouped background off the `TabView` and onto each page's `Form` via `.scrollContentBackground(.hidden)` + `.background(Color(uiColor: .systemGroupedBackground))` on the `Form` (so the background scrolls with content and the nav bar keeps its material), OR keep the TabView background but constrain it to not underlap the bar. Whichever renders correctly.
- [ ] **Step 2** — build; install on the sim; open the Add sheet; **screenshot at rest and mid-scroll**; compare to the Accounts tab scrolled (`-initialTab accounts`, scroll): the top should show faintly-blurred content beneath a translucent bar, and the four pages must still share one uniform background (no per-page color seams — the bug the opaque background originally fixed). Iterate Step 1 until both hold.
- [ ] **Step 3** — verify the Edit sheet (plain `Form`) already behaves; if it shows the same opaque issue, apply the same fix there.
- [ ] **Step 4: run shared block** (both builds + tests green) and **commit** — `feat(ios): Add sheet — translucent scroll-edge top matching main tabs`

---

## PR

Title: `feat(ios): Add/Edit transaction form redesign — reorder, sheet pickers, tag chips, translucent top`
Body: link spec+plan; the spec's manual checklist (reordered expense Add+Edit; bottom-sheet Category/Account/From/To; tag chips + show-all; translucent top vs Accounts; macOS).

## Self-review notes

- Spec coverage: §1→Tasks 3&4, §2→Task 2, §3→Task 1 (+wired in 3&4), §4→Task 5. Testing seam (partition)→Task 1.
- Type consistency: `TagChipFlow(tags:selected:)` + `collapsedVisible(tags:selected:cap:)` identical across Task 1 def and Tasks 3/4 call sites; `SearchablePickerRow(title:options:selection:)` API unchanged so call sites compile untouched.
- Risk flags stated inline: Edit split needs its own Account row (Step 2 note); transfer/adjustment Note placement (Step 4 note) — implementer verifies on the sim.
