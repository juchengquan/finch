# Add/Edit Sheet Layout Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify the five add/edit sheets on the transaction blueprint — one header rule, hints always as footers, and section-title spacing driven by global `Metrics` tokens.

**Architecture:** Add three `Metrics` tokens and a shared `finchSectionHeader(_:)` view, point `TxnTypeToolbar.caption` at the new inset token, then restructure Budget / Scheduled / Accounts to the agreed section map and route every labeled section across all five sheets through the helper. Layout only — no state, `save()`, or engine changes.

**Tech Stack:** SwiftUI (iOS 17 / macOS 14 floor); XcodeGen; `xcodebuild`.

## Global Constraints

- **Worktree / branch:** `/tmp/finch-sheets` on `feat/ios-sheet-layout-unification` (off `origin/feat/frontend`). PR targets `feat/frontend`.
- **Environment:** `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before any `xcodebuild`/`xcodegen`; run `xcodegen generate` (from `/tmp/finch-sheets/ios`) after adding a new file. Sim `ios-finch2`; iOS `-derivedDataPath /tmp/dd-sheets`, mac `-derivedDataPath /tmp/dd-sheetsmac CODE_SIGNING_ALLOWED=NO`.
- **Commits:** no `Co-Authored-By` trailer.
- **Layout only.** No FinchCore/engine/schema/web change. Do NOT touch any `save()`, `@State` declaration, binding, validation, or action — fields keep their existing behavior; only grouping, headers, and hint placement move.
- **Header rule (verbatim):** bare (no header) for the **type-caption section, the primary field group, and the error section**; a string header on **every secondary group**.
- **Hints are always section footers** — never an inline `Text` row inside a section.
- **`.textCase(nil)` is required** on the header helper: SwiftUI upper-cases grouped-list headers by default, and these sheets render "Receipt"/"Details" in title case today.
- **Cross-platform:** the helper must compile on macOS — use only plain SwiftUI views (unlike `finchSectionSpacing`, which is iOS-only because `listSectionSpacing` doesn't exist on macOS).
- **No unit tests** in this plan: every change is view layout with no pure logic introduced. Verification is that **both FinchApp and FinchMac build**, plus a human visual pass (the sim's UI-automation permission is revoked, so the agent cannot navigate into these sheets).

## File Map

| File | Task | Responsibility |
|------|------|----------------|
| `ios/FinchApp/Sources/FinchApp/Common/Metrics.swift` | 1 | the three new spacing tokens |
| `ios/FinchApp/Sources/FinchApp/Common/SectionHeader.swift` | 1 (create) | the shared `finchSectionHeader(_:)` view |
| `ios/FinchApp/Sources/FinchApp/Common/TxnTypeToolbar.swift` | 1 | `caption` uses `Metrics.captionInsets` |
| `ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetSheet.swift` | 2 | dedup onto `TxnTypeToolbar`; `Tracking`/`Rollover`; warning → footer |
| `ios/FinchApp/Sources/FinchApp/WriteScreens/ScheduledSheet.swift` | 3 | hint → footer; `Account`/`Schedule`/`Installment` |
| `ios/FinchApp/Sources/FinchApp/WriteScreens/AccountSheet.swift` | 3 | fold net-worth toggle; headers via helper |
| `ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift` | 4 | `Receipt`/`Details` via helper |
| `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift` | 4 | `Transfer`/`Account`/`Receipt`/`Details` via helper |

---

### Task 1: Foundation — tokens, header helper, caption insets

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Common/Metrics.swift`
- Create: `ios/FinchApp/Sources/FinchApp/Common/SectionHeader.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/Common/TxnTypeToolbar.swift`

**Interfaces:**
- Produces: `Metrics.headerTopPadding`, `Metrics.headerBottomPadding`, `Metrics.captionInsets`; and `func finchSectionHeader(_ title: String) -> some View`. Tasks 2–4 call `finchSectionHeader`.

- [ ] **Step 1: Add the tokens**

In `Metrics.swift`, inside `enum Metrics`, after the existing `sectionSpacing` line, add:

