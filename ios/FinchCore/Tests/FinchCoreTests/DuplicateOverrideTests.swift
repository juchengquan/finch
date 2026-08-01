import XCTest
import GRDB
@testable import FinchCore

/// The dedup hash is a double-submit backstop: identical (date, time, description,
/// legs) in one ledger collides on `idx_entry_dedup` and the insert is refused.
///
/// That guard has no override, which makes the Add sheet's "Add anyway" a lie —
/// the sheet asks for confirmation, the user gives it, and the write still fails
/// with "This looks like a duplicate". Reproduced on the simulator by duplicating
/// a transaction twice inside the same minute.
///
/// `allowDuplicate` is the escape hatch. The unique index is declared
/// `WHERE n IS NOT NULL`, so an entry that stores no hash is simply exempt: the
/// backstop keeps working for every ordinary save.
final class DuplicateOverrideTests: XCTestCase {
    private func seededDB() throws -> DatabaseQueue {
        let q = try DatabaseQueue()
        try Migrations.runAll(on: q)
        try Apply.apply(dbQueue: q, action: "createLedger", args: Args([
            "id": .string("l1"), "name": .string("L"), "base": .string("USD")]))
        try Apply.apply(dbQueue: q, action: "createAccount", args: Args([
            "ledgerId": .string("l1"), "id": .string("a1"), "name": .string("A"),
            "type": .string("cash"), "currency": .string("USD")]))
        return q
    }

    /// Same date, time, merchant, account and amount — what the Duplicate action
    /// produces when used twice inside one minute.
    private func args(allowDuplicate: Bool? = nil) -> Args {
        var a: [String: JSONValue] = [
            "ledgerId": .string("l1"), "accountId": .string("a1"), "amount": .double(-58.2),
            "merchant": .string("Target"), "date": .string("2026-08-01"),
            "time": .string("13:01"), "skipRules": .bool(true)]
        if let allowDuplicate { a["allowDuplicate"] = .bool(allowDuplicate) }
        return Args(a)
    }

    /// The backstop itself — unchanged behaviour, pinned so the override can't
    /// quietly disable it for everyone.
    func test_identicalTransaction_isRefused() throws {
        let q = try seededDB()
        try Apply.apply(dbQueue: q, action: "addTransaction", args: args())
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "addTransaction", args: args())) { err in
            XCTAssertEqual((err as? I18nError)?.code, "error.duplicate.txn")
        }
    }

    /// The fix: a confirmed override writes.
    func test_identicalTransaction_isAllowedWhenOverridden() throws {
        let q = try seededDB()
        try Apply.apply(dbQueue: q, action: "addTransaction", args: args())
        try Apply.apply(dbQueue: q, action: "addTransaction", args: args(allowDuplicate: true))
        let n = try q.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM entries WHERE ledger_id = 'l1'") }
        XCTAssertEqual(n, 2, "the confirmed duplicate should have been written")
    }

    /// An override must not disarm the backstop for later saves.
    func test_overrideDoesNotDisarmTheGuardForSubsequentSaves() throws {
        let q = try seededDB()
        try Apply.apply(dbQueue: q, action: "addTransaction", args: args())
        try Apply.apply(dbQueue: q, action: "addTransaction", args: args(allowDuplicate: true))
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "addTransaction", args: args())) { err in
            XCTAssertEqual((err as? I18nError)?.code, "error.duplicate.txn")
        }
    }
}
