import XCTest
import FinchCore
@testable import FinchApp

/// `scheduledLinkArgs` is the ONLY thing standing between the Duplicate feature
/// and silently reclaiming a scheduled occurrence: Duplicate hands the sheet a
/// real `Tx`, and a transaction previously posted FROM a schedule already
/// carries `sourceTemplateId`/`occurrenceDate`. Without gating on `posts`,
/// duplicating it would flip that occurrence's calendar badge and consume an
/// installment slot the duplicate never earned. These pin that gate as a pure,
/// machine-checked function instead of a doc comment.
final class ScheduledLinkArgsTests: XCTestCase {
    private func tx(sourceTemplateId: String?, occurrenceDate: String?) -> Tx {
        Tx(id: "t1", merchant: "M", amount: -10, account: "a1", date: "2026-07-20",
           sourceTemplateId: sourceTemplateId, occurrenceDate: occurrenceDate)
    }

    /// THE regression guard: a Tx carrying a template link — exactly what
    /// Duplicate hands over for a previously-scheduled posting — with the flag
    /// OFF (Duplicate's default) must yield nothing. This is what stops
    /// Duplicate from claiming the source's occurrence.
    func test_flagOff_withTemplateLink_yieldsEmpty() {
        let args = AddTransactionSheet.scheduledLinkArgs(
            prefill: tx(sourceTemplateId: "s1", occurrenceDate: "2026-07-20"), posts: false)
        XCTAssertTrue(args.isEmpty)
    }

    /// The "Post now" path: flag on yields both keys, which is what flips the
    /// calendar badge and resolves the installment.
    func test_flagOn_withTemplateLink_yieldsBothKeys() {
        let args = AddTransactionSheet.scheduledLinkArgs(
            prefill: tx(sourceTemplateId: "s1", occurrenceDate: "2026-07-20"), posts: true)
        XCTAssertEqual(args["sourceTemplateId"], .string("s1"))
        XCTAssertEqual(args["occurrenceDate"], .string("2026-07-20"))
    }

    /// A plain add/duplicate with no template link yields nothing regardless of
    /// the flag — there's nothing to gate.
    func test_noTemplateLink_yieldsEmpty_regardlessOfFlag() {
        XCTAssertTrue(AddTransactionSheet.scheduledLinkArgs(
            prefill: tx(sourceTemplateId: nil, occurrenceDate: nil), posts: false).isEmpty)
        XCTAssertTrue(AddTransactionSheet.scheduledLinkArgs(
            prefill: tx(sourceTemplateId: nil, occurrenceDate: nil), posts: true).isEmpty)
    }

    /// A brand-new add (no prefill at all) yields nothing regardless of the flag.
    func test_nilPrefill_yieldsEmpty_regardlessOfFlag() {
        XCTAssertTrue(AddTransactionSheet.scheduledLinkArgs(prefill: nil, posts: false).isEmpty)
        XCTAssertTrue(AddTransactionSheet.scheduledLinkArgs(prefill: nil, posts: true).isEmpty)
    }
}
