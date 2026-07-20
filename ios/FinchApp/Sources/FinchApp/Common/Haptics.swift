import Foundation
#if os(iOS)
import UIKit
#endif

/// Central, opt-out haptic feedback for key confirmations. Imperative (fires
/// immediately) because these events save-then-dismiss — a SwiftUI
/// `.sensoryFeedback(trigger:)` change racing the dismissal is unreliable.
/// No-op on macOS. iOS also suppresses all haptics when System Haptics is off,
/// so this toggle is an additional app-level control.
enum Haptics {
    static let enabledKey = "finch.haptics.enabled"

    /// Default ON; an unset key reads as enabled.
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func success() { fire(.success) }
    static func warning() { fire(.warning) }

    #if os(iOS)
    private static func fire(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
    #else
    private enum Kind { case success, warning }
    private static func fire(_ type: Kind) {}   // no-op on macOS
    #endif
}
