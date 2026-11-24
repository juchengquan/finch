import XCTest
import FinchCore
@testable import FinchApp

/// Under Hide amounts, starting a reconcile must not print the exact balance into
/// the statement field. It did, while every other figure on the screen was masked.
@MainActor
final class ReconcilePrivacyTests: XCTestCase {

    func test_reconcileDoesNotPrefillTheBalanceUnderHideAmounts() async throws {
        let store = try await SharedStoreFixture.load()
        let account = try XCTUnwrap(store.accounts.first { $0.balance != 0 } ?? store.accounts.first)
        let saved = store.privacyMode
        defer { store.privacyMode = saved }

        store.privacyMode = false
        let shown = AccountDetailVC(accountId: account.id)
        shown.loadViewIfNeeded()
        shown.enterReconcileMode()
        XCTAssertEqual(DecimalInput.parse(shown.reconcileSession.statementBalanceText), account.balance)

        store.privacyMode = true
        let hidden = AccountDetailVC(accountId: account.id)
        hidden.loadViewIfNeeded()
        hidden.enterReconcileMode()
        XCTAssertEqual(hidden.reconcileSession.statementBalanceText, "")
        XCTAssertEqual(hidden.reconcileSession.differenceText, FinchStore.moneyMask)
    }
}
