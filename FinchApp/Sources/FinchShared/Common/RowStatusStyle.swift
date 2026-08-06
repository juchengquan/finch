import Foundation

/// How a transaction row's leading glyph reflects the row's status, and what
/// tapping it would do.
///
/// Pure, so the decision can be tested without a rendered row — the glyph is a
/// control now, and a control whose appearance is wrong in one state is exactly
/// the bug a screenshot review misses.
///
/// **The clock still leads.** A pending row keeps its `clock` badge; this only
/// makes the tap target itself honest, so the thing you press looks different
/// depending on what pressing it will do. That is deliberately a SECOND signal
/// rather than the only one — see `pendingOpacity`.
enum RowStatusStyle {

    /// How faded the glyph is while pending. The one number to change if the
    /// treatment reads wrong: 1.0 makes the glyph identical in both states and
    /// the clock becomes the only status signal again, with no other edit needed.
    ///
    /// Deliberately mild. The rows that carry it are the ones being triaged, so
    /// the category has to stay readable — this is a hint that the control's
    /// state differs, not a second way of shouting "pending".
    static let pendingOpacity: Double = 0.55

    /// Opacity for a row's leading glyph.
    static func glyphOpacity(pending: Bool) -> Double {
        pending ? pendingOpacity : 1.0
    }

    /// The VoiceOver action name — what a tap WILL do, not what the row currently
    /// is. A label naming the present state would leave the user guessing which way
    /// the action goes; the sighted affordance has the glyph's appearance to
    /// disambiguate, this has only its name.
    ///
    /// The SAME WORDS the swipe action and the long-press menu already use
    /// (`TxRowActions.statusTitle`). Three routes to one action should not invent
    /// three vocabularies — and reusing them adds no catalog keys, so the zh-Hans
    /// translations that exist keep applying.
    static func actionTitle(pending: Bool) -> String {
        pending ? String(localized: "Confirm") : String(localized: "Set pending")
    }
}
