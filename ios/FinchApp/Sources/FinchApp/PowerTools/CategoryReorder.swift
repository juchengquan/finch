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
/// destination). `rows` is the projection's sort_order-ordered list, so the
/// destination's children appear in order and the append index is their count.
enum CategoryReorder {
    /// Nest `sourceId` under `destParentId` (nil = top level), appended after the
    /// destination's current children. Returns nil for a no-op (dropping onto
    /// itself). Cycle / depth validity is enforced downstream by the engine.
    static func reparent(_ sourceId: String, under destParentId: String?, in rows: [CategoryRow]) -> CategoryMove? {
        if let dest = destParentId, dest == sourceId { return nil }   // onto itself
        let siblingCount = rows.filter { $0.parentId == destParentId && $0.id != sourceId }.count
        return CategoryMove(id: sourceId, parentId: destParentId, sortOrder: siblingCount)
    }
}
