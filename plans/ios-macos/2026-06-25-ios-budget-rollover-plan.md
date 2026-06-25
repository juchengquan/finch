# Budget rollover UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface budget rollover in the iOS UI — a rollover toggle + optional cap in `BudgetSheet` (expense budgets), and a carried-forward display + "Rolls over" caption in `BudgetDetailView`.

**Architecture:** Pure UI. The `createBudget`/`updateBudget` actions already persist `rollover`/`rolloverLimit`, and `carryForward` is already in the progress math — so this only adds form controls + a display. One FinchApp task; no FinchCore/engine/schema/test changes.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), XcodeGen, XCTest (build/sim verification only).

## Global Constraints

- **No engine/model/schema/action change; no new FinchCore tests** (no new pure logic — actions + progress math already exist and are tested).
- Rollover controls are **expense-only** (hidden when `kind == .income`), matching the web. (No daily frequency on iOS, so the web's daily caveat is N/A.)
- Save sends `"rollover": .bool(expense && on)`; `"rolloverLimit"`: a valid cap ≥ 0 → `.double`, else `.null` (clears it). Cap validated only when rollover is on and the field is non-empty.
- `carryForward` is already in `base`/`remaining`/`pct` — **display only**, no math change.
- **Must build iOS AND macOS (FinchMac).** Sim `iPhone 17 Pro Max`. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit; **no `Co-Authored-By` trailer**.

---

## File Structure

**Modify (FinchApp):** `ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetSheet.swift`, `ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetDetailView.swift`.

---

### Task 1: Rollover toggle/cap in the form + carried display in the detail

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetSheet.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetDetailView.swift`

**Interfaces:**
- Consumes: `BudgetRow.rollover`/`rolloverLimit`/`carryForward` (already projected); `createBudget`/`updateBudget` `rollover`+`rolloverLimit` args (already accepted); `DecimalInput`, `store.displayMoneyBase`.

- [ ] **Step 1: `BudgetSheet` — add rollover state**

In `BudgetSheet.swift`, after `@State private var selectedCategories: Set<String>` (line 25) add:
```swift
    @State private var rollover: Bool
    @State private var rolloverCap: String
```

- [ ] **Step 2: `BudgetSheet` — prefill in init**

In `init`, after `_selectedCategories = State(initialValue: Set(budget?.categoryIds ?? []))` (line 37) add:
```swift
        _rollover = State(initialValue: (budget?.rollover ?? 0) != 0)
        _rolloverCap = State(initialValue: budget?.rolloverLimit.map { String(format: "%g", $0) } ?? "")
```

- [ ] **Step 3: `BudgetSheet` — rollover section (expense-only)**

In `body`, insert a new section after the categories `Section { … } header/footer` block (after its closing, currently line 80) and before the `if isEdit, budget?.isRecurring == 1` block:
```swift
                if kind == .expense {
                    Section {
                        Toggle("Roll over unused budget", isOn: $rollover)
                        if rollover {
                            HStack {
                                Text("Cap"); Spacer()
                                TextField("Optional", text: $rolloverCap)
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            }
                        }
                    } footer: {
                        Text("Unspent budget carries into the next period. Set a cap to limit how much.")
                    }
                }
```

- [ ] **Step 4: `BudgetSheet` — persist on save**

Replace the entire `save()` function (lines 112–136) with:
```swift
    private func save() {
        errorMessage = nil
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Enter a name."; return }
        guard let value = DecimalInput.parse(amount), value > 0 else { errorMessage = "Enter an amount."; return }
        let categoryIds: JSONValue = .array(selectedCategories.sorted().map { .string($0) })

        // Rollover is expense-only; cap is optional and validated only when set.
        let useRollover = kind == .expense && rollover
        let capValue: JSONValue
        if useRollover && !rolloverCap.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let c = DecimalInput.parse(rolloverCap), c >= 0 else { errorMessage = "Enter a valid rollover cap."; return }
            capValue = .double(c)
        } else {
            capValue = .null
        }

        if let budget {
            let patch: [String: JSONValue] = [
                "name": .string(name), "type": .string(kind.rawValue), "amount": .double(value),
                "frequency": .string(frequency), "categoryIds": categoryIds,
                "groupId": groupId.isEmpty ? .null : .string(groupId),
                "rollover": .bool(useRollover), "rolloverLimit": capValue,
            ]
            do { try store.apply(.updateBudget, Args(["id": .string(budget.id), "patch": .object(patch)])); dismiss() }
            catch { errorMessage = i18nMessage(error) }
        } else {
            var args: [String: JSONValue] = [
                "ledgerId": .string(store.activeLedgerId), "name": .string(name),
                "type": .string(kind.rawValue), "amount": .double(value), "frequency": .string(frequency),
                "rollover": .bool(useRollover),
            ]
            if !groupId.isEmpty { args["groupId"] = .string(groupId) }
            if !selectedCategories.isEmpty { args["categoryIds"] = categoryIds }
            if case .double = capValue { args["rolloverLimit"] = capValue }
            do { try store.apply(.createBudget, Args(args)); dismiss() }
            catch { errorMessage = i18nMessage(error) }
        }
    }
