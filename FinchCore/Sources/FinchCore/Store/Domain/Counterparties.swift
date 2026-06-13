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
    ]

    static func createCounterparty(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String?; let ledgerId: String?; let name: String }
        let a = try args.to(A.self)
        let name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw I18nError("error.required.merchantName", [:], "Merchant name is required") }
        try db.execute(sql: "INSERT INTO counterparties (id,ledger_id,name,is_verified,created_at,updated_at) VALUES (?,?,?,0,datetime('now'),datetime('now'))",
                       arguments: [a.id ?? Entries.newId("cp"), a.ledgerId ?? "personal", name])
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
}
