import XCTest
import GRDB
@testable import FinchCore

/// DESIGN §8.2 — the audit parity gate. For each of Task 0's 10 audit-corruption
/// fixtures, open the `.sqlite3`, run the Swift `Audit`, and assert it returns
/// EXACTLY the problem set the web's `auditLedger` recorded in the sibling JSON.
/// The fixtures were generated scoped to ledger `l1` with `checkBalances: true`.
final class AuditParityTests: XCTestCase {
    private struct ExpectedFixture: Decodable {
        let code: String
        let expected: [Audit.AuditProblem]
    }

    private static let codes = [
        "unsealed", "unbalanced", "too-few-legs", "no-account-leg", "currency-mismatch",
        "cross-ledger", "base-identity", "kind-shape", "trial-balance", "balance-drift",
    ]

    func test_allAuditFixturesMatchTheWebOracle() throws {
        let auditDir = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            .appendingPathComponent("audit")

        for code in Self.codes {
            let dbURL = auditDir.appendingPathComponent("\(code).sqlite3")
            let jsonURL = auditDir.appendingPathComponent("\(code)__corrupt.json")
            let fixture = try JSONDecoder().decode(ExpectedFixture.self, from: Data(contentsOf: jsonURL))

            let dbQueue = try DatabaseQueue(path: dbURL.path)
            let actual = try Audit.run(on: dbQueue, ledgerId: "l1", checkBalances: true)

            // Compare as sets — the web pushes per-check, but SQL row order within
            // a check is unspecified, so parity is order-independent.
            XCTAssertEqual(
                Set(actual), Set(fixture.expected),
                "audit parity mismatch for '\(code)'\n  web:   \(fixture.expected)\n  swift: \(actual)"
            )
            // Sanity: the fixture's primary code is present.
            XCTAssertTrue(actual.contains { $0.code.rawValue == code },
                          "fixture '\(code)' did not produce its primary code")
        }
    }
}
