import XCTest
@testable import FinchApp
import FinchCore

/// The hold-menu's one item, built once and shared by four screens.
///
/// Worth testing rather than eyeballing because the item is INVISIBLE until
/// someone long-presses a button they have only ever tapped — a wrong title or a
/// missing checkmark is not something a user will report, they will simply never
/// find the feature.
@MainActor
final class PrivacyMenuTests: XCTestCase {

    override func tearDown() {
        FinchStore.shared.privacyMode = false
        super.tearDown()
    }

    /// Reuses the string the Mac menu already uses — already translated, so this
    /// change adds no catalog key.
    func test_theItemIsTitledHideAmounts() {
        let action = PrivacyMenu.action(store: FinchStore.shared)
        XCTAssertEqual(action.title, String(localized: "Hide Amounts"))
    }

    /// A checkmark, so a hidden control can be READ and not only fired: hold the
    /// button and the menu tells you whether amounts are currently masked.
    func test_theItemCarriesItsState() {
        FinchStore.shared.privacyMode = false
        XCTAssertEqual(PrivacyMenu.action(store: FinchStore.shared).state, .off)

        FinchStore.shared.privacyMode = true
        XCTAssertEqual(PrivacyMenu.action(store: FinchStore.shared).state, .on)
    }

    /// And it actually drives the store — a menu that renders and toggles nothing
    /// is the failure mode this whole change could ship with unnoticed.
    func test_firingTheItemTogglesTheStore() {
        FinchStore.shared.privacyMode = false
        PrivacyMenu.action(store: FinchStore.shared).performWithSender(nil, target: nil)
        XCTAssertTrue(FinchStore.shared.privacyMode)
    }
}
