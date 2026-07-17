# Edit sheet type control + real transfer editing — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `EditTransactionSheet` gets the Add sheet's top icon type control (preselected to the transaction's kind, honest disabled states) and transfer legs open a real transfer editor saved through the engine's `updateTransfer`.

**Architecture:** UI-only inside `ios/FinchApp` + one pure helper with unit tests. Engine consumed as-is. Spec: `plans/ios-macos/2026-07-17-edit-type-control-design.md`.

**Tech Stack:** SwiftUI (iOS 17+/macOS 14+), XcodeGen, FinchCore via `store.apply`.

## Global Constraints

- Build **both** FinchApp (iOS sim) and FinchMac per task; run `FinchAppTests` per task.
- `xcodegen generate` after adding files (Tasks 1 & 2 add files).
- Engine untouched. Line-item editing behavior unchanged except the Type row moving to the toolbar. Category row dropped for transfer legs.
- `updateTransfer` contract (FinchCore `Store/Domain/Transfers.swift`): args `id` (either leg id) + `patch` with optional `fromAmount`/`toAmount` (abs values; when only one is given the engine ratio-scales the other; same-currency mismatches rejected), `date`, `time`, `note`. **Accounts immutable.**
- Commits: no `Co-Authored-By` trailer. One booted target sim per the session's sim rule; `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

**Build/test command block used by every task** (run from the worktree root):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
UDID=$(xcrun simctl list devices | grep "ios-finch (" | grep -oE '[0-9A-F-]{36}')
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp -destination "id=$UDID" 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination "id=$UDID" -only-testing:FinchAppTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|Executed .* tests"
```

---

### Task 1: `TransferEditPatch` helper (TDD)

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/WriteScreens/TransferEditPatch.swift`
- Create: `ios/FinchApp/Tests/FinchAppTests/TransferEditPatchTests.swift`

**Interfaces:**
- Consumes: `DecimalInput.parse` (existing), `JSONValue` (FinchCore; has `.asDouble`/`.asString` accessors).
- Produces: `TransferEditPatch.build(_: Inputs) -> Result<[String: JSONValue], Failure>` — Task 3 calls it.

- [ ] **Step 1: Write the failing tests** — create `TransferEditPatchTests.swift` with exactly:

