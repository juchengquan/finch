import XCTest

/// The month carousel must advance **exactly one month per swipe**.
///
/// That sounds too obvious to test, and it is precisely the thing that broke. The
/// carousel used to be a 3-page `TabView` centred on the anchored month: a settled
/// swipe committed the new month and snapped the pager back to centre. The snap-back
/// raced the page controller's own in-flight completion, which then re-emitted its
/// selection write on top of the recentred state — **two** months per swipe.
///
/// The fix at the time was `.id(monthIndex)` on the TabView, recreating the pager
/// after every commit so nothing was left in flight. It worked, and it cost the
/// animation: identity changes the instant the selection commits, which is when the
/// slide *starts*. SwiftUI tore the pager down mid-slide, so the transition rendered
/// 15 of 34 frames — motion, a ~50ms freeze on a half-slid grid, then a jump straight
/// to the settled month. The pager is now backed by `UIPageViewController`, which
/// reports when a transition actually finished and needs no recentring at all.
///
/// **This test is the net under that rewrite.** It asserts the property the `.id`
/// existed to protect, so the smoother implementation cannot quietly reintroduce the
/// double advance. Verified to FAIL against a build with the `.id` removed and the
/// TabView left in place (one swipe went August → October).
///
/// **Asserts the month label, not the animation.** No UI test can see a frame; the
/// observable is where the calendar ends up. The label is read from the header
/// button's accessibility VALUE — its label names the control ("Month and year"), so
/// the value is what carries the anchored month.
final class MonthPagerUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Scheduled opens straight onto the calendar — no mode picker to drive first.
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES",
                               "-initialTab", "scheduled"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// The header button whose accessibility value is the anchored month.
    private var monthButton: XCUIElement { app.buttons["Month and year"] }

    private func monthLabel() throws -> String {
        try XCTUnwrap(monthButton.value as? String, "the month header has no value")
    }

    /// Parses the header's month label back to year/month. Built to match the view's
    /// own formatter (`LLLL yyyy`, Gregorian) — the UI-test target can't import
    /// `AppDate`, so the format is restated rather than shared.
    private func parseMonth(_ label: String) throws -> Int {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale.current
        f.dateFormat = "LLLL yyyy"
        let date = try XCTUnwrap(f.date(from: label), "could not parse month label \(label.debugDescription)")
        let c = f.calendar!.dateComponents([.year, .month], from: date)
        // Absolute month index, so December → January counts as +1 and not −11.
        return (c.year ?? 0) * 12 + (c.month ?? 0)
    }

    /// Drags horizontally across the middle of the month grid. Anchored to the
    /// weekday row's frame rather than a guessed screen fraction, so it keeps
    /// landing on the pager if the surrounding layout shifts. `dx` is the start
    /// offset as a fraction of window width; the drag ends mirrored across centre.
    /// How the swipe is delivered. **Both are needed.** A flick and an unhurried drag
    /// take different paths through the scroll view's deceleration, and each of them
    /// has caught a two-month advance the other reported as fine: the flick caught the
    /// old TabView's in-flight race, and the drag caught a paged scroll view carrying
    /// its momentum past one month. Testing one gesture is how this bug shipped twice.
    enum Gesture {
        case flick, drag

        var velocity: XCUIGestureVelocity { self == .flick ? .fast : XCUIGestureVelocity(800) }
        var press: TimeInterval { self == .flick ? 0.01 : 0.1 }
    }

    private func dragGrid(from dx: CGFloat, _ gesture: Gesture = .flick) throws {
        let sun = app.staticTexts["Sun"].firstMatch
        XCTAssertTrue(sun.waitForExistence(timeout: 20), "no weekday row — the calendar isn't on screen")
        let window = app.windows.firstMatch
        // Well below the weekday row: clear of the header's buttons, inside the grid.
        let y = sun.frame.maxY + 180
        let origin = window.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: window.frame.width * dx, dy: y))
        let end = origin.withOffset(CGVector(dx: window.frame.width * (1 - dx), dy: y))
        start.press(forDuration: gesture.press, thenDragTo: end,
                    withVelocity: gesture.velocity, thenHoldForDuration: 0)
    }

    /// Waits for the header to settle on a month different from `previous`.
    private func waitForMonthChange(from previous: String) {
        let changed = expectation(for: NSPredicate(format: "value != %@", previous),
                                  evaluatedWith: monthButton)
        wait(for: [changed], timeout: 15)
    }

    private func assertOneSwipeMoves(_ expected: Int, _ gesture: Gesture) throws {
        XCTAssertTrue(monthButton.waitForExistence(timeout: 30), "no month header on the calendar")
        let before = try monthLabel()

        try dragGrid(from: expected > 0 ? 0.85 : 0.15, gesture)   // right→left = next
        waitForMonthChange(from: before)

        let moved = try parseMonth(try monthLabel()) - parseMonth(before)
        XCTAssertEqual(moved, expected,
                       "one \(gesture) moved \(moved) months, expected \(expected) — the pager is over-advancing")
    }

    func testOneFlickAdvancesExactlyOneMonth() throws {
        try assertOneSwipeMoves(1, .flick)
    }

    func testOneFlickBackRetreatsExactlyOneMonth() throws {
        try assertOneSwipeMoves(-1, .flick)
    }

    func testOneDragAdvancesExactlyOneMonth() throws {
        try assertOneSwipeMoves(1, .drag)
    }

    func testOneDragBackRetreatsExactlyOneMonth() throws {
        try assertOneSwipeMoves(-1, .drag)
    }

    /// The chevrons share the pager with the swipe, so they can double-advance for
    /// exactly the same reason and are worth their own assertion.
    func testNextMonthChevronAdvancesExactlyOneMonth() throws {
        XCTAssertTrue(monthButton.waitForExistence(timeout: 30), "no month header on the calendar")
        let before = try monthLabel()

        app.buttons["Next month"].tap()
        waitForMonthChange(from: before)

        let moved = try parseMonth(try monthLabel()) - parseMonth(before)
        XCTAssertEqual(moved, 1, "the next-month chevron moved \(moved) months")
    }
}
