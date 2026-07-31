import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The in-app Dynamic Type override (Settings › Appearance & Language › Text
/// size). One of the seven standard sizes is ALWAYS pinned — there is no
/// "follow the system" mode, so the OS accessibility sizes (AX1–AX5) are not
/// adopted inside finch; `.xxxLarge` is the ceiling.
enum TextSize {
    static let stepKey = "finch.textSize.step"
    static let defaultStep = 3   // .large — the iOS default

    static let steps: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge]

    /// Clamped step → size (out-of-range stored values fall back safely).
    static func size(forStep step: Int) -> DynamicTypeSize {
        steps[min(max(step, 0), steps.count - 1)]
    }

    // MARK: Migration off the removed "Use system size" toggle

    /// Defaults key of the toggle that used to sit above the slider. Nothing but
    /// the migration below reads it.
    static let legacySystemKey = "finch.textSize.system"

    /// Seeds the slider once for anyone upgrading from the toggle.
    ///
    /// While the toggle was on — its default — the slider had no effect, so those
    /// users have no step of their own on record. Dropping them on `defaultStep`
    /// would visibly SHRINK the app for anyone who had raised their system size,
    /// so seed from the size they were actually reading. Clearing the legacy key
    /// is what makes this run at most once.
    static func migrateLegacySystemPreference(systemStep: Int, defaults: UserDefaults = .standard) {
        let wasFollowingSystem = defaults.object(forKey: legacySystemKey) as? Bool
        // Already migrated: the legacy key is gone and a step is on record.
        if wasFollowingSystem == nil, defaults.object(forKey: stepKey) != nil { return }
        if wasFollowingSystem ?? true {
            defaults.set(min(max(systemStep, 0), steps.count - 1), forKey: stepKey)
        } else if defaults.object(forKey: stepKey) == nil {
            defaults.set(defaultStep, forKey: stepKey)
        }
        defaults.removeObject(forKey: legacySystemKey)
    }

    #if os(iOS)
    /// The device's system Dynamic Type setting, as a slider step.
    @MainActor static var currentSystemStep: Int {
        step(forCategory: UIApplication.shared.preferredContentSizeCategory)
    }

    /// Accessibility categories clamp to the largest step the slider can express —
    /// the slider does not reach them (see the type comment).
    static func step(forCategory category: UIContentSizeCategory) -> Int {
        switch category {
        case .extraSmall:            return 0
        case .small:                 return 1
        case .medium:                return 2
        case .large:                 return 3
        case .extraLarge:            return 4
        case .extraExtraLarge:       return 5
        case .extraExtraExtraLarge:  return 6
        default:                     return category.isAccessibilityCategory ? steps.count - 1 : defaultStep
        }
    }
    #else
    /// macOS has no Dynamic Type setting to inherit.
    @MainActor static var currentSystemStep: Int { defaultStep }
    #endif
}

/// Root modifier. Uses `transformEnvironment` (a SINGLE, always-same view type)
/// rather than an `if … else` @ViewBuilder branch: a branch is a
/// `_ConditionalContent` whose two arms have DIFFERENT identity, so changing the
/// setting tore down and rebuilt the whole subtree — including the shell's
/// NavigationStack, which reset its path and popped the user back to the Settings
/// root. transformEnvironment keeps identity stable.
struct TextSizeModifier: ViewModifier {
    let step: Int
    func body(content: Content) -> some View {
        content.transformEnvironment(\.dynamicTypeSize) { size in
            size = TextSize.size(forStep: step)
        }
    }
}
