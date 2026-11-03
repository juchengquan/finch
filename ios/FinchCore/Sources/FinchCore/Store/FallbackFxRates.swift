import Foundation
import GRDB

/// What pre-#820 code left behind when it converted a currency it had no rate
/// for: the entries it booked as if that currency were worth one US dollar, and
/// the 1.0 rates it saved along the way. NATIVE-ONLY and read-only: the rates go
/// through the ordinary `deleteExchangeRate`, and an entry is corrected by saving
/// it again, so nothing here enters WRITE_SEQUENCE.
///
/// **How it happened.** A currency with no stored rate and no entry in the static
/// fallback map resolved to 1 (USD per unit), and the write-through pinned that 1
/// as an ordinary `'derived'` row under the conversion's date. Every later lookup
/// took the nearest rate on or before its date, found the 1.0 and pinned it again
/// — so one missing rate left a trail of derived 1.0 rows, one per date anything
/// was converted. They kept converting the currency 1:1 after #820, until the
/// lookup stopped reading `'derived'` rows at all (#829). Now they convert nothing,
/// but they still show as the currency's rate wherever the app displays one.
///
/// **The entries are found from their postings, not from the rows.** A posting
/// keeps the rate it was booked at, so a conversion that valued one side at one
/// dollar says so itself. The rows were a poor index: a refresh on the same day
/// replaces a row (one per currency per day), which hid the entries booked with
/// it, and an entry re-saved at a real rate stayed counted for as long as its
/// date matched a row.
///
/// Rates are stored against the USD hub, not a ledger's base, so a base currency
/// is no exception: a KRW ledger's 1.0 KRW row booked $10 as ₩10.
public enum FallbackFxRates {

    /// One suspect 1.0 row, and how many of the entries booked at 1:1 it covers.
    public struct Suspect: Hashable, Sendable {
        public let currency: String
        public let date: String
        /// The entries dated on the row's date that valued `currency` at one
        /// dollar (`Review.entryIds(for:)`). The write-through pinned a row at
        /// every date it converted, so these are the ones this row stands for.
        public let entryCount: Int
        public init(currency: String, date: String, entryCount: Int) {
            self.currency = currency; self.date = date; self.entryCount = entryCount
        }
    }

    /// One entry booked at 1:1.
    public struct Booked: Hashable, Sendable {
        public let entryId: String
        public let date: String
        /// The currency or currencies the entry valued at one dollar: the unrated
        /// side of each conversion it records. Two when neither side had a rate.
        public let currencies: Set<String>
        public init(entryId: String, date: String, currencies: Set<String>) {
            self.entryId = entryId; self.date = date; self.currencies = currencies
        }
    }

    /// Everything the review shows. `entries` does not depend on `rates`: it stays
    /// after the rows are removed, until every entry is corrected.
    public struct Review: Equatable, Sendable {
        /// Oldest first, then by currency.
        public let rates: [Suspect]
        /// One per entry, in every ledger, oldest first.
        public let entries: [Booked]
        public init(rates: [Suspect], entries: [Booked]) {
            self.rates = rates; self.entries = entries
        }
        public static let empty = Review(rates: [], entries: [])

        public var isEmpty: Bool { rates.isEmpty && entries.isEmpty }
        public var entryIds: Set<String> { Set(entries.map(\.entryId)) }

        /// The entries `rate` stands for: dated on its day, valuing its currency at
        /// one dollar. Read from `entries`, so it still answers after the row is gone.
        public func entryIds(for rate: Suspect) -> Set<String> {
            Set(entries.filter { $0.date == rate.date && $0.currencies.contains(rate.currency) }.map(\.entryId))
        }
    }

    /// The static-fallback six (`Entries.fallbackUsdPerUnit`): their fallback was a
    /// real rate, never 1, so neither a 1.0 row nor a 1:1 entry is this bug for them.
    static let realFallback: Set<String> = ["USD", "EUR", "GBP", "JPY", "SGD", "CNY"]

    /// Pegged at exactly one US dollar, so 1:1 was correct for them.
    static let peggedToUSD: Set<String> = ["BMD", "BSD", "PAB"]

