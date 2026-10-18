import Foundation
import GRDB

/// The 1.0 rates the engine saved by mistake before #820, found so the user can
/// remove them. NATIVE-ONLY and read-only: the removal is the ordinary
/// `deleteExchangeRate`, so nothing here enters WRITE_SEQUENCE.
///
/// **How they were written.** A currency with no stored rate and no entry in the
/// static fallback map resolved to 1, and the write-through pinned that 1 as an
/// ordinary `'derived'` row under the conversion's date. Every later lookup took
/// the nearest rate on or before its date, found the 1.0 and pinned it again — so
/// one missing rate left a trail of derived 1.0 rows, one per date anything was
/// converted, and they keep converting the currency 1:1 after #820.
///
/// **What gives them away.** Three things, all required:
/// - `source = 'derived'` and `rate = 1` exactly. A rate the user typed, a fetched
///   one (ECB, er-api…) or an imported one never carries `'derived'`.
/// - The currency is not one of the static-fallback six (their fallback was a real
///   rate, never 1) and not one of the few pegged 1:1 to the dollar, where 1 was
///   the right answer.
/// - No non-derived row for the currency says 1. A derived row is otherwise a copy
///   of its neighbour, and a copy of a genuine 1 is genuine.
///
/// Rates are stored against the USD hub, not a ledger's base, so a base currency
/// is no exception: a KRW ledger's derived 1.0 KRW row booked $10 as ₩10.
public enum FallbackFxRates {

    /// One suspect row, and how many entries were converted with it.
    public struct Suspect: Hashable, Sendable {
        public let currency: String
        public let date: String
        /// Entries dated on the row's date that converted from, into or through
        /// `currency`. The write-through pinned a row at every date it converted,
        /// so these are the entries this row converted 1:1 (see `entriesUsing`).
        public let entryCount: Int
        public init(currency: String, date: String, entryCount: Int) {
            self.currency = currency; self.date = date; self.entryCount = entryCount
        }
    }

    /// The static-fallback six (`Entries.fallbackUsdPerUnit`): their fallback was a
    /// real rate, so a derived 1.0 for one of them is not this bug.
    static let realFallback: Set<String> = ["USD", "EUR", "GBP", "JPY", "SGD", "CNY"]

    /// Pegged at exactly one US dollar, so 1:1 was correct for them.
    static let peggedToUSD: Set<String> = ["BMD", "BSD", "PAB"]

    /// Every suspect row, oldest first, then by currency.
    public static func find(_ db: Database) throws -> [Suspect] {
        let excluded = realFallback.union(peggedToUSD).sorted()
        let marks = excluded.map { _ in "?" }.joined(separator: ",")
        let rows = try Row.fetchAll(db, sql: """
            SELECT r.date AS d, r.currency AS c FROM exchange_rates r
            WHERE r.source = 'derived' AND r.rate = 1
              AND r.currency NOT IN (\(marks))
              AND NOT EXISTS (SELECT 1 FROM exchange_rates g
                              WHERE g.currency = r.currency AND g.rate = 1
                                AND COALESCE(g.source, '') <> 'derived')
            ORDER BY r.date, r.currency
            """, arguments: StatementArguments(excluded))
        return try rows.map { r in
            let c: String = r["c"], d: String = r["d"]
            return Suspect(currency: c, date: d, entryCount: try entriesUsing(db, currency: c, date: d))
        }
    }

    /// Entries a rate for `currency` at `date` converted: a leg in `currency` on a
    /// ledger with another base, a leg in another currency on a `currency`-based
    /// ledger, or an amount typed in `currency` on an account that holds another.
    ///
    /// Same date only. A lookup on any other date pinned its own row, which is
    /// counted against that row, so nothing is counted twice.
    static func entriesUsing(_ db: Database, currency: String, date: String) throws -> Int {
        try Int.fetchOne(db, sql: """
            SELECT COUNT(DISTINCT e.id) FROM entries e
            JOIN ledgers l ON l.id = e.ledger_id
            JOIN postings p ON p.entry_id = e.id
            WHERE e.date = :d AND (
                 (p.currency = :c AND l.base_currency <> :c)
              OR (l.base_currency = :c AND p.currency <> :c)
              OR (p.orig_currency = :c AND p.currency <> :c))
            """, arguments: ["c": currency, "d": date]) ?? 0
    }
}
