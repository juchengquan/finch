# Demo budget groups — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven). Checkbox steps.

**Goal:** The simulator demo seed creates two budget groups with budgets (+ one ungrouped).

**Architecture:** One block in `FinchStore.seedSimulatorDemo` — add `budgetGroups` (mirrors `accountGroups`) + assign `groupId` on seeded budgets. No engine change.

Spec: `plans/ios-macos/2026-06-27-demo-budget-groups-design.md`.

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS). No `Co-Authored-By`. No engine change. PR → `feat/frontend`.
- `FinchStore.swift` is core/active — keep edits to the one block; **re-check `gh pr list --base feat/frontend --state open` before pushing**.

---

### Task 1: Seed budget groups + grouped budgets

**Files:** Modify `ios/FinchApp/Sources/FinchApp/FinchStore.swift`

- [ ] **Step 1:** In `seedSimulatorDemo`, replace this exact block:

```swift
        let budgets: [(name: String, amount: Double, cat: String)] = [
            ("Groceries", 600, "cat-groceries"), ("Dining", 300, "cat-dining"),
            ("Shopping", 400, "cat-shopping"), ("Transport", 200, "cat-transport"),
        ]
        for b in budgets {
            try apply("createBudget", [
                "ledgerId": .string("personal"), "name": .string(b.name), "type": .string("expense"),
                "amount": .double(b.amount), "frequency": .string("monthly"),
                "startDate": .string(monthStart(3)),
                "categoryIds": .array([.string(b.cat)])])
        }
```
with:

```swift
        let budgetGroups: [(id: String, name: String)] = [
            ("bgg-essentials", "Essentials"),
            ("bgg-lifestyle", "Lifestyle"),
        ]
        for g in budgetGroups {
            try apply("createBudgetGroup", [
                "id": .string(g.id), "ledgerId": .string("personal"), "name": .string(g.name)])
        }

        let budgets: [(name: String, amount: Double, cat: String, group: String?)] = [
            ("Rent", 1500, "cat-rent", "bgg-essentials"),
            ("Groceries", 600, "cat-groceries", "bgg-essentials"),
            ("Utilities", 150, "cat-utilities", "bgg-essentials"),
            ("Transport", 200, "cat-transport", "bgg-essentials"),
            ("Dining", 300, "cat-dining", "bgg-lifestyle"),
            ("Shopping", 400, "cat-shopping", "bgg-lifestyle"),
            ("Entertainment", 120, "cat-entertainment", "bgg-lifestyle"),
            ("Health", 100, "cat-health", nil),
        ]
        for b in budgets {
            var args: [String: JSONValue] = [
                "ledgerId": .string("personal"), "name": .string(b.name), "type": .string("expense"),
                "amount": .double(b.amount), "frequency": .string("monthly"),
                "startDate": .string(monthStart(3)),
                "categoryIds": .array([.string(b.cat)])]
            if let g = b.group { args["groupId"] = .string(g) }
            try apply("createBudget", args)
        }
```

- [ ] **Step 2: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/FinchStore.swift
git commit -m "feat(ios): demo seed — budget groups (Essentials/Lifestyle + ungrouped)"
```

---

### Task 2: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Fresh re-seed + install** (the demo seeds only on an empty DB):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
cd ios && xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/dbg-dd >/dev/null 2>&1
xcrun simctl list devices booted | grep -q "$SIM" || { xcrun simctl boot "$SIM"; open -a Simulator; sleep 5; }
xcrun simctl terminate "$SIM" com.juchengquan.finch 2>/dev/null
xcrun simctl uninstall "$SIM" com.juchengquan.finch 2>/dev/null   # wipe so seedSimulatorDemo re-runs
xcrun simctl install "$SIM" /tmp/dbg-dd/Build/Products/Debug-iphonesimulator/FinchApp.app
xcrun simctl launch "$SIM" com.juchengquan.finch -initialTab budgets
```

- [ ] **Step 2: Verify**
  - Budgets tab shows **Essentials** (Rent / Groceries / Utilities / Transport) and
    **Lifestyle** (Dining / Shopping / Entertainment) group sections, plus an ungrouped
    **Health**. Screenshot `/tmp/budget-groups.png`. Clean up `/tmp/dbg-dd` after.

- [ ] **Step 3 (no commit):** report; if a check fails, return to Task 1.

---

## Self-review notes
- Spec coverage: budgetGroups + grouped budgets + ungrouped Health (T1), build (T1 S2), manual (T2). ✓
- Type consistency: `createBudgetGroup` args `{id,ledgerId,name}`; `createBudget` `groupId` passed when set; categories all exist in the seed. ✓
- No engine change; demo seed only (`#if targetEnvironment(simulator)`). ✓
