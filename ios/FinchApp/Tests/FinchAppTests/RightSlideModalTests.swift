import XCTest
import UIKit
@testable import FinchApp

/// The ledger's dismissal must not reveal a hole.
///
/// `RightSlideModal` presents with `.fullScreen`, which means UIKit REMOVES the
/// presenting view from the hierarchy once the presentation completes and only puts
/// it back at `completeTransition`. A dismiss animator that merely slides the
/// outgoing view away therefore uncovers an empty container — the window's black
/// backdrop — and the previous page snaps in at the end instead of being revealed.
///
/// That shipped: measured on the simulator at 60fps, the left quarter of the screen
/// sat at luma 16 (black) for ~15 frames, roughly 250ms, before jumping to 223.
///
/// The animator is reached through the transitioning delegate rather than
/// constructed directly, so this test needs no change to the production type's
/// visibility.
@MainActor
final class RightSlideModalTests: XCTestCase {

    /// Minimal stand-in for the transition context. Only the members the animator
    /// actually touches do anything; the rest satisfy the protocol.
    private final class FakeContext: NSObject, UIViewControllerContextTransitioning {
        let container: UIView
        let fromView: UIView
        let toView: UIView
        private(set) var completed: Bool?

        init(container: UIView, fromView: UIView, toView: UIView) {
            self.container = container
            self.fromView = fromView
            self.toView = toView
        }

        var containerView: UIView { container }
        var isAnimated: Bool { true }
        var isInteractive: Bool { false }
        var transitionWasCancelled: Bool { false }
        var presentationStyle: UIModalPresentationStyle { .fullScreen }
        var targetTransform: CGAffineTransform { .identity }

        func view(forKey key: UITransitionContextViewKey) -> UIView? {
            key == .from ? fromView : (key == .to ? toView : nil)
        }
        func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? { nil }
        func initialFrame(for vc: UIViewController) -> CGRect { container.bounds }
        func finalFrame(for vc: UIViewController) -> CGRect { container.bounds }

        func completeTransition(_ didComplete: Bool) { completed = didComplete }
        func updateInteractiveTransition(_ percentComplete: CGFloat) {}
        func finishInteractiveTransition() {}
        func cancelInteractiveTransition() {}
        func pauseInteractiveTransition() {}
    }

    private func makeContext() -> FakeContext {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let fromView = UIView(frame: container.bounds)   // the ledger, on its way out
        let toView = UIView(frame: .zero)                // the page underneath
        container.addSubview(fromView)                   // as UIKit leaves it: only `from`
        return FakeContext(container: container, fromView: fromView, toView: toView)
    }

    private func dismissAnimator() throws -> UIViewControllerAnimatedTransitioning {
        let animator = RightSlideModal.SlideTransition.shared
            .animationController(forDismissed: UIViewController())
        return try XCTUnwrap(animator, "no dismiss animator")
    }

    func test_dismiss_putsThePresenterBackBeforeSlidingAway() throws {
        let ctx = makeContext()
        try dismissAnimator().animateTransition(using: ctx)

        XCTAssertTrue(ctx.toView.superview === ctx.container,
                      "the presenter is not in the container — the dismissal uncovers a black hole")
    }

    func test_dismiss_putsThePresenterBEHINDTheOutgoingView() throws {
        let ctx = makeContext()
        try dismissAnimator().animateTransition(using: ctx)

        let subviews = ctx.container.subviews
        let toIndex = try XCTUnwrap(subviews.firstIndex(of: ctx.toView))
        let fromIndex = try XCTUnwrap(subviews.firstIndex(of: ctx.fromView))
        XCTAssertLessThan(toIndex, fromIndex,
                          "the presenter is ON TOP of the outgoing view — it would hide the animation")
    }

    func test_dismiss_givesThePresenterTheFullContainerFrame() throws {
        let ctx = makeContext()
        try dismissAnimator().animateTransition(using: ctx)

        XCTAssertEqual(ctx.toView.frame, ctx.container.bounds,
                       "the presenter is mis-sized, so part of it would still read as a hole")
    }
}
