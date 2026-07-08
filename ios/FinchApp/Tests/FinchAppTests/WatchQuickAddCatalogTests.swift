import XCTest
import FinchCore
@testable import FinchApp

final class WatchQuickAddCatalogTests: XCTestCase {
    private let since = "2026-04-01"

    private func account(_ id: String, name: String, ledger: String = "l1", active: Bool = true) -> AccountRow {
        AccountRow(id: id, balance: 0, ledgerId: ledger, isActive: active, name: name)
    }
    private func category(_ id: String, _ name: String, kind: String = "expense", ledger: String = "l1") -> CategoryRow {
        CategoryRow(id: id, ledgerId: ledger, name: name, parentId: nil, kind: kind)
    }
    private func expense(_ account: String, _ cat: String?, _ date: String, ledger: String = "l1") -> Tx {
        Tx(id: UUID().uuidString, merchant: "M", category: cat, amount: -10,
           account: account, date: date, ledgerId: ledger, kind: "expense")
    }

    func test_defaultAccount_isMostUsed_categoriesRankedByUse() throws {
        let accounts = [account("a1", name: "Cash"), account("a2", name: "Card")]
        let cats = [category("c1", "Food"), category("c2", "Transit"), category("c3", "Fun")]
        // a2 used twice, a1 once; c3 twice, c1 once.
        let txns = [expense("a2", "c3", "2026-05-01"), expense("a2", "c3", "2026-05-02"),
                    expense("a1", "c1", "2026-05-03")]
        let cat = try XCTUnwrap(QuickAddCatalogBuilder.build(
            ledgerId: "l1", accounts: accounts, txns: txns, categories: cats, since: since))
        XCTAssertEqual(cat.accountId, "a2")
        XCTAssertEqual(cat.accountName, "Card")
        XCTAssertEqual(cat.categories.map(\.id), ["c3", "c1", "c2"])
    }

    func test_fallbacks_noHistory_firstActiveAccount_firstSixCategories() throws {
        let accounts = [account("arch", name: "Old", active: false), account("a1", name: "Cash")]
        let cats = (1...8).map { category("c\($0)", "Cat\($0)") } + [category("inc", "Salary", kind: "income")]
        let cat = try XCTUnwrap(QuickAddCatalogBuilder.build(
            ledgerId: "l1", accounts: accounts, txns: [], categories: cats, since: since))
        XCTAssertEqual(cat.accountId, "a1")                       // archived skipped
        XCTAssertEqual(cat.categories.count, 6)                   // capped
        XCTAssertEqual(cat.categories.first?.id, "c1")            // original order
        XCTAssertFalse(cat.categories.contains { $0.id == "inc" })  // expense-only
    }

    func test_ignoresPendingOldOtherLedgerAndNonExpense() throws {
        let accounts = [account("a1", name: "Cash"), account("a2", name: "Card")]
        let cats = [category("c1", "Food")]
        var pendingTx = expense("a2", "c1", "2026-05-01"); pendingTx.pending = true
        let txns = [pendingTx,
                    expense("a2", "c1", "2026-01-01"),                   // before `since`
                    expense("a2", "c1", "2026-05-01", ledger: "other"),  // other ledger
                    Tx(id: "i1", merchant: "Pay", category: nil, amount: 500,
                       account: "a2", date: "2026-05-01", ledgerId: "l1", kind: "income"),
                    expense("a1", "c1", "2026-05-02")]                   // the only qualifying row
        let cat = try XCTUnwrap(QuickAddCatalogBuilder.build(
            ledgerId: "l1", accounts: accounts, txns: txns, categories: cats, since: since))
        XCTAssertEqual(cat.accountId, "a1")
    }

    func test_noAccounts_returnsNil() {
        XCTAssertNil(QuickAddCatalogBuilder.build(
            ledgerId: "l1", accounts: [], txns: [], categories: [], since: since))
    }
}
