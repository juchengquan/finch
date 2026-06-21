import Foundation
import CryptoKit
import ZIPFoundation

/// The iOS port's mirror of the web's `lib/db/core/pack.ts`. A `.finch` pack is
/// a ZIP containing `finch.sqlite3` (DEFLATE) + `attachments/<entry_id>/<att>.<ext>`
/// (STORE) + `manifest.json` (DEFLATE, last). Ported verbatim. The manifest wire
/// shape is NESTED + snake_case (explicit CodingKeys; `row_counts` keeps its
/// snake_case table keys verbatim — do NOT use .convertFromSnakeCase, which would
/// mangle the dynamic dictionary keys). Byte-identical packs are a NON-GOAL.
public enum Pack {
    public static let formatVersion = "1"
    public static let dbFilename = "finch.sqlite3"
    public static let manifestFilename = "manifest.json"
    public static let attachmentsPrefix = "attachments/"

    /// SHA-256 of a byte slice as a lowercase hex string.
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Build

    public struct BuildInput {
        public var dbBytes: Data
        public var attachmentFiles: [AttachmentFile]
        public var meta: Meta
        public init(dbBytes: Data, attachmentFiles: [AttachmentFile] = [], meta: Meta) {
            self.dbBytes = dbBytes; self.attachmentFiles = attachmentFiles; self.meta = meta
        }
        public struct AttachmentFile { public var id: String; public var relPath: String; public var absPath: URL
            public init(id: String, relPath: String, absPath: URL) { self.id = id; self.relPath = relPath; self.absPath = absPath } }
        public struct Meta { public var appVersion: String; public var schemaVersion: String; public var exportedAt: String
            public var exportedFrom: PackManifest.ExportedFrom?; public var rowCounts: [String: Int]
            public init(appVersion: String, schemaVersion: String, exportedAt: String, exportedFrom: PackManifest.ExportedFrom?, rowCounts: [String: Int]) {
                self.appVersion = appVersion; self.schemaVersion = schemaVersion; self.exportedAt = exportedAt
                self.exportedFrom = exportedFrom; self.rowCounts = rowCounts } }
    }
    public struct BuiltPack { public let bytes: Data; public let manifest: PackManifest }

    /// Build a `.finch` pack as a single in-memory `Data`. Mirrors `buildPack`
    /// (pack.ts:99): DB DEFLATE, attachments STORE (sorted by rel_path), manifest
    /// DEFLATE last.
    public static func build(_ input: BuildInput) throws -> BuiltPack {
        let archive: Archive
        do { archive = try Archive(accessMode: .create) } catch { throw PackError.archiveCreateFailed }
        let dbSha = sha256Hex(input.dbBytes)
        try addEntry(archive, name: dbFilename, data: input.dbBytes, method: .deflate)

        let sorted = input.attachmentFiles.sorted { $0.relPath < $1.relPath }
        var items: [ManifestAttachment] = []
        var totalBytes = 0
        for att in sorted {
            guard att.relPath.hasPrefix(attachmentsPrefix) else {
                throw PackError.manifestInvalid("Attachment relPath outside \(attachmentsPrefix): \(att.relPath)")
            }
            let bytes = try Data(contentsOf: att.absPath)
            try addEntry(archive, name: att.relPath, data: bytes, method: .none)
            items.append(ManifestAttachment(id: att.id, relPath: att.relPath, byteSize: bytes.count, sha256: sha256Hex(bytes)))
            totalBytes += bytes.count
        }

        let manifest = PackManifest(
            packFormatVersion: formatVersion, appName: "finch",
            appVersion: input.meta.appVersion, schemaVersion: input.meta.schemaVersion,
            exportedAt: input.meta.exportedAt, exportedFrom: input.meta.exportedFrom,
            db: .init(filename: dbFilename, byteSize: input.dbBytes.count, sha256: dbSha, rowCounts: input.meta.rowCounts),
            attachments: .init(count: items.count, totalBytes: totalBytes, items: items))

        // Manifest LAST (it depends on the other entries' hashes).
        let manifestData = try manifestEncoder().encode(manifest)
        try addEntry(archive, name: manifestFilename, data: manifestData, method: .deflate)

        guard let bytes = archive.data else { throw PackError.archiveCreateFailed }
        return BuiltPack(bytes: bytes, manifest: manifest)
    }

