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

    /// A control responded — not an outcome. Used by the transaction row's status
    /// glyph, where the row typically moves to another section on tap and so
    /// leaves the screen: the haptic is the only confirmation that the press
    /// landed on the control rather than on the row behind it.
    ///
    /// An IMPACT, not `.success`: the notification haptics above announce that
    /// something finished, and firing one on every toggle — including un-confirming
    /// — would both overstate the event and read as "saved" in the wrong direction.
    static func tap() { impact() }

    #if os(iOS)
    private static func fire(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
    private static func impact() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    #else
    private enum Kind { case success, warning }
    private static func fire(_ type: Kind) {}   // no-op on macOS
    private static func impact() {}             // no-op on macOS
    #endif
}
