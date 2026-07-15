# Sidebar-Collapse Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist the iPad/macOS sidebar collapse across launches and tab switches without recording iPadOS's rotation auto-collapse (#414's deferred trap).

**Architecture:** Task 1 builds the mechanism in one new file — a pure, unit-tested `SplitVisibilityMapping` (Bool ⇄ `NavigationSplitViewVisibility`, per column arity) + a `PersistedSplitVisibility` wrapper view that owns the visibility `@State`, seeds it from `@AppStorage("finch.sidebarCollapsed")`, persists only landscape changes, and re-asserts the pref on rotation back. Task 2 adopts it at the two `NavigationSplitView` call sites.

**Tech Stack:** Swift / SwiftUI; XcodeGen; XCTest (`FinchAppTests`). Spec: `plans/ios-macos/2026-07-15-sidebar-persistence-spec.md`.

## Global Constraints

- UserDefaults key exactly **`finch.sidebarCollapsed`** (default `false`); never the DB/packs.
- Mapping (verbatim): 3-column — collapsed → `.doubleColumn`, expanded → `.all`; 2-column — collapsed → `.detailOnly`, expanded → `.doubleColumn`. Any other visibility value (e.g. `.automatic`, or `.detailOnly` on a 3-column shell) maps to **nil** ("don't record").
- Persist **only when the container is landscape** (`width > height`); on portrait→landscape transition, **re-apply the stored pref**. Geometry is read via a `.background(GeometryReader…)` so the split view's own layout is untouched (spec risk note).
- Compact/iPhone untouched; no `#if os` unless something genuinely doesn't compile (the logic is cross-platform).
- Build BOTH `FinchApp` (iOS) and `FinchMac` (macOS). Commands from `ios/` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `xcodegen generate` in a fresh worktree (and after adding the new file).
- The rotation matrix is **manual** (sandbox can't rotate the simulator) — the PR ships the 4-step checklist from the spec; the scripted sim check covers only the seed path.

---

### Task 1: `SplitVisibilityMapping` + `PersistedSplitVisibility` (+ tests)

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Shell/PersistedSplitVisibility.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/SplitVisibilityMappingTests.swift` (create)

**Interfaces:**
- Produces (consumed by Task 2): `enum SplitColumns { case two, three }`; `enum SplitVisibilityMapping { static func visibility(collapsed: Bool, columns: SplitColumns) -> NavigationSplitViewVisibility; static func collapsed(from: NavigationSplitViewVisibility, columns: SplitColumns) -> Bool? }`; `struct PersistedSplitVisibility<Content: View>: View` with `init(columns: SplitColumns, @ViewBuilder content: @escaping (Binding<NavigationSplitViewVisibility>) -> Content)`.

- [ ] **Step 1: Write the failing tests**

Create `ios/FinchApp/Tests/FinchAppTests/SplitVisibilityMappingTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import FinchApp

final class SplitVisibilityMappingTests: XCTestCase {
    func test_visibilityForCollapsed() {
        XCTAssertEqual(SplitVisibilityMapping.visibility(collapsed: true, columns: .three), .doubleColumn)
        XCTAssertEqual(SplitVisibilityMapping.visibility(collapsed: false, columns: .three), .all)
        XCTAssertEqual(SplitVisibilityMapping.visibility(collapsed: true, columns: .two), .detailOnly)
        XCTAssertEqual(SplitVisibilityMapping.visibility(collapsed: false, columns: .two), .doubleColumn)
    }

    func test_collapsedFromVisibility_definiteValues() {
        XCTAssertEqual(SplitVisibilityMapping.collapsed(from: .doubleColumn, columns: .three), true)
        XCTAssertEqual(SplitVisibilityMapping.collapsed(from: .all, columns: .three), false)
        XCTAssertEqual(SplitVisibilityMapping.collapsed(from: .detailOnly, columns: .two), true)
        XCTAssertEqual(SplitVisibilityMapping.collapsed(from: .doubleColumn, columns: .two), false)
    }

    func test_collapsedFromVisibility_transientValuesAreNil() {
        XCTAssertNil(SplitVisibilityMapping.collapsed(from: .automatic, columns: .three))
        XCTAssertNil(SplitVisibilityMapping.collapsed(from: .automatic, columns: .two))
        // .detailOnly on a THREE-column shell hides the list too — not a plain
        // "sidebar collapsed"; don't record it.
        XCTAssertNil(SplitVisibilityMapping.collapsed(from: .detailOnly, columns: .three))
        // .all on a TWO-column shell isn't one of its two states either.
        XCTAssertNil(SplitVisibilityMapping.collapsed(from: .all, columns: .two))
    }

    func test_roundTrip() {
        for columns in [SplitColumns.two, .three] {
            for collapsed in [true, false] {
                let v = SplitVisibilityMapping.visibility(collapsed: collapsed, columns: columns)
                XCTAssertEqual(SplitVisibilityMapping.collapsed(from: v, columns: columns), collapsed)
            }
        }
    }
}
```

- [ ] **Step 2: Run them to confirm they fail**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  -only-testing:FinchAppTests/SplitVisibilityMappingTests 2>&1 | grep -iE "cannot find|error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: FAIL to compile — `SplitVisibilityMapping`/`SplitColumns` don't exist. (If the named iPhone device is missing, use a booted sim's `id=<udid>`.)

- [ ] **Step 3: Create `PersistedSplitVisibility.swift`**

```swift
import SwiftUI

/// How many columns the hosting NavigationSplitView has — the persisted Bool
/// maps to different visibility values per arity.
enum SplitColumns { case two, three }

/// Pure mapping between the persisted "sidebar collapsed" Bool and
/// `NavigationSplitViewVisibility` (unit-tested — the only real logic here).
enum SplitVisibilityMapping {
    static func visibility(collapsed: Bool, columns: SplitColumns) -> NavigationSplitViewVisibility {
        switch columns {
        case .three: return collapsed ? .doubleColumn : .all
        case .two:   return collapsed ? .detailOnly : .doubleColumn
        }
    }

    /// The Bool a visibility value represents, or nil for transient/other values
    /// (`.automatic`, or arity-mismatched states like `.detailOnly` on a
    /// three-column shell) — nil means "don't record".
    static func collapsed(from v: NavigationSplitViewVisibility, columns: SplitColumns) -> Bool? {
        if v == visibility(collapsed: true, columns: columns) { return true }
        if v == visibility(collapsed: false, columns: columns) { return false }
        return nil
    }
}

/// Owns the `columnVisibility` state for a NavigationSplitView: seeds it from the
/// persisted per-device pref, records only *trustworthy* changes, and re-asserts
/// the pref after rotation. The #414-deferred trap this solves: iPadOS
/// auto-collapses columns on rotation to portrait, so naïvely persisting every
/// change would record that auto-collapse as a user preference and pin the
/// sidebar closed. Rules:
///   • persist a change only while the container is landscape (width > height);
///   • on portrait → landscape, re-apply the stored pref (undo the auto-collapse);
///   • portrait/overlay toggles are deliberately not recorded (accepted
///     limitation — see the spec).
/// macOS windows are effectively always landscape, so Mac toggles persist
/// naturally through the same path.
struct PersistedSplitVisibility<Content: View>: View {
    let columns: SplitColumns
    @ViewBuilder var content: (Binding<NavigationSplitViewVisibility>) -> Content

    @AppStorage("finch.sidebarCollapsed") private var sidebarCollapsed = false
    @State private var visibility: NavigationSplitViewVisibility = .automatic
    @State private var isLandscape = true

    var body: some View {
        content($visibility)
            .onAppear {
                visibility = SplitVisibilityMapping.visibility(collapsed: sidebarCollapsed, columns: columns)
            }
            .onChange(of: visibility) { _, v in
                guard isLandscape,
                      let collapsed = SplitVisibilityMapping.collapsed(from: v, columns: columns),
                      collapsed != sidebarCollapsed else { return }
                sidebarCollapsed = collapsed
            }
            // Read the container size WITHOUT wrapping the split view (a wrapping
            // GeometryReader can disturb NavigationSplitView's layout).
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { isLandscape = geo.size.width > geo.size.height }
                        .onChange(of: geo.size) { _, size in
                            let landscape = size.width > size.height
                            guard landscape != isLandscape else { return }
                            isLandscape = landscape
                            if landscape {   // portrait → landscape: undo any auto-collapse
                                visibility = SplitVisibilityMapping.visibility(collapsed: sidebarCollapsed, columns: columns)
                            }
                        }
                }
            )
    }
}
```

- [ ] **Step 4: Run the tests to confirm they pass**

```bash
cd ios && xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  -only-testing:FinchAppTests/SplitVisibilityMappingTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **` (4/4).

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Shell/PersistedSplitVisibility.swift \
        ios/FinchApp/Tests/FinchAppTests/SplitVisibilityMappingTests.swift
git commit -m "feat(ios): PersistedSplitVisibility — landscape-gated sidebar-collapse persistence"
```

