import Foundation
import FinchCore

/// Where a "Post now" tap should go. Most templates open a prefilled edit sheet so
/// the user can confirm the date and amount; split-income templates cannot be
/// represented there (their splits fan out across ACCOUNTS, while the sheet's
/// splits are categories inside one transaction), so they keep the silent engine
/// path — which posts every split correctly.
enum PostRoute { case sheet, silent }

enum ScheduledPostRouting {
    static func route(_ template: ScheduledTemplate, splitCount: Int) -> PostRoute {
        template.type == "income" && splitCount > 0 ? .silent : .sheet
    }

    /// The full "Post now" wiring for a calendar-occurrence tap: fetches the
    /// template's REAL split count from the store before deciding the route.
    /// `route` above is pure and well-tested, but nothing enforced that the
    /// call site feeds it the genuine count rather than a stray literal — a
    /// regression passing `splitCount: 0` here would silently reintroduce the
    /// exact split-income collapse this routing exists to prevent (N postings
    /// across N accounts becoming one), with `route`'s own tests still green.
    /// Centralizing the store read here, instead of at the call site in
    /// `ScheduledTab`, means there's exactly one place a test can exercise it
    /// against a real store (see `ScheduledPostRoutingTests`).
    @MainActor
    static func routeForPost(_ template: ScheduledTemplate, store: FinchStore) -> PostRoute {
        route(template, splitCount: store.scheduledSplitCount(templateId: template.id))
    }
}
