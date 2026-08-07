import XCTest

/// Tapping "Month Year" in the calendar header must actually produce the
/// month/year wheels — IN THE HOSTED CALENDAR, not just in a SwiftUI preview.
///
/// The control shipped presenting a `.popover` from inside `MonthCashCalendar`,
/// and every screen that shows the calendar (Activity, account detail,
/// Scheduled) hosts it in a `UIHostingConfiguration` cell — where SwiftUI
/// presentations have no presenting view controller, so the button flipped its
/// state and nothing appeared. Same works-in-SwiftUI/dead-in-the-host class as
/// the glyph-gesture bug (#744); this test exists so the calendar's header
/// control can never regress that way silently again. One host suffices: all
/// three screens share the component and the hosting pattern.
final class CalendarMonthYearPickerUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES",
                               "-uikitActivity", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testTappingMonthYearOpensTheWheelsAndTheGridFollows() throws {
        openActivityCalendar()

        let control = app.buttons["Month and year"]
        XCTAssertTrue(control.waitForExistence(timeout: 15),
                      "no Month-and-year control in the calendar header")
        let monthBefore = control.value as? String
        control.tap()

        // THE regression assertion: the wheels must exist after the tap. With the
        // popover presentation they never appear in a hosted cell.
        let monthWheel = app.pickerWheels.firstMatch
        XCTAssertTrue(monthWheel.waitForExistence(timeout: 10),
                      "tapped Month-and-year and no picker wheels appeared — the " +
                      "picker is presenting into a context the host cannot show")

        // Spin to January and check the header follows (live binding).
        monthWheel.adjust(toPickerWheelValue: "January")
        let deadline = Date().addingTimeInterval(5)
        var monthAfter = control.value as? String
        while (monthAfter?.contains("January") != true) && Date() < deadline {
            usleep(100_000)
            monthAfter = control.value as? String
        }
        XCTAssertTrue(monthAfter?.contains("January") == true,
                      "wheel set to January but the header reads \(monthAfter ?? "nil") " +
                      "(was \(monthBefore ?? "nil")) — the wheels are not driving the anchor")
    }

    // MARK: Reaching the calendar (compact: Accounts → All Transactions → Calendar)

    private func openActivityCalendar() {
        let accounts = app.buttons["Accounts"]
        if accounts.waitForExistence(timeout: 10) { accounts.tap() }
        let all = app.cells.staticTexts["All Transactions"].firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 15), "Accounts has no All Transactions row")
        all.tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 15),
                      "All Transactions did not push the Activity feed")
        let calendarSegment = app.buttons["Calendar"]
        XCTAssertTrue(calendarSegment.waitForExistence(timeout: 10),
                      "no List|Calendar mode picker in the feed")
        calendarSegment.tap()
    }
}
