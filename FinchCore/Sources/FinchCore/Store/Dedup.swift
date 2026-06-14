import Foundation

/// Translate a SQLite UNIQUE-violation into a localized I18nError — a port of the
/// web's _shared/with-dedup-message.ts. The dedup indices cross domains (entries,
/// budgets), so this lives at the Store level and wraps the relevant handlers.
public enum Dedup {
    private static let messages: [(sig: String, code: String, msg: String)] = [
        ("entries.ledger_id, entries.dedup_hash", "error.duplicate.txn",
         "This looks like a duplicate — an identical transaction already exists."),
        ("budgets.ledger_id, budgets.name", "error.duplicate.budget",
         "A budget with this name and cycle already exists."),
    ]

    public static func wrap<T>(_ run: () throws -> T) throws -> T {
        do { return try run() }
        catch let err {
            let msg = "\(err)"
            if msg.contains("UNIQUE constraint failed") {
                for m in messages where msg.contains(m.sig) { throw I18nError(m.code, [:], m.msg) }
            }
            throw err
        }
    }
}
