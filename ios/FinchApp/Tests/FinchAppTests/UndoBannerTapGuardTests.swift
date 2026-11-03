import XCTest
import UIKit
@testable import FinchApp

/// The Undo banner floats over the rows, so a tap aimed at Undo just as it went
/// used to fall through and open the transaction underneath. For a moment after it
/// goes, its window swallows touches where it sat; everywhere else they still fall
/// through to the app.
@MainActor
final class UndoBannerTapGuardTests: XCTestCase {
    private func window() -> (PassthroughWindow, UIView) {
        let window = PassthroughWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.isHidden = false
        let banner = UIView(frame: CGRect(x: 40, y: 600, width: 320, height: 48))
        window.addSubview(banner)
        window.passthroughTarget = banner
        return (window, banner)
    }

    func test_aVisibleBannerTakesItsTouches_andNothingElse() {
        let (w, banner) = window()
        XCTAssertTrue(w.hitTest(CGPoint(x: 200, y: 620), with: nil)?.isDescendant(of: banner) ?? false)
        XCTAssertNil(w.hitTest(CGPoint(x: 200, y: 300), with: nil), "a touch off the banner reaches the app")
    }

    func test_aLateTapWhereTheBannerWas_isSwallowed() {
        let (w, banner) = window()
        w.swallowTaps(in: banner.frame, for: 10)
        banner.alpha = 0
        XCTAssertNotNil(w.hitTest(CGPoint(x: 200, y: 620), with: nil), "the late tap fell through to the row")
        XCTAssertNil(w.hitTest(CGPoint(x: 200, y: 300), with: nil), "only the banner's spot is guarded")
    }

    func test_theGuardEnds() {
        let (w, banner) = window()
        w.swallowTaps(in: banner.frame, for: 0)
        banner.alpha = 0
        XCTAssertNil(w.hitTest(CGPoint(x: 200, y: 620), with: nil))
    }

    /// Eight seconds, up from five — the other half of the same fix.
    func test_theOfferStaysUpLongEnoughToReach() {
        guard !UIAccessibility.isVoiceOverRunning else { return }
        XCTAssertEqual(FinchStore.undoWindow, .seconds(8))
    }
}
