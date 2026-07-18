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
