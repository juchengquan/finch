import Foundation

/// DEBUG-only timing for the WRITE path — the sibling of ``LaunchTiming``, and it
/// exists for the same reason: an interaction that feels wrong is worth measuring
/// before it is worth theorising about.
///
/// Marks are logged under subsystem `com.juchengquan.finch`, category `write`. On a
/// device, filter to that subsystem and category in Console.app, or:
///
///     log stream --predicate 'subsystem == "com.juchengquan.finch" && category == "write"'
///
/// Two timelines, because they now happen at different moments:
///
///   - **`⏱ write`** — the synchronous part, between the tap and the next frame.
///     `ledgers → reproject → cloudkit`. This is what a row-move animation is
///     competing with, so it is the number that matters for smoothness.
///   - **`⏱ ambient`** — the debounced round that follows ~400ms later.
///     `dbInfo → widget → done`. Deferred out of the animation deliberately; if it
///     is large it is a candidate for leaving the main actor next.
///
/// Never compiled into release: every call is a no-op outside DEBUG, so the
/// production write path pays nothing for the instrumentation.
enum WriteTiming {
    #if DEBUG
    private static let log = OSLogShim.writeLogger
    /// Monotonic origins. Debug-only counters touched from the main actor.
    nonisolated(unsafe) private static var t0: UInt64 = 0
    nonisolated(unsafe) private static var ambientT0: UInt64 = 0

    private static func elapsedMs(since start: UInt64) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000)
    }
    #endif

    static func begin() {
        #if DEBUG
        t0 = DispatchTime.now().uptimeNanoseconds
        #endif
    }

    static func mark(_ label: String) {
        #if DEBUG
        guard t0 != 0 else { return }
        log.info("⏱ write \(label, privacy: .public): +\(elapsedMs(since: t0), privacy: .public)ms")
        #endif
    }

    static func beginAmbient() {
        #if DEBUG
        ambientT0 = DispatchTime.now().uptimeNanoseconds
        #endif
    }

    static func markAmbient(_ label: String) {
        #if DEBUG
        guard ambientT0 != 0 else { return }
        log.info("⏱ ambient \(label, privacy: .public): +\(elapsedMs(since: ambientT0), privacy: .public)ms")
        #endif
    }
}

#if DEBUG
import OSLog

/// A one-line holder so the `Logger` import stays inside the DEBUG island — the
/// enum above is compiled in every configuration, its bodies are not.
private enum OSLogShim {
    static let writeLogger = Logger(subsystem: "com.juchengquan.finch", category: "write")
}
#endif
