import XCTest
import FinchCore
@testable import FinchApp

/// The rules behind the account-side Budgets page.
///
/// All of them exist because `budgets.account_ids` is a list WITH A WILDCARD — an empty
/// list means "every account, including ones created later". A plain multi-select would
/// get every one of these cases wrong.
final class AccountBudgetsTests: XCTestCase {

    private func budget(_ id: String, accounts: [String]) -> BudgetRow {
        BudgetRow(id: id, ledgerId: "l1", groupId: nil, name: id, type: "expense",
                  amount: 100, saved: 0, carryForward: 0, frequency: "monthly",
                  startDate: "2026-01-01", endDate: nil, isRecurring: 1, rollover: 0,
                  rolloverLimit: nil, pendingAmount: nil, lastRolledPeriod: nil,
                  accountIds: accounts, categoryIds: [], warningPct: 80)
    }

    private func account(_ id: String) -> AccountRow {
        AccountRow(id: id, balance: 0, ledgerId: "l1", name: id, type: "cash")
    }

    // MARK: what counts as "tracking this account"

    func testAWildcardBudgetTracksEveryAccountIncludingThisOne() {
        // The load-bearing case: it names no accounts, so it counts them all. Showing
        // it unticked would make the page lie about what is being counted.
        let b = budget("groceries", accounts: [])
        XCTAssertTrue(AccountBudgets.tracksEveryAccount(b))
        XCTAssertTrue(AccountBudgets.tracks(b, "amex"))
        XCTAssertTrue(AccountBudgets.tracks(b, "any-account-at-all"))
    }

    func testAScopedBudgetTracksOnlyTheAccountsItNames() {
        let b = budget("travel", accounts: ["amex", "cash"])
        XCTAssertFalse(AccountBudgets.tracksEveryAccount(b))
        XCTAssertTrue(AccountBudgets.tracks(b, "amex"))
        XCTAssertFalse(AccountBudgets.tracks(b, "savings"))
    }

    // MARK: the case that must be refused

    func testABudgetNamingOnlyThisAccountCannotHaveItRemoved() {
        // Removing the last id empties the list, and an empty list is the wildcard —
        // so "stop tracking this account" would silently become "track every account".
        let b = budget("amex-only", accounts: ["amex"])
        XCTAssertTrue(AccountBudgets.isOnlyAccount(b, "amex"))
    }

    func testTwoAccountsIsNotOnlyThisAccount() {
        let b = budget("two", accounts: ["amex", "cash"])
        XCTAssertFalse(AccountBudgets.isOnlyAccount(b, "amex"))
    }

    func testAWildcardIsNotOnlyThisAccount() {
        // A wildcard names nothing, so it is not "only this account" — it is the
        // narrowing case instead, which is allowed (with consent).
        let b = budget("all", accounts: [])
        XCTAssertFalse(AccountBudgets.isOnlyAccount(b, "amex"))
    }

    // MARK: narrowing a wildcard

    func testNarrowingListsTodaysAccountsWithoutThisOne() {
        let all = [account("amex"), account("cash"), account("savings")]
        XCTAssertEqual(AccountBudgets.narrowed(all, excluding: "amex"), ["cash", "savings"])
    }

    func testNarrowingIsSortedSoRepeatedEditsDoNotChurnTheRow() {
        let all = [account("savings"), account("amex"), account("cash")]
        XCTAssertEqual(AccountBudgets.narrowed(all, excluding: "savings"), ["amex", "cash"])
    }

    func testNarrowingTheOnlyAccountYieldsAnEmptyListWhichIsWhyItIsRefusedUpstream() {
        // Documents the trap rather than endorsing it: with one account in the ledger,
        // narrowing produces [] — the wildcard again. The page refuses to reach here,
        // and this test exists so a future refactor notices if that guard is dropped.
        let all = [account("amex")]
        XCTAssertEqual(AccountBudgets.narrowed(all, excluding: "amex"), [])
    }
}
