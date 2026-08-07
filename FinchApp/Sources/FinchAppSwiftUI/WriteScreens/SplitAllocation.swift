import Foundation

/// The rows of a split and the arithmetic that keeps them adding up to the total.
/// Axis-agnostic: a purchase split across CATEGORIES (`CategoryPickerRow`) and one
/// split across the ACCOUNTS that paid for it (`SearchablePickerRow`'s `splitting`)
/// share this one allocation model rather than each carrying its own copy.
///
/// Deliberately free of SwiftUI: this is where every allocation rule lives, so the
/// rules are tested directly instead of through a sheet. The view owns presentation
/// only. See `ios/docs/category-split-toggle-design.md` for why each rule is what it is.
struct SplitAllocation: Equatable {

    /// One ticked category or account. `pinned` means the user typed this amount,
    /// so it is held fixed and the unpinned rows divide whatever is left around it.
    struct Row: Equatable, Identifiable {
        /// Category or account id; `""` is the Uncategorized row (a `nil` leg to the
        /// engine) — meaningful for categories only, since every account has a real id.
        var id: String
        var amount: Double
        var pinned: Bool
    }

    private(set) var rows: [Row] = []
    private(set) var total: Double

    init(total: Double) { self.total = total }

    var allocated: Double { rows.reduce(0) { $0 + $1.amount } }
    func isTicked(_ id: String) -> Bool { rows.contains { $0.id == id } }

    mutating func tick(_ id: String) {
        guard !isTicked(id) else { return }
        rows.append(Row(id: id, amount: 0, pinned: false))
        redistribute()
    }

    /// A value pins the row (the user typed it); `nil` unpins it so it floats again.
    mutating func setAmount(_ id: String, _ amount: Double?) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        if let amount {
            rows[i].amount = Self.round2(amount)
            rows[i].pinned = true
        } else {
            rows[i].pinned = false
        }
        redistribute()
    }

    mutating func untick(_ id: String) {
        rows.removeAll { $0.id == id }
        redistribute()
    }

    mutating func setTotal(_ total: Double) {
        self.total = total
        redistribute()
    }

    /// Divide what the pinned rows have not claimed evenly across the unpinned ones,
    /// giving the last of them the remainder so the rows sum to the total exactly —
    /// the same trick the engine uses on its final leg rather than leaving a residue.
    private mutating func redistribute() {
        let claimed = rows.filter(\.pinned).reduce(0) { $0 + $1.amount }
        let free = rows.indices.filter { !rows[$0].pinned }
        guard !free.isEmpty else { return }
        let remaining = max(0, Self.round2(total - claimed))
        let share = Self.round2(remaining / Double(free.count))
        var used = 0.0
        for (n, i) in free.enumerated() {
            let isLast = n == free.count - 1
            rows[i].amount = isLast ? Self.round2(remaining - used) : share
            if !isLast { used += share }
        }
    }

    static func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }

    // MARK: - Validation and collapse

    /// Why Confirm is blocked, or nil when the selection is writable.
    enum Problem: Equatable {
        /// Two-plus ticked but the transaction has no amount to divide yet.
        case needsAmount
        /// Two-plus ticked but fewer than two carry a positive amount.
        case needsTwo
        /// Funded rows do not add up to the total.
        case sumMismatch
    }

    private var funded: [Row] { rows.filter { $0.amount > 0 } }

    var problem: Problem? {
        // Fewer than two ticked is not a split at all — it is a plain single-category
        // transaction, which is legal and is all the engine will accept below two.
        guard rows.count >= 2 else { return nil }
        guard total > 0 else { return .needsAmount }
        guard funded.count >= 2 else { return .needsTwo }
        let sum = funded.reduce(0) { $0 + $1.amount }
        // Same tolerance the split editor used, and looser than the engine's own.
        guard abs(sum - total) <= 0.01 * Double(funded.count) else { return .sumMismatch }
        return nil
    }

    /// The row a collapse keeps — the largest leg, matching the rule the projection
    /// already uses to pick the category a split displays (and, for accounts, the
    /// same "keep the biggest one" rule applied one axis over).
    ///
    /// **Ties go to the LAST ticked.** The pickers no longer collect amounts, so
    /// a freshly ticked split is all zeros and every row ties; the newest choice
    /// is the most recent thing the user actually said. A REOPENED split does
    /// carry amounts, and there the largest still wins outright.
    ///
    /// `max(by:)` cannot express this — it keeps the first among equals — so the
    /// scan is explicit.
    var dominantId: String? {
        var best: Row?
        for row in rows where best == nil || row.amount >= best!.amount { best = row }
        return best?.id
    }

    /// What gets written. Zero rows drop out; `""` becomes a nil (uncategorised) leg
    /// — moot for accounts, which never tick an empty id.
    var payload: [(id: String?, amount: Double)] {
        funded.map { (id: $0.id.isEmpty ? nil : $0.id, amount: $0.amount) }
    }

    /// Load stored splits, folding repeats into one row each. Rows arrive PINNED:
    /// they are amounts the user set before, and must not be re-divided on open.
    static func merging(_ splits: [(id: String?, amount: Double)], total: Double) -> SplitAllocation {
        var out = SplitAllocation(total: total)
        for s in splits {
            let id = s.id ?? ""
            if let i = out.rows.firstIndex(where: { $0.id == id }) {
                out.rows[i].amount = round2(out.rows[i].amount + abs(s.amount))
            } else {
                out.rows.append(Row(id: id, amount: round2(abs(s.amount)), pinned: true))
            }
        }
        return out
    }
}
