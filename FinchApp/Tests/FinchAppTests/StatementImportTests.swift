import XCTest
@testable import FinchApp
import FinchCore

/// Phase 4 — the pure CSV statement parser + matcher (the tested core; the
/// .fileImporter UI is a thin shell).
final class StatementImportTests: XCTestCase {
    func test_parseWithHeaderAndFormats() {
        let csv = """
        Date,Description,Amount
        2026-05-01,Coffee Shop,-6.50
        05/02/2026,"Grocery, Local","$1,234.56"
        """
        let rows = StatementCSV.parse(csv)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].date, "2026-05-01")
        XCTAssertEqual(rows[0].amount, -6.50, accuracy: 0.001)
        XCTAssertEqual(rows[1].date, "2026-05-02")               // MM/DD/YYYY normalized
        XCTAssertEqual(rows[1].description, "Grocery, Local")     // quoted comma preserved
        XCTAssertEqual(rows[1].amount, 1234.56, accuracy: 0.001)  // $ + thousands comma
    }

    func test_parsePositionalNoHeader() {
        let rows = StatementCSV.parse("2026-05-03,Gas,-40")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].description, "Gas")
        XCTAssertEqual(rows[0].amount, -40, accuracy: 0.001)
    }

    func test_matchByAmountAndDateWindow() {
        let txns = [
            Tx(id: "t1", merchant: "Coffee", amount: -6.5, account: "a1", date: "2026-05-02", nativeAmount: -6.5),
            Tx(id: "t2", merchant: "Other", amount: -99, account: "a1", date: "2026-05-02", nativeAmount: -99),
            Tx(id: "t3", merchant: "WrongAcct", amount: -6.5, account: "a2", date: "2026-05-02", nativeAmount: -6.5),
        ]
        let rows = [
            StatementRow(date: "2026-05-01", description: "Coffee Shop", amount: -6.5),  // matches t1 (1 day)
            StatementRow(date: "2026-05-01", description: "New thing", amount: -12.0),    // no match
        ]
        let res = StatementMatcher.match(rows, txns: txns, accountId: "a1", dayWindow: 3)
        XCTAssertEqual(res[0].matchedTxId, "t1")   // amount + within window + right account
        XCTAssertNil(res[1].matchedTxId)
    }
}