---

### Task 2: Adopt at both split-view call sites

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Shell/MasterDetailShell.swift` (`ThreeColumnShell.body`, ~lines 55-68)
- Modify: `ios/FinchApp/Sources/FinchApp/Shell/AdaptiveShell.swift` (`SplitViewShell`'s `default:` branch, ~line 243)

**Interfaces:**
- Consumes (Task 1): `PersistedSplitVisibility(columns:content:)`, `SplitColumns`.

- [ ] **Step 1: Adopt in `ThreeColumnShell`**

Change the body from:
```swift
    var body: some View {
        NavigationSplitView {
            SectionSidebar()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } content: {
            // Keep the list a readable, list-like width — without this,
            // `.balanced` gives the middle column ~half the content area on iPad.
            list()
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
        } detail: {
            detail()
        }
        .navigationSplitViewStyle(.balanced)
    }
```
to:
```swift
    var body: some View {
        PersistedSplitVisibility(columns: .three) { $visibility in
            NavigationSplitView(columnVisibility: $visibility) {
                SectionSidebar()
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
            } content: {
                // Keep the list a readable, list-like width — without this,
                // `.balanced` gives the middle column ~half the content area on iPad.
                list()
                    .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
            } detail: {
                detail()
            }
            .navigationSplitViewStyle(.balanced)
        }
    }
