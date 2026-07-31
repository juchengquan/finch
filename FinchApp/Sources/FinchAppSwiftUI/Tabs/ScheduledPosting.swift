import SwiftUI
import FinchCore

/// One calendar occurrence awaiting its prefilled Add sheet. `.sheet(item:)`
/// needs Identifiable and a tuple can't conform. The id deliberately combines
/// template AND occurrence: posting two occurrences of the same template in
/// one sitting must re-present the sheet, which a template-only id would suppress.
struct PostPrefill: Identifiable {
    let template: ScheduledTemplate
    let occurrence: String
    var id: String { "\(template.id)|\(occurrence)" }
}

/// The `.sheet(item:)` content for `scheduledPostSheet` below. A separate View
/// (rather than building `AddTransactionSheet` inline in the modifier) so it can
/// read `store` from the environment to compute the prefill — the sheet content
/// closure isn't itself a View and so can't carry `@EnvironmentObject`, but any
/// environment-object-consuming View placed inside it, like this one, inherits
/// the environment from whatever presented the sheet, same as `ScheduledSheet`
/// elsewhere in this file's callers.
private struct ScheduledPostSheetContent: View {
    @EnvironmentObject private var store: FinchStore
    let prefill: PostPrefill

    var body: some View {
        AddTransactionSheet(prefill: store.txPrefill(for: prefill.template, occurrence: prefill.occurrence),
                            postsScheduledOccurrence: true)
    }
}

extension View {
    /// The prefilled Add sheet for one scheduled occurrence — shared by every
    /// "Post now" surface (`ScheduledTab`'s calendar/list/context-menu and
    /// `ScheduledDetailView`'s toolbar) so they all present identically instead
    /// of each owning a copy of this `.sheet(item:)`.
    func scheduledPostSheet(_ prefill: Binding<PostPrefill?>) -> some View {
        sheet(item: prefill) { p in ScheduledPostSheetContent(prefill: p) }
    }
}

/// The shared "post ONE occurrence" flow. The calendar already has an occurrence
/// in hand when the user taps a cell; the template-only entry points (list swipe/
/// context menu, detail toolbar) do not, so `postNow(_:store:prefill:errorMessage:)`
/// resolves one first via `Selectors.resumeOccurrence` (oldest unresolved, else the
/// next occurrence ≥ today, else nil ⇒ "nothing to post"). Both paths converge on
/// `postNow(_:occurrence:store:prefill:errorMessage:)`, which re-checks the
/// installment cap and the malformed-transfer case (both bypassed by the sheet
/// path) and then either posts silently or opens the prefilled sheet
/// (`ScheduledPostRouting`).
@MainActor
enum ScheduledPoster {
    /// Resolve which occurrence a bare "Post now" (no occurrence already in hand)
    /// should act on, then post it. Sets `errorMessage` when nothing is left to post.
    static func postNow(_ t: ScheduledTemplate, store: FinchStore,
                        prefill: Binding<PostPrefill?>, errorMessage: Binding<String?>) {
        let posted = Selectors.scheduledPostedMap(store.txns)
        guard let occ = Selectors.resumeOccurrence(template: t, posted: posted, today: store.wallToday) else {
            errorMessage.wrappedValue = nothingToPostMessage(t)
            return
        }
        // A bare "Post now" with no cell in hand that resolves to a FUTURE occurrence
        // on the SILENT path has no sheet to confirm the date in — refuse it rather
        // than silently book unconfirmed future-dated income (a fully-caught-up
        // split-income template falls forward this way). Strictly `>`: an occurrence
        // dated exactly today is due and still posts. The calendar is deliberately
        // exempt — it calls the occurrence-taking overload directly with a cell the
        // user TAPPED, which is itself the date confirmation.
        if occ > store.wallToday, ScheduledPostRouting.routeForPost(t, store: store) == .silent {
            errorMessage.wrappedValue = nothingToPostMessage(t)
            return
        }
        postNow(t, occurrence: occ, store: store, prefill: prefill, errorMessage: errorMessage)
    }

    private static func nothingToPostMessage(_ t: ScheduledTemplate) -> String {
        i18nMessage(I18nError("error.scheduled.nothingToPost",
                              ["name": t.name],
                              "Nothing left to post for \"\(t.name)\"."))
    }

    /// Post ONE explicitly-chosen occurrence (a calendar cell the user tapped, or the
    /// occurrence `resumeOccurrence` picked for a bare "Post now"). Most templates open
    /// a prefilled sheet so the user confirms the date/amount before it lands;
    /// split-income templates stay on the silent engine path (see `ScheduledPostRouting`).
    /// This overload posts whatever `occurrence` it is given — the future-date guard for
    /// auto-resolved posts lives in the resolving overload above, so an explicit calendar
    /// tap of a future cell still posts.
    static func postNow(_ t: ScheduledTemplate, occurrence: String, store: FinchStore,
                        prefill: Binding<PostPrefill?>, errorMessage: Binding<String?>) {
        // The installment cap lives in `Scheduled.post`, which the sheet path
        // bypasses — re-check it here, with the ENGINE's message key so the copy
        // (and its zh translation) is the same wherever the user hits the cap.
        if let total = t.installmentTotal, (t.installmentPaid ?? 0) >= total {
            errorMessage.wrappedValue = i18nMessage(I18nError("error.scheduled.installmentDone",
                                                 ["name": t.name, "total": String(total)],
                                                 "\"\(t.name)\" has finished its \(total)-payment plan"))
            return
        }
        // A transfer template with no from-account is malformed. The sheet's
        // account fallbacks would otherwise silently fill From/To with the
        // first two accounts — a complete, valid-looking form that fails on
        // Save forever with no way to fix it. Catch it here, before
        // presenting, with the same engine error the silent path throws.
        if t.type == "transfer", t.fromAccountId == nil {
            errorMessage.wrappedValue = i18nMessage(I18nError("error.scheduled.missingAccount",
                                                 ["name": t.name],
                                                 "\"\(t.name)\" is missing an account"))
            return
        }
        switch ScheduledPostRouting.routeForPost(t, store: store) {
        case .sheet:
            prefill.wrappedValue = PostPrefill(template: t, occurrence: occurrence)
        case .silent:
            do {
                try store.apply(.postScheduled, Args([
                    "templateId": .string(t.id), "date": .string(occurrence),
                ]))
            } catch { errorMessage.wrappedValue = i18nMessage(error) }
        }
    }
}
