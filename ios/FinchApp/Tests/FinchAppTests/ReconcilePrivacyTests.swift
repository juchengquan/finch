import XCTest
import FinchCore
@testable import FinchApp

/// Under Hide amounts, starting a reconcile must not print the exact balance into
/// the statement field. It did, while every other figure on the screen was masked.
@MainActor
final class ReconcilePrivacyTests: XCTestCase {

    func test_reconcileDoesNotPrefillTheBalanceUnderHideAmounts() async throws {
        let packURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore.shared
        if store.accounts.isEmpty { try await store.loadPack(from: try Data(contentsOf: packURL)) }
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
