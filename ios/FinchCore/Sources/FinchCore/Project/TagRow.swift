import Foundation

/// Phase 4 — a tag row for the tag-admin list.
public struct TagRow: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let color: String?
    public init(id: String, name: String, color: String?) { self.id = id; self.name = name; self.color = color }
}