    /// How far a booked rate may sit from the one it is compared with and still
    /// match. The other side's rate on record today can differ a little from the
    /// one the conversion used (a closer rate fetched since), while a currency
    /// valued at one dollar is off by far more than this unless it is worth about
    /// a dollar, which is then excluded as booked at its real rate.
    static let tolerance = 0.03

    public static func review(_ db: Database) throws -> Review {
        let entries = try bookedEntries(db)
        let rates = try suspectRows(db).map { r in
            Suspect(currency: r.currency, date: r.date, entryCount: entries.filter {
                $0.date == r.date && $0.currencies.contains(r.currency)
            }.count)
        }
        return Review(rates: rates, entries: entries)
    }

    /// Every suspect row with its count, oldest first, then by currency.
    public static func find(_ db: Database) throws -> [Suspect] { try review(db).rates }

    /// The 1.0 rows. Three things, all required:
    /// - `source = 'derived'` and `rate = 1` exactly. A rate the user typed, a
    ///   fetched one (ECB, er-api…) or an imported one never carries `'derived'`.
    /// - The currency is not one of the static-fallback six or a dollar peg.
    /// - No non-derived row for the currency says 1. A derived row is otherwise a
    ///   copy of its neighbour, and a copy of a genuine 1 is genuine.
    ///
    /// Only the 1.0 copies are offered for removal. Other `'derived'` rows copy a
    /// real rate and read as one, so they mislead nobody about this bug.
    private static func suspectRows(_ db: Database) throws -> [(currency: String, date: String)] {
        let excluded = realFallback.union(peggedToUSD).sorted()
        let marks = excluded.map { _ in "?" }.joined(separator: ",")
        return try Row.fetchAll(db, sql: """
            SELECT r.date AS d, r.currency AS c FROM exchange_rates r
            WHERE r.source = 'derived' AND r.rate = 1
              AND r.currency NOT IN (\(marks))
              AND NOT EXISTS (SELECT 1 FROM exchange_rates g
                              WHERE g.currency = r.currency AND g.rate = 1
                                AND COALESCE(g.source, '') <> 'derived')
            ORDER BY r.date, r.currency
            """, arguments: StatementArguments(excluded)).map { ($0["c"], $0["d"]) }
    }