    // MARK: Parse

    public struct ParsedPack {
        public let manifest: PackManifest
        let archive: Archive  // retained for extract
    }

    /// Open a pack and read + sanity-check the manifest (NOT per-file sha256 —
    /// that's `extract`'s job). Mirrors `parsePack` (pack.ts:179).
    public static func parse(_ bytes: Data) throws -> ParsedPack {
        let archive: Archive
        do { archive = try Archive(data: bytes, accessMode: .read) } catch { throw PackError.notAZip }
        guard archive[manifestFilename] != nil else { throw PackError.missingManifest }
        let manifestData = try entryData(archive, manifestFilename)
        let manifest: PackManifest
        do { manifest = try JSONDecoder().decode(PackManifest.self, from: manifestData) }
        catch { throw PackError.manifestInvalid("manifest.json is not valid JSON: \(error)") }

        guard manifest.packFormatVersion == formatVersion else {
            throw PackError.unsupportedVersion("Unsupported pack format version \(manifest.packFormatVersion) (this app understands \(formatVersion))")
        }
        guard manifest.appName == "finch" else { throw PackError.notFinch(manifest.appName) }
        guard manifest.db.sha256.count == 64 else { throw PackError.manifestInvalid("manifest.db.sha256 missing") }
        guard archive[dbFilename] != nil else { throw PackError.missingEntry(dbFilename) }

        for item in manifest.attachments.items {
            guard item.relPath.hasPrefix(attachmentsPrefix) else { throw PackError.manifestInvalid("Bad attachment rel_path: \(item.relPath)") }
            guard !item.relPath.contains("..") else { throw PackError.pathTraversal(item.relPath) }
            guard item.sha256.count == 64 else { throw PackError.manifestInvalid("Bad attachment sha256: \(item.id)") }
            guard item.byteSize >= 0 else { throw PackError.manifestInvalid("Bad attachment byte_size: \(item.id)") }
            guard archive[item.relPath] != nil else { throw PackError.missingEntry(item.relPath) }
        }
        return ParsedPack(manifest: manifest, archive: archive)
    }

    // MARK: Extract

    public struct ExtractedPack { public let dbPath: URL; public let attachmentsDir: URL; public let manifest: PackManifest }

    /// Extract a parsed pack to destDir, validating the DB sha256 + byte_size +
    /// every attachment along the way. Mirrors `extractPack` (pack.ts:256).
    public static func extract(_ parsed: ParsedPack, to destDir: URL) throws -> ExtractedPack {
        let fm = FileManager.default
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        let dbBytes = try entryData(parsed.archive, dbFilename)
        guard sha256Hex(dbBytes) == parsed.manifest.db.sha256 else {
            throw PackError.shaMismatch("DB sha256 mismatch")
        }
        guard dbBytes.count == parsed.manifest.db.byteSize else { throw PackError.manifestInvalid("DB byte_size mismatch") }
        let dbPath = destDir.appendingPathComponent(dbFilename)
        try dbBytes.write(to: dbPath)

        let attachmentsRoot = destDir.appendingPathComponent("attachments")
        try fm.createDirectory(at: attachmentsRoot, withIntermediateDirectories: true)
        for item in parsed.manifest.attachments.items {
            let bytes = try entryData(parsed.archive, item.relPath)
            guard sha256Hex(bytes) == item.sha256 else { throw PackError.shaMismatch("Attachment \(item.id) sha256 mismatch") }
            guard bytes.count == item.byteSize else { throw PackError.manifestInvalid("Attachment \(item.id) byte_size mismatch") }
            let absPath = item.relPath.split(separator: "/").reduce(destDir) { $0.appendingPathComponent(String($1)) }
            // Defense-in-depth: the result MUST live under destDir.
            guard absPath.standardizedFileURL.path.hasPrefix(destDir.standardizedFileURL.path + "/") else {
                throw PackError.pathTraversal(item.relPath)
            }
            try fm.createDirectory(at: absPath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: absPath)
        }
        return ExtractedPack(dbPath: dbPath, attachmentsDir: attachmentsRoot, manifest: parsed.manifest)
    }

