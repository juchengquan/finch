import Foundation
import FinchCore

/// The review queue: Activity narrowed to the transactions nobody has looked over yet.
///
/// Every entry carries `reviewed_at` — stamped by `setReviewed`, by `markAllReviewed`
/// and by a rule's "Mark reviewed" action — and a NULL there means "still needs a
/// look". The queue is what lets you work through those like an inbox: see them,
/// tick them off one at a time or all together, and watch the list empty.
///
/// **Not the "To confirm" bucket.** That one is about STATUS: a pending row is money
/// that has not settled yet (a scheduled item that came due, a wrist add from the
/// Watch), and confirming it changes balances. Review is about ATTENTION: the row is
/// already real and counted, and the question is only whether you have checked its
/// category, merchant and amount. Confirming does not review a row and reviewing does
/// not confirm one, so a pending row is never in this queue — it is already waiting in
/// "To confirm", and asking for it twice would make the two queues read as one.
/// The web's Activity "Needs review" toggle draws the same line (`!t.pending &&
/// !t.reviewedAt`).
///
/// Pure, so both feeds — `ActivityFeedVC` (iOS) and `ActivityFeedView` (macOS) — run
/// the same rules and cannot drift. It speaks `TxFilter.status` strings rather than
/// `TxFilter` itself, because that is the only field it reads.
enum ReviewQueue {
    /// The `TxFilter.status` value that turns the feed into the queue. Lives beside
    /// "pending" and "confirmed" because it is a narrower kind of confirmed — and so
    /// saved searches persist it with no schema change.
    static let status = "review"

    /// Whether a row belongs in the queue: settled, and not reviewed yet.
    static func needsReview(_ tx: Tx) -> Bool {
        tx.pending != true && tx.reviewedAt == nil
    }

    /// The status to hand `ListOptions`. The engine's selector knows only pending and
    /// confirmed — it compares against "pending" and treats anything else as
    /// confirmed — so the queue goes in as "confirmed" and `narrow` does the rest.
    /// Spelled out rather than relying on that fallthrough.
    static func listStatus(_ status: String?) -> String? {
        status == Self.status ? "confirmed" : status
    }

    /// Narrow an already-filtered list to the queue, when the status asks for it.
    /// Order is preserved, so the sort menu still applies.
    static func narrow(_ txns: [Tx], status: String?) -> [Tx] {
        status == Self.status ? txns.filter(needsReview) : txns
    }

    /// How many rows in a ledger still need review — the number on the entry chip.
    /// Deliberately ignores the feed's search and filters: it says how big the whole
    /// queue is, so it does not shrink as you type into the search field.
    static func count(_ txns: [Tx], ledgerId: String) -> Int {
        txns.reduce(0) { n, tx in
            n + ((tx.ledgerId ?? "personal") == ledgerId && needsReview(tx) ? 1 : 0)
        }
    }

    /// "Mark all reviewed" asks first from this many rows up.
    ///
    /// Below it, every row the action touches is on screen and you can see what you
    /// are about to tick off; the prompt would only slow a short queue down. At ten,
    /// rows start falling below the fold — and the action covers the whole filtered
    /// set, not just the 50-row page — so it says the number and waits. Marking
    /// reviewed is reversible one row at a time but has no bulk undo, which is why
    /// the threshold is low rather than absent.
    static let confirmationThreshold = 10

    static func needsConfirmation(_ count: Int) -> Bool { count >= confirmationThreshold }
}
