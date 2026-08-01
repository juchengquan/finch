import Foundation

/// The rows of a split and the arithmetic that keeps them adding up to the total.
///
/// Deliberately free of SwiftUI: this is where every allocation rule lives, so the
/// rules are tested directly instead of through a sheet. The view owns presentation
/// only. See `ios/docs/category-split-toggle-design.md` for why each rule is what it is.
struct SplitAllocation: Equatable {

    /// One ticked category. `pinned` means the user typed this amount, so it is held
    /// fixed and the unpinned rows divide whatever is left around it.
    struct Row: Equatable, Identifiable {
        /// Category id; `""` is the Uncategorized row (a `nil` leg to the engine).
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
}
