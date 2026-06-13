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

    /// Numeric payload as Double (int or double); nil otherwise.
    var asDouble: Double? {
        switch self { case .int(let i): return Double(i); case .double(let d): return d; default: return nil }
    }

    /// String elements of an array value (empty for non-arrays).
    var asStringArray: [String] {
        if case .array(let a) = self { return a.compactMap { $0.asString } }
        return []
    }

    /// Serialize back to a JSON string (for storing condition/actions blobs).
    var jsonString: String {
        guard let data = try? JSONEncoder().encode(self), let s = String(data: data, encoding: .utf8) else { return "null" }
        return s
    }

    /// JS-style truthiness (true, non-zero number, non-empty string).
    var isTruthy: Bool {
        switch self {
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .double(let d): return d != 0
        case .string(let s): return !s.isEmpty
        case .null, .array, .object: return false
        }
    }
}

extension Args {
    /// The `id` field as a string (or nil).
    var idString: String? { values["id"]?.asString }
    /// The nested `patch` object (empty if absent / not an object).
    var patchObject: [String: JSONValue] {
        if case .object(let p)? = values["patch"] { return p }
        return [:]
    }
}

/// YYYY-MM-DD format check (mirrors the web `/^\d{4}-\d{2}-\d{2}$/`).
func isYMD(_ s: String) -> Bool {
    guard s.count == 10 else { return false }
    let p = s.split(separator: "-", omittingEmptySubsequences: false)
    guard p.count == 3, p[0].count == 4, p[1].count == 2, p[2].count == 2 else { return false }
    return p.allSatisfy { $0.allSatisfy(\.isNumber) }
}
