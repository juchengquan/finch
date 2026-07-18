# Text size — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline; single task). Checkbox steps.

**Goal:** In-app font-size override: system-follow by default, 7-step slider override applied app-wide via one root `.dynamicTypeSize` modifier.

## Global Constraints
- Worktree `/tmp/finch-ts`, branch `feat/ios-text-size`; both FinchApp + FinchMac builds; no Co-Authored-By; PR → `feat/frontend`.

### Task 1 (single)

- [ ] Create `ios/FinchApp/Sources/FinchApp/Common/TextSize.swift`:

```swift
import SwiftUI

/// The in-app Dynamic Type override (Settings › Appearance & Language › Text
/// size). System mode (default) leaves the environment untouched — including
/// accessibility sizes; a custom step pins one of the seven standard sizes.
enum TextSize {
    static let systemKey = "finch.textSize.system"
    static let stepKey = "finch.textSize.step"
    static let defaultStep = 3   // .large — the iOS default

    static let steps: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge]

    /// Clamped step → size (out-of-range stored values fall back safely).
    static func size(forStep step: Int) -> DynamicTypeSize {
        steps[min(max(step, 0), steps.count - 1)]
    }
}

/// Root modifier: identity in system mode so the OS value (incl. accessibility
/// sizes) flows through untouched.
struct TextSizeModifier: ViewModifier {
    let useSystem: Bool
    let step: Int
    func body(content: Content) -> some View {
        if useSystem { content } else { content.dynamicTypeSize(TextSize.size(forStep: step)) }
    }
}
```

- [ ] `FinchApp.swift`: add below the `finch.appearance` @AppStorage (line ~16):

```swift
    @AppStorage(TextSize.systemKey) private var useSystemTextSize = true
    @AppStorage(TextSize.stepKey) private var textSizeStep = TextSize.defaultStep
```

and directly after `.preferredColorScheme(...)` (line ~53):

```swift
            .modifier(TextSizeModifier(useSystem: useSystemTextSize, step: textSizeStep))
```

- [ ] `Tabs/SettingsAppearanceView.swift`: add the @AppStorage pair (same two lines as above) to `SettingsAppearanceView`, and after the `Section("Theme") {...}` insert:

```swift
            Section {
                Toggle("Use system size", isOn: $useSystemTextSize)
                if !useSystemTextSize {
                    HStack(spacing: 12) {
                        Text("A").font(.footnote).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { Double(textSizeStep) },
                                              set: { textSizeStep = Int($0.rounded()) }),
                               in: 0...Double(TextSize.steps.count - 1), step: 1)
                            .accessibilityLabel("Text size")
                        Text("A").font(.title3).foregroundStyle(.secondary)
                    }
                    Text("Sample — $1,234.56")
                        .dynamicTypeSize(TextSize.size(forStep: textSizeStep))
                }
            } header: {
                Text("Text size")
            } footer: {
                Text(useSystemTextSize ? "Follows the system Text Size setting." : "Overrides the system text size inside finch.")
            }
```

- [ ] Create `ios/FinchApp/Tests/FinchAppTests/TextSizeTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import FinchApp

final class TextSizeTests: XCTestCase {
    func test_stepMapping_andClamping() {
        XCTAssertEqual(TextSize.steps.count, 7)
        XCTAssertEqual(TextSize.size(forStep: 0), .xSmall)
        XCTAssertEqual(TextSize.size(forStep: 3), .large)
        XCTAssertEqual(TextSize.size(forStep: 6), .xxxLarge)
        XCTAssertEqual(TextSize.size(forStep: -5), .xSmall)
        XCTAssertEqual(TextSize.size(forStep: 99), .xxxLarge)
        XCTAssertEqual(TextSize.defaultStep, 3)
    }
}
```

- [ ] `xcodegen generate`; run TextSizeTests + full FinchAppTests; build FinchApp + FinchMac — all clean.
- [ ] Commit: `feat(ios): Text size setting — 7-step in-app Dynamic Type override (default: system)`
- [ ] Sim: toggle OFF → slider + preview appear, whole app scales live; screenshot.
