import XCTest
@testable import FinchApp

@MainActor
final class ReportPdfTests: XCTestCase {
    func test_render_producesPdfMagicBytes() {
        let model = MonthlyReportModel(
            ledgerName: "Personal", monthLabel: "May 2026",
            income: "$3,000", spent: "$1,200", net: "$1,800",
            categories: [.init(name: "Food", amount: "$400", pct: 33),
                         .init(name: "Transit", amount: "$120", pct: 10)],
            merchants: [.init(name: "Cafe", amount: "$80")],
            generatedAt: "2026-05-31")
        let data = ReportPdf.render(MonthlyReportView(model: model))
        XCTAssertNotNil(data)
        XCTAssertTrue(data!.count > 100)
        XCTAssertTrue(data!.prefix(5).elementsEqual(Array("%PDF-".utf8)))
    }

    func test_render_emptySections_stillRenders() {
        let model = MonthlyReportModel(
            ledgerName: "Personal", monthLabel: "May 2026",
            income: "$0", spent: "$0", net: "$0",
            categories: [], merchants: [], generatedAt: "2026-05-31")
        XCTAssertNotNil(ReportPdf.render(MonthlyReportView(model: model)))
    }
}
