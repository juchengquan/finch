import XCTest
@testable import FinchCore

/// DESIGN §8.1/§8.4 — the selector parity gate. For each Task-0 selector fixture,
/// decode the `input`, run the Swift selector, and assert it equals the web's
/// `expected` (computed by running the REAL web selector in export-fixtures.ts).
final class SelectorParityTests: XCTestCase {
    private var selectorsDir: URL {
        get throws {
            try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
                .appendingPathComponent("selectors")
        }
    }

    private func load<T: Decodable>(_ selector: String, _ type: T.Type) throws -> [(String, T)] {
        let dir = try selectorsDir.appendingPathComponent(selector)
        let files = try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty, "no fixtures for \(selector)")
        return try files.map { ($0.lastPathComponent, try JSONDecoder().decode(T.self, from: Data(contentsOf: $0))) }
    }

    func test_accountBalance() throws {
        struct F: Decodable { let expected: Double; let input: I; struct I: Decodable { let accounts: [AccountRow]; let accountId: String } }
        for (name, f) in try load("accountBalance", F.self) {
            XCTAssertEqual(Selectors.accountBalance(f.input.accounts, f.input.accountId), f.expected, name)
        }
    }

    func test_selectTransactions() throws {
        struct F: Decodable { let expected: [Tx]; let input: I; struct I: Decodable { let txns: [Tx]; let opts: ListOptions } }
        for (name, f) in try load("selectTransactions", F.self) {
            XCTAssertEqual(Selectors.selectTransactions(f.input.txns, f.input.opts), f.expected, name)
        }
    }

    func test_categorySpend() throws {
        struct F: Decodable { let expected: [String: Double]; let input: I; struct I: Decodable { let txns: [Tx]; let ledgerId: String; let month: String? } }
        for (name, f) in try load("categorySpend", F.self) {
            XCTAssertEqual(Selectors.categorySpend(f.input.txns, f.input.ledgerId, f.input.month), f.expected, name)
        }
    }

    func test_cycleWindow() throws {
        struct F: Decodable { let expected: CycleWindow; let input: I; struct I: Decodable { let frequency: String; let startDate: String; let today: String; let endDate: String?; let isRecurring: Int? } }
        for (name, f) in try load("cycleWindow", F.self) {
            let got = Selectors.cycleWindow(f.input.frequency, f.input.startDate, f.input.today, f.input.endDate, f.input.isRecurring ?? 1)
            XCTAssertEqual(got, f.expected, name)
        }
    }

    func test_budgetProgress() throws {
        struct F: Decodable { let expected: BudgetProgress; let input: I; struct I: Decodable { let budget: BudgetRow; let txns: [Tx]; let today: String; let categories: [CategoryNode]? } }
        for (name, f) in try load("budgetProgress", F.self) {
            let got = Selectors.budgetProgress(f.input.budget, f.input.txns, f.input.today, f.input.categories ?? [])
            XCTAssertEqual(got, f.expected, name)
        }
    }

    func test_merchantStats() throws {
        struct F: Decodable { let expected: [String: MerchantStats]; let input: I; struct I: Decodable { let txns: [Tx]; let ledgerId: String } }
        for (name, f) in try load("merchantStats", F.self) {
            XCTAssertEqual(Selectors.merchantStats(f.input.txns, f.input.ledgerId), f.expected, name)
        }
    }

    func test_anomalyScore() throws {
        struct F: Decodable { let expected: AnomalyScore?; let input: I
            struct I: Decodable { let tx: Tx; let stats: [String: MerchantStats]; let opts: O?
                struct O: Decodable { let minCount: Int?; let threshold: Double? } } }
        for (name, f) in try load("anomalyScore", F.self) {
            let got = Selectors.anomalyScore(f.input.tx, f.input.stats,
                minCount: f.input.opts?.minCount ?? 3, threshold: f.input.opts?.threshold ?? 2.5)
            XCTAssertEqual(got, f.expected, name)
        }
    }
}