```swift
import XCTest
@testable import FinchApp
import FinchCore

/// The Edit sheet's transfer save path builds an updateTransfer patch from the
/// edited fields — pure, so the inclusion rules are unit-tested here.
final class TransferEditPatchTests: XCTestCase {
    private func inputs(sameCurrency: Bool = true,
                        originalFrom: Double = 100, originalTo: Double = 100,
                        editedFrom: String = "100", editedTo: String? = nil,
                        originalDate: String = "2026-07-01", originalTime: String? = "12:00",
                        originalNote: String? = nil,
                        newDate: String = "2026-07-01", newTime: String = "12:00",
                        newNote: String = "") -> TransferEditPatch.Inputs {
        TransferEditPatch.Inputs(sameCurrency: sameCurrency,
                                 originalFrom: originalFrom, originalTo: originalTo,
                                 editedFrom: editedFrom, editedTo: editedTo,
                                 originalDate: originalDate, originalTime: originalTime,
                                 originalNote: originalNote,
                                 newDate: newDate, newTime: newTime, newNote: newNote)
    }

    func test_unchanged_producesEmptyPatch() throws {
        let patch = try TransferEditPatch.build(inputs()).get()
        XCTAssertTrue(patch.isEmpty)
    }

    func test_sameCurrency_amountChange_sendsFromAmountOnly() throws {
        let patch = try TransferEditPatch.build(inputs(editedFrom: "150")).get()
        XCTAssertEqual(patch["fromAmount"]?.asDouble, 150)
        XCTAssertNil(patch["toAmount"])
    }

    func test_crossCurrency_bothChanged_sendsBoth() throws {
        let patch = try TransferEditPatch.build(inputs(sameCurrency: false,
            originalFrom: 100, originalTo: 92, editedFrom: "110", editedTo: "101")).get()
        XCTAssertEqual(patch["fromAmount"]?.asDouble, 110)
        XCTAssertEqual(patch["toAmount"]?.asDouble, 101)
    }

    func test_crossCurrency_onlyToChanged_sendsToOnly() throws {
        let patch = try TransferEditPatch.build(inputs(sameCurrency: false,
            originalFrom: 100, originalTo: 92, editedFrom: "100", editedTo: "95")).get()
        XCTAssertNil(patch["fromAmount"])
        XCTAssertEqual(patch["toAmount"]?.asDouble, 95)
    }

    func test_badAmount_fails() {
        XCTAssertEqual(TransferEditPatch.build(inputs(editedFrom: "0")), .failure(.badAmount))
        XCTAssertEqual(TransferEditPatch.build(inputs(editedFrom: "abc")), .failure(.badAmount))
        XCTAssertEqual(TransferEditPatch.build(inputs(sameCurrency: false, editedTo: nil)),
                       .failure(.badAmount))
    }

    func test_dateTimeNote_inclusionRules() throws {
        var patch = try TransferEditPatch.build(inputs(newDate: "2026-07-02")).get()
        XCTAssertEqual(patch["date"]?.asString, "2026-07-02")
        patch = try TransferEditPatch.build(inputs(newTime: "13:30")).get()
        XCTAssertEqual(patch["time"]?.asString, "13:30")
        patch = try TransferEditPatch.build(inputs(newNote: "hello")).get()
        XCTAssertEqual(patch["note"]?.asString, "hello")
        // Clearing an existing note sends explicit null.
        patch = try TransferEditPatch.build(inputs(originalNote: "old", newNote: "")).get()
        XCTAssertEqual(patch["note"], JSONValue.null)
        // nil original time == "" new time → no time key.
        patch = try TransferEditPatch.build(inputs(originalTime: nil, newTime: "")).get()
        XCTAssertNil(patch["time"])
    }
}
```

