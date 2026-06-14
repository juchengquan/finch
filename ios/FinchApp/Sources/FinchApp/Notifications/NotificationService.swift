import Foundation
import UserNotifications
import FinchCore

/// User toggles for the 4 categories (global, app-local — not ledger data, so
/// UserDefaults, not the chokepoint). All on by default.
public enum NotificationPrefs {
    private static let key = "finch.notifications.disabledKinds"
    public static var enabled: Set<NotificationKind> {
        let disabled = Set((UserDefaults.standard.array(forKey: key) as? [String] ?? [])
            .compactMap(NotificationKind.init(rawValue:)))
        return Set(NotificationKind.allCases).subtracting(disabled)
    }
    public static func isOn(_ k: NotificationKind) -> Bool { enabled.contains(k) }
    public static func set(_ k: NotificationKind, on: Bool) {
        var disabled = Set((UserDefaults.standard.array(forKey: key) as? [String] ?? []))
        if on { disabled.remove(k.rawValue) } else { disabled.insert(k.rawValue) }
        UserDefaults.standard.set(Array(disabled), forKey: key)
    }
}

/// Phase 6.2 — schedules the planned local notifications and routes their action
/// buttons / taps through `DeepLinkRouter`. Thin shell over `NotificationPlanner`
/// (the tested decision logic). All notifications are LOCAL (no push).
@MainActor
public final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()
    private weak var store: FinchStore?
    private weak var router: DeepLinkRouter?
    /// True when the user denied notification permission — surfaced in Settings
    /// so the otherwise-silently-dropped alerts have an explanation + a fix.
    @Published public private(set) var authorizationDenied = false

    public func configure(store: FinchStore, router: DeepLinkRouter) {
        self.store = store; self.router = router
        center.delegate = self
        registerCategories()
    }

    public func requestPermissionIfNeeded() async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        }
        authorizationDenied = await center.notificationSettings().authorizationStatus == .denied
    }

    /// Re-plan from current state and schedule anything not already pending or
    /// delivered (stable ids → no duplicate fires). Called on launch + writes.
    public func refresh() async {
        guard let store else { return }
        let status = await center.notificationSettings().authorizationStatus
        authorizationDenied = (status == .denied)
        if status == .denied { return }   // nothing to schedule; the system drops them
        let planned = NotificationPlanner.plan(
            budgets: store.budgets, txns: store.txns, scheduled: store.scheduled,
            categories: store.categoryNodes, today: store.today, ledgerId: store.activeLedgerId,
            enabled: NotificationPrefs.enabled, money: { store.displayMoneyBase($0) })

        let pending = Set(await center.pendingNotificationRequests().map(\.identifier))
        let delivered = Set(await center.deliveredNotifications().map(\.request.identifier))
        let existing = pending.union(delivered)

        for p in planned where !existing.contains(p.id) {
            let content = UNMutableNotificationContent()
            content.title = p.title
            content.body = p.body
            content.categoryIdentifier = p.kind.rawValue
            content.sound = .default
            var info: [String: String] = ["kind": p.kind.rawValue]
            if let tab = p.tab { info["tab"] = String(describing: tab) }
            if let fid = p.focusId { info["focusId"] = fid }
            content.userInfo = info

            let trigger: UNNotificationTrigger = p.kind == .weeklyDigest
                ? UNCalendarNotificationTrigger(dateMatching: Self.sundayMorning, repeats: true)
                : UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: p.id, content: content, trigger: trigger))
        }
    }

    private static var sundayMorning: DateComponents {
        var c = DateComponents(); c.weekday = 1; c.hour = 9; c.minute = 0; return c   // Sun 09:00
    }

    private func registerCategories() {
        let scheduled = UNNotificationCategory(identifier: NotificationKind.scheduledDue.rawValue, actions: [
            UNNotificationAction(identifier: "confirmNow", title: "Confirm now", options: [.foreground]),
            UNNotificationAction(identifier: "snooze1h", title: "Snooze 1 hour", options: []),
        ], intentIdentifiers: [], options: [])
        let budget = UNNotificationCategory(identifier: NotificationKind.budgetWarning.rawValue, actions: [
            UNNotificationAction(identifier: "viewBudgets", title: "View budgets", options: [.foreground]),
        ], intentIdentifiers: [], options: [])
        let anomaly = UNNotificationCategory(identifier: NotificationKind.anomaly.rawValue, actions: [
            UNNotificationAction(identifier: "viewTransaction", title: "View transaction", options: [.foreground]),
        ], intentIdentifiers: [], options: [])
        let digest = UNNotificationCategory(identifier: NotificationKind.weeklyDigest.rawValue, actions: [],
                                            intentIdentifiers: [], options: [])
        center.setNotificationCategories([scheduled, budget, anomaly, digest])
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                                   willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .list, .sound] }

    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                                   didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let focusId = info["focusId"] as? String
        await MainActor.run {
            switch action {
            case "confirmNow":
                if let id = focusId { try? store?.apply(.postScheduled, Args(["templateId": .string(id)])) }
                router?.open(.scheduled)
            case "viewBudgets": router?.open(.budgets)
            case "viewTransaction":
                if let id = focusId { router?.route(to: "tx:\(id)") } else { router?.open(.activity) }
            case "snooze1h": break   // dismiss; re-plan will re-surface if still due
            default:                  // tap (UNNotificationDefaultActionIdentifier)
                if let tab = info["tab"] as? String, let t = Self.tab(from: tab) { router?.open(t) }
            }
        }
    }

    private static func tab(from raw: String) -> AppTab? {
        switch raw {
        case "accounts": return .accounts; case "activity": return .activity
        case "budgets": return .budgets; case "insights": return .insights
        case "scheduled": return .scheduled; case "settings": return .settings
        default: return nil
        }
    }
}
