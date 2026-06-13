import XCTest
import GRDB
@testable import FinchCore

final class PackTests: XCTestCase {
    func test_parseRejectsNonZip() {
        let junk = Data("not a zip file".utf8)
        XCTAssertThrowsError(try Pack.parse(junk)) { error in
            guard case PackError.notAZip = error else {
                return XCTFail("Expected .notAZip, got \(error)")
            }
        }
    }

    func test_detectFileKind() {
        XCTAssertEqual(Pack.detectFileKind(Data([0x50, 0x4b, 0x03, 0x04, 0x00])), .zip)
        XCTAssertEqual(Pack.detectFileKind(Data("SQLite format 3\u{0}extra".utf8)), .sqlite)
        XCTAssertEqual(Pack.detectFileKind(Data("hello world not a db".utf8)), .unknown)
    }

    /// Build a pack from a real migrated DB, parse it back, extract it, and verify
    /// the round-tripped DB bytes hash to the same sha256 (wire-format self-consistency).
    func test_buildParseExtractRoundTrip() throws {
        // A real DB snapshot via VACUUM INTO.
        let dbQueue = try DatabaseQueue()
        try Migrations.runAll(on: dbQueue)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rt-\(UUID().uuidString).sqlite3")
        try dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM INTO ?", arguments: [tmp.path])
        }
        defer { try? FileManager.default.removeItem(at: tmp) }
        let dbBytes = try Data(contentsOf: tmp)

        let input = Pack.BuildInput(
            dbBytes: dbBytes,
            meta: .init(appVersion: FinchCore.version, schemaVersion: Schema.version,
                        exportedAt: "2026-06-13T00:00:00Z",
                        exportedFrom: .init(device: "ios"), rowCounts: ["entries": 0, "postings": 0]))

        let built = try Pack.build(input)
        XCTAssertEqual(Pack.detectFileKind(built.bytes), .zip)
        XCTAssertEqual(built.manifest.db.sha256, Pack.sha256Hex(dbBytes))
        XCTAssertEqual(built.manifest.exportedFrom?.device, "ios")

        let parsed = try Pack.parse(built.bytes)
        XCTAssertEqual(parsed.manifest.db.sha256, Pack.sha256Hex(dbBytes))
        XCTAssertEqual(parsed.manifest.appName, "finch")
        XCTAssertEqual(parsed.manifest.db.rowCounts["entries"], 0)

        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("ext-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dest) }
        let extracted = try Pack.extract(parsed, to: dest)
        let extractedBytes = try Data(contentsOf: extracted.dbPath)
        XCTAssertEqual(Pack.sha256Hex(extractedBytes), Pack.sha256Hex(dbBytes),
                       "round-tripped DB bytes must hash identically")
        // The extracted DB opens and is the canonical schema.
        let reopened = try DatabaseQueue(path: extracted.dbPath.path)
        try reopened.read { db in XCTAssertTrue(try db.tableExists("entries")) }
    }
}
