import Foundation

/// Which commit this build came from.
///
/// `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are fixed at `1.0.0` / `1`
/// across every target, and `FinchCore.version` is a hardcoded string — so before
/// this, nothing in a running app distinguished one build from another. That is
/// awkward when a test build behaves differently from the one you think you
/// installed.
///
/// The value is stamped into the built app's `Info.plist` by the "Stamp git hash"
/// build phase (`project.yml` / `project-mac.yml`), which runs **only in Debug**
/// — so this is `nil` in a Release build, and the About row that reads it is
/// itself `#if DEBUG`. Stamping the built product rather than generating a source
/// file is deliberate: writing a file into the source tree on every build would
/// make every build report itself dirty.
enum BuildInfo {
    /// Short commit SHA, plus `-dirty` when the build had uncommitted changes to
    /// TRACKED files — e.g. `b18fe45` or `b18fe45-dirty`. `nil` in Release, and
    /// `"unknown"` if the build happened outside a git checkout.
    static var gitHash: String? {
        Bundle.main.object(forInfoDictionaryKey: "FinchGitHash") as? String
    }
}
