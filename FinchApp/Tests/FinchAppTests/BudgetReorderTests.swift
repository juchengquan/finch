import XCTest
@testable import FinchApp
import FinchCore

final class BudgetReorderTests: XCTestCase {
    private func bgt(_ id: String, _ gid: String?) -> BudgetRow {
        BudgetRow(id: id, ledgerId: "l1", groupId: gid, name: id, type: "spending",
                  amount: 0, saved: 0, carryForward: 0, frequency: "monthly",
                  startDate: "2026-01-01", endDate: nil, isRecurring: 0, rollover: 0,
                  rolloverLimit: nil, pendingAmount: nil, lastRolledPeriod: nil,
                  accountIds: [], categoryIds: [], warningPct: 80)
    }
    private let groups = [GroupRow(id: "g1", name: "Bank"), GroupRow(id: "g2", name: "Cards")]
    // b1,b2 in g1; b3 in g2; b4 ungrouped
    private var budgets: [BudgetRow] { [bgt("b1","g1"), bgt("b2","g1"), bgt("b3","g2"), bgt("b4", nil)] }

    func test_build_interleavesGroupsThenUngroupedLast() {
        let rows = BudgetReorder.buildRows(groups: groups, budgets: budgets)
        XCTAssertEqual(rows.map(\.id), [
            "g:g1:Bank", "i:b1", "i:b2", "g:g2:Cards", "i:b3", "g:ungrouped:Ungrouped", "i:b4"
        ])
    }

    func test_plan_assignsGroupAndOrder() {
        let rows = BudgetReorder.buildRows(groups: groups, budgets: budgets)
        let plan = BudgetReorder.plan(rows)
        XCTAssertEqual(plan.groups.map { "\($0.id):\($0.order)" }, ["g1:0", "g2:1"])
        XCTAssertEqual(plan.items.map { "\($0.id):\($0.groupId ?? "nil"):\($0.order)" },
                       ["b1:g1:0", "b2:g1:1", "b3:g2:0", "b4:nil:0"])
    }

    func test_itemMove_acrossGroup_reparents() {
        // Move b1 (idx 1, in g1) down to just after b3 (into g2).
        var rows = BudgetReorder.buildRows(groups: groups, budgets: budgets)
        // rows: 0 g1,1 b1,2 b2,3 g2,4 b3,5 ungrouped,6 b4 → move idx1 to 5 (after b3)
        rows = BudgetReorder.applyMove(rows, from: IndexSet(integer: 1), to: 5)
        let plan = BudgetReorder.plan(rows)
        let b1 = plan.items.first { $0.id == "b1" }!
        XCTAssertEqual(b1.groupId, "g2", "b1 should re-parent to g2")
    }

    func test_itemMove_cannotLandAboveFirstHeader() {
        var rows = BudgetReorder.buildRows(groups: groups, budgets: budgets)
        rows = BudgetReorder.applyMove(rows, from: IndexSet(integer: 4), to: 0) // b3 to very top
        if case .group = rows[0] {} else { XCTFail("row 0 must remain a header") }
    }

    func test_groupMove_movesWholeBlock_andRenumbers() {
        // Move g2 (idx 3) above g1 (to 0).
        var rows = BudgetReorder.buildRows(groups: groups, budgets: budgets)
        rows = BudgetReorder.applyMove(rows, from: IndexSet(integer: 3), to: 0)
        XCTAssertEqual(rows.map(\.id), [
            "g:g2:Cards", "i:b3", "g:g1:Bank", "i:b1", "i:b2", "g:ungrouped:Ungrouped", "i:b4"
        ])
        let plan = BudgetReorder.plan(rows)
        XCTAssertEqual(plan.groups.map { "\($0.id):\($0.order)" }, ["g2:0", "g1:1"])
    }

    func test_ungroupedHeaderMove_isNoOp() {
        let rows = BudgetReorder.buildRows(groups: groups, budgets: budgets)
        let moved = BudgetReorder.applyMove(rows, from: IndexSet(integer: 5), to: 0) // ungrouped header
        XCTAssertEqual(moved.map(\.id), rows.map(\.id))
    }

    func test_realGroupMove_belowUngrouped_clampsBeforeIt() {
        // Drag g1's header (idx 0) past the Ungrouped header to the very end.
        var rows = BudgetReorder.buildRows(groups: groups, budgets: budgets)
        rows = BudgetReorder.applyMove(rows, from: IndexSet(integer: 0), to: rows.count)
        // g1 stays the LAST real group, still before Ungrouped (which is pinned last).
        XCTAssertEqual(rows.map(\.id), [
            "g:g2:Cards", "i:b3", "g:g1:Bank", "i:b1", "i:b2", "g:ungrouped:Ungrouped", "i:b4"
        ])
        let plan = BudgetReorder.plan(rows)
        XCTAssertEqual(plan.groups.map { "\($0.id):\($0.order)" }, ["g2:0", "g1:1"])
    }

    func test_visibleRows_hidesCollapsedGroupItems_keepsUngrouped() {
        let rows = BudgetReorder.buildRows(groups: groups, budgets: budgets)
        let vis = BudgetReorder.visibleRows(rows, collapsed: ["g1"])
        XCTAssertEqual(vis.map(\.id), ["g:g1:Bank", "g:g2:Cards", "i:b3", "g:ungrouped:Ungrouped", "i:b4"])
    }

    func test_itemCount_countsPerGroup() {
        let rows = BudgetReorder.buildRows(groups: groups, budgets: budgets)
        XCTAssertEqual(BudgetReorder.itemCount(of: "g1", in: rows), 2)
        XCTAssertEqual(BudgetReorder.itemCount(of: "g2", in: rows), 1)
    }

    func test_visibleMove_collapsedGroup_movesWholeBlock() {
        let rows = BudgetReorder.buildRows(groups: groups, budgets: budgets)
        // both groups collapsed → visible: [g1, g2, Ungrouped, b4]; drag g1 (0) below g2 (dest 2)
        let out = BudgetReorder.applyVisibleMove(rows, collapsed: ["g1", "g2"], from: IndexSet(integer: 0), to: 2)
        XCTAssertEqual(out.map(\.id), ["g:g2:Cards", "i:b3", "g:g1:Bank", "i:b1", "i:b2", "g:ungrouped:Ungrouped", "i:b4"])
    }

    func test_visibleMove_itemBelowCollapsedHeader_joinsThatGroupsEnd() {
        let rows = BudgetReorder.buildRows(groups: groups, budgets: budgets)
        // g1 collapsed → visible: [g1, g2, b3, Ungrouped, b4]; drag b4 (vis 4) to just below g2's b3 → dest 3 (before Ungrouped)
        let out = BudgetReorder.applyVisibleMove(rows, collapsed: ["g1"], from: IndexSet(integer: 4), to: 3)
        let plan = BudgetReorder.plan(out)
        XCTAssertEqual(plan.items.first { $0.id == "b4" }?.groupId, "g2")
    }

    func test_visibleMove_noCollapse_matchesApplyMove() {
        let rows = BudgetReorder.buildRows(groups: groups, budgets: budgets)
        let a = BudgetReorder.applyVisibleMove(rows, collapsed: [], from: IndexSet(integer: 1), to: 5)
        let b = BudgetReorder.applyMove(rows, from: IndexSet(integer: 1), to: 5)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
    }
}
