import Foundation
import FinchCore

/// A single category move: set `id`'s parent + sort_order. Applied via
/// `updateCategory` (parentId + sortOrder patch).
struct CategoryMove: Equatable {
    let id: String
    let parentId: String?
    let sortOrder: Int
}

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
}