```
(Edit sends `rolloverLimit: .null` to clear a removed cap; create only sends it when a real cap is entered.)

- [ ] **Step 5: `BudgetDetailView` — carried display + "Rolls over" caption**

In `BudgetDetailView.swift`, replace the `progress(_:_:)` function (the `@ViewBuilder private func progress(_ b: BudgetRow, _ p: BudgetProgress) -> some View { … }` block) with:
```swift
    @ViewBuilder private func progress(_ b: BudgetRow, _ p: BudgetProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(store.displayMoneyBase(p.used)) of \(store.displayMoneyBase(p.base))")
                    .fontWeight(.medium)
                Spacer()
                if p.over { Text("Over").font(.caption).foregroundStyle(.red) }
            }
            if b.carryForward > 0 {
                Text("+\(store.displayMoneyBase(b.carryForward)) carried over")
                    .font(.caption).foregroundStyle(.green)
            }
            ProgressView(value: min(Double(p.pct) / 100, 1.0))
                .tint(p.over ? .red : (p.pct >= 70 ? .yellow : .green))
            HStack {
                Text("\(store.displayMoneyBase(p.remaining)) left").font(.caption).foregroundStyle(.secondary)
                if b.rollover != 0 { Text("· Rolls over").font(.caption2).foregroundStyle(.secondary) }
                Spacer()
                Text("\(p.from) – \(p.to)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
```

- [ ] **Step 6: Build iOS + run the full FinchApp suite**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`. (No new files — `xcodegen` is a harmless no-op.)

- [ ] **Step 7: Full FinchCore suite (no regressions)**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test 2>&1 | grep -iE "error:|Test Suite 'All tests'"`
Expected: all pass.

- [ ] **Step 8: Build macOS (FinchMac)**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Manual verification on the simulator**

Launch (Budgets). Then:
- **New expense budget:** the **Roll over unused budget** toggle appears; turn it on → a **Cap** field appears; enter a cap; save. Reopen for edit → toggle on + cap prefilled.
- **Income budget:** no rollover row.
- **Edit:** turn rollover off → save → reopen: off, and the cap is cleared (rolloverLimit null).
- **Detail:** a budget whose prior cycle carried money shows **"+$X carried over"** (green) under the used/base line and a **"· Rolls over"** caption next to "left"; the bar/remaining already reflect the larger base.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch -initialTab budgets
```
(If `-initialTab budgets` isn't recognized, navigate manually.)

- [ ] **Step 10: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetSheet.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetDetailView.swift
git commit -m "feat(ios): budget rollover UI (toggle + cap in form; carried display in detail)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-25-ios-budget-rollover-design.md`):
- Rollover toggle + optional cap, expense-only, persisted on create+edit, prefilled → Steps 1-4. ✓
- `rolloverLimit` cleared (`.null`) when off/empty on edit; sent only when set on create → Step 4. ✓
- Validation (cap ≥ 0 when set) → Step 4. ✓
- Carried-forward display + "Rolls over" caption → Step 5. ✓
- No engine change; build iOS+macOS; full tests green → Steps 6-8. ✓

**Placeholder scan:** No TBD/TODO; full code in every step; sim step concrete. ✓

**Type consistency:** `rollover: Bool`/`rolloverCap: String` state + init prefill from `budget?.rollover`/`rolloverLimit`; `save()` sends `"rollover": .bool`, `"rolloverLimit": .double|.null` (accepted by the existing actions); `progress(b, p)` reads `b.carryForward`/`b.rollover` (both on `BudgetRow`); `DecimalInput.parse` + `store.displayMoneyBase` used as elsewhere in these files. ✓

---

## Out of scope

Engine/model/schema/action changes; rollover math; income rollover; new frequencies; a web rollover-cap UI.
