import XCTest
import FinchCore
@testable import FinchApp

/// Notifications are planned for every ledger, not only the one on screen. The
/// reconcile step withdraws whatever is not planned, so a plan of the active ledger
/// alone cancelled the other ledgers' reminders on every switch, and re-sent their
/// dismissed alerts on the way back.
@MainActor
final class OtherLedgerNotificationTests: XCTestCase {

    /// The sample pack, plus a yen ledger with a rent reminder due today.
    private func storeWithASecondLedger() async throws -> (FinchStore, templateId: String) {
        let packURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "sample", withExtension: "finch", subdirectory: "Fixtures/roundtrip"))
        let store = FinchStore()
        try await store.loadPack(from: try Data(contentsOf: packURL))
        let ledgerId = "biz-\(UUID().uuidString.prefix(6))"
        try store.apply(.createLedger, Args(["id": .string(ledgerId), "name": .string("Tokyo"), "base": .string("JPY")]))
        try store.apply(.createAccount, Args([
            "id": .string("\(ledgerId)-cash"), "ledgerId": .string(ledgerId), "name": .string("Cash"),
            "type": .string("cash"), "currency": .string("JPY")]))
        let templateId = "\(ledgerId)-rent"
        try store.apply(.createScheduled, Args([
            "id": .string(templateId), "ledgerId": .string(ledgerId), "name": .string("Office rent"),
            "type": .string("expense"), "amount": .double(80000), "frequency": .string("monthly"),
            "dayOfMonth": .int(1), "accountId": .string("\(ledgerId)-cash"),
            "startDate": .string(store.wallToday)]))
        return (store, templateId)
    }

    func test_anInactiveLedgersReminderIsPlanned() async throws {
        let (store, templateId) = try await storeWithASecondLedger()
        let q = try XCTUnwrap(store.dbQueue)
        let slices = FinchStore.loadOtherLedgers(q, active: store.activeLedgerId)
        XCTAssertTrue(slices.contains { $0.scheduled.contains { $0.id == templateId } },
                      "the yen ledger is not on screen, and is read from the database")
        let planned = store.planNotifications(for: slices, enabled: [.scheduledDue], deliveryHour: 9)
        XCTAssertEqual(planned.filter { $0.id.hasPrefix("scheduled:\(templateId):") }.count, 1)
        XCTAssertFalse(slices.contains { $0.ledger.id == store.activeLedgerId }, "the active ledger is planned from the store")
    }

    /// Each ledger's amounts are in its own currency.
    func test_anInactiveLedgersAmountsAreInItsCurrency() async throws {
        let (store, _) = try await storeWithASecondLedger()
        let other = try XCTUnwrap(store.ledgers.first { $0.base == "JPY" })
        XCTAssertTrue(store.displayMoney(80000, forLedger: other.id).contains("80,000"))
        XCTAssertTrue(store.displayMoney(80000, forLedger: other.id).contains("¥"))
        store.privacyMode = true
        defer { store.privacyMode = false }
        XCTAssertEqual(store.displayMoney(80000, forLedger: other.id), FinchStore.moneyMask)
    }

    /// The cache key moves when the other ledgers' entries do: a cross-ledger write
    /// lands on both sides.
    func test_theDataSignatureMovesWhenAnotherLedgerIsWritten() async throws {
        let (store, _) = try await storeWithASecondLedger()
        let q = try XCTUnwrap(store.dbQueue)
        let other = try XCTUnwrap(store.ledgers.first { $0.base == "JPY" })
        let before = FinchStore.otherLedgerDataSignature(q, active: store.activeLedgerId)
        try store.apply(.addTransaction, Args([
            "ledgerId": .string(other.id), "accountId": .string("\(other.id)-cash"), "amount": .double(-500),
            "merchant": .string("Coffee"), "date": .string(store.wallToday), "skipRules": .bool(true)]))
        XCTAssertNotEqual(FinchStore.otherLedgerDataSignature(q, active: store.activeLedgerId), before)
    }

    /// A wrist add for a ledger that is not on screen (the phone switched after the
    /// catalog was sent) resolves against that ledger's own accounts. It used to
    /// find none among the active ledger's, and was dropped for good.
    func test_aWatchAddForAnotherLedgerResolvesAgainstThatLedger() async throws {
        let (store, _) = try await storeWithASecondLedger()
        let other = try XCTUnwrap(store.ledgers.first { $0.base == "JPY" })
        XCTAssertNotEqual(store.activeLedgerId, other.id)
        let item = WatchQuickAddItem(merchant: "Konbini", amount: 600, currency: "JPY",
                                     ledgerId: other.id, accountId: "\(other.id)-cash", categoryId: nil)
        XCTAssertNil(PhoneWatchLink.resolvedItem(item, accounts: store.accounts, categories: store.pickableCategories),
                     "the old call site looked only among the active ledger's accounts")
        XCTAssertEqual(PhoneWatchLink.resolvedItem(item, store: store)?.accountId, "\(other.id)-cash")
        // And a stale account id still falls back within THAT ledger.
        var stale = item; stale.accountId = "gone"
        XCTAssertEqual(PhoneWatchLink.resolvedItem(stale, store: store)?.accountId, "\(other.id)-cash")
    }
}
