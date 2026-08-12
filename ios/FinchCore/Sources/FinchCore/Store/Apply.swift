import Foundation
import GRDB

/// The write chokepoint dispatcher — the iOS port's mirror of the web's
/// `lib/db/mutate.ts::applyMutation`. Each per-domain module (Tasks 3–15)
/// exposes a `handlers` map of `[ActionName: Handler]`; `registry` merges them
/// into one `ALL`-equivalent, and `apply` routes `(action, args)` to the right
/// handler inside a single write transaction. Unknown/unported actions throw a
/// translatable `I18nError`.
public enum Apply {
    /// A per-domain mutation handler: mutate the DB given the action's args.
    /// Synchronous — GRDB's `write` closure runs on the DB queue.
    public typealias Handler = (Database, Args) throws -> Void

    /// The merged handler registry. Per-domain `handlers` maps are folded in
    /// here as each domain lands (mirrors `mutate.ts`'s spread into `ALL`).
    /// Built once (was a computed `var` that rebuilt the whole map on every
    /// write — e.g. each step of a confirm-all loop).
    static let registry: [ActionName: Handler] = {
        var all: [ActionName: Handler] = [:]
        // Domains fold in their handlers as they are ported (Tasks 3–15):
        all.merge(Transactions.handlers) { _, new in new }
        all.merge(SaveTransaction.handlers) { _, new in new }
        all.merge(Counterparties.handlers) { _, new in new }
        all.merge(Tags.handlers) { _, new in new }
        all.merge(AccountGroups.handlers) { _, new in new }
        all.merge(BudgetGroups.handlers) { _, new in new }
        all.merge(Categories.handlers) { _, new in new }
        all.merge(Holdings.handlers) { _, new in new }
        all.merge(AppDomain.handlers) { _, new in new }
        all.merge(Accounts.handlers) { _, new in new }
        all.merge(Transfers.handlers) { _, new in new }
        all.merge(Interledger.handlers) { _, new in new }
        all.merge(Ledgers.handlers) { _, new in new }
        all.merge(Budgets.handlers) { _, new in new }
        all.merge(Scheduled.handlers) { _, new in new }
        all.merge(Rules.handlers) { _, new in new }
        return all
    }()

    /// Apply a single action to the database. Mirrors the web's
    /// `applyMutation(exec, action, args)`.
    public static func apply(dbQueue: DatabaseQueue, action: String, args: Args) throws {
        _ = try applyReturningId(dbQueue: dbQueue, action: action, args: args)
    }

    /// Like `apply`, but returns the new entry id for `addTransaction` (nil for
    /// every other action) so callers can attach a receipt to the fresh entry.
    public static func applyReturningId(dbQueue: DatabaseQueue, action: String, args: Args) throws -> String? {
        guard let name = ActionName(rawValue: action) else {
            throw I18nError("error.unknownAction", ["action": action], "Unknown action \"\(action)\"")
        }
        guard let handler = registry[name] else {
            throw I18nError("error.notImplemented", ["action": action],
                            "Action \"\(action)\" is not implemented on iOS yet")
        }
        return try dbQueue.write { db in
            if name == .addTransaction {
                return try Transactions.addTransactionReturningId(db, args)
            }
            // Same reason as above: the Add sheet needs the new entry id to attach
            // a receipt. Without this the switch returns nil and the receipt is
            // silently dropped — the very failure this special case exists for.
            if name == .saveTransaction {
                return try SaveTransaction.run(db, args)
            }
            try handler(db, args)
            return nil
        }
    }

    /// Like `apply`, but returns how many rows the action CREATED. Only the
    /// native-first copy actions report a real count — they dedup against the
    /// target, so "it worked" hides whether anything actually landed. Every other
    /// action returns 0; callers that care about a count only ever use these.
    public static func applyReturningCount(dbQueue: DatabaseQueue, action: String, args: Args) throws -> Int {
        guard let name = ActionName(rawValue: action) else {
            throw I18nError("error.unknownAction", ["action": action], "Unknown action \"\(action)\"")
        }
        guard let handler = registry[name] else {
            throw I18nError("error.notImplemented", ["action": action],
                            "Action \"\(action)\" is not implemented on iOS yet")
        }
        return try dbQueue.write { db in
            switch name {
            case .copyCategories: return try Categories.copyCategoriesReturningCount(db, args)
            case .copyTags:       return try Tags.copyTagsReturningCount(db, args)
            default:
                try handler(db, args)
                return 0
            }
        }
    }
}
