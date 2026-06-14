import XCTest
import GRDB
@testable import FinchCore

/// updateScheduled (the iOS edit sheet) + the categoryId now exposed on the
/// ScheduledTemplate projection (needed to prefill the edit form's category).
final class ScheduledEditTests: XCTestCase {
    private func seededTemplate() throws -> DatabaseQueue {
        let q = try TestSeed.base()   // l1 / a1 / c1
        try Apply.apply(dbQueue: q, action: "createScheduled", args: Args([
            "id": .string("s1"), "ledgerId": .string("l1"), "name": .string("Rent"),
            "type": .string("expense"), "amount": .double(1000), "frequency": .string("monthly"),
            "dayOfMonth": .int(1), "accountId": .string("a1"), "category": .string("c1"),
            "startDate": .string("2026-01-01"),
        ]))
        return q
    }

    func test_categoryIdIsProjected() throws {
        let q = try seededTemplate()
        let t = try Projection.scheduledTemplates(dbQueue: q, ledgerId: "l1").first { $0.id == "s1" }
        XCTAssertEqual(t?.categoryId, "c1")
    }

    func test_updateScheduled_patches() throws {
        let q = try seededTemplate()
        try Apply.apply(dbQueue: q, action: "updateScheduled", args: Args(["id": .string("s1"), "patch": .object([
            "name": .string("Mortgage"), "amount": .double(1200), "frequency": .string("weekly"),
        ])]))
        let t = try Projection.scheduledTemplates(dbQueue: q, ledgerId: "l1").first { $0.id == "s1" }!
        XCTAssertEqual(t.name, "Mortgage")
        XCTAssertEqual(t.amount ?? 0, 1200, accuracy: 0.001)
        XCTAssertEqual(t.frequency, "weekly")
    }

    func test_updateScheduled_clearsInstallmentWithNull() throws {
        let q = try seededTemplate()
        try Apply.apply(dbQueue: q, action: "updateScheduled", args: Args(["id": .string("s1"), "patch": .object(["installmentTotal": .int(12)])]))
        XCTAssertEqual(try Projection.scheduledTemplates(dbQueue: q, ledgerId: "l1").first { $0.id == "s1" }?.installmentTotal, 12)
        try Apply.apply(dbQueue: q, action: "updateScheduled", args: Args(["id": .string("s1"), "patch": .object(["installmentTotal": .null])]))
        XCTAssertNil(try Projection.scheduledTemplates(dbQueue: q, ledgerId: "l1").first { $0.id == "s1" }?.installmentTotal ?? nil)
    }
}
