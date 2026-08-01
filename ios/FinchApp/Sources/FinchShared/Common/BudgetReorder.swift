import Foundation
import FinchCore

/// A row in the flat reorder list: a group header (id == nil → Ungrouped) or a
/// budget. Used only while reordering on the Budgets tab.
enum BudgetReorderRow: Identifiable, Equatable {
    case group(id: String?, name: String)
    case item(BudgetRow)

    var id: String {
        switch self {
        case .group(let gid, let n): return "g:\(gid ?? "ungrouped"):\(n)"
        case .item(let b): return "i:\(b.id)"
        }
    }

    /// The pinned Ungrouped bucket (`id == nil`) cannot be lifted — `itemsForBeginning`
    /// refuses it — so it must not advertise a grip either.
    var isDraggable: Bool { if case .group(let gid, _) = self { return gid != nil }; return true }
    var isItem: Bool { if case .item = self { return true }; return false }
}

/// Pure reorder logic for the Budgets tab. SwiftUI-free → unit-testable.
/// Mirror of `AccountReorder` typed to `BudgetRow` (deliberate parallel).
enum BudgetReorder {
    /// Flat snapshot: each real group (in order) + its budgets, then the
    /// Ungrouped bucket (pinned last) + its budgets.
    static func buildRows(groups: [GroupRow], budgets: [BudgetRow]) -> [BudgetReorderRow] {
        var rows: [BudgetReorderRow] = []
        for g in groups {
            rows.append(.group(id: g.id, name: g.name))
            for b in budgets where b.groupId == g.id { rows.append(.item(b)) }
        }
        rows.append(.group(id: nil, name: "Ungrouped"))
        for b in budgets where b.groupId == nil { rows.append(.item(b)) }
        return rows
    }

    /// Apply a List move under the group rules. Budgets keep their dropped
    /// position (membership is derived later by `plan`); real groups move as a
    /// block by rebuilding from the new group order; the Ungrouped header is
    /// pinned (its move is a no-op).
    static func applyMove(_ rows: [BudgetReorderRow], from source: IndexSet, to destination: Int) -> [BudgetReorderRow] {
        guard let src = source.first, src < rows.count else { return rows }
        switch rows[src] {
        case .item:
            var out = rows
            out.move(fromOffsets: source, toOffset: destination)
            if !out.isEmpty, out[0].isItem {              // never leave a budget above the first header
                let b = out.remove(at: 0); out.insert(b, at: 1)
            }
            return out
        case .group(let gid, _) where gid == nil:
            return rows                                    // Ungrouped header pinned
        case .group(let gid, _):
            return rebuildWithGroupOrder(rows, movedGroup: gid!, toFlatIndex: destination)
        }
    }

    /// Rows visible when `collapsed` groups hide their budget rows. Ungrouped
    /// budgets (current header == nil) are always visible.
    static func visibleRows(_ rows: [BudgetReorderRow], collapsed: Set<String>) -> [BudgetReorderRow] {
        var out: [BudgetReorderRow] = []; var current: String? = nil
        for r in rows {
            switch r {
            case .group(let id, _): current = id; out.append(r)
            case .item: if current == nil || !collapsed.contains(current!) { out.append(r) }
            }
        }
        return out
    }

    /// Number of budgets under a real group header (for the collapsed row label).
    static func itemCount(of groupId: String, in rows: [BudgetReorderRow]) -> Int {
        var current: String? = nil; var n = 0
        for r in rows {
            switch r {
            case .group(let id, _): current = id
            case .item: if current == groupId { n += 1 }
            }
        }
        return n
    }

    /// Translate a move expressed in *visible* indices into the full row array,
    /// then apply the existing rules. The destination maps to the full index of
    /// the visible row at `destination` (or past the end) — so dropping a budget
    /// just below a collapsed header lands at the END of that group.
    static func applyVisibleMove(_ rows: [BudgetReorderRow], collapsed: Set<String>,
                                 from source: IndexSet, to destination: Int) -> [BudgetReorderRow] {
        let vis = visibleRows(rows, collapsed: collapsed)
        guard let vSrc = source.first, vSrc < vis.count else { return rows }
        guard let fSrc = rows.firstIndex(of: vis[vSrc]) else { return rows }
        let fDst = destination >= vis.count ? rows.count
                 : (rows.firstIndex(of: vis[destination]) ?? rows.count)
        return applyMove(rows, from: IndexSet(integer: fSrc), to: fDst)
    }

    /// Recompute the real-group order after a header drag, then rebuild the flat
    /// rows so each group's budgets stay with it; Ungrouped stays last.
    private static func rebuildWithGroupOrder(_ rows: [BudgetReorderRow], movedGroup gid: String, toFlatIndex dest: Int) -> [BudgetReorderRow] {
        var order: [String] = []
        for r in rows { if case .group(let id?, _) = r { order.append(id) } }
        guard let from = order.firstIndex(of: gid) else { return rows }
        // target position = number of real-group headers strictly above `dest`,
        // not counting the moved group.
        var targetPos = 0
        for i in 0..<min(dest, rows.count) {
            if case .group(let id?, _) = rows[i], id != gid { targetPos += 1 }
        }
        order.remove(at: from)
        order.insert(gid, at: min(targetPos, order.count))
        // names + budgets from current rows.
        var nameOf: [String: String] = [:]
        var itemsOf: [String: [BudgetReorderRow]] = [:]
        var ungroupedItems: [BudgetReorderRow] = []
        var current: String? = nil
        for r in rows {
            switch r {
            case .group(let id, let n): if let id { nameOf[id] = n; current = id; itemsOf[id] = [] } else { current = nil }
            case .item: if let c = current { itemsOf[c, default: []].append(r) } else { ungroupedItems.append(r) }
            }
        }
        var out: [BudgetReorderRow] = []
        for id in order { out.append(.group(id: id, name: nameOf[id] ?? "")); out.append(contentsOf: itemsOf[id] ?? []) }
        out.append(.group(id: nil, name: "Ungrouped")); out.append(contentsOf: ungroupedItems)
        return out
    }

    /// Derive the persisted state by walking top→bottom: each real group gets the
    /// next group order; each budget belongs to the most recent header (nil =
    /// Ungrouped) with a running per-group order.
    static func plan(_ rows: [BudgetReorderRow]) -> (groups: [(id: String, order: Int)], items: [(id: String, groupId: String?, order: Int)]) {
        var groups: [(id: String, order: Int)] = []
        var items: [(id: String, groupId: String?, order: Int)] = []
        var currentGroup: String? = nil
        var groupOrder = 0
        var orderInGroup = 0
        for r in rows {
            switch r {
            case .group(let gid, _):
                if let gid { groups.append((id: gid, order: groupOrder)); groupOrder += 1 }
                currentGroup = gid
                orderInGroup = 0
            case .item(let b):
                items.append((id: b.id, groupId: currentGroup, order: orderInGroup)); orderInGroup += 1
            }
        }
        return (groups, items)
    }
}
