# Edit counterparty suggestions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Add form's merchant counterparty suggestions ("pick / Create") to the Edit form's Merchant field.

**Architecture:** Mirror #264's `matchingCounterparties` / `merchantSuggestionRows` / `pickCounterparty` / `createCounterpartyOnSave` into `EditTransactionSheet`; the engine's merchant→counterparty resolution on the `updateTransaction` `merchant` patch does the linking. UI-only.

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-25-edit-counterparty-suggestions-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS).
- Commits: **no `Co-Authored-By` trailer**. No engine/parity changes. PR targets `feat/frontend`.

---

### Task 1: Counterparty suggestions in `EditTransactionSheet`

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift`

- [ ] **Step 1: Add state**

After `@State private var currencyCode: String`, add:

```swift
    @State private var createCounterpartyOnSave = false   // set by the "Create <name>" row
```

- [ ] **Step 2: Add the helpers**

Add these members (e.g. near the other computed vars / `refundedSummary`):

```swift
    private var matchingCounterparties: [Counterparty] {
        let t = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return [] }
        return Array(store.counterparties
            .filter { $0.name.localizedCaseInsensitiveContains(t)
                   && $0.name.caseInsensitiveCompare(t) != .orderedSame }
            .prefix(5))
    }
    @ViewBuilder private var merchantSuggestionRows: some View {
        let t = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        if txn.kind != "transfer", !t.isEmpty {
            ForEach(matchingCounterparties) { cp in
                Button { pickCounterparty(cp.name) } label: {
                    Label(cp.name, systemImage: "building.2").font(.callout)
                }
            }
            if !store.counterparties.contains(where: { $0.name.caseInsensitiveCompare(t) == .orderedSame }) {
                Button { createCounterpartyOnSave = true } label: {
                    Label("Create “\(t)”", systemImage: "plus.circle").font(.callout)
                }
            }
        }
    }
    private func pickCounterparty(_ name: String) {
        merchant = name
        createCounterpartyOnSave = false
    }
```

- [ ] **Step 3: Render the suggestions under the Merchant field**

In `body`, replace the Merchant `HStack`:

```swift
                    HStack {
                        Text("Merchant"); Spacer()
                        TextField("", text: $merchant).multilineTextAlignment(.trailing)
                    }
```
with:

```swift
                    HStack {
                        Text("Merchant"); Spacer()
                        TextField("", text: $merchant).multilineTextAlignment(.trailing)
                    }
                    merchantSuggestionRows
```

- [ ] **Step 4: Reset the create flag on text change**

Alongside the other view modifiers (e.g. right after the `.onAppear { … }` block), add:

```swift
            .onChange(of: merchant) { _, _ in createCounterpartyOnSave = false }
```

- [ ] **Step 5: Create the counterparty on save**

In `save()`, immediately **before** the `do { try store.apply(.updateTransaction, …) }` block, add:

```swift
        if createCounterpartyOnSave {
            let cpName = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cpName.isEmpty,
               !store.counterparties.contains(where: { $0.name.caseInsensitiveCompare(cpName) == .orderedSame }) {
                try store.apply(.createCounterparty, Args(["ledgerId": .string(store.activeLedgerId), "name": .string(cpName)]))
            }
        }
```
(The `updateTransaction` that follows patches `merchant`; the engine resolves the
now-existing name to its counterparty. No `counterpartyId` is passed.)

- [ ] **Step 6: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/WriteScreens/EditTransactionSheet.swift
git commit -m "feat(ios): Edit sheet — counterparty suggestions (mirror Add)"
```

---

### Task 2: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Install + launch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"; xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```
(A merchant or two helps — Power Tools › Merchants, or already seeded "Coffee".)

- [ ] **Step 2: Verify**
  - Open an expense in **Edit** → type in **Merchant** → matching counterparties are suggested; tap one → fills the name → save → linked.
  - Type a brand-new name → **Create "<name>"** row → tap → save → a new counterparty exists (Power Tools › Merchants) and the tx links.
  - A **transfer** opened in Edit shows no suggestions.
  - Screenshot evidence to `/tmp/editcpsuggest.png`.

- [ ] **Step 3 (no commit):** report; if a check fails, return to Task 1.

---

## Self-review notes
- Spec coverage: state (T1 S1), helpers (T1 S2), suggestions under merchant (T1 S3), flag reset (T1 S4), create-on-save before update (T1 S5), cross-platform build (T1 S6), manual incl. transfer-hidden (T2). ✓
- Type consistency: `matchingCounterparties`/`merchantSuggestionRows`/`pickCounterparty`/`createCounterpartyOnSave`, `store.counterparties`, `createCounterparty`, `updateTransaction` consistent with #264. ✓
- No engine change (resolve on merchant patch pre-existing). ✓