```

- [ ] **Step 2: Adopt in `SplitViewShell`'s 2-column branch**

Change (AdaptiveShell.swift `default:` branch):
```swift
            default:
                NavigationSplitView {
                    SectionSidebar()
                } detail: {
                    tabContent(router.selectedTab)
                }
                .navigationSplitViewStyle(.balanced)
```
to:
```swift
            default:
                PersistedSplitVisibility(columns: .two) { $visibility in
                    NavigationSplitView(columnVisibility: $visibility) {
                        SectionSidebar()
                    } detail: {
                        tabContent(router.selectedTab)
                    }
                    .navigationSplitViewStyle(.balanced)
                }
```

- [ ] **Step 3: Build iOS + macOS + full FinchAppTests**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios && xcodegen generate
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|reasonable time|BUILD SUCCEEDED|BUILD FAILED"
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" -only-testing:FinchAppTests 2>&1 | grep -iE "Executed .* tests|TEST SUCCEEDED|TEST FAILED"
```
Expected: both builds SUCCEED; suite green (incl. the 4 new tests).

- [ ] **Step 4: iPad simulator — scripted seed check**

```bash
DT="com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"
RT=$(xcrun simctl list runtimes | grep -oE 'com\.apple[^ ]*iOS[^ ]*' | tail -1)
PAD=$(xcrun simctl create "finch-ipad" "$DT" "$RT"); xcrun simctl boot "$PAD"; open -a Simulator
xcrun simctl bootstatus "$PAD" -b
# build for/install on the iPad sim, launch, screenshot the default (expanded) state
xcodebuild build -project FinchApp.xcodeproj -scheme FinchApp -destination "id=$PAD" 2>&1 | grep -iE "BUILD (SUCCEEDED|FAILED)"
APP=$(xcodebuild -project FinchApp.xcodeproj -scheme FinchApp -destination "id=$PAD" -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$PAD" "$APP"
xcrun simctl launch "$PAD" com.juchengquan.finch; sleep 2
xcrun simctl io "$PAD" screenshot /tmp/ipad-default.png
# seed collapsed → relaunch → sidebar starts hidden (verifies the seed path without rotation)
xcrun simctl terminate "$PAD" com.juchengquan.finch
xcrun simctl spawn "$PAD" defaults write com.juchengquan.finch finch.sidebarCollapsed -bool YES
xcrun simctl launch "$PAD" com.juchengquan.finch; sleep 2
xcrun simctl io "$PAD" screenshot /tmp/ipad-collapsed.png
# restore
xcrun simctl spawn "$PAD" defaults write com.juchengquan.finch finch.sidebarCollapsed -bool NO
```
Compare the two screenshots: the second must show the sidebar hidden. (Rotation cannot be scripted — the manual matrix below ships with the PR.)

- [ ] **Step 5: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Shell/MasterDetailShell.swift \
        ios/FinchApp/Sources/FinchApp/Shell/AdaptiveShell.swift
git commit -m "feat(ios): persist sidebar collapse across launches + tab switches (iPad/macOS)"
```

**Manual rotation matrix (goes in the PR body, for the human):**
1. Landscape: collapse the sidebar → relaunch → still collapsed.
2. Landscape: expand → rotate portrait (auto-collapse) → rotate back → sidebar re-opens.
3. Portrait: toggle the overlay sidebar → rotate to landscape → the stored pref wins.
4. macOS: collapse via toolbar → relaunch → still collapsed.

---

## Self-Review

**1. Spec coverage:** key/default + Bool mapping (incl. nil-for-transient) → Task 1 (mapping + tests); landscape gate + rotation re-assert + background GeometryReader → Task 1 Step 3; both call sites + tab-switch fix (seeding on creation) → Task 2 Steps 1-2; builds + iPad seed check + manual matrix → Task 2 Steps 3-4 + PR body. Accepted limitations documented in the helper's doc comment. ✅
**2. Placeholder scan:** none — complete code and commands throughout.
**3. Type consistency:** `SplitColumns`/`SplitVisibilityMapping.visibility(collapsed:columns:)`/`collapsed(from:columns:)`/`PersistedSplitVisibility(columns:content:)` identical across Task 1 definition, Task 1 tests, and Task 2 adoption; the `$visibility` binding closure matches `(Binding<NavigationSplitViewVisibility>) -> Content`.
