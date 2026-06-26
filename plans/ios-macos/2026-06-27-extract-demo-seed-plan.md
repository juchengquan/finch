# Extract demo seed — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven). Checkbox steps.

**Goal:** Move the simulator demo seed out of `FinchStore.swift` into its own `SimulatorDemoSeed.swift`. Pure refactor — no behavior change.

**Architecture:** `seedSimulatorDemo` is self-contained (0 `self`/store refs), so it moves verbatim into `enum SimulatorDemoSeed { static func seed(_:) }`; the gated call site calls the new type.

Spec: `plans/ios-macos/2026-06-27-extract-demo-seed-design.md`.

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds (a new source file is added).
- Builds: FinchApp (iOS) **and** FinchMac (macOS). No `Co-Authored-By`. No engine change. **No data/behavior change** — the seed body moves verbatim. PR → `feat/frontend`.
- `FinchStore.swift` is the other stream's recently-active file — **re-check `gh pr list --base feat/frontend --state open` and that `FinchStore.swift` is unchanged on origin before pushing**.

---

### Task 1: Move the seed into a new file

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/SimulatorDemoSeed.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/FinchStore.swift`

- [ ] **Step 1: Read the method to move.** Open `FinchStore.swift` and read the
  `private func seedSimulatorDemo(_ q: DatabaseQueue) throws { … }` method — it currently
  spans **lines 142–345** (signature at 142, closing `}` at 345). This whole method body
  is what moves.

- [ ] **Step 2: Create `SimulatorDemoSeed.swift`** with this exact scaffold, pasting the
  **entire body** of `seedSimulatorDemo` (everything between the method's opening `{` on
  line 142 and its closing `}` on line 345 — i.e. FinchStore.swift lines 143–344) verbatim
  in place of the comment:

```swift
import Foundation
import FinchCore

/// Simulator-only demo data — a Personal/USD ledger with accounts (+groups),
/// categories, budgets (+groups), and ~2 months of transactions. NOT shipped to real
/// users: the call site in `FinchStore.bootstrap()` is gated by
/// `#if targetEnvironment(simulator)`.
///
/// To remove the demo entirely: delete this file and the `SimulatorDemoSeed.seed(...)`
/// line in FinchStore.swift (real devices already fall back to `seedMinimalStarter`).
enum SimulatorDemoSeed {
    static func seed(_ q: DatabaseQueue) throws {
        // <<< paste FinchStore.swift lines 143–344 here, verbatim, unchanged >>>
    }
}
```
Do not alter the body — same locals (`apply`, `monthStart`, `cal`, `df`, `now`), same
data, same order.

- [ ] **Step 3: Delete the method from `FinchStore.swift`.** Remove the entire
  `private func seedSimulatorDemo(_ q: DatabaseQueue) throws { … }` method (the old lines
  142–345), leaving `seedMinimalStarter` and everything else intact.

- [ ] **Step 4: Update the call site** in `bootstrap()` (was line 104):

```swift
            do { try seedSimulatorDemo(live) } catch { try? seedMinimalStarter(live) }
```
→

```swift
            do { try SimulatorDemoSeed.seed(live) } catch { try? seedMinimalStarter(live) }
```
(Leave the surrounding `#if targetEnvironment(simulator)` / `#else … seedMinimalStarter`
branch unchanged.)

- [ ] **Step 5: Regenerate + build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`. (If "cannot find 'seedSimulatorDemo'": the call
site update in Step 4 was missed.)

- [ ] **Step 6: Sanity-check the move is behavior-neutral**

```bash
cd /tmp/finch-eds
# the seed body should now live only in the new file, not FinchStore
grep -c "createBudgetGroup\|seedSimulatorDemo" ios/FinchApp/Sources/FinchApp/FinchStore.swift   # expect 0
grep -c "static func seed" ios/FinchApp/Sources/FinchApp/SimulatorDemoSeed.swift                 # expect 1
```

- [ ] **Step 7: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/SimulatorDemoSeed.swift ios/FinchApp/Sources/FinchApp/FinchStore.swift ios/FinchApp.xcodeproj 2>/dev/null; git add -A
git commit -m "refactor(ios): extract simulator demo seed into SimulatorDemoSeed.swift"
```

---

### Task 2: Manual simulator verification

**Files:** none.

- [ ] **Step 1: Fresh re-seed + install** (demo seeds only on an empty DB):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=9500E54A-BC34-42E1-BC02-BC5E906B6901
cd ios && xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/eds-dd >/dev/null 2>&1
xcrun simctl list devices booted | grep -q "$SIM" || { xcrun simctl boot "$SIM"; open -a Simulator; sleep 5; }
xcrun simctl terminate "$SIM" com.juchengquan.finch 2>/dev/null
xcrun simctl uninstall "$SIM" com.juchengquan.finch 2>/dev/null
xcrun simctl install "$SIM" /tmp/eds-dd/Build/Products/Debug-iphonesimulator/FinchApp.app
xcrun simctl launch "$SIM" com.juchengquan.finch -initialTab budgets
```

- [ ] **Step 2: Verify** the demo loaded identically: Budgets shows the **Essentials** +
  **Lifestyle** groups (and ungrouped Health); Ledger has transactions. Screenshot
  `/tmp/eds-seed.png`. Clean up `/tmp/eds-dd` after.

- [ ] **Step 3 (no commit):** report; if a check fails, return to Task 1.

---

## Self-review notes
- Spec coverage: new file + verbatim body (T1 S2), delete method (S3), call site (S4), build (S5), neutrality check (S6), manual re-seed (T2). ✓
- Type consistency: `SimulatorDemoSeed.seed(_ q: DatabaseQueue) throws` matches the old signature shape; call site updated. ✓
- Pure move — no data/behavior/engine change; `seedMinimalStarter` untouched. ✓
