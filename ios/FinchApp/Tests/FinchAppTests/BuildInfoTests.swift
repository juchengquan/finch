import XCTest
@testable import FinchApp

/// End-to-end cover for the "Stamp git hash" build phase.
///
/// There is nothing to unit-test in `BuildInfo` itself — it reads one Info.plist
/// key. What can actually break is the chain around it: the script phase not
/// running, `PlistBuddy` failing silently, the key being renamed on one side only,
/// or the plist being stamped after it has already been copied. These tests fail
/// on all of those, because the test host IS the Debug app bundle the phase
/// stamped.
final class BuildInfoTests: XCTestCase {

    /// The phase runs in Debug, and tests build Debug — so a nil here means the
    /// phase did not run or wrote nothing.
    func test_gitHash_isStampedIntoTheTestHostBundle() {
        XCTAssertNotNil(BuildInfo.gitHash,
                        "FinchGitHash missing from the built Info.plist — the 'Stamp git hash' build phase did not run")
    }

    /// A short SHA, optionally marked dirty. Catches a stamp that wrote an error
    /// message, an empty string, or the literal `$(SOMETHING)` — all of which are
    /// non-nil and would otherwise pass.
    func test_gitHash_looksLikeAShortSHA() throws {
        let hash = try XCTUnwrap(BuildInfo.gitHash)
        // "unknown" is the script's documented fallback outside a git checkout.
        try XCTSkipIf(hash == "unknown", "built outside a git checkout")

        let pattern = "^[0-9a-f]{7,40}(-dirty)?$"
        XCTAssertNotNil(hash.range(of: pattern, options: .regularExpression),
                        "\(hash) is not a short SHA (optionally suffixed -dirty)")
    }

    /// The row renders the value verbatim in a narrow settings cell, so a full
    /// 40-char SHA — or anything longer — would truncate.
    func test_gitHash_isShortEnoughForASettingsRow() throws {
        let hash = try XCTUnwrap(BuildInfo.gitHash)
        try XCTSkipIf(hash == "unknown", "built outside a git checkout")
        XCTAssertLessThanOrEqual(hash.count, "0123456789abcdef-dirty".count)
    }
}
