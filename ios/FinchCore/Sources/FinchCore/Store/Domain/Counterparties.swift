import Foundation
import GRDB

/// Counterparties domain — port of lib/db/domain/counterparties/mutations.ts.
public enum Counterparties {
    public static let handlers: [ActionName: Apply.Handler] = [
        .createCounterparty: createCounterparty,
        .updateCounterparty: updateCounterparty,
        .deleteCounterparty: deleteCounterparty,
        .verifyCounterparty: verify,
        .unverifyCounterparty: unverify,
        .mergeCounterparty: merge,
        .mergeCounterparties: mergeMany,
    ]

    static func createCounterparty(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String?; let name: String }
        let a = try args.to(A.self)
        let name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw I18nError("error.required.merchantName", [:], "Merchant name is required") }
        try db.execute(sql: "INSERT INTO counterparties (id,name,is_verified,created_at,updated_at) VALUES (?,?,0,datetime('now'),datetime('now'))",
                       arguments: [a.id ?? Entries.newId("cp"), name])
    }

    static func updateCounterparty(_ db: Database, _ args: Args) throws {
        guard case .string(let id)? = args.values["id"] else { throw I18nError("error.invalidArgs", [:], "updateCounterparty requires an id") }
        guard case .object(let patch)? = args.values["patch"], let nameV = patch["name"] else { return }   // name-only patch
        guard case .string(let name) = nameV, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw I18nError("error.required.merchantName", [:], "Merchant name is required")
        }
        try db.execute(sql: "UPDATE counterparties SET name = ?, updated_at = datetime('now') WHERE id = ?", arguments: [name, id])
    }

    static func deleteCounterparty(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        try db.execute(sql: "DELETE FROM counterparties WHERE id = ?", arguments: [try args.to(A.self).id])
    }

    static func verify(_ db: Database, _ args: Args) throws { try setVerified(db, args, 1) }
    static func unverify(_ db: Database, _ args: Args) throws { try setVerified(db, args, 0) }
    private static func setVerified(_ db: Database, _ args: Args, _ v: Int) throws {
        struct A: Decodable { let id: String }
        try db.execute(sql: "UPDATE counterparties SET is_verified = ?, updated_at = datetime('now') WHERE id = ?",
                       arguments: [v, try args.to(A.self).id])
    }

    static func merge(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let sourceId: String; let targetId: String }
        let a = try args.to(A.self)
        try validateMerge(db, source: a.sourceId, target: a.targetId)
        try mergeOne(db, source: a.sourceId, target: a.targetId)
        try db.execute(sql: "DELETE FROM counterparties WHERE id = ?", arguments: [a.sourceId])
    }

    /// Combine many `sourceIds` into `targetId` in one transaction (Apply wraps).
    /// All sources are validated up-front, so a bad one aborts the whole set.
    static func mergeMany(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let sourceIds: [String]; let targetId: String }
        let a = try args.to(A.self)
        if a.sourceIds.isEmpty {
            throw I18nError("error.invalidArgs", [:], "mergeCounterparties requires at least one source")
        }
        for source in a.sourceIds { try validateMerge(db, source: source, target: a.targetId) }
        for source in a.sourceIds { try mergeOne(db, source: source, target: a.targetId) }
        for source in a.sourceIds {
            try db.execute(sql: "DELETE FROM counterparties WHERE id = ?", arguments: [source])
        }
    }

    /// Repoint transactions linked to `source` (by counterparty_id) onto `target`.
    /// Does NOT validate or delete `source`. Runs inside the caller's transaction.
    private static func mergeOne(_ db: Database, source: String, target: String) throws {
        try db.execute(sql: "UPDATE entries SET counterparty_id = ? WHERE counterparty_id = ?", arguments: [target, source])
    }

    /// Guards for a single source→target merge: not-self, both exist. Merchants are
    /// global (no ledger_id), so there is no same-ledger guard.
    private static func validateMerge(_ db: Database, source: String, target: String) throws {
        if source == target {
            throw I18nError("error.counterparty.mergeSelf", [:], "Cannot merge a merchant into itself")
        }
        guard try String.fetchOne(db, sql: "SELECT id FROM counterparties WHERE id = ?", arguments: [source]) != nil,
              try String.fetchOne(db, sql: "SELECT id FROM counterparties WHERE id = ?", arguments: [target]) != nil else {
            throw I18nError("error.notFound.counterparty", [:], "Merchant does not exist")
        }
    }
}
