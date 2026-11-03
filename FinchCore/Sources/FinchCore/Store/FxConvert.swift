import Foundation
import GRDB

/// A conversion the way a write would make it, for readers outside a write — the
/// account forecast valuing the far side of a scheduled transfer.
///
/// It is `Entries.convertToBase`, the lookup every posting uses, not a copy of it:
/// a forecast that credits a different figure from the one the transfer books
/// would be wrong by exactly that difference.
public enum FxConvert {
    /// `amount` in `from`, as `to`, on `date` (rounded to the cent, as posting
    /// rounds it). nil when either currency has no rate — where posting refuses.
    public static func convert(_ db: Database, _ amount: Double, from: String, to: String,
                               on date: String) throws -> Double? {
        do { return try Entries.convertToBase(db, amount, from, to, date).amountBase }
        catch let e as I18nError where e.code == "error.fx.noRate" { return nil }
    }

    /// The same, reading `dbQueue`. nil also when the read fails.
    public static func convert(dbQueue: DatabaseQueue, _ amount: Double, from: String, to: String,
                               on date: String) -> Double? {
        (try? dbQueue.read { try convert($0, amount, from: from, to: to, on: date) }) ?? nil
    }
}
