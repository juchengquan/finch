#if os(iOS)
import XCTest
import CoreGraphics
@testable import FinchApp

/// The floor under Categories' expand chevron.
///
/// This guards a number that has already been pushed the wrong way once. The
/// chevron shipped at 22×30 — a third of Apple's 44×44 minimum — at the trailing
/// edge of a row whose own tap pushes the category's transaction list, so a miss
/// did not fail quietly: it cost a navigation push and a Back. `ios/CLAUDE.md`
/// records shrinking it further as one of two levers once considered for getting
/// the row under the 60pt swipe-action boundary, which is exactly the change this
/// test exists to stop.
///
/// It asserts the token, not a rendered frame, because the two implementations
/// consume it differently — UIKit gives the accessory the full square, SwiftUI
/// clamps the reported height so the row stays 60pt — and only a measurement on a
/// running simulator can confirm either actually rendered. What a unit test CAN
/// pin is that both read the same number and that the number clears the HIG floor.
final class ExpandChevronTapTargetTests: XCTestCase {

    /// Apple's Human Interface Guidelines minimum for an interactive element.
    private let hig: CGFloat = 44

    func testTapTargetMinMeetsHIGFloor() {
        XCTAssertGreaterThanOrEqual(
            Metrics.tapTargetMin, hig,
            "Metrics.tapTargetMin drives the Categories expand chevron and reorder "
            + "grip on both the UIKit and SwiftUI screens. Below \(hig)pt the chevron "
            + "becomes hard to hit, and a miss drills into the category instead of "
            + "expanding it.")
    }

    /// The clamped layout height exists to keep SwiftUI rows at 60pt while the hit
    /// box overflows it. If it ever met or exceeded the tap target the clamp would
    /// be doing nothing, and the row would be sized by the chevron again.
    func testLayoutHeightIsClampedBelowTheTapTarget() {
        XCTAssertLessThan(
            Metrics.expandChevronLayoutHeight, Metrics.tapTargetMin,
            "expandChevronLayoutHeight is the height the chevron REPORTS to its row. "
            + "Once it reaches tapTargetMin the chevron drives the row height again "
            + "and iPad/macOS Categories rows grow past 60pt.")
    }
}
#endif
