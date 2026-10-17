import XCTest
@testable import FinchApp
import FinchCore

final class MonthGroupingTests: XCTestCase {
    private func tx(_ id: String, _ date: String, amount: Double = -10) -> Tx {
        Tx(id: id, merchant: "m", amount: amount, account: "a", date: date)
    }

    func test_sections_groupByMonth_preservingOrder() {
        // date-descending input across two months
        let input = [tx("1", "2026-09-20"), tx("2", "2026-09-05"), tx("3", "2026-08-31")]
        let s = MonthGrouping.sections(input)
        XCTAssertEqual(s.map(\.id), ["2026-09", "2026-08"])        // newest month first, order preserved
        XCTAssertEqual(s[0].txns.map(\.id), ["1", "2"])
        XCTAssertEqual(s[1].txns.map(\.id), ["3"])
    }

    func test_sections_interleavedMonths_firstOccurrenceOrder_andAppends() {
        // interleaved input: a wrong "sort section keys descending" impl would still
        // pass the date-monotonic test above, but would fail this one.
        let input = [tx("1", "2026-09-20"), tx("2", "2026-08-15"),
                     tx("3", "2026-09-05"), tx("4", "2026-07-30")]
        let s = MonthGrouping.sections(input)
        XCTAssertEqual(s.map(\.id), ["2026-09", "2026-08", "2026-07"])   // first-occurrence order, not sorted
        XCTAssertEqual(s[0].txns.map(\.id), ["1", "3"])                  // both Sep txns, appended in order
    }

