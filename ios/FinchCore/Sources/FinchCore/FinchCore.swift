// FinchCore/FinchCore.swift — the public API. Phase 1.0 ships the read-only
// surface (schema load, projection, audit, pack); Phases 1.5+ extend it.
import Foundation
import GRDB

public enum FinchCore {
    /// The version of the iOS port. Mirrors the web's `app_version` in the
    /// pack manifest (`db_metadata.app_version`).
    public static let version: String = "1.0.0"

    /// The `.finch` pack format version this build reads + writes. Must match
    /// `PACK_FORMAT_VERSION` in the web's `lib/db/core/pack.ts`.
    public static let packFormatVersion: String = "1"
}
