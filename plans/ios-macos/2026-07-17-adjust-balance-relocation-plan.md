# Adjust Balance relocation — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the `adjust` kind from the Add-transaction sheet and relocate the feature to a dedicated, account-locked `AdjustBalanceSheet` opened from the account detail's ⋯ menu.

**Architecture:** Pure UI relocation inside `ios/FinchApp` — the engine action `adjustAccountBalance` and all projections are untouched. Spec: `plans/ios-macos/2026-07-17-adjust-balance-relocation-design.md`.

**Tech Stack:** SwiftUI (iOS 17+/macOS 14+), XcodeGen project, FinchCore engine via `store.apply`.

## Global Constraints

- Build **both** FinchApp (iOS sim) and FinchMac before every commit; run `FinchAppTests` (`xcodebuild test … -only-testing:FinchAppTests`).
- `xcodegen generate` after adding the new file (Task 2) — the `.xcodeproj` is generated and gitignored.
- No engine/web changes; no new entry points beyond the account detail ⋯ menu.
- Commit messages: no `Co-Authored-By` trailer.
- One simulator only (one-sim rule); `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` first.

---

### Task 1: Remove `adjust` from `AddTransactionSheet`

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `Kind` = `{expense, income, transfer, refund}` (4 cases). No other file references `Kind.adjust` (verified by grep in the steps).

- [ ] **Step 1: Slim the `Kind` enum** (lines ~28–32). Replace:

```swift
        case expense, income, transfer, refund, adjust
        var id: String { rawValue }
        var label: String { self == .adjust ? "Adjust Balance" : rawValue.capitalized }
        /// SF Symbol for the segment (adjust reuses the engine's "adjustment" icon).
        var iconName: String { TxnKindIcon.icon(for: self == .adjust ? "adjustment" : rawValue) }
```

with:

```swift
        case expense, income, transfer, refund
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var iconName: String { TxnKindIcon.icon(for: rawValue) }
```

- [ ] **Step 2: Delete the `targetBalance` state** (line ~46):

```swift
    @State private var targetBalance = ""   // adjust-balance: the account's new balance
```

- [ ] **Step 3: Simplify the page-content switch** (lines ~216–222). Replace:

```swift
                if k == .transfer {
                    transferFields
                } else if k == .adjust {
                    adjustFields
                } else {
                    expenseIncomeFields(for: k)
                }
```

with:

```swift
                if k == .transfer {
                    transferFields
                } else {
                    expenseIncomeFields(for: k)
                }
```

- [ ] **Step 4: Unwrap the `k != .adjust` gate** (line ~233). The Status + Tags sections were wrapped in `if k != .adjust { … }` — remove the wrapper `if` and its closing brace, keeping the Status `Section` and the `if !store.tags.isEmpty { Section("Tags") { … } }` block at the same position, dedented one level.

- [ ] **Step 5: Delete `adjustFields`** (lines ~383–396) — the whole `@ViewBuilder private var adjustFields: some View { … }` property including its `Section`/footer.

- [ ] **Step 6: Delete the adjust save branch** (lines ~430–441). In `save()`, remove:

```swift
        if kind == .adjust {
            guard let target = DecimalInput.parse(targetBalance) else { errorMessage = "Enter a new balance."; return }
            do {
                var args: [String: JSONValue] = [
                    "accountId": .string(accountId), "targetBalance": .double(target), "date": .string(Self.day(date)),
                ]
                if !note.isEmpty { args["note"] = .string(note) }
                try store.apply(.adjustAccountBalance, Args(args))
                dismiss()
            } catch { errorMessage = i18nMessage(error) }
            return
        }
```

- [ ] **Step 7: Verify no stragglers**

Run: `grep -n "adjust" ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift`
Expected: no matches (`isLineItem` at ~line 69 never mentioned adjust; leave it as is).

- [ ] **Step 8: Build both + tests**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
UDID=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp -destination "id=$UDID" 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp -destination "id=$UDID" -only-testing:FinchAppTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)"
```

Expected: both `BUILD SUCCEEDED`, `TEST SUCCEEDED` (147+ tests, 0 failures).

- [ ] **Step 9: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/AddTransactionSheet.swift
git commit -m "feat(ios): Add sheet slims to 4 types — adjust kind removed"
```

---