    func test_sections_singleMonth_oneSection() {
        let s = MonthGrouping.sections([tx("1", "2026-09-20"), tx("2", "2026-09-01")])
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].id, "2026-09")
    }

    func test_sections_empty_isEmpty() {
        XCTAssertTrue(MonthGrouping.sections([]).isEmpty)
    }

    func test_dailyIncomeExpense_splitsBySign_perDay() {
        let d = MonthGrouping.dailyIncomeExpense([
            tx("1", "2026-09-20", amount: -42.18),
            tx("2", "2026-09-20", amount: 4_200),
            tx("3", "2026-09-20", amount: -10),
            tx("4", "2026-09-05", amount: -53.20),
        ])
        XCTAssertEqual(d["2026-09-20"]?.income, 4_200)
        XCTAssertEqual(d["2026-09-20"]?.expense ?? 0, 52.18, accuracy: 0.001)
        XCTAssertEqual(d["2026-09-05"]?.income, 0)
        XCTAssertEqual(d["2026-09-05"]?.expense ?? 0, 53.20, accuracy: 0.001)
        XCTAssertNil(d["2026-09-01"])           // no txns → absent, not zero
    }

    func test_label_wideMonthAndYear() {
        // en locale renders the wide month + year; assert the year is present and it isn't the raw key
        let out = MonthGrouping.label("2026-09")
        XCTAssertTrue(out.contains("2026"))
        XCTAssertNotEqual(out, "2026-09")
    }

    func test_label_malformedKey_returnsKey() {
        XCTAssertEqual(MonthGrouping.label("not-a-date"), "not-a-date")
    }

    func test_net_sumsSignedBaseAmounts() {
        let s = MonthGrouping.net([tx("1", "2026-09-01", amount: -54.20),
                                   tx("2", "2026-09-02", amount: 3200)])
        XCTAssertEqual(s, 3145.80, accuracy: 0.001)
    }

    func test_net_empty_isZero() {
        XCTAssertEqual(MonthGrouping.net([]), 0)
    }

    func test_incomeAndExpense_splitBySign_identityWithNet() {
        let txns = [tx("1", "2026-09-01", amount: -54.20),
                    tx("2", "2026-09-02", amount: 3200),
                    tx("3", "2026-09-03", amount: -145.80),
                    tx("4", "2026-09-04", amount: 500)]
        XCTAssertEqual(MonthGrouping.income(txns), 3700, accuracy: 0.001)
        XCTAssertEqual(MonthGrouping.expense(txns), 200, accuracy: 0.001)   // positive magnitude
        XCTAssertEqual(MonthGrouping.income(txns) - MonthGrouping.expense(txns),
                       MonthGrouping.net(txns), accuracy: 0.001)            // in − out == net
    }

    func test_incomeAndExpense_empty_areZero() {
        XCTAssertEqual(MonthGrouping.income([]), 0)
        XCTAssertEqual(MonthGrouping.expense([]), 0)
    }

    // MARK: - Transfers between your own accounts

    /// One leg of a two-account transfer, as the projection stamps it.
    private func leg(_ id: String, _ account: String, _ amount: Double,
                     group: String = "t1", date: String = "2026-09-10") -> Tx {
        Tx(id: id, merchant: "", amount: amount, account: account, date: date,
           kind: "transfer", transferGroupId: group, accountLegCount: 2)
    }

    /// The reported bug: a $250 Checking → Savings transfer added $250 to the
    /// ledger-wide month's in AND its out. Both legs are in the rows being summed, so
    /// the money never left them — it is neither in nor out.
    func test_transferWithBothLegsPresent_countsInNeitherInNorOut() {
        let txns = [tx("1", "2026-09-01", amount: 3200), tx("2", "2026-09-02", amount: -54.20),
                    leg("t-out", "checking", -250), leg("t-in", "savings", 250)]
        XCTAssertEqual(MonthGrouping.income(txns), 3200, accuracy: 0.001)
        XCTAssertEqual(MonthGrouping.expense(txns), 54.20, accuracy: 0.001)
        XCTAssertEqual(MonthGrouping.net(txns), 3145.80, accuracy: 0.001)
        XCTAssertEqual(MonthGrouping.income(txns) - MonthGrouping.expense(txns),
                       MonthGrouping.net(txns), accuracy: 0.001)            // identity still holds
    }

    /// One account's list holds one leg, and for that account the money really did
    /// arrive or leave — so it counts, on the side it moved.
    func test_transferWithOneLegPresent_countsOnItsSide() {
        let checking = [tx("1", "2026-09-02", amount: -54.20), leg("t-out", "checking", -250)]
        XCTAssertEqual(MonthGrouping.expense(checking), 304.20, accuracy: 0.001)
        XCTAssertEqual(MonthGrouping.net(checking), -304.20, accuracy: 0.001)
        let savings = [leg("t-in", "savings", 250)]
        XCTAssertEqual(MonthGrouping.income(savings), 250, accuracy: 0.001)
        XCTAssertEqual(MonthGrouping.expense(savings), 0)
    }

    /// Pairing is per transfer: a transfer with only one leg showing still counts,
    /// while the complete one beside it does not.
    func test_onlyCompleteTransfersAreDropped() {
        let txns = [leg("a-out", "checking", -250, group: "a"), leg("a-in", "savings", 250, group: "a"),
                    leg("b-out", "checking", -40, group: "b")]
        XCTAssertEqual(MonthGrouping.income(txns), 0)
        XCTAssertEqual(MonthGrouping.expense(txns), 40, accuracy: 0.001)
    }

    /// The calendar's day cells sum the same rows as the month header, so they follow
    /// the same rule — otherwise the day reads +$250 / −$250 under a header that says 0.
    func test_dailyIncomeExpense_dropsCompleteTransfers() {
        let d = MonthGrouping.dailyIncomeExpense([
            tx("1", "2026-09-10", amount: -12), leg("t-out", "checking", -250), leg("t-in", "savings", 250),
        ])
        XCTAssertEqual(d["2026-09-10"]?.income, 0)
        XCTAssertEqual(d["2026-09-10"]?.expense ?? 0, 12, accuracy: 0.001)
    }

    // MARK: - Transfer peers (the row title's "To Savings" / "From Checking")

    func test_transferPeers_eachLegNamesTheOtherAccount() {
        let peers = TransferLegs.peers([
            leg("t-out", "checking", -250), leg("t-in", "savings", 250), tx("1", "2026-09-10"),
        ])
        XCTAssertEqual(peers["t-out"], "savings")
        XCTAssertEqual(peers["t-in"], "checking")
        XCTAssertNil(peers["1"])                 // not a transfer
    }

    func test_transferPeers_aLoneLegHasNoPeer() {
        XCTAssertTrue(TransferLegs.peers([leg("t-out", "checking", -250)]).isEmpty)
    }
}