Note: `test_badAmount_fails` compares full `Result`s — this requires the `Result` to be `Equatable`, which holds because `Failure` is `Equatable` and `[String: JSONValue]` is (FinchCore's `JSONValue` is `Equatable`; verify with `grep -n "enum JSONValue" -A2 ios/FinchCore/Sources/FinchCore/**/*.swift` — if it is NOT `Equatable`, rewrite those three asserts as `guard case .failure(.badAmount)` pattern-matches instead).

- [ ] **Step 2: Run the tests to see them fail** (compile error: `TransferEditPatch` undefined). Run the shared command block's test line; expected FAIL.

- [ ] **Step 3: Implement the helper** — create `TransferEditPatch.swift` with exactly:

```swift
import Foundation
import FinchCore

/// Builds the `updateTransfer` patch for the Edit sheet's transfer editor.
/// Pure and unit-tested: only CHANGED keys are included (an empty patch means
/// "nothing to save"); amounts are validated > 0. Same-currency transfers send
/// `fromAmount` only — the engine ratio-scales the other leg, which for equal
/// legs keeps them equal (sending both would trip its mismatch check on
/// rounding). Cross-currency sends whichever side(s) changed.
enum TransferEditPatch {
    struct Inputs {
        var sameCurrency: Bool
        var originalFrom: Double        // abs native from-leg amount
        var originalTo: Double          // abs native to-leg amount
        var editedFrom: String          // the From-amount field (same-currency: the single Amount field)
        var editedTo: String?           // the To-amount field (cross-currency only; nil otherwise)
        var originalDate: String        // yyyy-MM-dd
        var originalTime: String?       // HH:mm (nil when the entry has none)
        var originalNote: String?
        var newDate: String
        var newTime: String
        var newNote: String
    }

    enum Failure: Error, Equatable { case badAmount }

    static func build(_ i: Inputs) -> Result<[String: JSONValue], Failure> {
        var patch: [String: JSONValue] = [:]
        guard let from = DecimalInput.parse(i.editedFrom), from > 0 else { return .failure(.badAmount) }
        if abs(from - i.originalFrom) > 0.001 { patch["fromAmount"] = .double(from) }
        if !i.sameCurrency {
            guard let toText = i.editedTo, let to = DecimalInput.parse(toText), to > 0 else {
                return .failure(.badAmount)
            }
            if abs(to - i.originalTo) > 0.001 { patch["toAmount"] = .double(to) }
        }
        if i.newDate != i.originalDate { patch["date"] = .string(i.newDate) }
        if i.newTime != (i.originalTime ?? "") { patch["time"] = .string(i.newTime) }
        if i.newNote != (i.originalNote ?? "") {
            patch["note"] = i.newNote.isEmpty ? .null : .string(i.newNote)
        }
        return .success(patch)
    }
}
```

- [ ] **Step 4: Run the full command block** — both builds SUCCEEDED, tests pass (147 existing + 6 new).

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/TransferEditPatch.swift ios/FinchApp/Tests/FinchAppTests/TransferEditPatchTests.swift
git commit -m "feat(ios): TransferEditPatch — tested updateTransfer patch builder"
```

---

### Task 2: `EditTypeControl` + toolbar integration

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTypeControl.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift`

**Interfaces:**
- Consumes: `TxnKindIcon.icon(for:)` (existing).
- Produces: `EditTypeControl(selected:enabled:onSelect:)` with nested `EditTypeControl.Kind` (`expense|income|transfer|refund`) — used only here.

- [ ] **Step 1: Create `EditTypeControl.swift`** with exactly:

```swift
import SwiftUI

/// The Edit sheet's top type control — the Add sheet's icon-segment language,
/// but with per-segment enable/disable (a system segmented Picker can't
/// disable individual segments, and Edit must show Transfer as present-but-
/// locked for line items). Selection highlight = soft neutral pill; selected
/// glyph tints accent; disabled glyphs dim.
struct EditTypeControl: View {
    /// Add-sheet kinds in Add-sheet order.
    enum Kind: String, CaseIterable, Identifiable {
        case expense, income, transfer, refund
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var iconName: String { TxnKindIcon.icon(for: rawValue) }
    }

    let selected: Kind
    /// Kinds the user may switch TO (empty → fully locked control).
    let enabled: Set<Kind>
    let onSelect: (Kind) -> Void

    private let width: CGFloat = 190   // matches AddTransactionSheet.typeControlWidth
    private let height: CGFloat = 36

    var body: some View {
        let seg = width / CGFloat(Kind.allCases.count)
        HStack(spacing: 0) {
            ForEach(Kind.allCases) { k in
                Button { onSelect(k) } label: {
                    Image(systemName: k.iconName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(color(for: k))
                        .frame(width: seg, height: height)
                        .background(k == selected ? Color.primary.opacity(0.08) : Color.clear, in: Capsule())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(k == selected || !enabled.contains(k))
                .accessibilityLabel(k.label)
                .accessibilityAddTraits(k == selected ? .isSelected : [])
            }
        }
        .frame(width: width, height: height)
    }

    private func color(for k: Kind) -> Color {
        if k == selected { return .accentColor }
        return enabled.contains(k) ? .primary : Color.secondary.opacity(0.4)
    }
}
```

- [ ] **Step 2: Integrate in `EditTransactionSheet`.** Add these computed properties after `private var effectiveKind: String { … }` (line ~114):

```swift
    /// Top control state: nil hides the control (adjustment/opening rows).
    private var typeControlKind: EditTypeControl.Kind? {
        switch txn.kind {
        case "transfer": return .transfer
        case "adjustment", "opening": return nil
        default: return EditTypeControl.Kind(rawValue: effectiveKind) ?? .expense
        }
    }
    /// Line items reclassify across expense/income/refund; everything else locks.
    private var typeControlEnabled: Set<EditTypeControl.Kind> {
        canReclassify ? [.expense, .income, .refund] : []
    }
```

- [ ] **Step 3: Add the toolbar item.** In the `.toolbar { … }` block (line ~250), after the cancellation item, insert:

```swift
                ToolbarItem(placement: .principal) {
                    if let kind = typeControlKind {
                        EditTypeControl(selected: kind, enabled: typeControlEnabled) { k in
                            if let ek = EditKind(rawValue: k.rawValue) { selectedKind = ek }
                        }
                    }
                }
```

(When the control shows, it replaces the inline "Edit Transaction" title in the principal slot — matching the Add sheet, which also has no text title. Adjustment/opening rows keep the plain title because the item renders empty.)

- [ ] **Step 4: Remove the inline Type picker.** In the "Amount & category" section (line ~148), delete:

```swift
                        if canReclassify {
                            Picker("Type", selection: $selectedKind) {
                                ForEach(EditKind.allCases) { Text($0.label).tag($0) }
                            }
                        }
```

- [ ] **Step 5: Run the command block** — builds green, tests pass.

- [ ] **Step 6: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/EditTypeControl.swift ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift
git commit -m "feat(ios): Edit sheet gets the Add-style top type control"
```

---

### Task 3: Transfer editor + `updateTransfer` save routing

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift`

**Interfaces:**
- Consumes: `TransferEditPatch.build` (Task 1), `ActionName.updateTransfer` (engine), `Tx.transferGroupId`.

- [ ] **Step 1: Add state + transfer helpers.** Add state (after `@State private var selectedKind: EditKind`, line ~45):

```swift
    @State private var fromAmountText = ""   // transfer editor: from-leg native amount
    @State private var toAmountText = ""     // transfer editor: to-leg native amount (cross-currency)
```

Add helpers after the `categories` computed property (line ~118):

```swift
    /// The transfer's two legs — this row plus its counterpart, resolved via
    /// transferGroupId. From = the negative-amount leg.
    private var transferLegs: (from: Tx, to: Tx)? {
        guard txn.kind == "transfer", let gid = txn.transferGroupId else { return nil }
        let legs = store.txns.filter { $0.transferGroupId == gid }
        guard let from = legs.first(where: { $0.amount < 0 }),
              let to = legs.first(where: { $0.amount > 0 }), from.id != to.id else { return nil }
        return (from, to)
    }
    private var transferSameCurrency: Bool {
        guard let legs = transferLegs else { return true }
        return (legs.from.currency ?? "") == (legs.to.currency ?? "")
    }
    private func accountName(_ id: String) -> String {
        store.accounts.first { $0.id == id }?.name ?? "—"
    }
```

- [ ] **Step 2: The transfer section.** Change the split/else structure (lines ~136–167): the current shape is `if isSplit { Section("Split") {…} } else { Section("Amount & category") {…} }`. Make it:

```swift
                if isSplit {
                    // …Split section UNCHANGED…
                } else if let legs = transferLegs {
                    // Transfer legs: a real transfer editor (spec §2). Accounts are
                    // immutable in updateTransfer → read-only; no Category row for
                    // transfers.
                    Section("Transfer") {
                        LabeledContent("From", value: accountName(legs.from.account))
                        LabeledContent("To", value: accountName(legs.to.account))
                        if transferSameCurrency {
                            HStack {
                                Text("Amount"); Spacer()
                                TextField("0.00", text: $fromAmountText)
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            }
                        } else {
                            HStack {
                                Text("From amount (\(legs.from.currency ?? ""))"); Spacer()
                                TextField("0.00", text: $fromAmountText)
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            }
                            HStack {
                                Text("To amount (\(legs.to.currency ?? ""))"); Spacer()
                                TextField("0.00", text: $toAmountText)
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                } else {
                    // …Amount & category section UNCHANGED (minus the Task 2 Picker removal)…
                }
```

Note `.keyboardType` is iOS-only — it is ALREADY used unguarded in this file (line ~156), which compiles on macOS via the project's cross-platform shims; keep the same call style as the neighboring code. A transfer row whose counterpart leg is missing (defensive `transferLegs == nil`) falls into the old line-item branch — same as today's behavior.

- [ ] **Step 3: Seed the editor.** In `.onAppear` (line ~269), append:

```swift
                if let legs = transferLegs {
                    fromAmountText = String(format: "%g", abs(legs.from.nativeAmount ?? legs.from.amount))
                    toAmountText = String(format: "%g", abs(legs.to.nativeAmount ?? legs.to.amount))
                }
```

- [ ] **Step 4: Save routing.** At the top of `save()` (line ~305), insert:

```swift
        if txn.kind == "transfer" { saveTransfer(); return }
```

and add the new method after `save()`:

```swift
    /// Transfer legs save through the engine's updateTransfer (entry-level:
    /// amounts/date/time/note — keeps BOTH legs consistent; the old single-leg
    /// patch path could diverge them). Merchant/status stay leg-level patches;
    /// tags stay setTransactionTags.
    private func saveTransfer() {
        errorMessage = nil
        guard let legs = transferLegs else { errorMessage = "Transfer legs not found."; return }
        let result = TransferEditPatch.build(.init(
            sameCurrency: transferSameCurrency,
            originalFrom: abs(legs.from.nativeAmount ?? legs.from.amount),
            originalTo: abs(legs.to.nativeAmount ?? legs.to.amount),
            editedFrom: fromAmountText,
            editedTo: transferSameCurrency ? nil : toAmountText,
            originalDate: txn.date, originalTime: txn.time, originalNote: txn.note,
            newDate: Self.day(date), newTime: Self.time(date), newNote: note))
        switch result {
        case .failure:
            errorMessage = "Enter an amount greater than 0."
        case .success(let patch):
            do {
                if !patch.isEmpty {
                    try store.apply(.updateTransfer, Args(["id": .string(txn.id), "patch": .object(patch)]))
                }
                var legPatch: [String: JSONValue] = [:]
                if merchant != txn.merchant { legPatch["merchant"] = .string(merchant.isEmpty ? "Untitled" : merchant) }
                if status != (txn.pending == true ? .pending : .confirmed) { legPatch["status"] = .string(status.rawValue) }
                if !legPatch.isEmpty {
                    try store.apply(.updateTransaction, Args(["id": .string(txn.id), "patch": .object(legPatch)]))
                }
                if selectedTags != Set(txn.tags ?? []) {
                    try store.apply(.setTransactionTags, Args(["id": .string(txn.id),
                        "tagIds": .array(selectedTags.sorted().map { .string($0) })]))
                }
                dismiss()
            } catch { errorMessage = i18nMessage(error) }
        }
    }
```

- [ ] **Step 5: Run the command block** — builds green, tests pass (incl. Task 1's six).

- [ ] **Step 6: Sim smoke** (session sim): install + launch; screenshot a transfer row's edit sheet is NOT scriptable (taps) — verify instead that the app launches and the Add sheet still opens via `finch://add`. The behavioral pass is the PR's manual checklist.

- [ ] **Step 7: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift
git commit -m "feat(ios): transfer legs edit as a real transfer via updateTransfer"
```

---

## PR

Title: `feat(ios): Edit sheet type control on top + real transfer editing`

Body: link spec + plan; manual checklist from the spec (expense reclass via top control w/ grayed Transfer · either transfer leg → locked Transfer + From/To read-only + both-legs amount update · cross-currency dual fields · split locked · adjustment row w/o control · macOS states).

## Self-review notes

- Spec coverage: §1 → Task 2; §2 → Tasks 1+3; §3 non-changes need no tasks; testing seam → Task 1.
- Type consistency: `EditTypeControl.Kind(rawValue:)` ↔ `EditKind(rawValue:)` bridge only for the three shared raw values; `TransferEditPatch.Inputs` field names match between Task 1 code and Task 3 call site.
- The Task 3 defensive fallback (missing counterpart leg → old branch) is intentional and stated.
- No placeholders; all code steps carry the code.
