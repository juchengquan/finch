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

    @MainActor static func success() { fire(.success) }
    @MainActor static func warning() { fire(.warning) }

    /// A control responded — not an outcome. Used by the transaction row's status
    /// glyph, where the row typically moves to another section on tap and so
    /// leaves the screen: the haptic is the only confirmation that the press
    /// landed on the control rather than on the row behind it.
    ///
    /// An IMPACT, not `.success`: the notification haptics above announce that
    /// something finished, and firing one on every toggle — including un-confirming
    /// — would both overstate the event and read as "saved" in the wrong direction.
    @MainActor static func tap() { impact() }

    #if os(iOS)
    /// Retained and prepared, for the same reason as ``impactGenerator``: an
    /// unprepared generator makes the Taptic Engine warm up before it can play.
    @MainActor private static let notificationGenerator = UINotificationFeedbackGenerator()

    @MainActor private static func fire(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard enabled else { return }
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
    }
    /// Retained and PREPARED, not built per call.
    ///
    /// A generator constructed at the call site is unprepared, and an unprepared
    /// Taptic Engine has to warm up before it can play — which is the whole reason
    /// `prepare()` exists. The row's status glyph fired one *before* running the
    /// toggle, so the warm-up sat between the tap and the state change on device.
    /// The simulator has no Taptic Engine, so none of this is visible there.
    ///
    /// Keeping one instance lets the engine stay warm across a burst of taps; the
    /// system spins it back down on its own, and `prepare()` before each play
    /// re-warms it when it has.
    @MainActor private static let impactGenerator = UIImpactFeedbackGenerator(style: .light)

    /// `@MainActor` so the compiler proves every caller is on it — the generator is
    /// UIKit state. `MainActor.assumeIsolated` would defer that to a runtime crash.
    @MainActor private static func impact() {
        guard enabled else { return }
        impactGenerator.impactOccurred()
        // Warm for the next one: taps on this control usually come in runs.
        impactGenerator.prepare()
    }
    #else
    private enum Kind { case success, warning }
    private static func fire(_ type: Kind) {}   // no-op on macOS
    private static func impact() {}             // no-op on macOS
    #endif
}
