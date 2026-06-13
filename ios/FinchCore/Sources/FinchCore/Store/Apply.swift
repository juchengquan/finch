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
    static var registry: [ActionName: Handler] {
        var all: [ActionName: Handler] = [:]
        // Domains fold in their handlers as they are ported (Tasks 3–15):
        all.merge(Transactions.handlers) { _, new in new }
        return all
    }

    /// Apply a single action to the database. Mirrors the web's
    /// `applyMutation(exec, action, args)`.
    public static func apply(dbQueue: DatabaseQueue, action: String, args: Args) throws {
        guard let name = ActionName(rawValue: action) else {
            throw I18nError("error.unknownAction", ["action": action], "Unknown action \"\(action)\"")
        }
        guard let handler = registry[name] else {
            throw I18nError("error.notImplemented", ["action": action],
                            "Action \"\(action)\" is not implemented on iOS yet")
        }
        try dbQueue.write { db in try handler(db, args) }
    }
}
