# Write-Sheet Icon Rows — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle every editable row in the native add/edit write-sheet family
into an icon-led, placeholder-driven row — `[colored field glyph] value-or-grey-placeholder … [one disclosure]` —
replacing today's `[name] … [value]` layout, so values get the full row width.

**Architecture:** One shared vocabulary (`FieldGlyph`: field → SF Symbol + color)
and one shared row chrome (`FieldRow`) that every picker component and inline row
renders through. The 8 shared picker components gain a `glyph:` parameter and
render via `FieldRow`; each sheet passes the right glyph per call site and
restyles its inline rows (Amount / Note / Date / menus) through the same chrome.
The picker *sheets* those rows present are untouched.

**Tech Stack:** SwiftUI (iOS 17 / macOS 14 floor), `FinchApp` target. Design doc:
`plans/ios-macos/2026-07-23-write-sheet-icon-rows-design.md`.

## Global Constraints

- **Deployment floor iOS 17.0 / macOS 14.0.** Every SF Symbol and API must exist
  on both. `FinchMac` shares these sources — no iOS-only API without a `#if os`.
- **Presentational only.** No change to save/validation/engine calls, field
  semantics, field order, or the picker *sheets* (searchable lists, Confirm/Cancel).
- **Keep the tokenized layout.** Do not hand-tune insets. Keep `finchSheetForm()`,
  the grouped `Form` sections, the type caption, and the first-section-no-header
  rule. Section headers stay `finchSectionHeader(_:)` (takes `LocalizedStringKey`).
- **One disclosure per row.** Menu rows (Amount currency, Status/Type/Group/
  Frequency/Currency menus) use the menu's own `⌵` — add NO chevron. Sheet-opening
  rows get a trailing `chevron.right`. Pure inline text rows (Note, New balance,
  Name, Target…) get NO trailing accessory.
- **Fixed per-field glyph + color** from `FieldGlyph`. No value-reflecting icons,
  no filled tiles. Color on the glyph itself.
- **Accessibility:** each row sets `accessibilityLabel` to the field name (the
  glyph is `accessibilityHidden`); the value is the accessibility value.
- **i18n:** any new user-facing string (placeholder, a11y label) goes through the
  generated catalog — use `LocalizedStringKey` / `String(localized:)`, never a raw
  `String` into `Text`/`accessibilityLabel`. Re-run the xcstrings pipeline and
  commit `extracted-keys.json` + the rebuilt catalog if keys change.
- **Commits:** NO `Co-Authored-By` trailer.

## Commands (referred to by name below)

Run from the worktree `/tmp/finch-sheet-icons`. Set once per shell:

- **ENV:** `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- **XGEN** (only after adding/removing a file): `cd /tmp/finch-sheet-icons/ios && xcodegen generate`
- **BUILD_IOS:** `cd /tmp/finch-sheet-icons/ios && xcodebuild -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,id=6A01D29F-FBCB-4B97-9080-522192E4D6DD' -derivedDataPath /tmp/finch-sheet-icons/dd build 2>&1 | tail -4`
- **BUILD_MAC:** `cd /tmp/finch-sheet-icons/ios && xcodebuild -project FinchApp.xcodeproj -scheme FinchMac -derivedDataPath /tmp/finch-sheet-icons/dd build 2>&1 | tail -4`
- **TEST_FIELD** (unit tests; sim already booted): `cd /tmp/finch-sheet-icons/ios && xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,id=6A01D29F-FBCB-4B97-9080-522192E4D6DD' -derivedDataPath /tmp/finch-sheet-icons/dd -only-testing:FinchAppTests/FieldGlyphTests 2>&1 | tail -15`

`** BUILD SUCCEEDED **` / `Test Suite … passed` is the pass signal. The `build`
does not need the sim booted; `test` does. The manual on-sim visual check is done
by the CONTROLLER, not the implementer.

---

## File Structure

- **Create** `ios/FinchApp/Sources/FinchApp/Common/FieldGlyph.swift` — the field→
  symbol→color vocabulary (Task 1).
- **Create** `ios/FinchApp/Sources/FinchApp/Common/FieldRow.swift` — the shared
  icon-led row chrome (Task 2).
