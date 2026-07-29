import SwiftUI

#if os(iOS)
import UIKit

// MARK: - Right-slide drill presenter
//
// Presents a SwiftUI view as a full-screen modal with a right-slide animation
// (like a push). The presented scroll view is a ROOT (not a child pushed on the
// main tab-bar NavigationStack), so iOS 26 Liquid Glass does NOT re-converge on
// resume — no shadow forms. Normal NavigationStack pushes *inside* the cover are
// fine (they don't shadow and keep native swipe-back) — only main-tab-stack
// pushes shadow.
//
// ⚠️ WORKAROUND, NOT A DESIGN CHOICE — REMOVE if Apple fixes the iOS 26
// scroll-edge re-converge on pushed views. There is no native "slide-from-right
// modal": the nav PUSH has the exact feel we want (slide-in + swipe-back) but is
// the thing that shadows; the modal (`.fullScreenCover`/`.overFullScreen`) is a
// shadow-free root but slides UP with no swipe-back. This file re-creates the
// push's look+feel on top of a modal — a custom transition + interactive gesture
// — purely to dodge the shadow bug. If the bug goes away, delete this and replace
// each `.rightSlideDrill(...)` with a plain `NavigationStack` push.
//
// STATE-DRIVEN API — use the `.rightSlideDrill(item:)` / `(isPresented:)` view
// modifiers, never the `_rd_*` free functions directly. Driving presentation off
// state (not off a `Button` action) is what lets `DeepLinkRouter` / App Intents /
// notifications / Spotlight open a drill. Each cover also gets an interactive
// left-edge swipe-to-dismiss.

// MARK: Transition animator

private final class SlideRightAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let presenting: Bool
    /// Fires once when a DISMISS transition completes and was NOT cancelled — i.e.
    /// the cover is actually gone (a completed swipe or a programmatic dismiss, but
    /// not a swipe the user cancelled). Used to reset the driving SwiftUI state.
    let onDismissed: (() -> Void)?
    /// The cover's nav bar, faded to 0 during a DISMISS so the chevron "disappears"
    /// in place — like a native pop back to a page that has no back button — instead
    /// of rigidly sliding off to the right with the rest of the cover. Scrubbed by the
    /// interactive swipe automatically (the percent-driven interactor scrubs this
    /// animation block), and restored on a cancelled swipe.
    weak var fadingBar: UIView?
    init(presenting: Bool, onDismissed: (() -> Void)? = nil, fadingBar: UIView? = nil) {
        self.presenting = presenting; self.onDismissed = onDismissed; self.fadingBar = fadingBar
    }

    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval { 0.35 }

    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        let container = ctx.containerView
        let bounds = container.bounds
        let duration = transitionDuration(using: ctx)

        if presenting {
            // Under `.overFullScreen`, `view(forKey: .from)` (the presenter) is nil —
            // only the incoming cover (`.to`) is required. Requiring `from` here once
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
            // Dismissing: slide the outgoing cover (`.from`) back off to the right.
            // Linear curve so the interactive (percent-driven) drag tracks the finger.
            guard let from = ctx.view(forKey: .from) else {
                ctx.completeTransition(true); onDismissed?(); return
            }
            from.frame = bounds
            UIView.animate(withDuration: duration, delay: 0, options: .curveLinear) {
                from.frame = bounds.offsetBy(dx: bounds.width, dy: 0)
                self.fadingBar?.alpha = 0
            } completion: { _ in
                let done = !ctx.transitionWasCancelled
                ctx.completeTransition(done)
                if done { self.onDismissed?() } else { self.fadingBar?.alpha = 1 }
            }
        }
    }
}

// MARK: Per-cover coordinator (transition + interactive edge-swipe)

