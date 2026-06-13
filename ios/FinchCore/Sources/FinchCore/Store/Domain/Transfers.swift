import Foundation
import GRDB

/// Transfers domain — port of lib/db/domain/transfers/mutations.ts.
/// DEFERRED: updateTransfer (amount-rebuild with ratio scaling via rebuildEntry).
public enum Transfers {
    public static let handlers: [ActionName: Apply.Handler] = [
        .createTransfer: create,
        .deleteTransfer: delete,
    ]

    static func create(_ db: Database, _ args: Args) throws {
        struct A: Decodable {
            let fromAccountId: String; let toAccountId: String; let fromAmount: Double
            let toAmount: Double?; let date: String; let time: String?; let note: String?; let sourceTemplateId: String?
        }
        let a = try args.to(A.self)
        try Entries.postTransfer(db, fromAccountId: a.fromAccountId, toAccountId: a.toAccountId,
                                 fromAmount: a.fromAmount, toAmount: a.toAmount, date: a.date,
                                 time: a.time, note: a.note, sourceTemplateId: a.sourceTemplateId)
    }

    static func delete(_ db: Database, _ args: Args) throws {
        struct A: Decodable { let id: String }
        guard let ref = try Entries.resolveEntryRef(db, try args.to(A.self).id) else { return }
        try Entries.deleteEntry(db, ref.entryId)
    }
}
