import Foundation
import FinchCore
import GRDB

/// The 1.0 exchange rates saved by mistake before #820 (`FallbackFxRates` has how
/// they are recognised). Found on demand and removed only when the user confirms
/// on the Currencies screen; nothing here runs at launch.
///
/// Removal is the plain `deleteExchangeRate` chokepoint, batched so N rows cost one
/// reprojection. It also means another device replays it with an action it
/// already knows.
///
/// Entries already booked at 1:1 are left alone. Re-converting them would rewrite
/// account balances (an amount typed in another currency, and the receiving side
/// of a cross-currency transfer, were themselves converted 1:1), and cleared or
/// reconciled legs would silently stop matching their statement.
extension FinchStore {

    /// Every suspect rate, oldest first. Empty on a read failure — the notice then
    /// simply doesn't show.
    public func fallbackRateSuspects() -> [FallbackFxRates.Suspect] {
        guard let q = dbQueue else { return [] }
        return (try? q.read { try FallbackFxRates.find($0) }) ?? []
    }

    /// The entries `rates` converted 1:1, in every ledger (`FallbackFxRates.entryIds`).
    /// Works for rates already removed: the rule reads only their currency and date.
    /// Empty on a read failure.
    public func fallbackRateEntryIds(_ rates: [FallbackFxRates.Suspect]) -> Set<String> {
        guard let q = dbQueue, !rates.isEmpty else { return [] }
        return (try? q.read { try FallbackFxRates.entryIds($0, for: rates) }) ?? []
    }

    /// Delete the rows in `rates` that are STILL suspect, in one write; returns how
    /// many went. Re-checked at confirm time, so a row that became a real rate
    /// while the list was open (a refresh, a rate typed in) is kept.
    @discardableResult
    public func removeFallbackRates(_ rates: [FallbackFxRates.Suspect]) -> Int {
        let current = Set(fallbackRateSuspects().map { "\($0.currency)|\($0.date)" })
        let ops = rates
            .filter { current.contains("\($0.currency)|\($0.date)") }
            .map { (action: ActionName.deleteExchangeRate,
                    args: Args(["date": .string($0.date), "currency": .string($0.currency)])) }
        return applyBatch(ops)
    }

    #if DEBUG
    /// `-seedFallbackRates YES` (UI tests, screenshots): recreate what pre-#820 code
    /// left behind. A KRW wallet with two purchases booked 1:1 against 1.0 rates
    /// pinned at their dates, plus one pinned THB rate nothing used. Written the way
    /// the old code wrote them — straight into the table as 'derived' — because no
    /// current action can produce them. The lookup skips 'derived' rows, so the
    /// rows go in untagged, the purchases book 1:1 against them, and only then do
    /// they take the tag.
    func seedPre820FallbackRatesForTesting() {
        guard let q = dbQueue, !activeLedgerId.isEmpty else { return }
        let cal = Calendar.current
        func day(_ ago: Int) -> String {
            Self.isoDay(cal.date(byAdding: .day, value: -ago, to: Date()) ?? Date())
        }
        let pins = [("KRW", day(3)), ("KRW", day(9)), ("THB", day(16))]
        do {
            try q.write { db in
                for (c, d) in pins {
                    try db.execute(sql: "INSERT OR IGNORE INTO exchange_rates (date, currency, rate, source) VALUES (?, ?, 1, 'pre-820')",
                                   arguments: [d, c])
                }
            }
            try Apply.apply(dbQueue: q, action: ActionName.createAccount.rawValue, args: Args([
                "id": .string("won-wallet"), "ledgerId": .string(activeLedgerId), "name": .string("Won wallet"),
                "type": .string("cash"), "currency": .string("KRW")]))
            for (amount, ago) in [(-48_000.0, 3), (-15_500.0, 9)] {
                try Apply.apply(dbQueue: q, action: ActionName.addTransaction.rawValue, args: Args([
                    "ledgerId": .string(activeLedgerId), "accountId": .string("won-wallet"),
                    "amount": .double(amount), "merchant": .string("Seoul market"),
                    "date": .string(day(ago)), "skipRules": .bool(true)]))
            }
            try q.write { db in
                try db.execute(sql: "UPDATE exchange_rates SET source = 'derived' WHERE source = 'pre-820'")
            }
        } catch {
            NSLog("seedFallbackRates failed: \(error)")
        }
        reprojectActiveLedger()
    }
    #endif
}
