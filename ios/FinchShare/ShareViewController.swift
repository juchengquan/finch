import UIKit
import UniformTypeIdentifiers
import CryptoKit
import FinchCore

/// Phase 6.5 — the Share Extension. Accepts a photo or PDF from any app's share
/// sheet, stages it (+ a manifest) into the shared App Group container, and
/// returns. The finch app imports staged manifests on next launch (creating a
/// transaction + dispatching setEntryAttachment). Minimal UI: a brief confirm.
final class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await handle() }
    }

    private func handle() async {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else { return complete() }
        for type in [UTType.image, UTType.pdf] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let loaded = try? await provider.loadItem(forTypeIdentifier: type.identifier) {
                stage(loaded, isPdf: type == .pdf)
            }
            break
        }
        complete()
    }

    private func stage(_ item: NSSecureCoding, isPdf: Bool) {
        var data: Data?
        var ext = isPdf ? "pdf" : "jpg"
        var originalName: String?
        if let url = item as? URL {
            data = try? Data(contentsOf: url)
            if !url.pathExtension.isEmpty { ext = url.pathExtension }
            originalName = url.lastPathComponent
        } else if let d = item as? Data {
            data = d
        } else if let img = item as? UIImage {
            data = img.jpegData(compressionQuality: 0.9)
        }
        guard let bytes = data else { return }

        let id = "att-\(UUID().uuidString.prefix(8).lowercased())"
        let filesDir = AppGroup.pendingFilesDir.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
        let rel = "pending_attachments/files/\(id)/\(id).\(ext)"
        try? bytes.write(to: AppGroup.containerURL.appendingPathComponent(rel))

        let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let manifest = PendingAttachment(
            id: id, kind: isPdf ? "pdf" : "image", relPath: rel,
            mimeType: isPdf ? "application/pdf" : "image/jpeg",
            byteSize: bytes.count, sha256: sha, originalFilename: originalName)
        try? FileManager.default.createDirectory(at: AppGroup.pendingManifestsDir, withIntermediateDirectories: true)
        if let mdata = try? JSONEncoder().encode(manifest) {
            try? mdata.write(to: AppGroup.pendingManifestsDir.appendingPathComponent("\(id).json"))
        }
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
