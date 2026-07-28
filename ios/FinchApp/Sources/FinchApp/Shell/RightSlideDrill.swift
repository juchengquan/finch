import SwiftUI

#if os(iOS)
import UIKit

// MARK: - Right-slide drill presenter
//
// Presents a SwiftUI view as a full-screen modal with a right-slide
// animation (like a push). The presented scroll view is a root (not
// a pushed child), so iOS 26 Liquid Glass does NOT re-converge on
// resume — no shadow forms.
//
// STATE-DRIVEN API — use the `.rightSlideDrill(item:)` / `(isPresented:)`
// view modifiers, never the `_rd_*` free functions directly. Driving
// presentation off state (not off a `Button` action) is what lets
// `DeepLinkRouter` / App Intents / notifications / Spotlight open a drill,
// and keeps one uniform mechanism across every tab. The `_rd_*` functions
// below are the modifier's private plumbing.

private final class SlideRightAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let presenting: Bool
    init(presenting: Bool) { self.presenting = presenting }

    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval { 0.35 }

    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        let container = ctx.containerView
        let bounds = container.bounds
        let duration = transitionDuration(using: ctx)

        if presenting {
            // Under `.overFullScreen`, `view(forKey: .from)` (the presenter) is nil —
            // only the incoming cover (`.to`) is required. Requiring `from` here
            // aborted the whole presentation, so no cover ever showed.
            guard let to = ctx.view(forKey: .to) else { ctx.completeTransition(false); return }
            let from = ctx.view(forKey: .from)
            to.frame = bounds.offsetBy(dx: bounds.width, dy: 0)
            container.addSubview(to)
            UIView.animate(withDuration: duration, delay: 0, options: .curveEaseInOut) {
                to.frame = bounds
                from?.transform = CGAffineTransform(translationX: -bounds.width * 0.08, y: 0)
            } completion: { _ in
                from?.transform = .identity
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
        } else {
            // Dismissing: the outgoing cover is `.from`; slide it back off to the right.
            guard let from = ctx.view(forKey: .from) else { ctx.completeTransition(true); return }
            from.frame = bounds
            UIView.animate(withDuration: duration, delay: 0, options: .curveEaseInOut) {
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
    hosting.modalPresentationStyle = UIModalPresentationStyle.overFullScreen
    hosting.transitioningDelegate = delegate
    _rd_hosting = hosting
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard let scene = scenes.first,
          let root = scene.keyWindow?.rootViewController ?? scene.windows.first?.rootViewController
    else { return }
    var top = root
    while let presented = top.presentedViewController { top = presented }
    top.present(hosting, animated: true)
}

/// Dismiss the currently presented right-slide cover, if any.
func _rd_dismissModal() {
    guard let hosting = _rd_hosting else { return }
    hosting.dismiss(animated: true) {
        _rd_delegate = nil
        _rd_hosting = nil
    }
}

// MARK: - State-driven view modifiers (the public API)

private struct RightSlideDrillItemModifier<Item: Identifiable, DrillContent: View>: ViewModifier {
    @Binding var item: Item?
    let drillContent: (Item) -> DrillContent
    func body(content: Content) -> some View {
        // Presence-and-identity keyed: nil→x presents, x→y re-presents, x→nil dismisses.
        // Present/dismiss on the NEXT runloop: onChange fires inside SwiftUI's update
        // pass, and a synchronous UIKit present there is silently dropped. (The
        // original imperative call sites presented from Button actions, outside the
        // update pass, so they didn't need this.)
        content.onChange(of: item?.id) { _, _ in
            if let item {
                let cover = drillContent(item)
                DispatchQueue.main.async { _rd_presentModal(cover) }
            } else {
                DispatchQueue.main.async { _rd_dismissModal() }
            }
        }
    }
}

private struct RightSlideDrillBoolModifier<DrillContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let drillContent: () -> DrillContent
    func body(content: Content) -> some View {
        content.onChange(of: isPresented) { _, show in
            if show { _rd_presentModal(drillContent()) } else { _rd_dismissModal() }
        }
    }
}

extension View {
    /// Present `content(item)` as a right-slide top-level cover while `item` is
    /// non-nil (dismiss when it returns to nil). State-driven, so router / deep-link
    /// entry works — not just row taps. The `content` closure should build its own
    /// `NavigationStack` + `.rsdBackToolbar(_:dismiss:)` that sets `item` back to nil.
    func rightSlideDrill<Item: Identifiable, C: View>(
        item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> C
    ) -> some View {
        modifier(RightSlideDrillItemModifier(item: item, drillContent: content))
    }

    /// Boolean-driven variant for a single fixed destination.
    func rightSlideDrill<C: View>(
        isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C
    ) -> some View {
        modifier(RightSlideDrillBoolModifier(isPresented: isPresented, drillContent: content))
    }

    /// A leading "‹ <title>" back button for a right-slide cover; `dismiss` should
    /// set the driving state back to nil/false so the modifier tears the cover down.
    func rsdBackToolbar(_ title: LocalizedStringKey, dismiss: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: dismiss) {
                    HStack(spacing: 4) { Image(systemName: "chevron.left"); Text(title) }
                }
            }
        }
    }
}

#endif