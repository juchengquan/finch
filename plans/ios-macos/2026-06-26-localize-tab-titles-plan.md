# Localize tab titles — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven). Checkbox steps.

**Goal:** Make `AppTab.title` localized so tab chrome shows Chinese under zh-Hans.

**Architecture:** One change — `AppTab.title` resolves each case via `String(localized:)` against the existing catalog. No catalog/engine change.

Spec: `plans/ios-macos/2026-06-26-localize-tab-titles-design.md`.

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; builds: FinchApp (iOS) + FinchMac (macOS). No `Co-Authored-By`. No engine change. PR → `feat/frontend`.

---

### Task 1: Localize `AppTab.title`

**Files:** Modify `ios/FinchApp/Sources/FinchApp/DeepLink/DeepLinkRouter.swift`

- [ ] **Step 1:** Replace the `AppTab.title` body:

```swift
    public var title: String {
        switch self {
        case .ledger: return "Ledger"
        case .accounts: return "Accounts"; case .activity: return "Activity"
        case .budgets: return "Budgets"; case .insights: return "Insights"
        case .scheduled: return "Scheduled"; case .settings: return "Settings"
        }
    }
```
with:

```swift
    public var title: String {
        switch self {
        case .ledger: return String(localized: "Ledger")
        case .accounts: return String(localized: "Accounts")
        case .activity: return String(localized: "Activity")
        case .budgets: return String(localized: "Budgets")
        case .insights: return String(localized: "Insights")
        case .scheduled: return String(localized: "Scheduled")
        case .settings: return String(localized: "Settings")
        }
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
git add ios/FinchApp/Sources/FinchApp/DeepLink/DeepLinkRouter.swift
git commit -m "fix(ios): localize AppTab.title so tab chrome translates (zh-Hans)"
```

---

### Task 2: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Install + apply zh-Hans + relaunch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install "$SIM" "$APP"; xcrun simctl terminate "$SIM" com.juchengquan.finch 2>/dev/null
xcrun simctl spawn "$SIM" defaults write com.juchengquan.finch AppleLanguages -array zh-Hans
xcrun simctl launch "$SIM" com.juchengquan.finch
```

- [ ] **Step 2: Verify + cleanup**
  - The **bottom tab bar** reads 账本 / 账户 / 预算 / 计划 / 洞察 (was English in #338). Screenshot to `/tmp/tabzh.png`.
  - Cleanup: `xcrun simctl spawn "$SIM" defaults delete com.juchengquan.finch AppleLanguages`.

- [ ] **Step 3 (no commit):** report; if English persists, return to Task 1.

---

## Self-review notes
- Spec coverage: `AppTab.title` localized (T1), cross-platform build (T1 S2), sim zh-Hans tab bar (T2). ✓
- Type consistency: `title: String` unchanged signature; `String(localized:)` returns `String`; consumers untouched. ✓
- No catalog/engine change (keys already present). ✓
