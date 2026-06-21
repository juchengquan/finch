import Foundation
import GRDB

/// Accounts domain — port of lib/db/domain/accounts/mutations.ts.
public enum Accounts {
    static let validTypes: Set<String> = ["savings", "credit_card", "investment", "cash", "fx", "virtual"]

    public static let handlers: [ActionName: Apply.Handler] = [
        .createAccount: create,
        .updateAccount: update,
        .archiveAccount: archive,
        .unarchiveAccount: unarchive,
        .deleteAccount: delete,
    ]

    static func create(_ db: Database, _ args: Args) throws {
        struct A: Decodable {
            let id: String?; let ledgerId: String?; let name: String; let type: String?
            let currency: String?; let groupId: String?; let openingBalance: Double?; let color: String?
        }
        let a = try args.to(A.self)
        let ledgerId = a.ledgerId ?? "personal"
        let name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw I18nError("error.required.accountName", [:], "Account name is required") }
        let type = a.type ?? "savings"
        if !validTypes.contains(type) { throw I18nError("error.account.unknownType", ["type": type], "Unknown account type \"\(type)\"") }
        let currency = a.currency ?? "SGD"
        let id = a.id ?? Entries.newId("acct")
        let sortOrder: Int
        if let g = a.groupId {
            sortOrder = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM accounts WHERE ledger_id = ? AND group_id = ?", arguments: [ledgerId, g]) ?? 0
        } else {
            sortOrder = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM accounts WHERE ledger_id = ? AND group_id IS NULL", arguments: [ledgerId]) ?? 0
        }
        let inw = type == "credit_card" ? 0 : 1
        try db.execute(sql: """
            INSERT INTO accounts (id,ledger_id,group_id,name,type,currency,current_balance,color,sort_order,include_in_net_worth,is_active,created_at,updated_at)
            VALUES (?,?,?,?,?,?,0,?,?,?,1,datetime('now'),datetime('now'))
            """, arguments: [id, ledgerId, a.groupId, name, type, currency, a.color, sortOrder, inw])
        let opening = a.openingBalance ?? 0
        if opening != 0 {
            let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
            try Entries.postOpening(db, ledgerId: ledgerId, accountId: id, amount: opening, date: today)
        }
    }

    private static let cols: [String: String] = ["name": "name", "type": "type", "color": "color", "groupId": "group_id", "includeInNetWorth": "include_in_net_worth", "sortOrder": "sort_order"]

    static func update(_ db: Database, _ args: Args) throws {
        guard let id = args.idString else { throw I18nError("error.invalidArgs", [:], "updateAccount requires an id") }
        let patch = args.patchObject
        if let nameV = patch["name"], !nameV.isNonEmptyTrimmedString { throw I18nError("error.required.accountName", [:], "Account name is required") }
        if let typeV = patch["type"], let t = typeV.asString, !validTypes.contains(t) {
            throw I18nError("error.account.unknownType", ["type": t], "Unknown account type \"\(t)\"")
        }
        var sets: [String] = []
        var bind: [DatabaseValueConvertible?] = []
        for key in ["name", "type", "color", "groupId", "includeInNetWorth", "sortOrder"] where patch.keys.contains(key) {
            sets.append("\(cols[key]!) = ?"); bind.append(patch[key]!.sqlBind)   // currency is intentionally non-patchable
        }
        if sets.isEmpty { return }
        sets.append("updated_at = datetime('now')")
        bind.append(id)
        try db.execute(sql: "UPDATE accounts SET \(sets.joined(separator: ", ")) WHERE id = ?", arguments: StatementArguments(bind))
    }

    static func archive(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        try db.execute(sql: "UPDATE accounts SET is_active = 0, archived_at = datetime('now'), updated_at = datetime('now') WHERE id = ?", arguments: [try args.to(A.self).id])
    }
    static func unarchive(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        try db.execute(sql: "UPDATE accounts SET is_active = 1, archived_at = NULL, updated_at = datetime('now') WHERE id = ?", arguments: [try args.to(A.self).id])
    }

    static func delete(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        let id = try args.to(A.self).id
        let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE account_id = ?", arguments: [id]) ?? 0
        if total > 0 {
            let openEntryId = "open-\(id)"
            let other = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM postings WHERE account_id = ? AND entry_id != ?", arguments: [id, openEntryId]) ?? 0
            if other > 0 { throw I18nError("error.account.hasTransactions", [:], "Account has transactions — archive it instead") }
            try Entries.deleteEntry(db, openEntryId)
        }
        try db.execute(sql: "DELETE FROM accounts WHERE id = ?", arguments: [id])
    }
}
