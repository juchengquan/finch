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

    // ──────────────── Phase 1.5 — batch 1: time series / deltas ────────────────

    func test_currentMonth() throws {
        struct F: Decodable { let expected: String; let input: I; struct I: Decodable { let txns: [Tx]; let ledgerId: String? } }
        for (name, f) in try load("currentMonth", F.self) {
            XCTAssertEqual(Selectors.currentMonth(f.input.txns, f.input.ledgerId), f.expected, name)
        }
    }

    func test_prevMonth() throws {
        struct F: Decodable { let expected: String; let input: I; struct I: Decodable { let month: String } }
        for (name, f) in try load("prevMonth", F.self) {
            XCTAssertEqual(Selectors.prevMonth(f.input.month), f.expected, name)
        }
    }

    func test_monthlySpending() throws {
        struct F: Decodable { let expected: [MonthlyPoint]; let input: I
            struct I: Decodable { let txns: [Tx]; let ledgerId: String; let endMonth: String; let n: Int } }
        for (name, f) in try load("monthlySpending", F.self) {
            XCTAssertEqual(Selectors.monthlySpending(f.input.txns, f.input.ledgerId, f.input.endMonth, f.input.n), f.expected, name)
        }
    }

    func test_dailySpending() throws {
        struct F: Decodable { let expected: [DailyPoint]; let input: I
            struct I: Decodable { let txns: [Tx]; let ledgerId: String; let endDate: String; let n: Int } }
        for (name, f) in try load("dailySpending", F.self) {
            XCTAssertEqual(Selectors.dailySpending(f.input.txns, f.input.ledgerId, f.input.endDate, f.input.n), f.expected, name)
        }
    }

    func test_monthlyCashflow() throws {
        struct F: Decodable { let expected: [CashflowPoint]; let input: I
            struct I: Decodable { let txns: [Tx]; let ledgerId: String; let endMonth: String; let n: Int } }
        for (name, f) in try load("monthlyCashflow", F.self) {
            XCTAssertEqual(Selectors.monthlyCashflow(f.input.txns, f.input.ledgerId, f.input.endMonth, f.input.n), f.expected, name)
        }
    }

    func test_topCategoryDeltas() throws {
        struct F: Decodable { let expected: [CategoryDelta]; let input: I
            struct I: Decodable { let txns: [Tx]; let ledgerId: String; let curMonth: String; let categories: [CategoryRef]; let count: Int? } }
        for (name, f) in try load("topCategoryDeltas", F.self) {
            XCTAssertEqual(Selectors.topCategoryDeltas(f.input.txns, f.input.ledgerId, f.input.curMonth, f.input.categories, f.input.count ?? 5), f.expected, name)
        }
    }

    // ──────────────── Phase 1.5 — batch 2: aggregates / digest ────────────────

    func test_incomeCategoryFlow() throws {
        struct F: Decodable { let expected: IncomeFlow; let input: I
            struct I: Decodable { let txns: [Tx]; let categories: [ColoredCategory]; let ledgerId: String; let month: String; let topN: Int? } }
        for (name, f) in try load("incomeCategoryFlow", F.self) {
            XCTAssertEqual(Selectors.incomeCategoryFlow(f.input.txns, f.input.categories, f.input.ledgerId, f.input.month, f.input.topN ?? 6), f.expected, name)
        }
    }

    func test_recentExpenses() throws {
        struct F: Decodable { let expected: [RecentExpense]; let input: I
            struct I: Decodable { let txns: [Tx]; let ledgerId: String; let limit: Int? } }
        for (name, f) in try load("recentExpenses", F.self) {
            XCTAssertEqual(Selectors.recentExpenses(f.input.txns, f.input.ledgerId, f.input.limit ?? 5), f.expected, name)
        }
    }

    func test_findDuplicate() throws {
        struct F: Decodable { let expected: DuplicateMatch?; let input: I
            struct I: Decodable { let txns: [Tx]; let ledgerId: String; let draft: DuplicateDraft } }
        for (name, f) in try load("findDuplicate", F.self) {
            XCTAssertEqual(Selectors.findDuplicate(f.input.txns, f.input.ledgerId, f.input.draft), f.expected, name)
        }
    }

    func test_suggestCategory() throws {
        struct F: Decodable { let expected: CategorySuggestion?; let input: I
            struct I: Decodable { let txns: [Tx]; let ledgerId: String; let description: String; let counterpartyId: String?; let opts: O?
                struct O: Decodable { let minCount: Int?; let minConfidence: Double? } } }
        for (name, f) in try load("suggestCategory", F.self) {
            let got = Selectors.suggestCategory(f.input.txns, f.input.ledgerId, f.input.description, f.input.counterpartyId,
                minCount: f.input.opts?.minCount ?? 1, minConfidence: f.input.opts?.minConfidence ?? 0.5)
            XCTAssertEqual(got, f.expected, name)
        }
    }

    func test_weeklyDigest() throws {
        struct F: Decodable { let expected: WeeklyDigest?; let input: I
            struct I: Decodable { let txns: [Tx]; let ledgerId: String; let anchor: String } }
        for (name, f) in try load("weeklyDigest", F.self) {
            XCTAssertEqual(Selectors.weeklyDigest(f.input.txns, f.input.ledgerId, f.input.anchor), f.expected, name)
        }
    }

    // ──────────────── Phase 1.5 — batch 3a: account / net worth ────────────────

    func test_netWorthByMonth() throws {
        struct F: Decodable { let expected: [MonthlyPoint]; let input: I
            struct I: Decodable { let txns: [Tx]; let accounts: [AccountRow]; let ledgerId: String; let endMonth: String; let n: Int } }
        for (name, f) in try load("netWorthByMonth", F.self) {
            XCTAssertEqual(Selectors.netWorthByMonth(f.input.txns, f.input.accounts, f.input.ledgerId, f.input.endMonth, f.input.n), f.expected, name)
        }
    }

    func test_netWorthExplained() throws {
        struct F: Decodable { let expected: [NetWorthExplained]; let input: I
            struct I: Decodable { let txns: [Tx]; let accounts: [AccountRow]; let ledgerId: String; let endMonth: String; let n: Int } }
        for (name, f) in try load("netWorthExplained", F.self) {
            XCTAssertEqual(Selectors.netWorthExplained(f.input.txns, f.input.accounts, f.input.ledgerId, f.input.endMonth, f.input.n), f.expected, name)
        }
    }

    func test_balanceSeries() throws {
        struct F: Decodable { let expected: [Double]; let input: I
            struct I: Decodable { let txns: [Tx]; let accountId: String; let currentBalance: Double } }
        for (name, f) in try load("balanceSeries", F.self) {
            XCTAssertEqual(Selectors.balanceSeries(f.input.txns, f.input.accountId, f.input.currentBalance), f.expected, name)
        }
    }

    func test_netWorthSeries() throws {
        struct F: Decodable { let expected: [Double]; let input: I
            struct I: Decodable { let txns: [Tx]; let accounts: [AccountRow]; let ledgerId: String } }
        for (name, f) in try load("netWorthSeries", F.self) {
            XCTAssertEqual(Selectors.netWorthSeries(f.input.txns, f.input.accounts, f.input.ledgerId), f.expected, name)
        }
    }

    func test_netWorthByAccountType() throws {
        struct F: Decodable { let expected: [AccountTypeBalance]; let input: I
            struct I: Decodable { let accounts: [AccountRow]; let ledgerId: String } }
        for (name, f) in try load("netWorthByAccountType", F.self) {
            XCTAssertEqual(Selectors.netWorthByAccountType(f.input.accounts, f.input.ledgerId), f.expected, name)
        }
    }

    func test_selectTransfers() throws {
        struct F: Decodable { let expected: [Transfer]; let input: I
            struct I: Decodable { let txns: [Tx]; let accounts: [AccountRow]; let ledgerId: String } }
        for (name, f) in try load("selectTransfers", F.self) {
            XCTAssertEqual(Selectors.selectTransfers(f.input.txns, f.input.accounts, f.input.ledgerId), f.expected, name)
        }
    }
}