### Task 2: New `AdjustBalanceSheet`

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/WriteScreens/AdjustBalanceSheet.swift`

**Interfaces:**
- Consumes: `FinchStore` (`displayMoney(_:from:)`, `apply`), `AccountRow`, `DecimalInput`, `AppDate`, `i18nMessage`, `errorAlert` — all existing.
- Produces: `struct AdjustBalanceSheet: View` with `init(account: AccountRow)` — Task 3 presents it.

- [ ] **Step 1: Create the file** with exactly:

```swift
import SwiftUI
import FinchCore

/// Adjust an account's balance to a target value — posts an `adjustment`
/// entry for the difference via the engine's `adjustAccountBalance`. Reached
/// from the account detail's ⋯ menu (relocated out of the Add sheet, where it
/// occupied a 5th transaction type despite being account maintenance; spec
/// `2026-07-17-adjust-balance-relocation-design.md`). Locked to one account.
struct AdjustBalanceSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let account: AccountRow
    @State private var targetBalance = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(account.name ?? "Account",
                                   value: store.displayMoney(account.balance, from: account.currency ?? store.baseCurrency))
                    HStack {
                        Text("New balance"); Spacer()
                        // numbersAndPunctuation allows a leading minus (e.g. a credit-card balance).
                        TextField("0.00", text: $targetBalance)
                            #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                            #endif
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Posts an adjustment for the difference from the account's current balance.")
                }
                Section {
                    // Date-only: adjustAccountBalance takes no time argument.
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                        .environment(\.locale, AppDate.h24Locale)
                    HStack {
                        Text("Note"); Spacer()
                        TextField("Optional", text: $note, axis: .vertical).multilineTextAlignment(.trailing)
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Adjust Balance")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
        guard let target = DecimalInput.parse(targetBalance) else { errorMessage = "Enter a new balance."; return }
        do {
            var args: [String: JSONValue] = [
                "accountId": .string(account.id), "targetBalance": .double(target),
                "date": .string(AppDate.isoDay.string(from: date)),
            ]
            if !note.isEmpty { args["note"] = .string(note) }
            try store.apply(.adjustAccountBalance, Args(args))
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
```

Note: if `TextField` + postfix `#if os(iOS)` fails to parse in this position, hoist the field into a small `private var balanceField: some View` with the `#if` inside — same pattern the codebase uses elsewhere.

- [ ] **Step 2: Regenerate the project + build both + tests** (new file ⇒ `xcodegen generate` is mandatory). Same commands/expectations as Task 1 Step 8.

- [ ] **Step 3: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/AdjustBalanceSheet.swift
git commit -m "feat(ios): dedicated account-locked AdjustBalanceSheet"
```

---

### Task 3: Entry point in `AccountDetailView`

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift`

**Interfaces:**
- Consumes: `AdjustBalanceSheet(account:)` from Task 2.
- Produces: n/a (leaf task).

- [ ] **Step 1: Add state** next to `showingReconcile` (line ~16):

```swift
    @State private var showingAdjust = false
```

- [ ] **Step 2: Add the menu item** directly after the Reconcile button (line ~52):

```swift
                            Button { showingAdjust = true } label: { Label("Adjust balance…", systemImage: TxnKindIcon.icon(for: "adjustment")) }
```

- [ ] **Step 3: Present the sheet** next to the Reconcile sheet (line ~61):

```swift
                .sheet(isPresented: $showingAdjust) { AdjustBalanceSheet(account: account) }
```

(This sits inside the `if let account` branch like the other sheets, so `account` is non-optional here.)

- [ ] **Step 4: Build both + tests** — same commands/expectations as Task 1 Step 8.

- [ ] **Step 5: Sim smoke** (one-sim rule): install + launch, `xcrun simctl openurl "$UDID" "finch://add"` → screenshot shows 4 segments; then manual checklist in the PR body covers the menu flow (taps aren't scriptable).

- [ ] **Step 6: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/AccountDetailView.swift
git commit -m "feat(ios): Adjust balance entry in account detail menu"
```

---

## PR

Title: `feat(ios): relocate Adjust Balance — Add sheet slims to 4 types, account-detail menu entry`

Body: link the spec; note the deliberate web-parity divergence; manual checklist from the spec (4-type Add sheet + swipe across 4 · adjust from ⋯ menu posts the correct difference · negative target accepted · cancel posts nothing · macOS menu item + 4 segments).

## Self-review notes

- Spec coverage: Task 1 = spec §1, Task 2 = spec §2 (date-only picker included), Task 3 = spec §3. Non-changes need no tasks.
- Types: `AdjustBalanceSheet(account: AccountRow)` consistent between Tasks 2 and 3; `Kind` 4-case enum consumed only within `AddTransactionSheet` (grep step guards).
- No placeholders; every code step carries the actual code.
