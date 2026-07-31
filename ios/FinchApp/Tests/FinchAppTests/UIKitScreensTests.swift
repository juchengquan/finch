#if os(iOS)
import XCTest
@testable import FinchApp

/// The rollout switch for the converted UIKit screens.
///
/// Worth testing rather than eyeballing: "did the flag take effect" is a boolean, and
/// the two implementations are deliberately built to be behaviour-identical, so
/// comparing accessibility trees between modes answers it only noisily — the visible
/// difference between them can come down to a progress element's label.
final class UIKitScreensTests: XCTestCase {

    private let key = UIKitScreens.defaultsKey
    private var saved: Any?

    override func setUpWithError() throws {
        saved = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDownWithError() throws {
        if let saved { UserDefaults.standard.set(saved, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    func test_absentKeyMeansEnabled() {
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(UIKitScreens.isEnabled, "a plain launch must get the converted screens")
        XCTAssertEqual(UIKitScreens.navTabs, [.accounts, .budgets, .scheduled, .settings])
    }

    func test_explicitFalseOptsOut() {
        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(UIKitScreens.isEnabled)
        XCTAssertTrue(UIKitScreens.navTabs.isEmpty, "opting out must leave every tab hosted")
    }

    func test_explicitTrueStaysOn() {
        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(UIKitScreens.isEnabled)
    }

    /// The shape that actually reaches the app from `-uikitActivity NO`.
    ///
    /// Launch arguments land in the argument domain as STRINGS, so `object(forKey:) as?
    /// Bool` would be nil for these and fall back to the default — the opt-out would be
    /// silently dead exactly when someone reached for it. That is a real bug shipped
    /// twice in this codebase (a text-size step, and the `-initialTab` flag), so it is
    /// pinned here.
    func test_stringValuesFromTheLaunchArgumentDomain() {
        UserDefaults.standard.set("NO", forKey: key)
        XCTAssertFalse(UIKitScreens.isEnabled, "-uikitActivity NO must opt out")
        UserDefaults.standard.set("YES", forKey: key)
        XCTAssertTrue(UIKitScreens.isEnabled, "-uikitActivity YES must stay on")
    }
}
#endif
