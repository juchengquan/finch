import Foundation
import FinchCore

/// A single category move: set `id`'s parent + sort_order. Applied via
/// `updateCategory` (parentId + sortOrder patch).
struct CategoryMove: Equatable {
    let id: String
    let parentId: String?
    let sortOrder: Int
}

/// Where a sibling-reorder drop lands relative to the target row.
enum InsertPosition { case before, after }

/// Pure drop math for the category tree. CP2 Step 1 = reparent (append under the
/// destination). Uses max(sortOrder)+1 among siblings to place the moved row last
/// even when sibling sort_order values are sparse/large (engine assigns globally).
enum CategoryReorder {
    /// Nest `sourceId` under `destParentId` (nil = top level), appended after the
    /// destination's current children. Returns nil for a no-op (dropping onto
    /// itself). Cycle / depth validity is enforced downstream by the engine.
    static func reparent(_ sourceId: String, under destParentId: String?, in rows: [CategoryRow]) -> CategoryMove? {
        if let dest = destParentId, dest == sourceId { return nil }   // onto itself
        let siblings = rows.filter { $0.parentId == destParentId && $0.id != sourceId }
        let nextSort = (siblings.map(\.sortOrder).max() ?? -1) + 1
        return CategoryMove(id: sourceId, parentId: destParentId, sortOrder: nextSort)
    }

    /// Insert `sourceId` before/after `targetId` within the target's sibling
    /// group (parent = the target's parent), renumbering that group 0,1,2,….
    /// Returns a move for every member in the new order, or `[]` for a no-op
    /// (source == target, target missing, or order unchanged). `rows` is the
    /// projection's sort_order-ordered list, so the filtered group is in order.
    static func reorder(_ sourceId: String, _ position: InsertPosition, of targetId: String, in rows: [CategoryRow]) -> [CategoryMove] {
        guard sourceId != targetId,
              let target = rows.first(where: { $0.id == targetId }),
              let source = rows.first(where: { $0.id == sourceId }) else { return [] }
        let destParent = target.parentId
        var group = rows.filter { $0.parentId == destParent && $0.id != sourceId }
        guard let ti = group.firstIndex(where: { $0.id == targetId }) else { return [] }
        let insertAt = position == .before ? ti : ti + 1
        group.insert(source, at: insertAt)
        // No-op: the group already has exactly this id order (source already in place).
        let currentIds = rows.filter { $0.parentId == destParent }.map(\.id)
        if currentIds == group.map(\.id) { return [] }
        return group.enumerated().map { idx, row in
            CategoryMove(id: row.id, parentId: destParent, sortOrder: idx)
        }
    }
}