- **Create** `ios/FinchApp/Tests/FinchAppTests/FieldGlyphTests.swift` — unit tests
  for the pure vocabulary (Task 1).
- **Modify** the 8 shared picker components in `WriteScreens/` (Tasks 3–5).
- **Modify** the 5 sheets in `WriteScreens/` (Tasks 6–10):
  `AddTransactionSheet`, `EditTransactionSheet`, `ScheduledSheet`, `AccountSheet`,
  `BudgetSheet`.

## Phasing

- **Phase 1 (Tasks 1–7):** foundation + all shared components + the flagship
  **Add** and **Edit** transaction sheets. Independently mergeable and visible.
- **Phase 2 (Tasks 8–10):** the remaining sheets — Scheduled, Account, Budget.

Stop after Phase 1 for a controller review before Phase 2.

---

## Row Transform Recipes (referenced by every sheet task)

These are the complete code archetypes. Sheet tasks below say "row X → recipe R
with glyph G"; use the matching recipe verbatim, substituting the glyph.

### Recipe P — a shared picker row (component already restyled)

Just pass the glyph at the call site. Example:

```swift
// BEFORE
SearchablePickerRow(title: "Account",
    options: accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $accountId)
// AFTER
SearchablePickerRow(title: "Account", glyph: .account,
    options: accounts.map { PickerOption(id: $0.id, name: $0.name ?? "—") }, selection: $accountId)
```

### Recipe T — inline text field row

```swift
// BEFORE
HStack { Text("Note"); Spacer()
    TextField("Optional", text: $note, axis: .vertical).multilineTextAlignment(.trailing) }
// AFTER
FieldRow(glyph: .note, title: "Note") {
    TextField("Optional", text: $note, axis: .vertical)   // no trailing alignment; fills width
}
```

`FieldRow`'s content is left-aligned after the icon and fills the row; no
chevron (text field, nothing to disclose). `FieldRow` applies the a11y label
from `title`.

### Recipe A — amount row (text field + trailing currency menu)

```swift
// AFTER — currency menu is the disclosure; number left-aligned after the icon
FieldRow(glyph: .amount, title: "Amount", trailing: {
    Picker("", selection: $currencyCode) {
        ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
    }
    .pickerStyle(.menu).labelsHidden().fixedSize()
}) {
    TextField("0.00", text: $amount).keyboardType(.decimalPad).numericInput($amount)
}
```

