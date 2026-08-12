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
        .setOpeningBalance: setOpening,
    ]

    static func create(_ db: Database, _ args: Args) throws {
        struct A: Decodable {
            let id: String?; let ledgerId: String?; let name: String; let type: String?
            let currency: String?; let groupId: String?; let openingBalance: Double?; let color: String?
            let icon: String?; let notes: String?
            let statementDay: Int?; let dueDay: Int?; let creditLimit: Double?
            let institution: String?; let accountLast4: String?
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
        // All account types default to net-worth-included (incl. credit cards),
        // so a card's debt reduces net worth and shows under Liabilities. Users
        // can still exclude an individual account via updateAccount. (Diverges
        // from the web default, which excludes credit_card.)
        let inw = 1
        try db.execute(sql: """
            INSERT INTO accounts (id,ledger_id,group_id,name,type,currency,current_balance,color,icon,notes,statement_day,due_day,credit_limit,institution,account_last4,sort_order,include_in_net_worth,is_active,created_at,updated_at)
            VALUES (?,?,?,?,?,?,0,?,?,?,?,?,?,?,?,?,?,1,datetime('now'),datetime('now'))
            """, arguments: [id, ledgerId, a.groupId, name, type, currency, a.color,
                             a.icon, a.notes, a.statementDay, a.dueDay, a.creditLimit,
                             a.institution, a.accountLast4,
                             sortOrder, inw])
        let opening = a.openingBalance ?? 0
        if opening != 0 {
            let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
            try Entries.postOpening(db, ledgerId: ledgerId, accountId: id, amount: opening, date: today)
        }
    }

    private static let cols: [String: String] = ["name": "name", "type": "type", "color": "color", "groupId": "group_id", "includeInNetWorth": "include_in_net_worth", "sortOrder": "sort_order",
                                                 "icon": "icon", "notes": "notes", "statementDay": "statement_day", "dueDay": "due_day", "creditLimit": "credit_limit",
                                                 "institution": "institution", "accountLast4": "account_last4"]

    static func update(_ db: Database, _ args: Args) throws {
        guard let id = args.idString else { throw I18nError("error.invalidArgs", [:], "updateAccount requires an id") }
        let patch = args.patchObject
        if let nameV = patch["name"], !nameV.isNonEmptyTrimmedString { throw I18nError("error.required.accountName", [:], "Account name is required") }
        if let typeV = patch["type"], let t = typeV.asString, !validTypes.contains(t) {
            throw I18nError("error.account.unknownType", ["type": t], "Unknown account type \"\(t)\"")
        }
        var sets: [String] = []
        var bind: [DatabaseValueConvertible?] = []
        // The detail fields are patchable like any other column, INCLUDING to
        // null — `.null` clears a card's statement day or an account's note,
        // which is the only way to undo setting one.
        for key in ["name", "type", "color", "groupId", "includeInNetWorth", "sortOrder",
                    "icon", "notes", "statementDay", "dueDay", "creditLimit",
                    "institution", "accountLast4"] where patch.keys.contains(key) {
            sets.append("\(cols[key]!) = ?"); bind.append(patch[key]!.sqlBind)   // currency is intentionally non-patchable
        }
        if sets.isEmpty { return }
        sets.append("updated_at = datetime('now')")
        bind.append(id)
        try db.execute(sql: "UPDATE accounts SET \(sets.joined(separator: ", ")) WHERE id = ?", arguments: StatementArguments(bind))
    }

    /// Native-first (no web counterpart): set/replace/remove the account's
    /// opening balance post-creation. `amount` is in the ACCOUNT's currency,
    /// mirroring createAccount's `openingBalance` arg. Implemented as
    /// delete + repost of the `open-<id>` entry through the existing
    /// primitives, so double-entry balance, FX conversion, balance recompute,
    /// and the pre-cleared reconcile anchor all hold by construction. The
    /// entry keeps its original date when it already exists (repricing at
    /// that date's FX), and lands on "today" when added for the first time —
    /// the same date createAccount would have stamped.
    static func setOpening(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String; let amount: Double }
        let a = try args.to(A.self)
        guard let ledgerId = try String.fetchOne(
            db, sql: "SELECT ledger_id FROM accounts WHERE id = ?", arguments: [a.id]) else {
            throw I18nError("error.notFound.account", [:], "Account not found")
        }
        let entryId = "open-\(a.id)"
        let existingDate = try String.fetchOne(
            db, sql: "SELECT date FROM entries WHERE id = ?", arguments: [entryId])
        if existingDate != nil { try Entries.deleteEntry(db, entryId) }
        if Entries.r2(a.amount) != 0 {
            let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
            try Entries.postOpening(db, ledgerId: ledgerId, accountId: a.id,
                                    amount: a.amount, date: existingDate ?? today)
        }
        try db.execute(sql: "UPDATE accounts SET updated_at = datetime('now') WHERE id = ?", arguments: [a.id])
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
