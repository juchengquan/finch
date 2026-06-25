# Refund badge on transaction rows — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a "Refund" badge on `kind == "refund"` rows in the transaction feed.

**Architecture:** A small capsule in `TxRow`'s merchant `HStack`, gated on `txn.kind == "refund"`. UI-only, no engine change. Web parity (`RefundBadge`).

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-25-refund-badge-design.md`.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds.
- Builds: FinchApp (iOS) **and** FinchMac (macOS) — `TxRow` is shared.
- Commits: **no `Co-Authored-By` trailer**. No engine/parity changes. PR targets `feat/frontend`.

---

### Task 1: Refund badge in `TxRow`

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift`

- [ ] **Step 1: Add the badge to the merchant HStack**

In `struct TxRow`, in the merchant `HStack(spacing: 4) { … }`, replace:

```swift
                    if store.isAnomaly(txn) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange)
                            .accessibilityLabel("Unusual amount")
                    }
                }
```
with:

```swift
                    if store.isAnomaly(txn) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange)
                            .accessibilityLabel("Unusual amount")
                    }
                    if txn.kind == "refund" {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.uturn.left")
                            Text("Refund")
                        }
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                        .accessibilityLabel("Refund")
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
git add ios/FinchApp/Sources/FinchApp/Tabs/ActivityTab.swift
git commit -m "feat(ios): Refund badge on transaction rows"
```

---

### Task 2: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Install + launch (ensure a refund exists)**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/FinchApp-*/Build/Products/Debug-iphonesimulator/FinchApp.app | head -1)
xcrun simctl install $SIM "$APP"; xcrun simctl terminate $SIM com.juchengquan.finch 2>/dev/null
xcrun simctl launch $SIM com.juchengquan.finch
```
(If no refund exists, add one: + → Refund → amount + category → save.)

- [ ] **Step 2: Verify**
  - A **refund** transaction's feed row shows a green **"Refund"** pill next to the merchant.
  - Non-refund rows (expense/income/transfer) show no badge.
  - Screenshot evidence to `/tmp/refundbadge.png`.

- [ ] **Step 3 (no commit):** report; if it fails, return to Task 1.

---

## Self-review notes
- Spec coverage: refund badge in TxRow gated on `kind == "refund"` (T1), cross-platform build (T1 S2), manual (T2). ✓
- No engine change; refund rows only. ✓