    /// Every entry with a conversion that valued one side at one dollar, in every
    /// ledger. A posting records two kinds of conversion, X → Y at the rate r it
    /// was booked at:
    /// - an account leg in a currency other than its ledger's base (X the leg's
    ///   currency, Y the base, r = amount_base / amount);
    /// - an amount typed in a currency other than the posting's (X `orig_currency`,
    ///   Y the posting's currency, r = amount / orig_amount). Category legs carry
    ///   this too, for a purchase typed in another currency.
    ///
    /// A side "could have been unrated" when it is not USD, a static-fallback
    /// currency or a peg, and has no non-derived rate of exactly 1 (the user's own
    /// 1 is genuine). The conversion is the bug when such a side was valued at one
    /// dollar — r = 1 / hub(Y) for X, r = hub(X) for Y, r = 1 when both — and r is
    /// not simply the rate on record today (hub(X) / hub(Y)), which is what a
    /// corrected entry, or one booked after a rate came in, was booked at.
    ///
    /// One query over the postings (or one entry's, with `entryId`); each
    /// currency's rate on a date is looked up once, the way a write looks it up
    /// (`Entries.lookupRateToHub`).
    static func bookedEntries(_ db: Database, entryId: String? = nil) throws -> [Booked] {
        let excluded = realFallback.union(peggedToUSD).sorted()
        let marks = excluded.map { _ in "?" }.joined(separator: ",")
        let genuineOne = Set(try String.fetchAll(db, sql: """
            SELECT DISTINCT currency FROM exchange_rates
            WHERE rate = 1 AND COALESCE(source, '') <> 'derived'
            """))
        func couldHaveBeenUnrated(_ c: String) -> Bool {
            !realFallback.contains(c) && !peggedToUSD.contains(c) && !genuineOne.contains(c)
        }
        var hubCache: [String: Double?] = [:]
        func hub(_ c: String, _ d: String) throws -> Double? {
            let key = "\(c)|\(d)"
            if let hit = hubCache[key] { return hit }
            var h = try Entries.lookupRateToHub(db, c, d)
            if h == nil, peggedToUSD.contains(c) { h = 1 }
            hubCache[key] = h
            return h
        }
        func near(_ a: Double, _ b: Double) -> Bool { b > 0 && abs(a / b - 1) <= tolerance }

        let only = entryId == nil ? "" : "AND e.id = ?"
        let rows = try Row.fetchAll(db, sql: """
            SELECT * FROM (
                SELECT e.id AS eid, e.date AS d, p.currency AS x, l.base_currency AS y,
                       p.amount_base / p.amount AS r
                  FROM postings p
                  JOIN entries e ON e.id = p.entry_id
                  JOIN ledgers l ON l.id = e.ledger_id
                 WHERE p.account_id IS NOT NULL AND p.currency <> l.base_currency AND p.amount <> 0
                   \(only)
                UNION ALL
                SELECT e.id, e.date, p.orig_currency, p.currency, p.amount / p.orig_amount
                  FROM postings p
                  JOIN entries e ON e.id = p.entry_id
                 WHERE p.orig_currency IS NOT NULL AND p.orig_currency <> p.currency
                   AND p.orig_amount <> 0
                   \(only)
            )
            WHERE x NOT IN (\(marks)) OR y NOT IN (\(marks))
            """, arguments: StatementArguments(entryId.map { [$0, $0] } ?? []) + StatementArguments(excluded + excluded))

        var byEntry: [String: Booked] = [:]
        for row in rows {
            let eid: String = row["eid"], d: String = row["d"], x: String = row["x"], y: String = row["y"]
            guard let r: Double = row["r"], r > 0 else { continue }
            let ux = couldHaveBeenUnrated(x), uy = couldHaveBeenUnrated(y)
            guard ux || uy else { continue }
            let hx = try hub(x, d), hy = try hub(y, d)
            if let hx, let hy, hy > 0, near(r, hx / hy) { continue }   // booked at the rate on record
            var atOne = Set<String>()
            if ux, uy, near(r, 1) { atOne.formUnion([x, y]) }
            if ux, let hy, near(r * hy, 1) { atOne.insert(x) }
            if uy, let hx, near(r, hx) { atOne.insert(y) }
            guard !atOne.isEmpty else { continue }
            byEntry[eid] = Booked(entryId: eid, date: d,
                                  currencies: (byEntry[eid]?.currencies ?? []).union(atOne))
        }
        return byEntry.values.sorted { ($0.date, $0.entryId) < ($1.date, $1.entryId) }
    }

    /// Whether `entryId` is one of the entries booked at 1:1 — what a save that
    /// would otherwise keep a transfer's valuation asks first, so saving one of
    /// these again re-values it.
    public static func isBookedAtOneToOne(_ db: Database, entryId: String) throws -> Bool {
        try !bookedEntries(db, entryId: entryId).isEmpty
    }

    /// The rows a transaction list shows for `entryIds`: ONE PER ENTRY, the unit the
    /// review counts, in `txns`' order.
    ///
    /// `txns` is a projection, one row per account leg, so an entry can arrive as
    /// several rows. A split-tender purchase's legs are summed (`byPurchase`, within
    /// the entry). A transfer keeps the leg it leaves from — its legs would cancel to
    /// zero, and that leg already reads "To <account>". Not `byPurchase` over the
    /// lot: it collapses a grid purchase's entries into one row, and the list would
    /// then show fewer rows than the count.
    ///
    /// An id with no row here is not listed: the app projects only the active
    /// ledger, and no ledger projects an opening balance.
    public static func rows(_ txns: [Tx], entryIds: Set<String>) -> [Tx] {
        var order: [String] = []
        var legs: [String: [Tx]] = [:]
        for t in txns {
            guard let e = t.entryId, entryIds.contains(e) else { continue }
            if legs[e] == nil { order.append(e) }
            legs[e, default: []].append(t)
        }
        return order.compactMap { e -> Tx? in
            guard let l = legs[e] else { return nil }
            if l.first?.kind == "transfer" { return l.first { $0.amount < 0 } ?? l.first }
            return Selectors.byPurchase(l).first
        }
    }
}
