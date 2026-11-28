import XCTest
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import FinchCore
import GRDB
@testable import FinchApp

/// Every receipt is stored the way the web's `processBytes` stores it: an image
/// becomes an upright JPEG with no metadata, a PDF is kept. A photo used to be
/// stored exactly as Photos handed it over (usually HEIC, with its location)
/// under a `.jpg` name and an `image/jpeg` label, so a browser was told to open
/// a HEIC as a JPEG.
@MainActor
final class ReceiptFileTypeTests: XCTestCase {

    // MARK: Test images

    /// A plain image, wider than tall so a rotation shows.
    static func pixels(width: Int = 40, height: Int = 20) throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(ctx.makeImage())
    }

    /// What a phone camera writes: turned on its side by tag, with a location and a camera make.
    static let cameraProperties: [CFString: Any] = [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 37.33, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 122.03, kCGImagePropertyGPSLongitudeRef: "W",
        ] as [CFString: Any],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "TestCam"] as [CFString: Any],
    ]

    static func encode(_ type: UTType, properties: [CFString: Any] = cameraProperties) throws -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, try pixels(), properties as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    private func typeOf(_ data: Data) -> String? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
    }

    private func properties(_ data: Data) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    // MARK: The stored shape

    func test_aHEICPhotoIsStoredAsAJPEG() throws {
        guard let heic = try Self.encode(.heic) else { throw XCTSkip("this runtime can't encode HEIC") }
        XCTAssertEqual(typeOf(heic), UTType.heic.identifier, "the premise: a HEIC goes in")
        let stored = try AttachmentWriter.stored(heic)
        XCTAssertEqual(stored.kind, "image")
        XCTAssertEqual(stored.mime, "image/jpeg")
        XCTAssertEqual(stored.ext, "jpg")
        XCTAssertEqual(typeOf(stored.bytes), UTType.jpeg.identifier, "and a JPEG comes out, as labelled")
    }

    func test_aPNGIsStoredAsAJPEG() throws {
        let png = try XCTUnwrap(try Self.encode(.png, properties: [:]))
        let stored = try AttachmentWriter.stored(png)
        XCTAssertEqual(stored.mime, "image/jpeg")
        XCTAssertEqual(typeOf(stored.bytes), UTType.jpeg.identifier)
    }

    /// Turned upright by its tag, with the location and camera left behind.
    func test_theStoredPhotoIsUprightAndCarriesNoMetadata() throws {
        let photo = try XCTUnwrap(try Self.encode(.jpeg))
        let before = try properties(photo)
        XCTAssertNotNil(before[kCGImagePropertyGPSDictionary], "the premise: the photo carries a location")

        let after = try properties(try AttachmentWriter.stored(photo).bytes)
        XCTAssertEqual(after[kCGImagePropertyPixelWidth] as? Int, 20, "40×20 on its side is 20×40 upright")
        XCTAssertEqual(after[kCGImagePropertyPixelHeight] as? Int, 40)
        XCTAssertEqual((after[kCGImagePropertyOrientation] as? Int) ?? 1, 1, "no rotation left to apply")
        XCTAssertNil(after[kCGImagePropertyGPSDictionary], "no location")
        XCTAssertNil((after[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake], "no camera")
    }

    func test_aPDFIsKeptAsItIs() throws {
        let pdf = Data("%PDF-1.4\n%receipt\n".utf8)
        let stored = try AttachmentWriter.stored(pdf)
        XCTAssertEqual(stored.bytes, pdf)
        XCTAssertEqual(stored.kind, "pdf")
        XCTAssertEqual(stored.mime, "application/pdf")
        XCTAssertEqual(stored.ext, "pdf")
    }

    func test_somethingElseIsRefused() {
        XCTAssertThrowsError(try AttachmentWriter.stored(Data("not a receipt".utf8))) {
            XCTAssertEqual(($0 as? I18nError)?.code, "error.attachment.unreadable")
        }
        XCTAssertNotEqual(i18nMessage(AttachmentWriter.unreadable, zh: true), AttachmentWriter.unreadable.message,
                          "and it has Chinese")
    }

    // MARK: Writers

    /// A picked photo lands as a JPEG on disk under a `.jpg` name, its row says
    /// so, and the row's hash is the stored file's.
    func test_aPickedPhotoIsRecordedAsWhatItIs() async throws {
        let store = try await SharedStoreFixture.load()
        let entryId = try XCTUnwrap(store.txns.first?.id)
        let before = Set(store.attachments(for: entryId).map(\.id))
        try await AttachmentWriter.write(photo: try XCTUnwrap(try Self.encode(.png, properties: [:])),
                                         entryId: entryId, store: store)
        let row = try XCTUnwrap(store.attachments(for: entryId).first { !before.contains($0.id) })
        XCTAssertTrue(row.relPath.hasSuffix(".jpg"), row.relPath)
        let q = try XCTUnwrap(store.dbQueue)
        let found: Row? = try await q.read { db in
            try Row.fetchOne(db, sql: "SELECT mime_type, sha256 FROM entry_attachments WHERE id = ?", arguments: [row.id])
        }
        let recorded = try XCTUnwrap(found)
        XCTAssertEqual(recorded["mime_type"] as String?, "image/jpeg")
        let onDisk = try Data(contentsOf: store.attachmentURL(for: row))
        XCTAssertEqual(typeOf(onDisk), UTType.jpeg.identifier)
        XCTAssertEqual(recorded["sha256"] as String?, SHA256.hash(data: onDisk).map { String(format: "%02x", $0) }.joined())
    }
}
