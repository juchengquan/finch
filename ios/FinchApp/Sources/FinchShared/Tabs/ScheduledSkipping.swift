import Foundation
import FinchCore

/// Skipping one occurrence of a scheduled item ("no gym fee this month"), and the
/// row captions that say what a schedule will do next — shared by every surface
/// that offers them: the UIKit list (`ScheduledListVC`), the SwiftUI list and
/// calendar (`ScheduledTab`, `ScheduledCalendarView`, which FinchMac renders) and
/// the detail column (`ScheduledDetailView`). The views only choose WHERE the
/// actions sit; which occurrence they act on, and what the row says, is decided
/// here once.
///
/// What a skip means lives in the engine (`Selectors.occurrencesUpTo`): the
/// occurrence is not due, not generated, not forecast and not reminded about, and
/// it is not an execution — an installment plan still makes all its payments.
@MainActor
enum ScheduledSkipping {
    /// The occurrence a bare "Skip" acts on — this cycle's (`Selectors.skipTarget`) —
    /// or nil when nothing is left to skip.
    static func skipTarget(_ t: ScheduledTemplate, store: FinchStore) -> String? {
        Selectors.skipTarget(template: t, posted: Selectors.scheduledPostedMap(store.txns), today: store.wallToday)
    }

    /// The skip a bare "Unskip" undoes (the latest still in effect), or nil.
    static func unskipTarget(_ t: ScheduledTemplate, store: FinchStore) -> String? {
        Selectors.unskipTarget(template: t, posted: Selectors.scheduledPostedMap(store.txns))
    }

    /// Skip `occurrence`. Returns the error to show, or nil on success.
    @discardableResult
    static func skip(_ t: ScheduledTemplate, occurrence: String, store: FinchStore) -> String? {
        apply(.skipScheduledOccurrence, t, occurrence, store)
    }

    /// Un-skip `occurrence`: it is due again. Returns the error to show, or nil.
    @discardableResult
    static func unskip(_ t: ScheduledTemplate, occurrence: String, store: FinchStore) -> String? {
        apply(.unskipScheduledOccurrence, t, occurrence, store)
    }

    private static func apply(_ action: ActionName, _ t: ScheduledTemplate, _ occurrence: String,
                              _ store: FinchStore) -> String? {
        do {
            try store.apply(action, Args(["templateId": .string(t.id), "date": .string(occurrence)]))
            return nil
        } catch { return i18nMessage(error) }
    }

    /// Menu titles carry the date — "Skip Nov 15" — because a bare Skip can take the
    /// occurrence just passed or the one coming up, and the user should see which
    /// before tapping. Swipe buttons are too narrow for it and say only "Skip"; the
    /// row's "Skipping …" caption confirms it afterwards.
    static func skipTitle(_ occurrence: String, today: String) -> String {
        String(localized: "Skip \(ScheduledCaption.shortDay(occurrence, today: today))")
    }
    static func unskipTitle(_ occurrence: String, today: String) -> String {
        String(localized: "Unskip \(ScheduledCaption.shortDay(occurrence, today: today))")
    }
}

/// What a scheduled row says under its name. Pure — `today` is the wall-clock day.
enum ScheduledCaption {
    /// "Monthly · next 2026-11-15", plus " · ends 2026-12-31" when an end date is set;
    /// "Monthly · ended 2026-09-30" once nothing is left before it.
    ///
    /// "Next" is the next occurrence that will HAPPEN — a skipped one is passed over,
    /// so skipping this month's visibly moves it to the next.
    static func cadence(_ t: ScheduledTemplate, today: String) -> String {
        let freq = t.frequency.capitalized
        let next = Selectors.nextOccurrence(t, onOrAfter: today)
        if let end = t.endDate.map({ String($0.prefix(10)) }), !end.isEmpty {
            if let next { return String(localized: "\(freq) · next \(next) · ends \(end)") }
            // Nothing left. Past the end date it has ended; before it, the remaining
            // occurrences were skipped (or fall after the last one), so it simply ends.
            return end < today ? String(localized: "\(freq) · ended \(end)")
                               : String(localized: "\(freq) · ends \(end)")
        }
        // No end date: unchanged — the stored next_run is the fallback for a
        // template whose recurrence has run out (a past "once"), else a dash.
        let shown = next ?? (t.nextRun.isEmpty ? "—" : t.nextRun)
        return String(localized: "\(freq) · next \(shown)")
    }

    /// "Skipping 2026-11-15" while the current occurrence or a later one is skipped;
    /// nil otherwise. From the CURRENT occurrence (`Selectors.currentOccurrence`), the
    /// same point a bare Skip starts from — so skipping the one just passed still
    /// shows. Older skips are history, and the calendar still shows those.
    static func skips(_ t: ScheduledTemplate, today: String) -> String? {
        let from = Selectors.currentOccurrence(t, today: today) ?? today
        let upcoming = (t.skippedDates ?? []).filter { $0 >= from }.sorted()
        guard !upcoming.isEmpty else { return nil }
        // Pre-joined, so the localized string has a single argument whatever the count.
        let list = upcoming.prefix(3).joined(separator: ", ") + (upcoming.count > 3 ? "…" : "")
        return String(localized: "Skipping \(list)")
    }

    /// "Nov 15", or "Nov 15, 2025" outside the current year — short enough for a menu
    /// title, unambiguous for an old missed occurrence.
    static func shortDay(_ iso: String, today: String) -> String {
        guard let d = AppDate.isoDay.date(from: iso) else { return iso }
        let sameYear = iso.prefix(4) == today.prefix(4)
        return sameYear ? d.formatted(.dateTime.month(.abbreviated).day())
                        : d.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