    // MARK: detectFileKind

    public enum FileKind { case zip, sqlite, unknown }

    /// Recognise the first bytes as a ZIP local-file header (`PK\x03\x04`) or a
    /// SQLite header. Mirrors `detectFileKind` (pack.ts:310).
    public static func detectFileKind(_ head: Data) -> FileKind {
        let b = [UInt8](head.prefix(16))
        if b.count >= 4 && b[0] == 0x50 && b[1] == 0x4b && b[2] == 0x03 && b[3] == 0x04 { return .zip }
        if b.count >= 16 {
            let magic = String(decoding: b[0..<15], as: UTF8.self)
            if magic == "SQLite format 3" && b[15] == 0 { return .sqlite }
        }
        return .unknown
    }

    // MARK: helpers

    private static func manifestEncoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }

    private static func addEntry(_ archive: Archive, name: String, data: Data, method: CompressionMethod) throws {
        try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count),
                             compressionMethod: method) { position, size in
            let start = Int(position)
            return data.subdata(in: start ..< min(start + size, data.count))
        }
    }

    private static func entryData(_ archive: Archive, _ name: String) throws -> Data {
        guard let entry = archive[name] else { throw PackError.missingEntry(name) }
        var out = Data()
        _ = try archive.extract(entry) { out.append($0) }
        return out
    }
}

/// Errors from the pack module. Task 9 adds the import-pipeline cases
/// (migrationFailed / auditFailed / swapFailed) onto the consumer side.
public enum PackError: Error, Equatable {
    case notAZip
    case archiveCreateFailed
    case missingManifest
    case manifestInvalid(String)
    case unsupportedVersion(String)
    case notFinch(String)
    case missingEntry(String)
    case shaMismatch(String)
    case pathTraversal(String)
    // Import/export pipeline (FinchStore, DESIGN §4). String payloads (not
    // `Error`) keep PackError Equatable. `auditFailed` carries the gate's
    // problems so the import UI can surface them / offer the iOS-only override.
    case auditFailed([Audit.AuditProblem])
    case migrationFailed(String)
    case swapFailed(String)
    case exportFailed(String)
}

// MARK: - Manifest wire types (NESTED, snake_case via explicit CodingKeys)

public struct PackManifest: Codable, Equatable {
    public let packFormatVersion: String
    public let appName: String
    public let appVersion: String
    public let schemaVersion: String
    public let exportedAt: String
    public let exportedFrom: ExportedFrom?
    public let db: Db
    public let attachments: Attachments

    enum CodingKeys: String, CodingKey {
        case packFormatVersion = "pack_format_version"
        case appName = "app_name"
        case appVersion = "app_version"
        case schemaVersion = "schema_version"
        case exportedAt = "exported_at"
        case exportedFrom = "exported_from"
        case db, attachments
    }

    public struct ExportedFrom: Codable, Equatable {
        public let device: String
        public let deviceId: String?
        public let deviceName: String?
        public init(device: String, deviceId: String? = nil, deviceName: String? = nil) {
            self.device = device; self.deviceId = deviceId; self.deviceName = deviceName
        }
        enum CodingKeys: String, CodingKey {
            case device
            case deviceId = "device_id"
            case deviceName = "device_name"
        }
    }
    public struct Db: Codable, Equatable {
        public let filename: String
        public let byteSize: Int
        public let sha256: String
        public let rowCounts: [String: Int]   // snake_case table keys kept verbatim
        enum CodingKeys: String, CodingKey {
            case filename, sha256
            case byteSize = "byte_size"
            case rowCounts = "row_counts"
        }
    }
    public struct Attachments: Codable, Equatable {
        public let count: Int
        public let totalBytes: Int
        public let items: [ManifestAttachment]
        enum CodingKeys: String, CodingKey {
            case count, items
            case totalBytes = "total_bytes"
        }
    }
}

public struct ManifestAttachment: Codable, Equatable {
    public let id: String
    public let relPath: String
    public let byteSize: Int
    public let sha256: String
    enum CodingKeys: String, CodingKey {
        case id, sha256
        case relPath = "rel_path"
        case byteSize = "byte_size"
    }
}