private final class RightSlideDelegate: NSObject, UIViewControllerTransitioningDelegate, UIGestureRecognizerDelegate {
    weak var hosting: UIViewController?
    weak var innerNav: UINavigationController?
    /// Runs when the cover is fully gone (see SlideRightAnimator.onDismissed).
    var onDismissed: (() -> Void)?
    private var interactor: UIPercentDrivenInteractiveTransition?

    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideRightAnimator(presenting: true)
    }
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideRightAnimator(presenting: false, onDismissed: { [weak self] in self?.onDismissed?() },
                           fadingBar: innerNav?.navigationBar)
    }
    /// Non-nil only while a left-edge swipe is in progress → interactive dismiss.
    func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        interactor
    }

    /// Begin for a rightward, horizontal drag anywhere, but only at the cover's nav
    /// root (deeper levels keep the native pop). Row swipe-actions still win via
    /// `shouldRequireFailureOf` below — so this effectively fires from blank/gap areas.
    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let pan = g as? UIPanGestureRecognizer, let view = pan.view else { return false }
        let t = pan.translation(in: view)
        guard t.x > abs(t.y) else { return false }   // clearly rightward + horizontal
        if let nav = innerNav, nav.viewControllers.count > 1 { return false }
        return true
    }

    /// Rows win: the back-swipe defers to a row's swipe-action gesture, so it only
    /// activates from non-row (blank/gap) areas. Identify the row gesture by class
    /// name ("…SwipeActionPanGestureRecognizer") or by living inside a list cell; do
    /// NOT defer to the scroll pan (so scrolling keeps its instant response).
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
        if String(describing: type(of: other)).contains("Swipe") { return true }
        var v = other.view
        while let cur = v {
            if cur is UICollectionViewCell || cur is UITableViewCell { return true }
            v = cur.superview
        }
        return false
    }

    @objc func handleEdgePan(_ g: UIPanGestureRecognizer) {
        guard let view = g.view else { return }
        let width = max(view.bounds.width, 1)
        let progress = min(max(g.translation(in: view).x / width, 0), 1)
        switch g.state {
        case .began:
            interactor = UIPercentDrivenInteractiveTransition()
            hosting?.dismiss(animated: true)   // runs the dismiss transition through `interactor`
        case .changed:
            interactor?.update(progress)
        case .ended, .cancelled, .failed:
            let velocity = g.velocity(in: view).x
            if progress > 0.4 || velocity > 800 { interactor?.finish() } else { interactor?.cancel() }
            interactor = nil
        default:
            break
        }
    }
}

/// Finds the `UINavigationController` SwiftUI creates for a hosted `NavigationStack`.
private func rsdInnerNav(_ vc: UIViewController) -> UINavigationController? {
    if let nav = vc as? UINavigationController { return nav }
    for child in vc.children { if let nav = rsdInnerNav(child) { return nav } }
    return nil
}

/// Forwards every `UINavigationControllerDelegate` call to SwiftUI's original
/// delegate (ObjC message forwarding), hooking only `willShow` to make each pushed
/// view's back button chevron-only (`.minimal` — arrow, no previous-title text) so
/// the whole drill matches the cover's own chevron dismiss. Holding `original` keeps
/// SwiftUI's NavigationStack state syncing intact. Mirrors `TabTransitionProxy`.
private final class RSDNavProxy: NSObject, UINavigationControllerDelegate {
    weak var original: UINavigationControllerDelegate?
    func navigationController(_ navigationController: UINavigationController,
                             willShow viewController: UIViewController, animated: Bool) {
        viewController.navigationItem.backButtonDisplayMode = .minimal
        original?.navigationController?(navigationController, willShow: viewController, animated: animated)
    }
    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }
    override func forwardingTarget(for aSelector: Selector!) -> Any? { original }
}

/// Hosting controller that installs the cover's left-edge swipe-to-dismiss ONCE its
/// SwiftUI `NavigationStack` (and thus the inner nav's pop gesture) exists. The
/// dismiss gesture is set to `require(toFail:)` that pop gesture, so it only fires
/// at the nav ROOT — deeper levels use the native pop, the root closes the cover.
private final class RSDHostingController<Content: View>: UIHostingController<Content> {
    weak var edgeDelegate: RightSlideDelegate?
    private var installed = false
    /// Strongly held — `UINavigationController.delegate` is weak (see RSDNavProxy).
    private var navProxy: RSDNavProxy?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installEdgeSwipe()
    }

    private func installEdgeSwipe(retriesLeft: Int = 5) {
        guard !installed, let delegate = edgeDelegate else { return }
        guard let nav = rsdInnerNav(self) else {
            // The inner nav may not be attached on the first pass — retry shortly.
            if retriesLeft > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.installEdgeSwipe(retriesLeft: retriesLeft - 1)
                }
            }
            return
        }
        // A plain pan (not a screen-edge gesture) so the start margin can be wider;
        // `gestureRecognizerShouldBegin` gates it to a left-margin rightward drag at
        // the nav root, so deeper levels still use the native edge-pop gesture.
        let pan = UIPanGestureRecognizer(target: delegate,
                                         action: #selector(RightSlideDelegate.handleEdgePan(_:)))
        pan.delegate = delegate
        delegate.innerNav = nav
        nav.view.addGestureRecognizer(pan)

        // Chevron-only back buttons for every push inside the cover, forwarding all
        // other nav-delegate calls to SwiftUI so its NavigationStack state stays live.
        let proxy = RSDNavProxy()
        proxy.original = nav.delegate
        nav.delegate = proxy
        navProxy = proxy
        for vc in nav.viewControllers { vc.navigationItem.backButtonDisplayMode = .minimal }

        installed = true
    }
}

