import SwiftUI
import UIKit

#if os(iOS)

// MARK: - Right-slide drill (replaces fullScreenCover's bottom-slide)
//
// iOS 26 fullScreenCover slides up by default. Pushing via NavigationStack
// slides from right but re-samples the Liquid Glass on resume (the shadow).
// This component presents as a full-screen modal with a right-slide animation
// — the scroll view stays a root (no shadow on resume) while the UX matches
// a standard push. Use `.rightSlideDrill(item:)` in place of
// `.fullScreenCover(item:)` for drill-in pages.

/// A right-slide full-screen modal presentation animator.
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
            container.addSubview(to) // to is already on screen underneath
            container.bringSubviewToFront(from)
            UIView.animate(withDuration: transitionDuration(using: ctx), delay: 0,
                           options: .curveEaseInOut) {
                from.frame = bounds.offsetBy(dx: bounds.width, dy: 0)
            } completion: { _ in
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
        }
    }
}

/// A transitioning delegate that provides the right-slide animator.
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

// MARK: - Representable

/// A UIViewControllerRepresentable that presents a SwiftUI view as a
/// full-screen modal with a right-slide transition. Use via the
/// `.rightSlideDrill(item:)` modifier.
private struct RightSlideDrillRepresentable<Item: Identifiable, Content: View>: UIViewControllerRepresentable {
    @Binding var item: Item?
    @ViewBuilder let content: (Item) -> Content
    let onDismiss: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(item: $item, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.isHidden = true // transparent host
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.item = $item
        context.coordinator.onDismiss = onDismiss
        context.coordinator.presentIfNeeded(on: uiViewController, content: content)
    }

    final class Coordinator: NSObject {
        var item: Binding<Item?>?
        var onDismiss: (() -> Void)?
        private var lastId: Item.ID?
        private let delegate = RightSlideDelegate()

        init(item: Binding<Item?>, onDismiss: (() -> Void)?) {
            self.item = item
            self.onDismiss = onDismiss
        }

        func presentIfNeeded<Content: View>(on host: UIViewController,
                                             @ViewBuilder content: (Item) -> Content) {
            guard let item else { lastId = nil; return }
            let id = item.wrappedValue?.id
            if lastId == nil || lastId != id {
                lastId = id
                if let target = item.wrappedValue {
                    let hosting = UIHostingController(rootView: content(target))
                    hosting.modalPresentationStyle = UIModalPresentationStyle.overFullScreen
                    hosting.transitioningDelegate = delegate
                    host.present(hosting, animated: true)
                }
            }
            // If item becomes nil and a presented VC exists, dismiss it
            if item.wrappedValue == nil, let presented = host.presentedViewController {
                host.dismiss(animated: true) { [weak self] in
                    self?.lastId = nil
                    DispatchQueue.main.async { self?.onDismiss?() }
                }
            }
        }
    }
}

// MARK: - View modifier

extension View {
    /// Present `content` as a full-screen modal that slides from the right,
    /// replacing `.fullScreenCover(item:)` for drill-in pages. The presented
    /// scroll view is a root (not pushed), so iOS 26 Liquid Glass does NOT
    /// re-converge on resume — no shadow forms.
    ///
    /// - Parameters:
    ///   - item: Binding to an optional `Identifiable` item. When non-nil,
    ///     the cover is presented.
    ///   - onDismiss: Called after the cover is dismissed.
    ///   - content: A view builder for the cover's content, given the item.
    func rightSlideDrill<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        self.background(
            RightSlideDrillRepresentable(item: item, content: content, onDismiss: onDismiss)
                .allowsHitTesting(false)
        )
    }
}
#endif