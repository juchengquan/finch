# Ring + StackedBar primitives — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Checkbox steps.

**Goal:** Add `Ring` + `StackedBar` SwiftUI primitives (with `#Preview`s) to `Common/ChartViews/`.

**Architecture:** Two new focused SwiftUI views, faithful ports of the web primitives. No screen wiring, no engine change.

**Tech Stack:** Swift / SwiftUI, XcodeGen.

Spec: `plans/ios-macos/2026-06-26-ring-stackedbar-primitives-design.md` (contains the full verbatim source).

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `cd ios && xcodegen generate` before builds (new files added).
- Builds: FinchApp (iOS) **and** FinchMac (macOS). No `Co-Authored-By`. No engine change. PR → `feat/frontend`.

---

### Task 1: Add the two primitives

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Common/ChartViews/Ring.swift`
- Create: `ios/FinchApp/Sources/FinchApp/Common/ChartViews/StackedBar.swift`

- [ ] **Step 1:** Create `Ring.swift` — copy the `Ring<Label>` struct + `EmptyView` convenience init + `#Preview("Ring")` **verbatim from the design spec's §1**.

- [ ] **Step 2:** Create `StackedBar.swift` — copy the `StackedBar` struct (with nested `Slice`) + `#Preview("StackedBar")` **verbatim from the design spec's §2**.

- [ ] **Step 3: Build iOS + macOS**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
echo "=== iOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
echo "=== macOS ==="; xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -2
```
Expected: both `** BUILD SUCCEEDED **`. (If `Circle().inset(by:)` + `.trim` chaining complains, the `inset(by:)` returns an `InsettableShape` then `.trim` returns a `Shape` — keep that order; do not reorder `.stroke` before `.trim`.)

- [ ] **Step 4: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Common/ChartViews/Ring.swift \
        ios/FinchApp/Sources/FinchApp/Common/ChartViews/StackedBar.swift
git commit -m "feat(ios): Ring + StackedBar chart primitives (port from web)"
```

---

## Self-review notes
- Spec coverage: Ring (T1 S1), StackedBar (T1 S2), cross-platform build (T1 S3). ✓
- Type consistency: `Ring<Label: View>(value:max:size:stroke:color:track:label:)` + `EmptyView` init; `StackedBar(slices:[Slice], height:cornerRadius:)` consistent with spec. ✓
- No engine change; no screen wiring (build is the verification; `#Preview`s document). ✓
