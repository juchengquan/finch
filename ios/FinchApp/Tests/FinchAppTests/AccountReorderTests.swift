import XCTest
@testable import FinchApp
import FinchCore

final class AccountReorderTests: XCTestCase {
    private func acct(_ id: String, _ gid: String?) -> AccountRow {
        AccountRow(id: id, balance: 0, name: id, groupId: gid, groupName: nil, sortOrder: 0)
    }
    private let groups = [AccountGroupRow(id: "g1", name: "Bank"), AccountGroupRow(id: "g2", name: "Cards")]
    // a1,a2 in g1; a3 in g2; a4 ungrouped
    private var accounts: [AccountRow] { [acct("a1","g1"), acct("a2","g1"), acct("a3","g2"), acct("a4", nil)] }

    func test_build_interleavesGroupsThenUngroupedLast() {
        let rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        XCTAssertEqual(rows.map(\.id), [
            "g:g1:Bank", "a:a1", "a:a2", "g:g2:Cards", "a:a3", "g:ungrouped:Ungrouped", "a:a4"
        ])
    }

    func test_persistencePlan_assignsGroupAndOrder() {
        let rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        let plan = AccountReorder.persistencePlan(rows)
        XCTAssertEqual(plan.groups.map { "\($0.id):\($0.order)" }, ["g1:0", "g2:1"])
        XCTAssertEqual(plan.accounts.map { "\($0.id):\($0.groupId ?? "nil"):\($0.order)" },
                       ["a1:g1:0", "a2:g1:1", "a3:g2:0", "a4:nil:0"])
    }

    func test_accountMove_acrossGroup_reparents() {
        // Move a1 (idx 1, in g1) down to just after a3 (into g2).
        var rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        // rows: 0 g1,1 a1,2 a2,3 g2,4 a3,5 ungrouped,6 a4 → move idx1 to 5 (after a3)
        rows = AccountReorder.applyMove(rows, from: IndexSet(integer: 1), to: 5)
        let plan = AccountReorder.persistencePlan(rows)
        let a1 = plan.accounts.first { $0.id == "a1" }!
        XCTAssertEqual(a1.groupId, "g2", "a1 should re-parent to g2")
    }

    func test_accountMove_cannotLandAboveFirstHeader() {
        var rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        rows = AccountReorder.applyMove(rows, from: IndexSet(integer: 4), to: 0) // a3 to very top
        if case .group = rows[0] {} else { XCTFail("row 0 must remain a header") }
    }

    func test_groupMove_movesWholeBlock_andRenumbers() {
        // Move g2 (idx 3) above g1 (to 0).
        var rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        rows = AccountReorder.applyMove(rows, from: IndexSet(integer: 3), to: 0)
        XCTAssertEqual(rows.map(\.id), [
            "g:g2:Cards", "a:a3", "g:g1:Bank", "a:a1", "a:a2", "g:ungrouped:Ungrouped", "a:a4"
        ])
        let plan = AccountReorder.persistencePlan(rows)
        XCTAssertEqual(plan.groups.map { "\($0.id):\($0.order)" }, ["g2:0", "g1:1"])
    }

    func test_ungroupedHeaderMove_isNoOp() {
        let rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        let moved = AccountReorder.applyMove(rows, from: IndexSet(integer: 5), to: 0) // ungrouped header
        XCTAssertEqual(moved.map(\.id), rows.map(\.id))
    }

    func test_realGroupMove_belowUngrouped_clampsBeforeIt() {
        // Drag g1's header (idx 0) past the Ungrouped header to the very end.
        var rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        rows = AccountReorder.applyMove(rows, from: IndexSet(integer: 0), to: rows.count)
        // g1 stays the LAST real group, still before Ungrouped (which is pinned last).
        XCTAssertEqual(rows.map(\.id), [
            "g:g2:Cards", "a:a3", "g:g1:Bank", "a:a1", "a:a2", "g:ungrouped:Ungrouped", "a:a4"
        ])
        let plan = AccountReorder.persistencePlan(rows)
        XCTAssertEqual(plan.groups.map { "\($0.id):\($0.order)" }, ["g2:0", "g1:1"])
    }

    func test_visibleRows_hidesCollapsedGroupAccounts_keepsUngrouped() {
        let rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        let vis = AccountReorder.visibleRows(rows, collapsed: ["g1"])
        XCTAssertEqual(vis.map(\.id), ["g:g1:Bank", "g:g2:Cards", "a:a3", "g:ungrouped:Ungrouped", "a:a4"])
    }

    func test_accountCount_countsPerGroup() {
        let rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        XCTAssertEqual(AccountReorder.accountCount(of: "g1", in: rows), 2)
        XCTAssertEqual(AccountReorder.accountCount(of: "g2", in: rows), 1)
    }

    func test_visibleMove_collapsedGroup_movesWholeBlock() {
        let rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        // both groups collapsed → visible: [g1, g2, Ungrouped, a4]; drag g1 (0) below g2 (dest 2)
        let out = AccountReorder.applyVisibleMove(rows, collapsed: ["g1", "g2"], from: IndexSet(integer: 0), to: 2)
        XCTAssertEqual(out.map(\.id), ["g:g2:Cards", "a:a3", "g:g1:Bank", "a:a1", "a:a2", "g:ungrouped:Ungrouped", "a:a4"])
    }

    func test_visibleMove_accountBelowCollapsedHeader_joinsThatGroupsEnd() {
        let rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        // g1 collapsed → visible: [g1, g2, a3, Ungrouped, a4]; drag a4 (vis 4) to just below g2's a3 → dest 3 (before Ungrouped)
        let out = AccountReorder.applyVisibleMove(rows, collapsed: ["g1"], from: IndexSet(integer: 4), to: 3)
        let plan = AccountReorder.persistencePlan(out)
        XCTAssertEqual(plan.accounts.first { $0.id == "a4" }?.groupId, "g2")
    }

    func test_visibleMove_noCollapse_matchesApplyMove() {
        let rows = AccountReorder.buildRows(groups: groups, accounts: accounts)
        let a = AccountReorder.applyVisibleMove(rows, collapsed: [], from: IndexSet(integer: 1), to: 5)
        let b = AccountReorder.applyMove(rows, from: IndexSet(integer: 1), to: 5)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
    }
}
