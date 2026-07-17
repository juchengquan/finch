import Foundation
import FinchCore

/// Builds the `updateTransfer` patch for the Edit sheet's transfer editor.
/// Pure and unit-tested: only CHANGED keys are included (an empty patch means
/// "nothing to save"); amounts are validated > 0. Same-currency transfers send
/// `fromAmount` only — the engine ratio-scales the other leg, which for equal
/// legs keeps them equal (sending both would trip its mismatch check on
/// rounding). Cross-currency sends whichever side(s) changed.
enum TransferEditPatch {
    struct Inputs {
        var sameCurrency: Bool
        var originalFrom: Double        // abs native from-leg amount
        var originalTo: Double          // abs native to-leg amount
        var editedFrom: String          // the From-amount field (same-currency: the single Amount field)
        var editedTo: String?           // the To-amount field (cross-currency only; nil otherwise)
        var originalDate: String        // yyyy-MM-dd
        var originalTime: String?       // HH:mm (nil when the entry has none)
        var originalNote: String?
        var newDate: String
        var newTime: String
        var newNote: String
    }

    enum Failure: Error, Equatable { case badAmount }

    static func build(_ i: Inputs) -> Result<[String: JSONValue], Failure> {
        var patch: [String: JSONValue] = [:]
        guard let from = DecimalInput.parse(i.editedFrom), from > 0 else { return .failure(.badAmount) }
        if abs(from - i.originalFrom) > 0.001 { patch["fromAmount"] = .double(from) }
        if !i.sameCurrency {
            guard let toText = i.editedTo, let to = DecimalInput.parse(toText), to > 0 else {
                return .failure(.badAmount)
            }
            if abs(to - i.originalTo) > 0.001 { patch["toAmount"] = .double(to) }
        }
        if i.newDate != i.originalDate { patch["date"] = .string(i.newDate) }
        if i.newTime != (i.originalTime ?? "") { patch["time"] = .string(i.newTime) }
        if i.newNote != (i.originalNote ?? "") {
            patch["note"] = i.newNote.isEmpty ? .null : .string(i.newNote)
        }
        return .success(patch)
    }
}
