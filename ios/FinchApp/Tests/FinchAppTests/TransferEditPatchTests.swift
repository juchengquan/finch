import XCTest
@testable import FinchApp
import FinchCore

/// The Edit sheet's transfer save path builds an updateTransfer patch from the
/// edited fields — pure, so the inclusion rules are unit-tested here.
final class TransferEditPatchTests: XCTestCase {
    private func inputs(sameCurrency: Bool = true,
                        originalFrom: Double = 100, originalTo: Double = 100,
                        editedFrom: String = "100", editedTo: String? = nil,
                        originalDate: String = "2026-07-01", originalTime: String? = "12:00",
                        originalNote: String? = nil,
                        newDate: String = "2026-07-01", newTime: String = "12:00",
                        newNote: String = "") -> TransferEditPatch.Inputs {
        TransferEditPatch.Inputs(sameCurrency: sameCurrency,
                                 originalFrom: originalFrom, originalTo: originalTo,
                                 editedFrom: editedFrom, editedTo: editedTo,
                                 originalDate: originalDate, originalTime: originalTime,
                                 originalNote: originalNote,
                                 newDate: newDate, newTime: newTime, newNote: newNote)
    }

    func test_unchanged_producesEmptyPatch() throws {
        let patch = try TransferEditPatch.build(inputs()).get()
        XCTAssertTrue(patch.isEmpty)
    }

    func test_sameCurrency_amountChange_sendsFromAmountOnly() throws {
        let patch = try TransferEditPatch.build(inputs(editedFrom: "150")).get()
        XCTAssertEqual(patch["fromAmount"]?.asDouble, 150)
        XCTAssertNil(patch["toAmount"])
    }

    func test_crossCurrency_bothChanged_sendsBoth() throws {
        let patch = try TransferEditPatch.build(inputs(sameCurrency: false,
            originalFrom: 100, originalTo: 92, editedFrom: "110", editedTo: "101")).get()
        XCTAssertEqual(patch["fromAmount"]?.asDouble, 110)
        XCTAssertEqual(patch["toAmount"]?.asDouble, 101)
    }

    func test_crossCurrency_onlyToChanged_sendsToOnly() throws {
        let patch = try TransferEditPatch.build(inputs(sameCurrency: false,
            originalFrom: 100, originalTo: 92, editedFrom: "100", editedTo: "95")).get()
        XCTAssertNil(patch["fromAmount"])
        XCTAssertEqual(patch["toAmount"]?.asDouble, 95)
    }

    func test_badAmount_fails() {
        XCTAssertEqual(TransferEditPatch.build(inputs(editedFrom: "0")), .failure(.badAmount))
        XCTAssertEqual(TransferEditPatch.build(inputs(editedFrom: "abc")), .failure(.badAmount))
        XCTAssertEqual(TransferEditPatch.build(inputs(sameCurrency: false, editedTo: nil)),
                       .failure(.badAmount))
    }

    func test_dateTimeNote_inclusionRules() throws {
        var patch = try TransferEditPatch.build(inputs(newDate: "2026-07-02")).get()
        XCTAssertEqual(patch["date"]?.asString, "2026-07-02")
        patch = try TransferEditPatch.build(inputs(newTime: "13:30")).get()
        XCTAssertEqual(patch["time"]?.asString, "13:30")
        patch = try TransferEditPatch.build(inputs(newNote: "hello")).get()
        XCTAssertEqual(patch["note"]?.asString, "hello")
        // Clearing an existing note sends explicit null.
        patch = try TransferEditPatch.build(inputs(originalNote: "old", newNote: "")).get()
        XCTAssertEqual(patch["note"], JSONValue.null)
        // nil original time == "" new time → no time key.
        patch = try TransferEditPatch.build(inputs(originalTime: nil, newTime: "")).get()
        XCTAssertNil(patch["time"])
    }
}
