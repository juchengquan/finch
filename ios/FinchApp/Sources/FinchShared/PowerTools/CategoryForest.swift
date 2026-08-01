import Foundation
import FinchCore

/// Step limit for every ancestor walk in this file.
///
/// Derived from `Categories.maxDepth`, never a literal: these bounds exist to stop a
/// walk spinning forever on corrupt data, which is a different job from the depth
/// rule. When the two are written independently, raising the cap leaves the walks
/// one step short and they start returning wrong answers with no error.
private let ancestorWalkLimit = Categories.maxDepth + 2

/// A node in the category forest. Depth is capped at `Categories.maxDepth`,
/// enforced by the engine, not here.
struct CategoryTreeNode: Identifiable, Equatable {
    let row: CategoryRow
    let children: [CategoryTreeNode]
    var id: String { row.id }
}

/// Build a forest from a flat, sort_order-ordered category list. A row whose
/// `parentId` is nil OR points to a missing id becomes a top-level node (orphan
/// promotion, mirroring the web). Input order is preserved within each level.
func categoryForest(_ rows: [CategoryRow]) -> [CategoryTreeNode] {
    let ids = Set(rows.map(\.id))
    var childrenOf: [String: [CategoryRow]] = [:]
    var tops: [CategoryRow] = []
    for r in rows {
        if let p = r.parentId, ids.contains(p) { childrenOf[p, default: []].append(r) }
        else { tops.append(r) }
    }
    func node(_ r: CategoryRow) -> CategoryTreeNode {
        CategoryTreeNode(row: r, children: (childrenOf[r.id] ?? []).map(node))
    }
    return tops.map(node)
}

/// Effective icon short-name: own → nearest ancestor's → nil (caller maps nil to
/// the default symbol).
///
/// The walk is bounded only so corrupt data cannot spin it forever, and the bound
/// is DERIVED from the depth cap. It was a literal `4` justified by "the tree is ≤3
/// deep" — which silently becomes wrong the moment the cap rises: a category deeper
/// than the bound would stop walking before reaching the ancestor that actually
/// carries the icon, and quietly render the default instead.
func effectiveIcon(_ row: CategoryRow, _ byId: [String: CategoryRow]) -> String? {
    var cur: CategoryRow? = row
    var hops = 0
    while let c = cur, hops < ancestorWalkLimit {
        if let icon = c.icon, !icon.isEmpty { return icon }
        cur = c.parentId.flatMap { byId[$0] }; hops += 1
    }
    return nil
}

/// Effective color hex: own → nearest ancestor's → `CategoryPalette.defaultHex`.
/// Same derived bound as `effectiveIcon` — see the note there.
func effectiveColor(_ row: CategoryRow, _ byId: [String: CategoryRow]) -> String {
    var cur: CategoryRow? = row
    var hops = 0
    while let c = cur, hops < ancestorWalkLimit {
        if let color = c.color, !color.isEmpty { return color }
        cur = c.parentId.flatMap { byId[$0] }; hops += 1
    }
    return CategoryPalette.defaultHex
}

/// A flattened, display-ready row (the node + its depth + whether it has kids).
struct FlatCategory: Identifiable, Equatable {
    let row: CategoryRow
    let depth: Int
    let hasChildren: Bool
    var id: String { row.id }
}

/// Depth-first flatten honoring expand/collapse and search.
/// - Empty search: a node's children appear only if its id is in `expanded`.
/// - Non-empty search: a node appears iff it OR a descendant matches (name,
///   case-insensitive); included nodes always show their (matching-bearing)
///   children, so ancestors of a match are force-expanded.
func flattenCategories(_ forest: [CategoryTreeNode], expanded: Set<String>, search: String) -> [FlatCategory] {
    let q = search.trimmingCharacters(in: .whitespaces).lowercased()
    func matches(_ n: CategoryTreeNode) -> Bool { n.row.name.lowercased().contains(q) }
    func subtreeMatches(_ n: CategoryTreeNode) -> Bool { matches(n) || n.children.contains(where: subtreeMatches) }
    var out: [FlatCategory] = []
    func walk(_ n: CategoryTreeNode, _ depth: Int) {
        if !q.isEmpty && !subtreeMatches(n) { return }
        out.append(FlatCategory(row: n.row, depth: depth, hasChildren: !n.children.isEmpty))
        let showChildren = q.isEmpty ? expanded.contains(n.row.id) : true
        if showChildren { for c in n.children { walk(c, depth + 1) } }
    }
    for top in forest { walk(top, 0) }
    return out
}

/// True if `candidate` shares an ancestor/descendant line with any id in
/// `selected` (excluding itself). Used to disable a category during multi-select
/// merge when one of its ancestors or descendants is already selected, so the
/// selected set stays mutually unrelated (no merging a category with its own
/// parent/child). Bounded walk, derived from the depth cap for the same reason as
/// `effectiveIcon`.
func mergeSelectionDisabled(_ candidate: String, selected: Set<String>, byId: [String: CategoryRow]) -> Bool {
    func isAncestor(_ a: String, of b: String) -> Bool {
        var cur = byId[b]?.parentId
        var hops = 0
        while let c = cur, hops < ancestorWalkLimit {
            if c == a { return true }
            cur = byId[c]?.parentId
            hops += 1
        }
        return false
    }
    for s in selected where s != candidate {
        if isAncestor(candidate, of: s) || isAncestor(s, of: candidate) { return true }
    }
    return false
}
