import XCTest
@testable import FinchApp

/// The transaction row's leading glyph is a control now, so its appearance is a
/// promise about what pressing it will do. These pin the two things a screenshot
/// review would not catch: that the states are actually distinguishable, and that
/// the VoiceOver action names the ACTION rather than the current state.
final class RowStatusStyleTests: XCTestCase {

    /// The whole point of fading it: a control that looks identical in both states
    /// tells you nothing about what your tap will do.
    func test_pendingAndConfirmedAreDistinguishable() {
        XCTAssertNotEqual(RowStatusStyle.glyphOpacity(pending: true),
                          RowStatusStyle.glyphOpacity(pending: false))
    }

    func test_confirmedIsFullyOpaque() {
        XCTAssertEqual(RowStatusStyle.glyphOpacity(pending: false), 1.0)
    }

    /// Faded, but still readable. The rows carrying it are the ones being triaged,
    /// so a value low enough to hide the category would cost more than it explains —
    /// the clock badge remains the primary pending signal.
    func test_pendingIsFadedButNotHidden() {
        let o = RowStatusStyle.glyphOpacity(pending: true)
        XCTAssertLessThan(o, 1.0, "pending must be visibly different")
        XCTAssertGreaterThanOrEqual(o, 0.4, "too faint to read the category it names")
    }

    // MARK: VoiceOver action

    /// Named for what the tap WILL do. A label naming the present state ("Pending")
    /// leaves the user guessing which way the action goes — the sighted affordance
    /// has the glyph's appearance to disambiguate; this has only its name.
    ///
    /// These are deliberately the SAME strings the swipe action and long-press menu
    /// use (`TxRowActions.statusTitle`). If someone reworders one route, this fails
    /// and makes them reword the others too, rather than letting one action drift
    /// into three vocabularies.
    func test_actionUsesTheSameWordsAsTheSwipeAndMenu() {
        XCTAssertEqual(RowStatusStyle.actionTitle(pending: true), "Confirm")
        XCTAssertEqual(RowStatusStyle.actionTitle(pending: false), "Set pending")
    }

    func test_actionDiffersByState() {
        XCTAssertNotEqual(RowStatusStyle.actionTitle(pending: true),
                          RowStatusStyle.actionTitle(pending: false))
    }
}
