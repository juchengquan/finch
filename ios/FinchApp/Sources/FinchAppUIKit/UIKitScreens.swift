#if os(iOS)
import Foundation

/// Whether the converted UIKit screens are in play — **on by default**.
///
/// The `uikitActivity` key started as "is the converted Activity feed at parity yet",
/// became "the migration preview" as Budgets, Scheduled and Settings joined for their
/// own reasons, and is now simply the rollout switch. It defaults ON: a plain build
/// gets the converted screens, and `-uikitActivity NO` opts back out.
///
/// **Why an opt-out rather than deleting the flag.** `NavigationUITests` runs its whole
/// suite twice, once per implementation, and that is the only thing asserting the two
/// stay in step. Removing the key would delete half that coverage on the day it is
/// still most useful. It is also the one-word rollback if something reaches a device.
///
/// **One source of truth on purpose.** The compact root and the regular-width column
/// each used to read the key themselves, with comments on both sides reminding the
/// reader they must agree. Two reads that must agree is a drift waiting to happen; this
/// is the single read they now share.
enum UIKitScreens {

    static let defaultsKey = "uikitActivity"

    /// Absent ⇒ on. Present ⇒ whatever it says.
    ///
    /// The presence check is what makes `-uikitActivity NO` work: launch arguments land
    /// in UserDefaults' argument domain as **strings**, so `object(forKey:) as? Bool`
    /// would be nil for `NO` and silently fall back to the default — the flag would look
    /// dead exactly when someone reached for it. `bool(forKey:)` coerces "NO"/"YES"
    /// properly; `object(forKey:)` is only asked whether the key is there at all.
    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: defaultsKey) != nil else { return true }
        return defaults.bool(forKey: defaultsKey)
    }

    /// The tabs whose drill-ins push converted view controllers. Not every one of these
    /// has a native ROOT yet (Phase 3b converts those; Activity and Accounts are still
    /// hosted SwiftUI roots) — this set is about the destinations.
    static var navTabs: Set<AppTab> {
        isEnabled ? [.accounts, .budgets, .scheduled, .settings] : []
    }
}
#endif
