#if os(iOS)
import UIKit

/// Every swipe action in the app is built here.
///
/// The point is the haptic **and its order**. The handler runs first and the tap
/// follows, because a buzz placed in front of the work puts the Taptic Engine's
/// warm-up between the gesture and what it does — the bug fixed for the row's
/// status glyph and then for every save, toast and alert. Defining it once means
/// that ordering cannot drift across the ~30 swipe actions the app has, and a new
/// action written through this helper inherits it.
///
/// The shape is deliberately narrow: every existing action is `.normal` with an SF
/// Symbol and a tint, and none of them used the recogniser or view arguments, so
/// the handler takes only the completion. Widen it when something actually needs
/// more rather than in anticipation.
enum SwipeAction {

    /// - Parameter handler: receives the completion to call with `true` (the swipe
    ///   closes) or `false` (the row stays open — used where an alert answers first).
    static func make(_ title: String,
                     systemImage: String,
                     tint: UIColor,
                     handler: @escaping (@escaping (Bool) -> Void) -> Void) -> UIContextualAction {
        let action = UIContextualAction(style: .normal, title: title) { _, _, done in
            handler(done)
            // After, never before — see the note above.
            Haptics.tap()
        }
        action.image = UIImage(systemName: systemImage)
        action.backgroundColor = tint
        return action
    }
}
#endif