private var _rd_delegate: RightSlideDelegate?
private var _rd_hosting: UIViewController?

/// Present a SwiftUI view as a full-screen right-slide cover from the top-most
/// presented view controller. `onDismiss` fires when the cover is fully gone (a
/// completed swipe OR a programmatic dismiss) so the caller can reset its state.
func _rd_presentModal<Content: View>(_ view: Content, onDismiss: (() -> Void)? = nil) {
    // Single slot: replace any previous cover (internal navigation is native
    // NavigationStack, not nested covers). Don't fire the old cover's onDismiss —
    // it's being replaced, not user-dismissed.
    if let old = _rd_hosting {
        _rd_delegate?.onDismissed = nil
        old.dismiss(animated: false)
        _rd_hosting = nil; _rd_delegate = nil
    }
    let delegate = RightSlideDelegate()
    let hosting = RSDHostingController(rootView: view
        .environmentObject(FinchStore.shared)
        .environmentObject(DeepLinkRouter.shared)
        .environmentObject(BiometricGate.shared))
    hosting.modalPresentationStyle = .overFullScreen
    hosting.transitioningDelegate = delegate
    hosting.edgeDelegate = delegate     // installs the root-only edge-swipe (see RSDHostingController)
    delegate.hosting = hosting
    delegate.onDismissed = {
        _rd_hosting = nil; _rd_delegate = nil
        onDismiss?()
    }
    _rd_delegate = delegate
    _rd_hosting = hosting

    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard let scene = scenes.first,
          let root = scene.keyWindow?.rootViewController ?? scene.windows.first?.rootViewController
    else { _rd_hosting = nil; _rd_delegate = nil; return }
    var top = root
    while let presented = top.presentedViewController { top = presented }
    top.present(hosting, animated: true)
}

/// Dismiss the currently presented right-slide cover, if any. The dismiss runs the
/// SlideRightAnimator → onDismissed → clears state.
func _rd_dismissModal() {
    guard let hosting = _rd_hosting else { return }
    hosting.dismiss(animated: true)
}

// MARK: - State-driven view modifiers (the public API)

private struct RightSlideDrillItemModifier<Item: Identifiable, DrillContent: View>: ViewModifier {
    @Binding var item: Item?
    let drillContent: (Item) -> DrillContent
    func body(content: Content) -> some View {
        // Present/dismiss on the NEXT runloop: onChange fires inside SwiftUI's update
        // pass, and a synchronous UIKit present there is silently dropped.
        content.onChange(of: item?.id) { _, _ in
            if let value = item {
                let cover = drillContent(value)
                let binding = $item
                DispatchQueue.main.async { _rd_presentModal(cover, onDismiss: { binding.wrappedValue = nil }) }
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
            if show {
                let cover = drillContent()
                let binding = $isPresented
                DispatchQueue.main.async { _rd_presentModal(cover, onDismiss: { binding.wrappedValue = false }) }
            } else {
                DispatchQueue.main.async { _rd_dismissModal() }
            }
        }
    }
}

extension View {
    /// Present `content(item)` as a right-slide top-level cover while `item` is
    /// non-nil (dismiss when it returns to nil). State-driven, so router / deep-link
    /// entry works — not just row taps. The `content` closure builds its own
    /// `NavigationStack`; use `.rsdBackToolbar` for the leading dismiss control.
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

    /// A leading chevron-only back button (for covers whose parent has no fixed name,
    /// e.g. the Ledger cover, reachable from any tab).
    func rsdBackToolbar(dismiss: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: dismiss) {
                    Image(systemName: "chevron.left").toolbarTapTarget()
                }
                .toolbarCircleClip()
                .accessibilityLabel("Back")
            }
        }
    }
}

#endif
