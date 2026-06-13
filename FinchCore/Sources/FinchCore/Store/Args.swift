import Foundation

/// The per-action mutation arguments — a type-erased JSON object. The chokepoint
/// dispatcher routes `(ActionName, Args)` to a per-domain handler, which decodes
/// the args into a concrete Swift struct via `to(_:)`. Mirrors the web's `Args`
/// map (`lib/db/domain/_args.ts`).
public struct Args: Codable, Sendable, Equatable {
    public let values: [String: JSONValue]

    public init(_ values: [String: JSONValue]) { self.values = values }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.values = try c.decode([String: JSONValue].self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(values)
    }

    /// Decode the args into a concrete `Decodable` per-action struct.
    public func to<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(values)
        return try JSONDecoder().decode(type, from: data)
    }
}
