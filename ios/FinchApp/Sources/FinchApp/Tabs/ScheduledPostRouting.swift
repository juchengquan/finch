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
}
