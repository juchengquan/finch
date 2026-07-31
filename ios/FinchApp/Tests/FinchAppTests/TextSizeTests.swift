import XCTest
import SwiftUI
@testable import FinchApp

final class TextSizeTests: XCTestCase {
    func test_stepMapping_andClamping() {
        XCTAssertEqual(TextSize.steps.count, 7)
        XCTAssertEqual(TextSize.size(forStep: 0), .xSmall)
        XCTAssertEqual(TextSize.size(forStep: 3), .large)
        XCTAssertEqual(TextSize.size(forStep: 6), .xxxLarge)
        XCTAssertEqual(TextSize.size(forStep: -5), .xSmall)
        XCTAssertEqual(TextSize.size(forStep: 99), .xxxLarge)
        XCTAssertEqual(TextSize.defaultStep, 3)
    }

    #if os(iOS)
    func test_systemCategoryMapsToStep_accessibilitySizesClampToLargest() {
        XCTAssertEqual(TextSize.step(forCategory: .extraSmall), 0)
        XCTAssertEqual(TextSize.step(forCategory: .large), 3)
        XCTAssertEqual(TextSize.step(forCategory: .extraExtraExtraLarge), 6)
        // The slider stops at .xxxLarge, so every AX category pins to its top.
        XCTAssertEqual(TextSize.step(forCategory: .accessibilityMedium), 6)
        XCTAssertEqual(TextSize.step(forCategory: .accessibilityExtraExtraExtraLarge), 6)
        // Unknown / unspecified categories fall back rather than crash.
        XCTAssertEqual(TextSize.step(forCategory: .unspecified), TextSize.defaultStep)
    }
    #endif

    // MARK: Migration off the removed "Use system size" toggle

    /// A defaults store scoped to one test, so these never touch the real app's.
    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "TextSizeTests.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    func test_migrate_untouchedInstall_seedsFromSystemSize() {
        let d = makeDefaults()
        // No keys at all: the toggle defaulted ON, so the user was reading the
        // system size — and must keep reading it.
        TextSize.migrateLegacySystemPreference(systemStep: 5, defaults: d)
        XCTAssertEqual(d.object(forKey: TextSize.stepKey) as? Int, 5)
        XCTAssertNil(d.object(forKey: TextSize.legacySystemKey))
    }

    func test_migrate_toggleWasOn_overwritesStaleStepWithSystemSize() {
        let d = makeDefaults()
        // Turned the toggle off, picked a step, then turned it back on: the step
        // is stale — what they SEE is the system size.
        d.set(true, forKey: TextSize.legacySystemKey)
        d.set(0, forKey: TextSize.stepKey)
        TextSize.migrateLegacySystemPreference(systemStep: 6, defaults: d)
        XCTAssertEqual(d.object(forKey: TextSize.stepKey) as? Int, 6)
        XCTAssertNil(d.object(forKey: TextSize.legacySystemKey))
    }

    func test_migrate_toggleWasOff_keepsTheChosenStep() {
        let d = makeDefaults()
        d.set(false, forKey: TextSize.legacySystemKey)
        d.set(1, forKey: TextSize.stepKey)
        TextSize.migrateLegacySystemPreference(systemStep: 6, defaults: d)
        XCTAssertEqual(d.object(forKey: TextSize.stepKey) as? Int, 1)
        XCTAssertNil(d.object(forKey: TextSize.legacySystemKey))
    }

    func test_migrate_isIdempotent_andDoesNotResurrectSystemSize() {
        let d = makeDefaults()
        TextSize.migrateLegacySystemPreference(systemStep: 5, defaults: d)
        // The user then drags the slider; a later launch (bigger system size)
        // must not stomp that choice.
        d.set(2, forKey: TextSize.stepKey)
        TextSize.migrateLegacySystemPreference(systemStep: 6, defaults: d)
        XCTAssertEqual(d.object(forKey: TextSize.stepKey) as? Int, 2)
    }

    func test_migrate_clampsOutOfRangeSystemStep() {
        let d = makeDefaults()
        TextSize.migrateLegacySystemPreference(systemStep: 99, defaults: d)
        XCTAssertEqual(d.object(forKey: TextSize.stepKey) as? Int, TextSize.steps.count - 1)
    }
}
