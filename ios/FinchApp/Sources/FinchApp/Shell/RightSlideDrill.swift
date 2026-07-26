import SwiftUI
import UIKit

#if os(iOS)

// MARK: - Right-slide drill presenter
//
// Presents a SwiftUI view as a full-screen modal with a right-slide
// animation (like a push). The presented scroll view is a root (not
// a pushed child), so iOS 26 Liquid Glass does NOT re-converge on
// resume — no shadow forms.
//
// Use `_rd_presentModal(_:)` from an `.onChange` handler in each tab.

private final class SlideRightAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let presenting: Bool
    init(presenting: Bool) { self.presenting = presenting }

    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval { 0.35 }

    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        let container = ctx.containerView
        guard let to = ctx.view(forKey: .to), let from = ctx.view(forKey: .from) else {
            ctx.completeTransition(false); return
        }
        let bounds = container.bounds

        if presenting {
            to.frame = bounds.offsetBy(dx: bounds.width, dy: 0)
            container.addSubview(to)
            UIView.animate(withDuration: transitionDuration(using: ctx), delay: 0,
                           options: .curveEaseInOut) {
                to.frame = bounds
                from.transform = CGAffineTransform(translationX: -bounds.width * 0.08, y: 0)
            } completion: { _ in
                from.transform = .identity
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
        } else {
            from.frame = bounds
            UIView.animate(withDuration: transitionDuration(using: ctx), delay: 0,
                           options: .curveEaseInOut) {
                from.frame = bounds.offsetBy(dx: bounds.width, dy: 0)
            } completion: { _ in
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
        }
    }
}

private final class RightSlideDelegate: NSObject, UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideRightAnimator(presenting: true)
    }
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideRightAnimator(presenting: false)
    }
}

private var _rd_delegate: RightSlideDelegate?
private var _rd_hosting: UIViewController?

/// Present a SwiftUI view as a full-screen right-slide modal from the
/// key window's root view controller. Call from an `.onChange` handler.
func _rd_presentModal<Content: View>(_ view: Content) {
    // Dismiss any previous cover first
    if let old = _rd_hosting {
        old.dismiss(animated: false)
        _rd_hosting = nil
        _rd_delegate = nil
    }
    let delegate = RightSlideDelegate()
    _rd_delegate = delegate
    let hosting = UIHostingController(rootView: view
        .environmentObject(FinchStore.shared)
        .environmentObject(DeepLinkRouter.shared)
        .environmentObject(BiometricGate.shared))
    hosting.modalPresentationStyle = .overFullScreen
    hosting.transitioningDelegate = delegate
    _rd_hosting = hosting
    DispatchQueue.main.async {
        // Try the key window first, fall through to the scene's first window.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first else { return }
        guard let root = scene.keyWindow?.rootViewController ?? scene.windows.first?.rootViewController
        else { return }
        // Walk up to the topmost presented VC so we never present on a child
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(hosting, animated: true)
    }
}

/// Dismiss the currently presented right-slide cover, if any.
func _rd_dismissModal() {
    guard let hosting = _rd_hosting else { return }
    hosting.dismiss(animated: true) {
        _rd_delegate = nil
        _rd_hosting = nil
    }
}

#endif