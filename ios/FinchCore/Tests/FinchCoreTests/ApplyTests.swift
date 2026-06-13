import XCTest
import GRDB
@testable import FinchCore

final class ApplyTests: XCTestCase {
    private func freshDB() throws -> DatabaseQueue {
        let q = try DatabaseQueue()        // in-memory
        try Migrations.runAll(on: q)
        return q
    }

    func test_unknownActionThrowsI18n() throws {
        let q = try freshDB()
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "nonExistentAction", args: Args([:]))) { err in
            guard let e = err as? I18nError else { return XCTFail("expected I18nError") }
            XCTAssertEqual(e.code, "error.unknownAction")
            XCTAssertEqual(e.params["action"], "nonExistentAction")
        }
    }

    func test_unportedActionThrowsNotImplemented() throws {
        let q = try freshDB()
        // addTransaction is a real action, but no domain handler is registered yet.
        XCTAssertThrowsError(try Apply.apply(dbQueue: q, action: "addTransaction", args: Args([:]))) { err in
            guard let e = err as? I18nError else { return XCTFail("expected I18nError") }
            XCTAssertEqual(e.code, "error.notImplemented")
        }
    }
}
