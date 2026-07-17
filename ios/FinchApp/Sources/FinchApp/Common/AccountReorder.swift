import Foundation
import FinchCore

/// A row in the flat reorder list: a group header (id == nil → Ungrouped) or an
/// account. Used only while reordering on the Accounts tab.
enum ReorderRow: Identifiable, Equatable {
    case group(id: String?, name: String)
    case account(AccountRow)

    var id: String {
        switch self {
        case .group(let gid, let n): return "g:\(gid ?? "ungrouped"):\(n)"
        case .account(let a): return "a:\(a.id)"
        }
    }
    var isAccount: Bool { if case .account = self { return true }; return false }
}

/// Pure reorder logic for the Accounts tab. SwiftUI-free → unit-testable.
enum AccountReorder {
    /// Flat snapshot: each real group (in order) + its accounts, then the
    /// Ungrouped bucket (pinned last) + its accounts.
    static func buildRows(groups: [AccountGroupRow], accounts: [AccountRow]) -> [ReorderRow] {
        var rows: [ReorderRow] = []
        for g in groups {
            rows.append(.group(id: g.id, name: g.name))
            for a in accounts where a.groupId == g.id { rows.append(.account(a)) }
        }
        rows.append(.group(id: nil, name: "Ungrouped"))
        for a in accounts where a.groupId == nil { rows.append(.account(a)) }
        return rows
    }

    /// Apply a List move under the group rules. Accounts keep their dropped
    /// position (membership is derived later by `persistencePlan`); real groups
    /// move as a block by rebuilding from the new group order; the Ungrouped
    /// header is pinned (its move is a no-op).
    static func applyMove(_ rows: [ReorderRow], from source: IndexSet, to destination: Int) -> [ReorderRow] {
        guard let src = source.first, src < rows.count else { return rows }
        switch rows[src] {
        case .account:
            var out = rows
            out.move(fromOffsets: source, toOffset: destination)
            if !out.isEmpty, out[0].isAccount {           // never leave an account above the first header
                let a = out.remove(at: 0); out.insert(a, at: 1)
            }
            return out
        case .group(let gid, _) where gid == nil:
            return rows                                    // Ungrouped header pinned
        case .group(let gid, _):
            return rebuildWithGroupOrder(rows, movedGroup: gid!, toFlatIndex: destination)
        }
    }

    /// Rows visible when `collapsed` groups hide their account rows. Ungrouped
    /// accounts (current header == nil) are always visible.
    static func visibleRows(_ rows: [ReorderRow], collapsed: Set<String>) -> [ReorderRow] {
        var out: [ReorderRow] = []; var current: String? = nil
        for r in rows {
            switch r {
            case .group(let id, _): current = id; out.append(r)
            case .account: if current == nil || !collapsed.contains(current!) { out.append(r) }
            }
        }
        return out
    }

    /// Number of accounts under a real group header (for the collapsed row label).
    static func accountCount(of groupId: String, in rows: [ReorderRow]) -> Int {
        var current: String? = nil; var n = 0
        for r in rows {
            switch r {
            case .group(let id, _): current = id
            case .account: if current == groupId { n += 1 }
            }
        }
        return n
    }

    /// Translate a move expressed in *visible* indices into the full row array,
    /// then apply the existing rules. The destination maps to the full index of
    /// the visible row at `destination` (or past the end) — so dropping an
    /// account just below a collapsed header lands at the END of that group.
    static func applyVisibleMove(_ rows: [ReorderRow], collapsed: Set<String>,
                                 from source: IndexSet, to destination: Int) -> [ReorderRow] {
        let vis = visibleRows(rows, collapsed: collapsed)
        guard let vSrc = source.first, vSrc < vis.count else { return rows }
        guard let fSrc = rows.firstIndex(of: vis[vSrc]) else { return rows }
        let fDst = destination >= vis.count ? rows.count
                 : (rows.firstIndex(of: vis[destination]) ?? rows.count)
        return applyMove(rows, from: IndexSet(integer: fSrc), to: fDst)
    }

    /// Recompute the real-group order after a header drag, then rebuild the flat
    /// rows so each group's accounts stay with it; Ungrouped stays last.
    private static func rebuildWithGroupOrder(_ rows: [ReorderRow], movedGroup gid: String, toFlatIndex dest: Int) -> [ReorderRow] {
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
        // names + accounts from current rows.
        var nameOf: [String: String] = [:]
        var acctsOf: [String: [ReorderRow]] = [:]
        var ungroupedAccts: [ReorderRow] = []
        var current: String? = nil
        for r in rows {
            switch r {
            case .group(let id, let n): if let id { nameOf[id] = n; current = id; acctsOf[id] = [] } else { current = nil }
            case .account: if let c = current { acctsOf[c, default: []].append(r) } else { ungroupedAccts.append(r) }
            }
        }
        var out: [ReorderRow] = []
        for id in order { out.append(.group(id: id, name: nameOf[id] ?? "")); out.append(contentsOf: acctsOf[id] ?? []) }
        out.append(.group(id: nil, name: "Ungrouped")); out.append(contentsOf: ungroupedAccts)
        return out
    }

    /// Derive the persisted state by walking top→bottom: each real group gets the
    /// next group order; each account belongs to the most recent header (nil =
    /// Ungrouped) with a running per-group order.
    static func persistencePlan(_ rows: [ReorderRow]) -> (groups: [(id: String, order: Int)], accounts: [(id: String, groupId: String?, order: Int)]) {
        var groups: [(id: String, order: Int)] = []
        var accounts: [(id: String, groupId: String?, order: Int)] = []
        var currentGroup: String? = nil
        var groupOrder = 0
        var orderInGroup = 0
        for r in rows {
            switch r {
            case .group(let gid, _):
                if let gid { groups.append((id: gid, order: groupOrder)); groupOrder += 1 }
                currentGroup = gid
                orderInGroup = 0
            case .account(let a):
                accounts.append((id: a.id, groupId: currentGroup, order: orderInGroup)); orderInGroup += 1
            }
        }
        return (groups, accounts)
    }
}
