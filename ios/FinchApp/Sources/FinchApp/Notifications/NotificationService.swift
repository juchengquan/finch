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

/// Durable "already shown" / "snoozed until" records. Device-local view state,
/// so UserDefaults — never the chokepoint, never exported (same rule as the
/// per-kind toggles above).
enum NotificationState {
    private static let firedKey = "finch.notifications.firedIds"
    private static let snoozeKey = "finch.notifications.snoozedUntil"

    static var fired: Set<String> {
        get { Set(UserDefaults.standard.array(forKey: firedKey) as? [String] ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: firedKey) }
    }

    /// id → deadline. Stored as epoch seconds so it survives relaunches.
    static var snoozedUntil: [String: Date] {
        get {
            let raw = UserDefaults.standard.dictionary(forKey: snoozeKey) as? [String: Double] ?? [:]
            return raw.mapValues { Date(timeIntervalSince1970: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.mapValues(\.timeIntervalSince1970), forKey: snoozeKey)
        }
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
        // today = data-anchored (budget windows); wallToday = the real calendar
        // day (is-it-due-now). See NotificationPlanner.plan.
        let planned = NotificationPlanner.plan(
            budgets: store.budgets, txns: store.txns, scheduled: store.scheduled,
            categories: store.categoryNodes, today: store.today, wallToday: store.wallToday,
            ledgerId: store.activeLedgerId,
            enabled: NotificationPrefs.enabled, money: { store.displayMoneyBase($0) })

        let pending = Set(await center.pendingNotificationRequests().map(\.identifier))
        let delivered = Set(await center.deliveredNotifications().map(\.request.identifier))
        let existing = pending.union(delivered)

        let stalePending = NotificationPlanner.cancelIDs(planned: planned, existing: pending)
        if !stalePending.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stalePending) }
        let staleDelivered = NotificationPlanner.cancelIDs(planned: planned, existing: delivered)
        if !staleDelivered.isEmpty { center.removeDeliveredNotifications(withIdentifiers: staleDelivered) }

        // Forget ids whose condition has resolved, so the same budget can alert
        // again next time it crosses. Pruning BEFORE the schedule decision keeps
        // "already shown" scoped to the current episode.
        NotificationState.fired = NotificationPlanner.retainedFired(NotificationState.fired, planned: planned)
        NotificationState.snoozedUntil = NotificationPlanner.retained(NotificationState.snoozedUntil, planned: planned)

        let now = Date()
        let due = NotificationPlanner.toSchedule(
            planned: planned, existing: existing,
            fired: NotificationState.fired, snoozedUntil: NotificationState.snoozedUntil, now: now)

        for p in due {
            let trigger: UNNotificationTrigger = p.kind == .weeklyDigest
                ? UNCalendarNotificationTrigger(dateMatching: Self.sundayMorning, repeats: true)
                : UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: p.id, content: Self.content(for: p), trigger: trigger))
            // The digest repeats on a calendar trigger — recording it as fired
            // would suppress every future week.
            if p.kind != .weeklyDigest { NotificationState.fired.insert(p.id) }
        }

        await updateBadge(planned: planned)
    }

    /// Badge = things still awaiting action. The digest is informational, so it
    /// doesn't count — otherwise the badge would never clear. `.badge` was being
    /// requested at authorization but never set, so this makes the permission honest.
    private func updateBadge(planned: [PlannedNotification]) async {
        let actionable = planned.filter { $0.kind != .weeklyDigest }.count
        try? await center.setBadgeCount(actionable)
    }

    private static func content(for p: PlannedNotification) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = p.title
        content.body = p.body
        content.categoryIdentifier = p.kind.rawValue
        content.sound = .default
        var info: [String: String] = ["kind": p.kind.rawValue]
        if let tab = p.tab { info["tab"] = String(describing: tab) }
        if let fid = p.focusId { info["focusId"] = fid }
        content.userInfo = info
        return content
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
        let request = response.notification.request
        let info = request.content.userInfo
        let action = response.actionIdentifier
        let focusId = info["focusId"] as? String
        let tabName = info["tab"] as? String   // extract before the @Sendable hop (info isn't Sendable)
        let kindName = info["kind"] as? String
        let notifId = request.identifier
        let title = request.content.title
        let body = request.content.body

        if action == "snooze1h" {
            // A real hour, not a dismissal. The old handler just fell through with
            // "re-plan will re-surface if still due", so the next write fired it
            // again within seconds — the button's label was a promise the code
            // didn't keep. Re-arm the same alert on a 1h trigger and record the
            // deadline so re-planning leaves it alone until then.
            await snooze(id: notifId, title: title, body: body, kind: kindName,
                         tab: tabName, focusId: focusId)
            return
        }

        await MainActor.run {
            switch action {
            case "confirmNow":
                if let id = focusId { try? store?.apply(.postScheduled, Args(["templateId": .string(id)])) }
                router?.open(.scheduled)
            case "viewBudgets": router?.open(.budgets)
            case "viewTransaction":
                if let id = focusId { router?.route(to: "tx:\(id)") } else { router?.open(.activity) }
            default:                  // tap (UNNotificationDefaultActionIdentifier)
                if let tabName, let t = Self.tab(from: tabName) { router?.open(t) }
            }
        }
    }

    /// Re-arm a notification an hour out and mark it snoozed until then.
    private func snooze(id: String, title: String, body: String,
                        kind: String?, tab: String?, focusId: String?) async {
        NotificationState.snoozedUntil[id] = Date().addingTimeInterval(Self.snoozeInterval)
        // Clear the once-only record: this alert is deliberately meant to return.
        NotificationState.fired.remove(id)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let kind { content.categoryIdentifier = kind }
        content.sound = .default
        var info: [String: String] = [:]
        if let kind { info["kind"] = kind }
        if let tab { info["tab"] = tab }
        if let focusId { info["focusId"] = focusId }
        content.userInfo = info

        try? await center.add(UNNotificationRequest(
            identifier: id, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: Self.snoozeInterval, repeats: false)))
    }

    static let snoozeInterval: TimeInterval = 3600

    private static func tab(from raw: String) -> AppTab? {
        switch raw {
        case "accounts": return .accounts; case "activity": return .activity
        case "budgets": return .budgets; case "insights": return .insights
        case "scheduled": return .scheduled; case "settings": return .settings
        default: return nil
        }
    }
}
