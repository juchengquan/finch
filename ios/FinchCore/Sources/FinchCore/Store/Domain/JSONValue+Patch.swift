import Foundation
import GRDB

extension JSONValue {
    /// The string payload, or nil for any non-string (incl. .null).
    var asString: String? { if case .string(let s) = self { return s }; return nil }

    /// True only for a non-empty, trimmed string value.
    var isNonEmptyTrimmedString: Bool {
        if case .string(let s) = self { return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return false
    }

    /// Bind a patch value to SQLite (string/int/double/bool pass through; null → nil).
    var sqlBind: DatabaseValueConvertible? {
        switch self {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .null, .array, .object: return nil
        }
    }
}
