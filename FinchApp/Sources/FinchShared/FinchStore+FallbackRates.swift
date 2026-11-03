import Foundation
import FinchCore
import GRDB

/// What pre-#820 code left behind (`FallbackFxRates` has how it is recognised):
/// the 1.0 exchange rates it saved by mistake, and the entries it booked at 1:1.
/// Found on demand; the rates are removed only when the user confirms on the
/// review, and nothing here runs at launch.
///
/// Removal is the plain `deleteExchangeRate` chokepoint, batched so N rows cost one
/// reprojection. It also means another device replays it with an action it
/// already knows.
///
/// Entries already booked at 1:1 are left alone. Re-converting them would rewrite
/// account balances (an amount typed in another currency, and the receiving side
/// of a cross-currency transfer, were themselves converted 1:1), and cleared or
/// reconciled legs would silently stop matching their statement. The review lists
/// them until each is saved again at a real rate.
extension FinchStore {

    /// The rates and the entries, computed once per change to what they are read
    /// from. Empty on a read failure — the notice then simply doesn't show.
    ///
    /// Currencies and the review re-read this on every reprojection, i.e. after
    /// every write. Most writes cannot change it, so it is recomputed only when
    /// `FallbackReviewKey` changes: a rate, a ledger's base, or a transaction of the
    /// active ledger that involves another currency. Other ledgers' transactions
    /// change only through a ledger switch, which changes the key, or a new
    /// database, which clears the cache.
    public func fallbackRateReview() -> FallbackFxRates.Review {
        guard let q = dbQueue else { return .empty }
        let key = FallbackReviewKey(self)
        if let cached = fallbackReviewCache, cached.key == key { return cached.review }
        fallbackReviewRunCount += 1
        guard let review = try? q.read({ try FallbackFxRates.review($0) }) else { return .empty }
        fallbackReviewCache = (key, review)
        return review
    }

    /// Delete the rows in `rates` that are STILL suspect, in one write; returns how
    /// many went. Re-checked against the database at confirm time, not the cached
    /// review, so a row that became a real rate while the list was open (a refresh,
    /// a rate typed in) is kept.
    @discardableResult
    public func removeFallbackRates(_ rates: [FallbackFxRates.Suspect]) -> Int {
        guard let q = dbQueue else { return 0 }
        let fresh = (try? q.read { try FallbackFxRates.find($0) }) ?? []
        let current = Set(fresh.map { "\($0.currency)|\($0.date)" })
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

/// What `fallbackRateReview` is computed from, as the app already holds it — so
/// telling whether it changed costs no query. Rates and ledger bases in full; of
/// the active ledger's transactions only those in or converted from another
/// currency, so an ordinary purchase in the base currency leaves it unchanged.
struct FallbackReviewKey: Equatable {
    let rates: [ExchangeRate]
    let bases: [String]
    let ledgerId: String
    let foreign: [Tx]

    @MainActor init(_ store: FinchStore) {
        rates = store.exchangeRates
        bases = store.ledgers.map { "\($0.id)|\($0.base)" }
        ledgerId = store.activeLedgerId
        let base = store.ledgers.first { $0.id == store.activeLedgerId }?.base
        let accountCurrency = Dictionary(store.accounts.map { ($0.id, $0.currency) },
                                         uniquingKeysWith: { first, _ in first })
        foreign = store.txns.filter { t in
            // `currency` is what was typed (`orig_currency ?? posting currency`), so an
            // account in another currency is checked separately.
            (t.currency.map { $0 != base } ?? false)
                || ((accountCurrency[t.account] ?? nil).map { $0 != base } ?? false)
                || (t.splits?.contains { $0.origCurrency != nil } ?? false)
        }
    }
}