```swift

    /// Gap above a section title rendered by `finchSectionHeader`.
    static let headerTopPadding: CGFloat = 16
    /// Gap between a section title and its group.
    static let headerBottomPadding: CGFloat = 6
    /// Row insets for the type-caption row (`TxnTypeToolbar.caption`).
    static let captionInsets = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
```

`Metrics.swift` currently imports only `CoreGraphics`; `EdgeInsets` is a SwiftUI type, so change the import line at the top of the file from:

```swift
import CoreGraphics
```
to:
```swift
import SwiftUI
```

- [ ] **Step 2: Create the header helper**

Create `ios/FinchApp/Sources/FinchApp/Common/SectionHeader.swift`:

```swift
import SwiftUI

/// The app-wide section title for grouped `Form`/`List` sections — used as a
/// section's `header:` so title spacing is driven by `Metrics` instead of the
/// system default:
///
///     Section { … } header: { finchSectionHeader("Tracking") }
///
/// `.textCase(nil)` is required: SwiftUI upper-cases grouped-list headers by
/// default, and these sheets render their titles in title case.
func finchSectionHeader(_ title: String) -> some View {
    Text(title)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .textCase(nil)
        .padding(.top, Metrics.headerTopPadding)
        .padding(.bottom, Metrics.headerBottomPadding)
}
```

- [ ] **Step 3: Point the caption at the token**

In `TxnTypeToolbar.swift`, in `caption(_:)`, replace:

```swift
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
```
with:
```swift
            .listRowInsets(Metrics.captionInsets)
```

- [ ] **Step 4: Build both platforms**

```bash
cd /tmp/finch-sheets/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null
xcodebuild build -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -derivedDataPath /tmp/dd-sheets 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
xcodebuild build -scheme FinchMac -destination 'platform=macOS' -derivedDataPath /tmp/dd-sheetsmac CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```
Expected: both `** BUILD SUCCEEDED **`. (The caption is visually unchanged — the token holds the same values it replaced. `finchSectionHeader` has no callers yet.)

- [ ] **Step 5: Commit**

```bash
cd /tmp/finch-sheets && git add ios/FinchApp/Sources/FinchApp/Common/Metrics.swift ios/FinchApp/Sources/FinchApp/Common/SectionHeader.swift ios/FinchApp/Sources/FinchApp/Common/TxnTypeToolbar.swift && git commit -m "feat(ios): section-title spacing tokens + shared finchSectionHeader"
```

---

### Task 2: BudgetSheet — adopt `TxnTypeToolbar`, restructure sections

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetSheet.swift`

**Interfaces:**
- Consumes: `finchSectionHeader(_:)` (Task 1); `TxnTypeToolbar.caption(_:)` and `TxnTypeToolbar.segmented(_:selection:icon:label:)` (existing, `Common/TxnTypeToolbar.swift`).

- [ ] **Step 1: Replace the hand-rolled caption with the shared one**

Replace this section (the first section inside `Form {`):

```swift
                Section {
                    Text(kind.label)   // names the icon-only type control in the toolbar
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
```
with:
```swift
                Section { TxnTypeToolbar.caption(kind.label) }   // names the toolbar type control above
```

- [ ] **Step 2: Move the cycle re-base warning into the primary section's footer**

The primary section currently ends at the `Group` picker's closing `}`. Replace:

```swift
                    Picker("Group", selection: $groupId) {
                        Text("None").tag("")
                        ForEach(store.budgetGroups) { Text($0.name).tag($0.id) }
                    }
                }
```
with:
```swift
                    Picker("Group", selection: $groupId) {
                        Text("None").tag("")
                        ForEach(store.budgetGroups) { Text($0.name).tag($0.id) }
                    }
                } footer: {
                    if isEdit, budget?.isRecurring == 1 {
                        Text("Changing the start date or frequency re-bases the cycle and clears any staged amount and rolled-over balance.")
                    }
                }