Transfer amount rows use glyph `.amount` too, with a fixed currency `Text($currency)`
as the `trailing` (no menu — the leg's account owns the currency), and the mirrored
same-currency "To amount" keeps `.disabled(true)` + `.foregroundStyle(.secondary)`.

### Recipe D — DatePicker row

```swift
// AFTER — the compact date button is its own disclosure; date is never empty
FieldRow(glyph: .date, title: "Date", showsDefaultTrailing: false) {
    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
        .labelsHidden()
        .environment(\.locale, AppDate.h24Locale)
}
```

### Recipe M — inline `Picker` menu row (Status / Type / Group / Frequency / Currency)

```swift
// AFTER — the menu's own ⌵ is the disclosure
FieldRow(glyph: .status, title: "Status", showsDefaultTrailing: false) {
    Picker("Status", selection: $status) {
        Text("Confirmed").tag(Entries.Status.confirmed)
        Text("Pending").tag(Entries.Status.pending)
    }
    .labelsHidden()
}
```

### Recipe R — Receipt button row

```swift
// AFTER (iOS branch) — opens the photo picker, so it gets the chevron
FieldRow(glyph: .receipt, title: "Receipt", isEmpty: pickedPhoto == nil) {
    Text(pickedPhoto == nil ? "Add receipt photo" : "Receipt photo selected")
}
// wrapped in the existing PhotosPicker(...) / #if os(macOS) fileImporter(...) as today
```

---

### Task 1: `FieldGlyph` vocabulary (pure, tested)

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Common/FieldGlyph.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/FieldGlyphTests.swift`

**Interfaces:**
- Produces: `enum FieldGlyph { case account, fromAccount, toAccount, amount, category, date, merchant, note, status, tags, receipt, refund, name, group, frequency, currency, color, icon }`
  with `var symbol: String` and `var tint: Color`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import SwiftUI
@testable import FinchApp

final class FieldGlyphTests: XCTestCase {
    func testSymbolsAreStableAndNonEmpty() {
        // A representative mapping — the vocabulary must be deterministic.
        XCTAssertEqual(FieldGlyph.account.symbol, "building.columns")
        XCTAssertEqual(FieldGlyph.amount.symbol, "dollarsign.circle")
        XCTAssertEqual(FieldGlyph.category.symbol, "folder")
        XCTAssertEqual(FieldGlyph.date.symbol, "calendar")
        XCTAssertEqual(FieldGlyph.merchant.symbol, "storefront")
        XCTAssertEqual(FieldGlyph.tags.symbol, "tag")
        XCTAssertEqual(FieldGlyph.status.symbol, "checkmark.circle")
    }
    func testFromAndToAreDistinct() {
        XCTAssertNotEqual(FieldGlyph.fromAccount.symbol, FieldGlyph.toAccount.symbol)
    }
    func testEveryCaseHasANonEmptySymbol() {
        let all: [FieldGlyph] = [.account,.fromAccount,.toAccount,.amount,.category,.date,
            .merchant,.note,.status,.tags,.receipt,.refund,.name,.group,.frequency,.currency,.color,.icon]
        for g in all { XCTAssertFalse(g.symbol.isEmpty, "\(g) has empty symbol") }
    }
}
```

- [ ] **Step 2: Run it, verify it fails** — TEST_FIELD → FAIL (no `FieldGlyph`).

- [ ] **Step 3: Create `FieldGlyph.swift`**

```swift
import SwiftUI

/// The fixed per-field icon + color vocabulary for the add/edit write sheets.
/// One glyph and one color per field, defined once. The glyph is the row's
/// persistent identity (the visible text label is dropped once a value is set),
/// so it must be stable per field, never value-reflecting. Colors are system/
/// semantic colors so light + dark + macOS all resolve for free.
///
/// Lives beside `TxnKindIcon` / `CategoryIcon` in the app icon vocabulary.
enum FieldGlyph {
    case account, fromAccount, toAccount, amount, category, date, merchant
    case note, status, tags, receipt, refund, name, group, frequency, currency, color, icon

    var symbol: String {
        switch self {
        case .account:                return "building.columns"
        case .fromAccount:            return "arrow.up.circle"
        case .toAccount:              return "arrow.down.circle"
        case .amount:                 return "dollarsign.circle"
        case .category:               return "folder"
        case .date, .frequency:       return "calendar"
        case .merchant:               return "storefront"
        case .note:                   return "note.text"
        case .status:                 return "checkmark.circle"
        case .tags:                   return "tag"
        case .receipt:
            #if os(macOS)
            return "paperclip"
            #else
            return "camera"
            #endif
        case .refund:                 return "arrow.uturn.backward.circle"
        case .name:                   return "textformat"
        case .group:                  return "folder.badge.gearshape"
        case .currency:               return "dollarsign.arrow.circlepath"
        case .color:                  return "paintpalette"
        case .icon:                   return "star"
        }
    }

    var tint: Color {
        switch self {
        case .account, .fromAccount, .toAccount: return .blue
        case .amount:                            return .green
        case .category:                          return .orange
        case .date, .frequency:                  return .red
        case .merchant:                          return .purple
        case .note, .name:                       return .secondary
        case .status:                            return .teal
        case .tags:                              return .pink
        case .receipt, .refund:                  return .indigo
        case .group:                             return .brown
        case .currency, .color, .icon:           return .mint
        }
    }
}
```

- [ ] **Step 4: XGEN** (new files) then **TEST_FIELD** → PASS. Then **BUILD_IOS** + **BUILD_MAC** → both SUCCEEDED.

- [ ] **Step 5: Commit** — `feat(ios): field-glyph vocabulary for write-sheet icon rows`

---

### Task 2: `FieldRow` shared chrome

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Common/FieldRow.swift`

**Interfaces:**
- Consumes: `FieldGlyph` (Task 1).
- Produces: `struct FieldRow<Content, Trailing>` with initializers:
  - `FieldRow(glyph:title:@ViewBuilder content:)` — always shows `content`
    (text-field/menu/date rows manage their own empty state); no chevron.
  - `FieldRow(glyph:title:isEmpty:@ViewBuilder content:)` — picker rows: shows a
    grey `title` placeholder when `isEmpty`, else `content`; adds a trailing `chevron.right`.
  - `FieldRow(glyph:title:isEmpty:trailing:content:)` and
    `FieldRow(glyph:title:showsDefaultTrailing:content:)` overloads for custom
    trailing (currency menu) / suppressing the chevron (menu/date rows).

- [ ] **Step 1: Create `FieldRow.swift`**

```swift
import SwiftUI

/// The shared icon-led form-row chrome for the add/edit sheets:
/// `[colored glyph]  content-or-grey-placeholder  ……  [one trailing disclosure]`.
///
/// - The glyph (from `FieldGlyph`) leads in a fixed-width column so values align.
/// - `title` is the grey placeholder shown when the row is empty (picker rows);
///   text-field/menu/date rows always render their `content` and manage their own
///   empty state, so they use the initializer without `isEmpty`.
/// - Exactly one trailing disclosure: a `chevron.right` for sheet-opening rows,
///   or a caller-supplied `trailing` (e.g. a currency menu), or nothing.
/// - Accessibility: `title` is the row's a11y label; the glyph is hidden.
struct FieldRow<Content: View, Trailing: View>: View {
    private let glyph: FieldGlyph
    private let title: LocalizedStringKey
    private let isEmpty: Bool
    private let content: Content
    private let trailing: Trailing

    /// Full initializer.
    init(glyph: FieldGlyph, title: LocalizedStringKey, isEmpty: Bool = false,
         @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.glyph = glyph; self.title = title; self.isEmpty = isEmpty
        self.trailing = trailing(); self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: glyph.symbol)
                .font(.body)
                .foregroundStyle(glyph.tint)
                .frame(width: 24, alignment: .center)
                .accessibilityHidden(true)
            if isEmpty {
                Text(title).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
            trailing
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

extension FieldRow where Trailing == EmptyView {
    /// Text-field / date / menu rows: always render `content`, no chevron.
    init(glyph: FieldGlyph, title: LocalizedStringKey, showsDefaultTrailing: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.init(glyph: glyph, title: title, isEmpty: false,
                  trailing: { EmptyView() }, content: content)
    }
}

extension FieldRow where Trailing == FieldRowChevron {
    /// Picker rows that open a sheet: grey `title` placeholder when `isEmpty`,
    /// else `content`, plus a trailing chevron.
    init(glyph: FieldGlyph, title: LocalizedStringKey, isEmpty: Bool,
         @ViewBuilder content: () -> Content) {
        self.init(glyph: glyph, title: title, isEmpty: isEmpty,
                  trailing: { FieldRowChevron() }, content: content)
    }
}

/// The standard trailing disclosure for sheet-opening rows.
struct FieldRowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}
```

- [ ] **Step 2: XGEN** (new file) then **BUILD_IOS** + **BUILD_MAC** → both SUCCEEDED.
      (No unit test — SwiftUI view chrome is verified by build + the on-sim check.)

- [ ] **Step 3: Commit** — `feat(ios): shared FieldRow chrome for write-sheet icon rows`

---

### Task 3: Single-select picker components adopt `FieldRow`

**Files (modify):**
- `WriteScreens/SearchablePickerRow.swift`
- `WriteScreens/MerchantPickerRow.swift`
- `WriteScreens/CurrencyPickerRow.swift`
- `WriteScreens/IconPickerRow.swift`

**Interfaces:**
- Each component gains a `let glyph: FieldGlyph` stored property (placed right
  after `title`). Callers pass it (wired in Tasks 6–10). The picker *sheet* bodies
  are unchanged.

For EACH component, replace the collapsed `Button { label: HStack {...} }` with a
`FieldRow(glyph:title:isEmpty:)`, keeping the `Button`/`.sheet` wrapper. The
`isEmpty` predicate and value `Text` are component-specific:

- [ ] **Step 1: `SearchablePickerRow`** — add `let glyph: FieldGlyph` after `title`. Body:

```swift
var body: some View {
    Button { presented = true } label: {
        FieldRow(glyph: glyph, title: LocalizedStringKey(title), isEmpty: selection.isEmpty) {
            Text(selectedName).foregroundStyle(.primary).lineLimit(1).truncationMode(.tail)
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .sheet(isPresented: $presented) { /* unchanged */ }
}
```

- [ ] **Step 2: `MerchantPickerRow`** — add `glyph`; `isEmpty: merchant.isEmpty`; value `Text(merchant)`.
- [ ] **Step 3: `CurrencyPickerRow`** — add `glyph`; `title` is already `LocalizedStringKey`; `isEmpty: code.isEmpty`; value keeps the `willActivate` ternary `Text`.
- [ ] **Step 4: `IconPickerRow`** — add `glyph`; `isEmpty: selection.isEmpty`; value keeps `Image(systemName: CategoryIcon.symbol(for: selection))`.

  Note: `title` params are `String` in these components; wrap as
  `LocalizedStringKey(title)` when handing to `FieldRow` (except `CurrencyPickerRow`,
  already `LocalizedStringKey`).

- [ ] **Step 5: BUILD** — these components now REQUIRE `glyph:` at every call site,
      so the build will fail until Tasks 6–10 wire them. To keep Task 3 independently
      green, **give `glyph` a temporary default** `= .name` in each initializer; Tasks
      6–10 pass real glyphs and the defaults become dead (a final cleanup step in Task 10
      removes the defaults). Run **BUILD_IOS** + **BUILD_MAC** → SUCCEEDED.

- [ ] **Step 6: Commit** — `feat(ios): single-select picker rows render via FieldRow`

---

### Task 4: Multi-select + category picker components adopt `FieldRow`

**Files (modify):**
- `WriteScreens/CategoryPickerRow.swift` (preserve the split affordance)
- `WriteScreens/CategoryMultiPickerRow.swift`
- `WriteScreens/MultiSelectPickerRow.swift`

**Interfaces:** each gains `let glyph: FieldGlyph` (temporary default `= .category`).

- [ ] **Step 1: `CategoryPickerRow`** — the split button is a SECOND trailing element
      and must survive. Render the value area via `FieldRow` with a custom `trailing`
      that holds BOTH the optional split button AND the chevron:

```swift
var body: some View {
    HStack(spacing: 0) {
        Button {
            if splitSummary != nil { onSplit?() } else { presented = true }
        } label: {
            FieldRow(glyph: glyph, title: LocalizedStringKey(title),
                     isEmpty: (splitSummary ?? (selection.isEmpty ? nil : selectedName)) == nil,
                     trailing: {
                if let onSplit {
                    Button { onSplit() } label: {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(splitSummary != nil ? Color.accentColor : Color.secondary)
                            .frame(width: 30, height: 30).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                FieldRowChevron()
            }) {
                Text(splitSummary ?? selectedName).foregroundStyle(.primary)
                    .lineLimit(1).truncationMode(.tail)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    .sheet(isPresented: $presented) { /* unchanged */ }
}
```

  (Confirm the exact current `body` wrapping before editing — re-read the file; the
  split button currently lives in an outer `HStack` beside the main button. Fold it
  into the `trailing` closure as above so there's still one row.)

- [ ] **Step 2: `CategoryMultiPickerRow`** — `glyph` default `.category`; `isEmpty: selection.isEmpty`; value `Text(summary)`; chevron.
- [ ] **Step 3: `MultiSelectPickerRow`** — `glyph` default `.account`; `isEmpty: selection.isEmpty`; value `Text(summary)`; chevron. (Note: `summary` shows `emptyLabel` when empty, but with `isEmpty` true the grey `title` placeholder shows instead — that's intended; the field name replaces "All accounts" as the empty hint. Keep `emptyLabel` for the sheet.)
- [ ] **Step 4: BUILD_IOS + BUILD_MAC** → SUCCEEDED (temporary glyph defaults keep callers compiling).
- [ ] **Step 5: Commit** — `feat(ios): category & multi-select picker rows render via FieldRow`

---

### Task 5: `TagField` adopts `FieldRow`

**Files (modify):** `WriteScreens/TagChipFlow.swift`

- [ ] **Step 1:** add `let glyph: FieldGlyph` (default `.tags`). Render the row via
      `FieldRow(glyph: glyph, title: "Tags", isEmpty: chosen.isEmpty)` whose content
      is the existing `FlowLayout { chips }` (shown when non-empty); the empty state
      is handled by `FieldRow`'s grey "Tags" placeholder (drop the inline "None"):

```swift
var body: some View {
    let chosen = Self.selectedRows(tags: tags, selected: selected)
    Button { presented = true } label: {
        FieldRow(glyph: glyph, title: "Tags", isEmpty: chosen.isEmpty) {
            FlowLayout(spacing: 8, rowSpacing: 8) {
                ForEach(chosen) { tag in chip(tag.name, tint: Color(hex: tag.color ?? "") ?? .accentColor) }
            }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .sheet(isPresented: $presented) { /* unchanged */ }
}
```

- [ ] **Step 2: BUILD_IOS + BUILD_MAC** → SUCCEEDED.
- [ ] **Step 3: Commit** — `feat(ios): Tags row renders via FieldRow`

---

### Task 6: `AddTransactionSheet` — glyphs + inline rows

**Files (modify):** `WriteScreens/AddTransactionSheet.swift`

Apply the recipes. Re-read the file first (line numbers drift). Row map:

- `expenseIncomeFields`: Account → **P** `.account`; Amount (`amountField`) → **A** `.amount`; Category (`CategoryPickerRow`) → **P** `.category`; Date → **D** `.date`; Refunds button → wrap in `FieldRow(glyph: .refund, title: "Refunds", isEmpty: refundedTxId == nil){ Text(refundedSummary) }` + chevron.
- Status section: Status `Picker` → **M** `.status`; Tags (`TagField`) → **P** `.tags`.
- Receipt section → **R** `.receipt` (keep the `#if os(macOS)` fileImporter branch).
- `detailsSection`: Merchant/Source (`MerchantPickerRow`) → **P** `.merchant`; Note → **T** `.note`.
- `adjustFields`: Account → **P** `.account`; New balance (`TextField $targetBalance`) → **T**-style with glyph `.amount` (keep `.numbersAndPunctuation` keyboard, no currency menu, no chevron); Date → **D** `.date`; Note → **T** `.note`.
- `transferFields`: From → **P** `.fromAccount`; To → **P** `.toAccount`; From amount (`transferAmountRow`) → **A**-fixed-currency `.amount`; To amount → **A**-fixed-currency `.amount` (mirrored stays disabled+secondary); Date → **D** `.date`; Note → **T** `.note`.

- [ ] **Step 1:** convert each row per its recipe/glyph above. `transferAmountRow` and `amountField` are helper funcs — update them to return a `FieldRow` (Recipe A). Keep `numericInput`, `keyboardType`, `.disabled(mirrored)` behavior.
- [ ] **Step 2: BUILD_IOS + BUILD_MAC** → SUCCEEDED.
- [ ] **Step 3:** Manual reset check deferred to controller.
- [ ] **Step 4: Commit** — `feat(ios): Add-transaction sheet — icon rows`

---

### Task 7: `EditTransactionSheet` — glyphs + inline rows

**Files (modify):** `WriteScreens/EditTransactionSheet.swift`

Re-read first. Same recipes as Task 6, matching this sheet's rows (from the
inventory): Account → **P** `.account`; Amount (inline `HStack` + currency `Picker`)
→ **A** `.amount`; Category (`CategoryPickerRow`, incl. the transfer/refund variants
with `.constant("")`) → **P** `.category`; Date → **D** `.date`; Refunds button →
`FieldRow(.refund)` + chevron; Status `Picker` → **M** `.status`; Tags → **P**
`.tags`; Receipt → **R** `.receipt`; Merchant/Source → **P** `.merchant`; Note (both
the transfer-path and line-item-path Note rows) → **T** `.note`.

- [ ] **Step 1:** convert per recipe. Preserve the transfer-leg editing and the
      cross-currency amount rows (fixed-currency Recipe A).
- [ ] **Step 2: BUILD_IOS + BUILD_MAC** → SUCCEEDED.
- [ ] **Step 3: Commit** — `feat(ios): Edit-transaction sheet — icon rows`

**→ PHASE 1 COMPLETE. Controller reviews before Phase 2.**

---

### Task 8: `ScheduledSheet` — glyphs + inline rows

**Files (modify):** `WriteScreens/ScheduledSheet.swift`

Re-read first. Rows: Name (`TextField("Name")`) → **T** `.name`; Amount → **A**
`.amount` (currency handling as today — this sheet's amount has no inline currency
menu; use the no-trailing text variant with glyph `.amount`); Category → **P**
`.category`; From/To (transfer) → **P** `.fromAccount`/`.toAccount`; Account → **P**
`.account`; Frequency `Picker` → **M** `.frequency`; Start `DatePicker` → **D**
`.date`; Number of payments (`TextField`) → **T** `.amount` (numeric) — or a neutral
glyph; keep `numberPad`.

- [ ] **Step 1:** convert per recipe. **Step 2: BUILD_IOS + BUILD_MAC** → SUCCEEDED.
- [ ] **Step 3: Commit** — `feat(ios): Scheduled sheet — icon rows`

---

### Task 9: `AccountSheet` — glyphs + inline rows

**Files (modify):** `WriteScreens/AccountSheet.swift`

Re-read first. Rows: Name → **T** `.name`; Type `Picker` → **M** `.status` (reuse a
neutral glyph — propose `.icon`); Currency `Picker` → **M** `.currency`; Group
`Picker` → **M** `.group`; Opening balance (`TextField`) → **T** `.amount`; Color
section row → glyph `.color` (keep its existing control). Confirm the Color
section's actual control when re-reading.

- [ ] **Step 1:** convert per recipe. **Step 2: BUILD_IOS + BUILD_MAC** → SUCCEEDED.
- [ ] **Step 3: Commit** — `feat(ios): Account sheet — icon rows`

---

### Task 10: `BudgetSheet` — glyphs + inline rows + remove temporary glyph defaults

**Files (modify):** `WriteScreens/BudgetSheet.swift` + the 8 shared components
(remove the temporary `glyph` defaults from Task 3/4/5).

Re-read first. BudgetSheet has two kinds (goal / limit). Rows across both:
Name → **T** `.name`; Target/Limit (`TextField`) → **T** `.amount`; Group `Picker`
→ **M** `.group`; Saved so far (`TextField`) → **T** `.amount`; Target date
(`DatePicker`) → **D** `.date`; category scopes (`CategoryMultiPickerRow`) → **P**
`.category`; account/tag/merchant scopes (`MultiSelectPickerRow`) → **P** `.account`
/`.tags`/`.merchant` as matching; Frequency `Picker` → **M** `.frequency`; Start
date → **D** `.date`; Rollover Cap (`TextField`) → **T** `.amount`.

- [ ] **Step 1:** convert BudgetSheet rows per recipe.
- [ ] **Step 2: Remove the temporary `glyph` defaults** added in Tasks 3–5 from all 8
      shared components (now every call site passes a real glyph). This makes the
      parameter required, catching any missed call site at compile time.
- [ ] **Step 3: BUILD_IOS + BUILD_MAC** → SUCCEEDED (a failure here names any
      unconverted call site — fix it).
- [ ] **Step 4:** Re-run the i18n pipeline if any new keys were added (per ios/CLAUDE.md);
      commit `extracted-keys.json` + rebuilt catalog if changed.
- [ ] **Step 5: Commit** — `feat(ios): Budget sheet — icon rows; require field glyph`

---

## Final whole-branch review

After Task 10: dispatch the broad code review (most-capable model) over
`git merge-base origin/feat/frontend HEAD..HEAD`. Then run the full
`FinchAppTests` suite + both builds, and the controller does the on-sim
`idb ui describe-all` pass across all five sheets to confirm row frames stay
within the tokenized layout and filled/empty/placeholder states render as specced.
Finish via superpowers:finishing-a-development-branch.

## Self-Review notes (author)

- Every field in every sheet maps to a recipe + glyph (coverage table in Tasks 6–10).
- Placeholders/a11y labels are `LocalizedStringKey` — i18n-safe.
- Temporary `glyph` defaults keep each foundation/component task independently
  green; Task 10 removes them so the compiler enforces full coverage.
- macOS: only `#if os` split is Receipt (already present) + the `FieldGlyph.receipt`
  symbol; everything else is cross-platform.
- Not changed: picker sheets, save/validation, field order, `finchSheetForm`.
