import XCTest
@testable import FinchCore

final class ArgsTests: XCTestCase {
    /// The web's 73 actions (was 74; `contributeBudget` removed — goal progress is
    /// transaction-derived) + Phase 6.5's native-only `setEntryAttachment`
    /// + the native-first `setBudgetOrder` + `setTrackedCurrencies`
    /// + `mergeCategory` + `mergeCategories` (native-only) = 78
    /// + `mergeCounterparty` + `mergeCounterparties` (native-only) = 80
    /// + `mergeTag` + `mergeTags` (native-only, tag merge) = 82
    /// + `copyCategories` + `copyTags` (native-first, ledger reference copy) = 84
    /// + `setOpeningBalance` (native-first, post-creation opening edit) = 85
    /// + `setCategoryOrder` (native-first — one write per category drag, so a drop
    ///   that renumbers a sibling group costs ONE reprojection and one round of
    ///   write side-effects instead of one per moved row) = 86.
    func test_actionCount() {
        XCTAssertEqual(ActionName.allCases.count, 86)
    }

    func test_actionNameRawValues() {
        XCTAssertEqual(ActionName.addTransaction.rawValue, "addTransaction")
        XCTAssertNotNil(ActionName(rawValue: "reset"))
        // setEntryAttachment is the 75th action (Phase 6.5; native-only).
        XCTAssertNotNil(ActionName(rawValue: "setEntryAttachment"))
    }

    /// Args decodes a JSON object and `to(_:)` projects it into a concrete
    /// struct — integers must survive the re-encode (not become 3.0).
    func test_argsDecodeRoundTrip() throws {
        struct AddTx: Decodable, Equatable {
            let id: String; let amount: Double; let count: Int; let pending: Bool; let note: String?
        }
        let json = #"{"id":"t1","amount":-12.5,"count":3,"pending":true,"note":null}"#
        let args = try JSONDecoder().decode(Args.self, from: Data(json.utf8))
        let decoded = try args.to(AddTx.self)
        XCTAssertEqual(decoded, AddTx(id: "t1", amount: -12.5, count: 3, pending: true, note: nil))
    }
}
