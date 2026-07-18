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

/// Root modifier. Uses `transformEnvironment` (a SINGLE, always-same view type)
/// rather than an `if useSystem { … } else { … }` branch: a @ViewBuilder branch
/// is a `_ConditionalContent` whose two arms have DIFFERENT identity, so toggling
/// the switch tore down and rebuilt the whole subtree — including the shell's
/// NavigationStack, which reset its path and popped the user back to the
/// Settings root. transformEnvironment keeps identity stable. In system mode the
/// closure leaves the inherited OS value untouched (incl. accessibility sizes).
struct TextSizeModifier: ViewModifier {
    let useSystem: Bool
    let step: Int
    func body(content: Content) -> some View {
        content.transformEnvironment(\.dynamicTypeSize) { size in
            if !useSystem { size = TextSize.size(forStep: step) }
        }
    }
}
