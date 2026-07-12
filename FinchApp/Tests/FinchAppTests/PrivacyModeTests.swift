import XCTest
@testable import FinchApp

@MainActor
final class PrivacyModeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: FinchStore.privacyKey)
    }
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: FinchStore.privacyKey)
        super.tearDown()
    }

    func test_offByDefault_formatsRealAmounts() {
        let store = FinchStore()
        XCTAssertFalse(store.privacyMode)
        XCTAssertNotEqual(store.displayMoneyBase(1234.5), FinchStore.moneyMask)
        XCTAssertTrue(store.displayMoneyBase(1234.5).contains("1"))
    }

    func test_on_masksAllDisplayFormatters() {
        let store = FinchStore()
        store.privacyMode = true
        XCTAssertEqual(store.displayMoneyBase(1234.5), FinchStore.moneyMask)
        XCTAssertEqual(store.displayMoney(99.0, from: "EUR"), FinchStore.moneyMask)
        XCTAssertEqual(store.displayNative(42.0, currency: "USD"), FinchStore.moneyMask)
    }

    func test_off_displayNativeFormatsInOwnCurrency() {
        let store = FinchStore()
        XCTAssertTrue(store.displayNative(42.0, currency: "USD").contains("42"))
    }

    func test_togglePersistsToUserDefaults_andNewStoreReadsIt() {
        let store = FinchStore()
        store.privacyMode = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: FinchStore.privacyKey))
        XCTAssertTrue(FinchStore().privacyMode)   // fresh store re-reads the flag
        store.privacyMode = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: FinchStore.privacyKey))
    }
}
