import Foundation

#if DEBUG
import OSLog

/// DEBUG-only launch / first-paint timing. Marks are logged under subsystem
/// `com.juchengquan.finch`, category `launch`, so a device run shows exactly where
/// the launch spinner's time goes — in Console.app filter by that subsystem and
/// category, or run `log stream --predicate 'subsystem == "com.juchengquan.finch"
/// && category == "launch"'`. Never compiled into release.
///
/// Milestones (see `FinchApp.task` / `FinchStore.bootstrap`):
///   launch begin → db open+migrate+seed → bootstrap done (projection ready) →
///   first paint (spinner cleared) → audit done → spotlight done
enum LaunchTiming {
    private static let log = Logger(subsystem: "com.juchengquan.finch", category: "launch")
    /// Monotonic launch origin (uptime nanoseconds). Written once by `begin()` on the
    /// main thread, then only read — a debug timer, so `nonisolated(unsafe)` is fine.
    nonisolated(unsafe) private static var t0: UInt64 = 0

    static func begin() {
        t0 = DispatchTime.now().uptimeNanoseconds
        log.info("⏱ launch begin")
    }

    /// Log `label` with whole-millisecond elapsed since `begin()`.
    static func mark(_ label: String) {
        guard t0 != 0 else { return }
        let ms = Int((DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000)
        log.info("⏱ \(label, privacy: .public): +\(ms, privacy: .public)ms")
    }
}
#endif
