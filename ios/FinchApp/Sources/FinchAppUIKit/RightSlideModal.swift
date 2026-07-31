#if os(iOS)
import UIKit

/// Present a view controller with a slide-from-right transition — the native
/// counterpart of `RightSlideDrill`.
///
/// **Why not a plain modal.** The default `.fullScreenCover` slides UP, which was
/// tried on the SwiftUI side and rejected as jarring for something that reads as a
/// drill-in. `RightSlideDrill` exists to give a push's *feel* to a presentation that
/// is really a root, and this is the same trick for a `UIViewController`.
///
/// **Why a presentation rather than a push.** The ledger opens from the top-left
/// corner control, which is present on every tab — including the ones still hosting a
/// SwiftUI root, which have no `UINavigationController` to push onto. When every tab
/// is native this can become a plain push and this file goes away with
/// `RightSlideDrill`.
enum RightSlideModal {

    static func present(_ vc: UIViewController, from presenter: UIViewController) {
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen
        nav.transitioningDelegate = SlideTransition.shared
        presenter.present(nav, animated: true)
    }

    /// Retained for the lifetime of the process: `transitioningDelegate` is a weak
    /// reference, so a per-call instance would be gone before the animation runs.
    final class SlideTransition: NSObject, UIViewControllerTransitioningDelegate {
        static let shared = SlideTransition()

        func animationController(forPresented presented: UIViewController,
                                 presenting: UIViewController,
                                 source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
            Animator(presenting: true)
        }
        func animationController(forDismissed dismissed: UIViewController)
            -> UIViewControllerAnimatedTransitioning? {
            Animator(presenting: false)
        }
    }

    private final class Animator: NSObject, UIViewControllerAnimatedTransitioning {
        private let presenting: Bool
        init(presenting: Bool) { self.presenting = presenting }

        func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval { 0.35 }

        func animateTransition(using ctx: UIViewControllerContextTransitioning) {
            let container = ctx.containerView
            // `.from` is nil under some presentation styles — the trap that made the
            // SwiftUI animator abort every present until it was fixed. Drive the
            // animation off the view that definitely exists in each direction.
            if presenting {
                guard let to = ctx.view(forKey: .to) else { ctx.completeTransition(false); return }
                to.frame = container.bounds.offsetBy(dx: container.bounds.width, dy: 0)
                container.addSubview(to)
                UIView.animate(withDuration: transitionDuration(using: ctx),
                               delay: 0, options: .curveEaseOut) {
                    to.frame = container.bounds
                } completion: { _ in ctx.completeTransition(!ctx.transitionWasCancelled) }
            } else {
                guard let from = ctx.view(forKey: .from) else { ctx.completeTransition(false); return }
                // Put the presenter BACK before sliding away from it. Under
                // `.fullScreen` UIKit removes the presenting view once the
                // presentation completes and only restores it at
                // `completeTransition` — so without this the container is empty
                // behind the outgoing view and the window's black backdrop is what
                // gets revealed. Measured before this line: ~250ms of black
                // (left-quarter luma 16) before the previous page snapped in at 223.
                if let to = ctx.view(forKey: .to) {
                    to.frame = container.bounds
                    container.insertSubview(to, belowSubview: from)
                }
                UIView.animate(withDuration: transitionDuration(using: ctx),
                               delay: 0, options: .curveEaseIn) {
                    from.frame = container.bounds.offsetBy(dx: container.bounds.width, dy: 0)
                } completion: { _ in
                    from.removeFromSuperview()
                    ctx.completeTransition(!ctx.transitionWasCancelled)
                }
            }
        }
    }
}
#endif
