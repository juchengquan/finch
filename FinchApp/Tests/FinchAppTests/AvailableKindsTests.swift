import XCTest
import FinchCore
@testable import FinchApp

/// `AddTransactionSheet.availableKinds` decides which segments the Kind picker
/// offers. The scheduled-occurrence case is the one that must never regress:
/// save()'s `.adjust` branch (`adjustAccountBalance`) returns early without ever
/// forwarding `sourceTemplateId`/`occurrenceDate` — switching to Adjust while
/// posting a scheduled occurrence would silently drop the link (transaction
/// posts, sheet dismisses, calendar badge never flips, no error shown).
final class AvailableKindsTests: XCTestCase {
    private func tx(kind: String?) -> Tx {
        Tx(id: "t1", merchant: "M", category: nil, amount: -10, account: "a1",
           date: "2026-07-20", kind: kind)
    }

    /// THE regression guard: posting a scheduled occurrence excludes Adjust even
    /// when the user has opted the segment in via Settings.
    func test_postsScheduledOccurrence_excludesAdjust_evenWithOptInOn() {
        let kinds = AddTransactionSheet.availableKinds(
            postsScheduledOccurrence: true, showAdjustInAddSheet: true, prefill: nil)
        XCTAssertFalse(kinds.contains(.adjust))
    }

    func test_postsScheduledOccurrence_excludesAdjust_optInOff() {
        let kinds = AddTransactionSheet.availableKinds(
            postsScheduledOccurrence: true, showAdjustInAddSheet: false, prefill: nil)
        XCTAssertFalse(kinds.contains(.adjust))
    }

    /// Normal add flow, opt-in off (the default): Adjust stays hidden.
    func test_normalFlow_optInOff_excludesAdjust() {
        let kinds = AddTransactionSheet.availableKinds(
            postsScheduledOccurrence: false, showAdjustInAddSheet: false, prefill: nil)
        XCTAssertFalse(kinds.contains(.adjust))
    }

    /// Normal add flow, opt-in on: Adjust is offered alongside everything else.
    func test_normalFlow_optInOn_includesAdjust() {
        let kinds = AddTransactionSheet.availableKinds(
            postsScheduledOccurrence: false, showAdjustInAddSheet: true, prefill: nil)
        XCTAssertEqual(Set(kinds), Set(AddTransactionSheet.Kind.allCases))
    }

    /// Duplicating an adjustment forces the segment in regardless of the opt-in
    /// — unchanged behaviour, preserved here as the precedence this function
    /// still has to honour underneath the new scheduled-occurrence check.
    func test_duplicatingAnAdjustment_includesAdjust_evenWithOptInOff() {
        let kinds = AddTransactionSheet.availableKinds(
            postsScheduledOccurrence: false, showAdjustInAddSheet: false, prefill: tx(kind: "adjustment"))
        XCTAssertTrue(kinds.contains(.adjust))
    }
}