```

Then delete the now-redundant standalone note section entirely:

```swift
                if isEdit, budget?.isRecurring == 1 {
                    Section {
                        Text("Changing the start date or frequency re-bases the cycle and clears any staged amount and rolled-over balance.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
```

- [ ] **Step 3: Add the `Tracking` header**

On the section holding `CategoryMultiPickerRow` + `MultiSelectPickerRow`, add a header before its existing footer. Replace:

```swift
                } footer: {
                    Text("Leave empty to track all \(kind.rawValue) categories and accounts.")
                }
```
with:
```swift
                } header: {
                    finchSectionHeader("Tracking")
                } footer: {
                    Text("Leave empty to track all \(kind.rawValue) categories and accounts.")
                }
```

- [ ] **Step 4: Add the `Rollover` header**

On the expense-only rollover section, replace:

```swift
                    } footer: {
                        Text("Unspent budget carries into the next period. Set a cap to limit how much.")
                    }
```
with:
```swift
                    } header: {
                        finchSectionHeader("Rollover")
                    } footer: {
                        Text("Unspent budget carries into the next period. Set a cap to limit how much.")
                    }
```

- [ ] **Step 5: Replace the hand-rolled toolbar picker with the shared control**

Replace:

```swift
                ToolbarItem(placement: .principal) {
                    Picker("Type", selection: $kind) {
                        ForEach(Kind.allCases) { k in
                            Image(systemName: TxnKindIcon.icon(for: k.rawValue)).accessibilityLabel(k.label).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                }
```
with:
```swift
                ToolbarItem(placement: .principal) {
                    TxnTypeToolbar.segmented(Kind.allCases, selection: $kind,
                        icon: { TxnKindIcon.icon(for: $0.rawValue) }, label: { $0.label })
                }
```

(`Kind.allCases` is 2 cases, so the shared control's `count * 50` width is 100 — identical to the hardcoded frame it replaces.)

- [ ] **Step 6: Build both platforms**

```bash
cd /tmp/finch-sheets/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null
xcodebuild build -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -derivedDataPath /tmp/dd-sheets 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
xcodebuild build -scheme FinchMac -destination 'platform=macOS' -derivedDataPath /tmp/dd-sheetsmac CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd /tmp/finch-sheets && git add ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetSheet.swift && git commit -m "refactor(ios): BudgetSheet adopts TxnTypeToolbar + Tracking/Rollover headers"
```

---

### Task 3: ScheduledSheet + AccountSheet

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/ScheduledSheet.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AccountSheet.swift`

**Interfaces:**
- Consumes: `finchSectionHeader(_:)` (Task 1).

- [ ] **Step 1: ScheduledSheet — move the inline hint into a footer**

Replace the primary section (Name/Amount + inline hint):

```swift
                Section {
                    TextField("Name", text: $name)
                    HStack {
                        Text("Amount"); Spacer()
                        TextField("0.00", text: $amount).numericInput($amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    if !installmentEnabled {
                        Text("Leave empty for a variable amount (entered when posting).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
```
with:
```swift
                Section {
                    TextField("Name", text: $name)
                    HStack {
                        Text("Amount"); Spacer()
                        TextField("0.00", text: $amount).numericInput($amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                } footer: {
                    if !installmentEnabled {
                        Text("Leave empty for a variable amount (entered when posting).")
                    }
                }
```

- [ ] **Step 2: ScheduledSheet — add the three secondary headers**

The account/category section currently opens with a bare `Section {` and contains the `isEdit` / `kind == .transfer` branches ending with `CategoryPickerRow(...)`. Add a header to its closing brace — replace that section's closing:

```swift
                }

                Section {
                    Picker("Frequency", selection: $frequency) {
```
with:
```swift
                } header: {
                    finchSectionHeader("Account")
                }

                Section {
                    Picker("Frequency", selection: $frequency) {
```

Then the frequency/start section — replace its closing:

```swift
                    if isEdit {
                        LabeledContent("Start", value: template?.startDate ?? "—")
                    } else {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    }
                }
```
with:
```swift
                    if isEdit {
                        LabeledContent("Start", value: template?.startDate ?? "—")
                    } else {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    }
                } header: {
                    finchSectionHeader("Schedule")
                }
```

Then the installment section — replace its closing:

```swift
                    Toggle("Installment plan", isOn: $installmentEnabled)
                    if installmentEnabled {
                        HStack {
                            Text("Number of payments"); Spacer()
                            TextField("12", text: $installmentTotal).numericInput($installmentTotal, allowsDecimal: false).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        }
                    }
                }
```
with:
```swift
                    Toggle("Installment plan", isOn: $installmentEnabled)
                    if installmentEnabled {
                        HStack {
                            Text("Number of payments"); Spacer()
                            TextField("12", text: $installmentTotal).numericInput($installmentTotal, allowsDecimal: false).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    finchSectionHeader("Installment")
                }
```

- [ ] **Step 3: AccountSheet — fold the net-worth toggle into the primary section**

Replace the primary section's closing `Group` picker block:

```swift
                    Picker("Group", selection: $groupId) {
                        Text("None").tag("")
                        ForEach(store.accountGroups) { Text($0.name).tag($0.id) }
                    }
                }
```
with:
```swift
                    Picker("Group", selection: $groupId) {
                        Text("None").tag("")
                        ForEach(store.accountGroups) { Text($0.name).tag($0.id) }
                    }
                    if isEdit {
                        Toggle("Include in net worth", isOn: $includeInNetWorth)
                    }
                }
```

Then delete the now-duplicate standalone section:

```swift
                if isEdit {
                    Section { Toggle("Include in net worth", isOn: $includeInNetWorth) }
                }
```

- [ ] **Step 4: AccountSheet — route its two headers through the helper**

Replace:

```swift
                    Section("Opening balance") {
```
with:
```swift
                    Section {
```
and add a header to that section's closing brace — replace:

```swift
                        HStack {
                            Text("Amount"); Spacer()
                            TextField("0.00", text: $openingBalance).numericInput($openingBalance)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    }
                }
```
with:
```swift
                        HStack {
                            Text("Amount"); Spacer()
                            TextField("0.00", text: $openingBalance).numericInput($openingBalance)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    } header: {
                        finchSectionHeader("Opening balance")
                    }
                }
```

Then the Color section — replace:

```swift
                Section("Color") {
```
with:
```swift
                Section {
```
and its closing brace — replace:

```swift
                            .accessibilityLabel("Color \(swatch.hex)")
                        }
                    }
                }
```
with:
```swift
                            .accessibilityLabel("Color \(swatch.hex)")
                        }
                    }
                } header: {
                    finchSectionHeader("Color")
                }
```

- [ ] **Step 5: Build both platforms**

```bash
cd /tmp/finch-sheets/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null
xcodebuild build -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -derivedDataPath /tmp/dd-sheets 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
xcodebuild build -scheme FinchMac -destination 'platform=macOS' -derivedDataPath /tmp/dd-sheetsmac CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd /tmp/finch-sheets && git add ios/FinchApp/Sources/FinchApp/WriteScreens/ScheduledSheet.swift ios/FinchApp/Sources/FinchApp/WriteScreens/AccountSheet.swift && git commit -m "refactor(ios): Scheduled + Account sheets adopt the unified section layout"
```

---

### Task 4: Transaction sheets — route existing headers through the helper

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift`

**Interfaces:**
- Consumes: `finchSectionHeader(_:)` (Task 1).

**Nature of this task:** purely mechanical. Do NOT rename a header, move a field, regroup a section, or change any behavior — only the rendering path of the title changes. Each edit applies the identical transformation:

```swift
// before
Section("NAME") {
    …body…
}

// after
Section {
    …body…
} header: {
    finchSectionHeader("NAME")
}
```

- [ ] **Step 1: Apply the transformation to all six occurrences**

Apply the transformation above to each of these, keeping the header string exactly as-is:

| File | Header string |
|---|---|
| `AddTransactionSheet.swift` | `"Receipt"` |
| `AddTransactionSheet.swift` | `"Details"` |
| `EditTransactionSheet.swift` | `"Transfer"` |
| `EditTransactionSheet.swift` | `"Account"` |
| `EditTransactionSheet.swift` | `"Receipt"` |
| `EditTransactionSheet.swift` | `"Details"` (appears **twice** — both occurrences) |

Locate them with:
```bash
grep -n 'Section("' /tmp/finch-sheets/ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift /tmp/finch-sheets/ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift
```
After the edits that same grep must return **no matches** in these two files.

- [ ] **Step 2: Verify nothing else changed**

```bash
cd /tmp/finch-sheets && git diff --stat ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift
```
Expected: only these two files, and the insertions/deletions should be small and symmetric (each occurrence turns 1 line into 3). If a field or behavior line appears in the diff, revert it — it's out of scope.

- [ ] **Step 3: Build both platforms**

```bash
cd /tmp/finch-sheets/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null
xcodebuild build -scheme FinchApp -destination 'platform=iOS Simulator,name=ios-finch2' -derivedDataPath /tmp/dd-sheets 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
xcodebuild build -scheme FinchMac -destination 'platform=macOS' -derivedDataPath /tmp/dd-sheetsmac CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /tmp/finch-sheets && git add ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift && git commit -m "refactor(ios): route transaction sheet headers through finchSectionHeader"
```

---

## Manual verification (human — required)

This change is layout-only, and the simulator's UI-automation permission is revoked, so **the agent cannot verify appearance**. After Task 4, build + install and check by hand:

```bash
cd /tmp/finch-sheets/ios && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun simctl install ios-finch2 /tmp/dd-sheets/Build/Products/Debug-iphonesimulator/FinchApp.app
xcrun simctl launch ios-finch2 com.juchengquan.finch
```

Open each sheet and confirm: section titles read in **title case** (not SHOUTING — that means `.textCase(nil)` didn't take); the gap above/below titles looks right (tune `Metrics.headerTopPadding` / `headerBottomPadding` — that's the one-line knob the tokens exist for); the type caption on Budget/Scheduled is unchanged; Scheduled's variable-amount hint now sits below its group, not as a row inside it; Accounts' "Include in net worth" now sits in the first group on edit. Then open **Add Transaction** and **Edit Transaction** and confirm `Receipt`/`Details`/`Transfer`/`Account` look exactly as before.

## Out of scope

A footer helper or footer tokens; moving Accounts' type into the toolbar; renaming/regrouping any transaction section; a sheet-vs-tab `sectionSpacing` split; any behavior, state, `save()`, engine, or web change; zh-Hans for the new header strings (`Tracking`, `Rollover`, `Account`, `Schedule`, `Installment`) — standard localization pass.

## Self-Review

**Spec coverage:** tokens + helper + caption insets (Task 1); helper applied to all four families (Tasks 2–4); header rule — bare caption/primary/error, headers on secondary groups (Tasks 2–4 add exactly `Tracking`, `Rollover`, `Account`, `Schedule`, `Installment` and keep `Opening balance`/`Color`/`Receipt`/`Details`/`Transfer`/`Account`); hints always footers (Task 2 Step 2 Budget warning, Task 3 Step 1 Scheduled hint); Accounts folds the net-worth toggle (Task 3 Step 3); Accounts keeps its Type row and visible nav title (untouched by design — no task changes them); Budget dedups onto `TxnTypeToolbar` (Task 2 Steps 1, 5); `.textCase(nil)` (Task 1 Step 2); macOS-safe helper (Task 1 Step 2 uses only plain views); one PR (single branch). All covered.

**Placeholder scan:** none — every step carries the exact before/after code, and Task 4's uniform transformation is shown in full with an exhaustive occurrence table plus a grep that must return zero matches.

**Type consistency:** `finchSectionHeader(_ title: String) -> some View` (Task 1) is called with a single string literal in Tasks 2, 3, and 4. `Metrics.headerTopPadding` / `headerBottomPadding` / `captionInsets` (Task 1) are referenced only inside `SectionHeader.swift` and `TxnTypeToolbar.caption`. `TxnTypeToolbar.segmented(_:selection:icon:label:)` and `.caption(_:)` match the existing signatures in `Common/TxnTypeToolbar.swift`.
