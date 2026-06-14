import Foundation

/// A receipt attached to an entry (for in-app display/remove).
public struct AttachmentRow: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let kind: String          // "image" | "pdf"
    public let relPath: String
    public let originalFilename: String?
    public init(id: String, kind: String, relPath: String, originalFilename: String?) {
        self.id = id; self.kind = kind; self.relPath = relPath; self.originalFilename = originalFilename
    }
}
