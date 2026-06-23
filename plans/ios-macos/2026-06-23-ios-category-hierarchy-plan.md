# Category hierarchy / icons / colors — CP1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring iOS Power Tools › Categories to web parity (checkpoint 1): a 3-level tree with inline expand/collapse, per-category icon + color, search, create-child, edit, and delete-with-promotion. (Drag-to-reparent is checkpoint 2, a separate plan.)

**Architecture:** No FinchCore engine work — `create/update/deleteCategory` already accept `parentId/icon/color`, enforce the depth cap + cycle prevention, and promote children on delete. CP1 = (a) carry `icon`/`color` through the `CategoryRow` projection, (b) three small pure helpers in FinchApp (`Color(hex:)`, a `CategoryIcon` name→SF-Symbol mapper, a category forest/flatten module), and (c) a rewrite of `CategoryAdminView` into a tree + an extended edit sheet.

**Tech Stack:** Swift / SwiftUI, FinchCore (GRDB-backed engine + projections), XcodeGen project, XCTest. FinchCore tests run via `swift test`; FinchApp tests via `xcodebuild … -only-testing:FinchAppTests/…`.

## Global Constraints

- **No FinchCore engine changes** — the category engine is feature-complete. CP1 touches only the projection (read more columns), FinchApp helpers, and the view.
- **Pack parity:** store the web's shared vocabulary verbatim — icon = one of the 12 short-names (`fork, home, car, bag, film, heart, sync, tag, coins, wallet, chart, doc`); color = a `#rrggbb` hex. Render natively (SF Symbols + `Color(hex:)`). Never store SF-Symbol names in the `icon` column.
- **8 shared color hexes:** `#d16b7a #d1714f #ae8a0d #31a773 #00a6ae #00a0c5 #8085dc #b273c0`. Default `#00a0c5`.
- **Must build iOS *and* macOS (FinchMac)** — CI builds both (per #251). Avoid macOS-unavailable APIs (e.g. `.topBarTrailing`). `.navigationBarTitleDisplayMode` is fine (already used app-wide, no-ops on macOS).
- **Reparenting (changing an existing category's parent) is OUT of CP1** — it's drag, which is checkpoint 2. CP1 only sets a parent at *create* time (via "create child").
- **Kind (expense/income) stays create-only** (matches web + current iOS).
- **Commits:** conventional-commit messages; **do not** add a `Co-Authored-By` trailer.
- **New `.swift` files require `xcodegen generate`** before building (sources are path-globbed).

---

## File Structure

**Modify (FinchCore):**
- `ios/FinchCore/Sources/FinchCore/Project/Category.swift` — add `icon`/`color` to `CategoryRow`.
- `ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift` — `categories()` SELECTs + maps `icon`/`color`.

**Create (FinchApp):**
- `ios/FinchApp/Sources/FinchApp/Common/Color+Hex.swift` — `Color(hex:)` + `Color.rgb(fromHex:)` + `CategoryPalette` (8 hexes + default).
- `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryForest.swift` — `CategoryTreeNode`, `categoryForest()`, `effectiveIcon`/`effectiveColor`, `FlatCategory`, `flattenCategories()`.

**Modify (FinchApp):**
- `ios/FinchApp/Sources/FinchApp/Common/Icons.swift` — add `CategoryIcon` (12 names + name→SF Symbol).
- `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift` — full rewrite (tree + extended `CategoryEditSheet` + delete-with-note).

**Create (tests):**
- `ios/FinchCore/Tests/FinchCoreTests/CategoryProjectionTests.swift`
- `ios/FinchApp/Tests/FinchAppTests/ColorHexTests.swift`
- `ios/FinchApp/Tests/FinchAppTests/CategoryIconTests.swift`
- `ios/FinchApp/Tests/FinchAppTests/CategoryForestTests.swift`

**Common run commands:**
```bash
# FinchCore (Swift Package) tests:
cd /Users/blackmount8/_repository/finch/ios && swift test --filter <ClassName>

# FinchApp (Xcode) tests — regenerate project first if files were added:
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests/<ClassName>
```

---

### Task 1: Carry `icon` + `color` through the `CategoryRow` projection

**Files:**
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Category.swift:8-18`
- Modify: `ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift:113-123`
- Test: `ios/FinchCore/Tests/FinchCoreTests/CategoryProjectionTests.swift` (create)

**Interfaces:**
- Produces: `CategoryRow` now has `public let icon: String?` and `public let color: String?`; the memberwise init gains `icon: String? = nil, color: String? = nil` (defaults keep the single existing call site valid). `Projection.categories(dbQueue:ledgerId:)` returns rows populated with both.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchCore/Tests/FinchCoreTests/CategoryProjectionTests.swift`:

```swift
import XCTest
@testable import FinchCore

final class CategoryProjectionTests: XCTestCase {
    func test_projection_carries_icon_and_color() throws {
        let q = try TestSeed.base()
        try Apply.apply(dbQueue: q, action: "createCategory", args: Args([
            "id": .string("cx"), "ledgerId": .string("l1"), "name": .string("Coffee"),
            "type": .string("expense"), "icon": .string("fork"), "color": .string("#00a0c5"),
        ]))
        let cats = try Projection.categories(dbQueue: q, ledgerId: "l1")
        let c = try XCTUnwrap(cats.first { $0.id == "cx" })
        XCTAssertEqual(c.icon, "fork")
        XCTAssertEqual(c.color, "#00a0c5")
    }

    func test_projection_nil_icon_color_when_absent() throws {
        let q = try TestSeed.base()   // seeds category 'c1' (Food) with no icon/color
        let cats = try Projection.categories(dbQueue: q, ledgerId: "l1")
        let c = try XCTUnwrap(cats.first { $0.id == "c1" })
        XCTAssertNil(c.icon)
        XCTAssertNil(c.color)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter CategoryProjectionTests`
Expected: FAIL to compile — `CategoryRow` has no member `icon`/`color`.

- [ ] **Step 3: Add `icon`/`color` to `CategoryRow`**

In `Category.swift`, replace the struct body (lines 8-18) with:

```swift
public struct CategoryRow: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let ledgerId: String
    public let name: String
    public let parentId: String?
    public let kind: String?
    public let icon: String?
    public let color: String?

    public init(id: String, ledgerId: String, name: String, parentId: String?, kind: String?,
                icon: String? = nil, color: String? = nil) {
        self.id = id; self.ledgerId = ledgerId; self.name = name; self.parentId = parentId
        self.kind = kind; self.icon = icon; self.color = color
    }
}
```

- [ ] **Step 4: Read `icon`/`color` in the projection**

In `Projections+State.swift`, replace the `categories(...)` body (lines 113-123) with:

```swift
public static func categories(dbQueue: DatabaseQueue, ledgerId: String) throws -> [CategoryRow] {
    try dbQueue.read { db in
        try Row.fetchAll(db, sql: """
            SELECT id, ledger_id AS ledgerId, name, parent_id AS parentId, kind, icon, color
              FROM categories WHERE ledger_id = ? AND kind != 'equity' ORDER BY sort_order
            """, arguments: [ledgerId]).map { r in
            CategoryRow(id: r["id"], ledgerId: r["ledgerId"], name: r["name"],
                        parentId: r["parentId"], kind: r["kind"],
                        icon: r["icon"], color: r["color"])
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test --filter CategoryProjectionTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Run the full FinchCore suite (no regressions)**

Run: `cd /Users/blackmount8/_repository/finch/ios && swift test`
Expected: all tests pass (the new optional fields don't affect existing behavior).

- [ ] **Step 7: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchCore/Sources/FinchCore/Project/Category.swift \
        ios/FinchCore/Sources/FinchCore/Project/Projections+State.swift \
        ios/FinchCore/Tests/FinchCoreTests/CategoryProjectionTests.swift
git commit -m "feat(ios): carry category icon/color through the projection"
```

---

### Task 2: `Color(hex:)` helper + category palette

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Common/Color+Hex.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/ColorHexTests.swift` (create)

**Interfaces:**
- Produces: `Color.rgb(fromHex: String) -> (r: Double, g: Double, b: Double)?` (pure, testable); `Color(hex: String)` failable init; `enum CategoryPalette { static let hexes: [String]; static let defaultHex: String }`.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchApp/Tests/FinchAppTests/ColorHexTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import FinchApp

final class ColorHexTests: XCTestCase {
    func test_parses_rrggbb_with_hash() {
        let c = Color.rgb(fromHex: "#00a0c5")
        XCTAssertNotNil(c)
        XCTAssertEqual(c!.r, 0.0, accuracy: 0.001)
        XCTAssertEqual(c!.g, 160.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c!.b, 197.0 / 255.0, accuracy: 0.001)
    }

    func test_parses_without_hash() {
        XCTAssertNotNil(Color.rgb(fromHex: "ffffff"))
    }

    func test_rejects_malformed() {
        XCTAssertNil(Color.rgb(fromHex: "#fff"))      // too short
        XCTAssertNil(Color.rgb(fromHex: "#zzzzzz"))   // non-hex
        XCTAssertNil(Color.rgb(fromHex: ""))
    }

    func test_palette_has_eight_and_default() {
        XCTAssertEqual(CategoryPalette.hexes.count, 8)
        XCTAssertEqual(CategoryPalette.defaultHex, "#00a0c5")
        XCTAssertTrue(CategoryPalette.hexes.contains(CategoryPalette.defaultHex))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests/ColorHexTests
```
Expected: FAIL to compile — `Color.rgb(fromHex:)` / `CategoryPalette` undefined.

- [ ] **Step 3: Write the implementation**

Create `ios/FinchApp/Sources/FinchApp/Common/Color+Hex.swift`:

```swift
import SwiftUI

extension Color {
    /// Parse a `#rrggbb` (or `rrggbb`) hex string into 0...1 RGB components.
    /// Returns nil on anything that isn't exactly 6 hex digits. Pure + testable.
    static func rgb(fromHex hex: String) -> (r: Double, g: Double, b: Double)? {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xff) / 255.0,
                Double((v >> 8) & 0xff) / 255.0,
                Double(v & 0xff) / 255.0)
    }

    /// Failable init from a `#rrggbb` hex string.
    init?(hex: String) {
        guard let c = Color.rgb(fromHex: hex) else { return nil }
        self.init(red: c.r, green: c.g, blue: c.b)
    }
}

/// The shared 8-swatch category palette (parity with web `lib/colors.ts`).
enum CategoryPalette {
    static let hexes = ["#d16b7a", "#d1714f", "#ae8a0d", "#31a773",
                        "#00a6ae", "#00a0c5", "#8085dc", "#b273c0"]
    static let defaultHex = "#00a0c5"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests/ColorHexTests
```
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/Common/Color+Hex.swift \
        ios/FinchApp/Tests/FinchAppTests/ColorHexTests.swift
git commit -m "feat(ios): add Color(hex:) helper + shared category palette"
```

---

### Task 3: `CategoryIcon` name → SF Symbol mapper

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Common/Icons.swift` (append a new enum)
- Test: `ios/FinchApp/Tests/FinchAppTests/CategoryIconTests.swift` (create)

**Interfaces:**
- Produces: `enum CategoryIcon { static let names: [String]; static func symbol(for name: String?) -> String }`. `names` are the 12 shared short-names in picker order; `symbol(for:)` maps each to an SF Symbol; unknown/nil → `"tag.fill"`.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchApp/Tests/FinchAppTests/CategoryIconTests.swift`:

```swift
import XCTest
@testable import FinchApp

final class CategoryIconTests: XCTestCase {
    func test_twelve_shared_names() {
        XCTAssertEqual(CategoryIcon.names,
            ["fork", "home", "car", "bag", "film", "heart", "sync", "tag", "coins", "wallet", "chart", "doc"])
    }

    func test_known_names_map_to_symbols() {
        XCTAssertEqual(CategoryIcon.symbol(for: "fork"), "fork.knife")
        XCTAssertEqual(CategoryIcon.symbol(for: "home"), "house.fill")
        XCTAssertEqual(CategoryIcon.symbol(for: "sync"), "arrow.triangle.2.circlepath")
    }

    func test_unknown_and_nil_default_to_tag() {
        XCTAssertEqual(CategoryIcon.symbol(for: nil), "tag.fill")
        XCTAssertEqual(CategoryIcon.symbol(for: ""), "tag.fill")
        XCTAssertEqual(CategoryIcon.symbol(for: "nope"), "tag.fill")
    }

    func test_every_name_maps_to_nonempty_symbol() {
        for n in CategoryIcon.names { XCTAssertFalse(CategoryIcon.symbol(for: n).isEmpty) }
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests/CategoryIconTests
```
Expected: FAIL to compile — `CategoryIcon` undefined.

- [ ] **Step 3: Append the mapper to `Icons.swift`**

Add to the end of `ios/FinchApp/Sources/FinchApp/Common/Icons.swift`:

```swift
/// SF Symbol for a category `icon` short-name. The 12 names mirror the web's
/// shared set (stored verbatim in the pack for cross-platform parity); we map to
/// SF Symbols only at render. Unknown / nil → "tag.fill" (web's 'tag' fallback).
enum CategoryIcon {
    static let names = ["fork", "home", "car", "bag", "film", "heart",
                        "sync", "tag", "coins", "wallet", "chart", "doc"]

    static func symbol(for name: String?) -> String {
        switch name {
        case "fork":   "fork.knife"
        case "home":   "house.fill"
        case "car":    "car.fill"
        case "bag":    "bag.fill"
        case "film":   "film.fill"
        case "heart":  "heart.fill"
        case "sync":   "arrow.triangle.2.circlepath"
        case "tag":    "tag.fill"
        case "coins":  "dollarsign.circle.fill"
        case "wallet": "wallet.pass.fill"
        case "chart":  "chart.pie.fill"
        case "doc":    "doc.fill"
        default:       "tag.fill"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests/CategoryIconTests
```
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/Common/Icons.swift \
        ios/FinchApp/Tests/FinchAppTests/CategoryIconTests.swift
git commit -m "feat(ios): add CategoryIcon name→SF Symbol mapper (12 shared names)"
```

---

### Task 4: Category forest + inheritance + flatten module

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryForest.swift`
- Test: `ios/FinchApp/Tests/FinchAppTests/CategoryForestTests.swift` (create)

**Interfaces:**
- Produces:
  - `struct CategoryTreeNode: Identifiable, Equatable { let row: CategoryRow; let children: [CategoryTreeNode]; var id: String }`
  - `func categoryForest(_ rows: [CategoryRow]) -> [CategoryTreeNode]` — input order preserved; a row whose `parentId` is nil OR points to a missing id is a top-level node.
  - `func effectiveIcon(_ row: CategoryRow, _ byId: [String: CategoryRow]) -> String?` and `func effectiveColor(_ row: CategoryRow, _ byId: [String: CategoryRow]) -> String` — walk the parent chain; icon falls back to nil (→ caller maps to default symbol), color falls back to `CategoryPalette.defaultHex`.
  - `struct FlatCategory: Identifiable, Equatable { let row: CategoryRow; let depth: Int; let hasChildren: Bool; var id: String }`
  - `func flattenCategories(_ forest: [CategoryTreeNode], expanded: Set<String>, search: String) -> [FlatCategory]` — DFS; empty search shows children only for expanded nodes; non-empty search includes a node iff it or a descendant matches (name, case-insensitive) and force-shows children of included nodes.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchApp/Tests/FinchAppTests/CategoryForestTests.swift`:

```swift
import XCTest
import FinchCore
@testable import FinchApp

final class CategoryForestTests: XCTestCase {
    private func cat(_ id: String, _ name: String, parent: String? = nil,
                     icon: String? = nil, color: String? = nil) -> CategoryRow {
        CategoryRow(id: id, ledgerId: "l1", name: name, parentId: parent, kind: "expense", icon: icon, color: color)
    }

    func test_builds_three_levels_preserving_order() {
        let rows = [cat("food", "Food"), cat("groc", "Groceries", parent: "food"),
                    cat("organic", "Organic", parent: "groc"), cat("home", "Home")]
        let forest = categoryForest(rows)
        XCTAssertEqual(forest.map(\.id), ["food", "home"])
        XCTAssertEqual(forest[0].children.map(\.id), ["groc"])
        XCTAssertEqual(forest[0].children[0].children.map(\.id), ["organic"])
    }

    func test_orphan_is_promoted_to_top() {
        let rows = [cat("a", "A", parent: "missing")]
        XCTAssertEqual(categoryForest(rows).map(\.id), ["a"])
    }

    func test_effective_color_inherits_then_defaults() {
        let rows = [cat("p", "P", color: "#31a773"), cat("c", "C", parent: "p")]
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        XCTAssertEqual(effectiveColor(rows[1], byId), "#31a773")           // inherited
        XCTAssertEqual(effectiveColor(cat("x", "X"), [:]), CategoryPalette.defaultHex)  // default
    }

    func test_effective_icon_inherits() {
        let rows = [cat("p", "P", icon: "fork"), cat("c", "C", parent: "p")]
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        XCTAssertEqual(effectiveIcon(rows[1], byId), "fork")
        XCTAssertNil(effectiveIcon(cat("x", "X"), [:]))
    }

    func test_flatten_empty_search_respects_expanded() {
        let forest = categoryForest([cat("food", "Food"), cat("groc", "Groceries", parent: "food")])
        XCTAssertEqual(flattenCategories(forest, expanded: [], search: "").map(\.id), ["food"])
        XCTAssertEqual(flattenCategories(forest, expanded: ["food"], search: "").map(\.id), ["food", "groc"])
    }

    func test_flatten_search_force_expands_ancestors() {
        let forest = categoryForest([cat("food", "Food"), cat("groc", "Groceries", parent: "food"),
                                     cat("home", "Home")])
        // "groc" matches; its ancestor "food" is shown even though collapsed; "home" is hidden.
        XCTAssertEqual(flattenCategories(forest, expanded: [], search: "groc").map(\.id), ["food", "groc"])
    }

    func test_flatten_marks_hasChildren_and_depth() {
        let forest = categoryForest([cat("food", "Food"), cat("groc", "Groceries", parent: "food")])
        let flat = flattenCategories(forest, expanded: ["food"], search: "")
        XCTAssertTrue(flat[0].hasChildren); XCTAssertEqual(flat[0].depth, 0)
        XCTAssertFalse(flat[1].hasChildren); XCTAssertEqual(flat[1].depth, 1)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests/CategoryForestTests
```
Expected: FAIL to compile — symbols undefined.

- [ ] **Step 3: Write the implementation**

Create `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryForest.swift`:

```swift
import Foundation
import FinchCore

/// A node in the category forest (≤3 levels; enforced by the engine).
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
/// the default symbol). Bounded walk (≤4 hops; the tree is ≤3 deep).
func effectiveIcon(_ row: CategoryRow, _ byId: [String: CategoryRow]) -> String? {
    var cur: CategoryRow? = row
    var hops = 0
    while let c = cur, hops < 4 {
        if let icon = c.icon, !icon.isEmpty { return icon }
        cur = c.parentId.flatMap { byId[$0] }; hops += 1
    }
    return nil
}

/// Effective color hex: own → nearest ancestor's → `CategoryPalette.defaultHex`.
func effectiveColor(_ row: CategoryRow, _ byId: [String: CategoryRow]) -> String {
    var cur: CategoryRow? = row
    var hops = 0
    while let c = cur, hops < 4 {
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests/CategoryForestTests
```
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/PowerTools/CategoryForest.swift \
        ios/FinchApp/Tests/FinchAppTests/CategoryForestTests.swift
git commit -m "feat(ios): category forest builder, icon/color inheritance, flatten"
```

---

### Task 5: Rewrite `CategoryAdminView` — tree + icon/color edit + delete-with-note

**Files:**
- Modify (full rewrite): `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift`

**Interfaces:**
- Consumes: `CategoryRow.icon/color` (Task 1); `Color(hex:)`, `CategoryPalette` (Task 2); `CategoryIcon` (Task 3); `categoryForest`, `effectiveIcon`, `effectiveColor`, `FlatCategory`, `flattenCategories` (Task 4).
- Produces: the user-facing tree. No new public symbols for later tasks (CP2 builds on this file).

- [ ] **Step 1: Verify the data source includes parents**

Read `ios/FinchApp/Sources/FinchApp/FinchStore+ViewHelpers.swift` and confirm `store.pickableCategories` returns **all** non-equity categories (parents + children) — the current `CategoryAdminView` already lists it as the full admin set, so it does. If (unexpectedly) it filters out parent rows, use the full projection list instead (e.g. expose `store.categories` publicly) and adjust `rows` below. Proceed once confirmed.

- [ ] **Step 2: Write the new view**

Replace the entire contents of `ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift` with:

```swift
import SwiftUI
import FinchCore

/// Categories admin — a 3-level tree (inline expand/collapse) with per-category
/// icon + color, search, create-child, edit, and delete (children promote up a
/// level). create / update / deleteCategory through the chokepoint. Reparenting
/// (drag-to-move) is checkpoint 2.
struct CategoryAdminView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var expanded: Set<String> = []
    @State private var search = ""
    @State private var editing: CategoryRow?
    @State private var creatingTop = false
    @State private var creatingUnder: CategoryRow?
    @State private var deleting: CategoryRow?
    @State private var errorMessage: String?

    private var rows: [CategoryRow] { store.pickableCategories }
    private var byId: [String: CategoryRow] { Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) }) }
    private var visible: [FlatCategory] {
        flattenCategories(categoryForest(rows), expanded: expanded, search: search)
    }

    var body: some View {
        List {
            ForEach(visible) { item in row(item) }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("Categories")
        .errorAlert($errorMessage)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creatingTop = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add category")
            }
        }
        .sheet(isPresented: $creatingTop) { CategoryEditSheet(category: nil) }
        .sheet(item: $creatingUnder) { parent in CategoryEditSheet(category: nil, parent: parent) }
        .sheet(item: $editing) { CategoryEditSheet(category: $0) }
        .confirmationDialog("Delete \(deleting?.name ?? "")?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting, titleVisibility: .visible) { c in
            Button("Delete", role: .destructive) { delete(c) }
        } message: { _ in
            Text("Its subcategories move up a level — they won't be deleted.")
        }
    }

    @ViewBuilder private func row(_ item: FlatCategory) -> some View {
        let c = item.row
        HStack(spacing: 8) {
            if item.hasChildren {
                Button {
                    if expanded.contains(c.id) { expanded.remove(c.id) } else { expanded.insert(c.id) }
                } label: {
                    Image(systemName: (expanded.contains(c.id) || !search.isEmpty) ? "chevron.down" : "chevron.right")
                        .font(.caption).foregroundStyle(.secondary).frame(width: 16)
                }
                .buttonStyle(.plain)
                .disabled(!search.isEmpty)   // search force-expands; chevron is inert
            } else {
                Color.clear.frame(width: 16)
            }

            ZStack {
                Circle().fill(Color(hex: effectiveColor(c, byId)) ?? .gray).frame(width: 28, height: 28)
                Image(systemName: CategoryIcon.symbol(for: effectiveIcon(c, byId)))
                    .font(.system(size: 13)).foregroundStyle(.white)
            }

            Button { editing = c } label: {
                Text(c.name).foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.depth < 2 {   // engine caps nesting at 3 levels
                Button { creatingUnder = c } label: {
                    Image(systemName: "plus.circle").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add subcategory under \(c.name)")
            }
        }
        .padding(.leading, CGFloat(item.depth) * 16)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { deleting = c } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func delete(_ c: CategoryRow) {
        errorMessage = nil
        do { try store.apply(.deleteCategory, Args(["id": .string(c.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
}

/// Create (category == nil), create-under-a-parent (parent != nil), or edit an
/// existing category. Name + icon + color always; kind is create-top-level only.
struct CategoryEditSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let category: CategoryRow?
    let parent: CategoryRow?
    @State private var name: String
    @State private var kind: String
    @State private var icon: String     // "" = none (inherit at render)
    @State private var color: String    // "" = none (inherit/default at render)
    @State private var errorMessage: String?

    init(category: CategoryRow?, parent: CategoryRow? = nil) {
        self.category = category
        self.parent = parent
        _name = State(initialValue: category?.name ?? "")
        _kind = State(initialValue: category?.kind ?? parent?.kind ?? "expense")
        _icon = State(initialValue: category?.icon ?? "")
        _color = State(initialValue: category?.color ?? "")
    }

    private let iconColumns = Array(repeating: GridItem(.flexible()), count: 6)

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                if category == nil && parent == nil {
                    Picker("Kind", selection: $kind) { Text("Expense").tag("expense"); Text("Income").tag("income") }
                        .pickerStyle(.segmented)
                }
                Section("Icon") {
                    LazyVGrid(columns: iconColumns, spacing: 12) {
                        ForEach(CategoryIcon.names, id: \.self) { n in
                            Image(systemName: CategoryIcon.symbol(for: n))
                                .font(.system(size: 18))
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(icon == n ? Color.accentColor.opacity(0.2) : .clear))
                                .overlay(Circle().stroke(Color.accentColor, lineWidth: icon == n ? 2 : 0))
                                .contentShape(Circle())
                                .onTapGesture { icon = (icon == n ? "" : n) }
                                .accessibilityLabel("Icon \(n)")
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Color") {
                    HStack(spacing: 10) {
                        ForEach(CategoryPalette.hexes, id: \.self) { hex in
                            Circle().fill(Color(hex: hex) ?? .gray).frame(width: 26, height: 26)
                                .overlay(Circle().stroke(Color.primary, lineWidth: color == hex ? 2.5 : 0))
                                .contentShape(Circle())
                                .onTapGesture { color = (color == hex ? "" : hex) }
                                .accessibilityLabel("Color \(hex)")
                        }
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }.accessibilityLabel("Save").bold()
                }
            }
        }
    }

    private var title: String {
        if category != nil { return "Edit Category" }
        if let parent { return "New under \(parent.name)" }
        return "New Category"
    }

    private func save() {
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorMessage = "Enter a name."; return }
        do {
            if let c = category {
                let patch: [String: JSONValue] = [
                    "name": .string(trimmed),
                    "icon": icon.isEmpty ? .null : .string(icon),
                    "color": color.isEmpty ? .null : .string(color),
                ]
                try store.apply(.updateCategory, Args(["id": .string(c.id), "patch": .object(patch)]))
            } else {
                var args: [String: JSONValue] = [
                    "ledgerId": .string(store.activeLedgerId), "name": .string(trimmed), "type": .string(kind),
                ]
                if !icon.isEmpty { args["icon"] = .string(icon) }
                if !color.isEmpty { args["color"] = .string(color) }
                if let parent { args["parentId"] = .string(parent.id) }
                try store.apply(.createCategory, Args(args))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
```

- [ ] **Step 3: Verify `.null` clears a column in `updateCategory`**

Confirm the engine writes SQL NULL when a patch value is `.null` (so clearing an icon/color works). Read `ios/FinchCore/Sources/FinchCore/Store/Domain/Categories.swift` `update`. If it does not bind `.null` → NULL, change the edit `save()` to omit the key instead of sending `.null` (clearing then becomes a non-CP1 concern; setting still works). Note the outcome in the commit body.

- [ ] **Step 4: Build iOS + run the full FinchApp suite**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **` (all FinchAppTests, including the new ones).

- [ ] **Step 5: Build macOS (FinchMac) — CI gate**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual verification on the simulator**

Install + launch (Settings › Power Tools › Categories), then check:
- Tree renders with colored icon badges; parents collapse/expand via chevron.
- "+" on a parent creates a child (kind inherited, hidden picker); top "+" creates a top-level (kind picker shown).
- Setting an icon + color on a category shows on its row; a child with none inherits the parent's.
- Search filters and force-expands ancestors of matches.
- Deleting a parent shows the "subcategories move up a level" dialog; after delete, children remain at the promoted level.
- Verify all 12 icon glyphs actually render (no blank squares); swap any missing SF Symbol for the closest available and re-run Task 3's test expectation.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch -initialTab settings
```

- [ ] **Step 7: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/PowerTools/CategoryAdminView.swift
git commit -m "feat(ios): category tree UI — hierarchy, icons, colors, search, create-child"
```

---

## Self-Review

**Spec coverage** (against `2026-06-23-ios-category-hierarchy-design.md`, CP1 scope):
- Data layer (`CategoryRow` + projection icon/color) → Task 1. ✓
- Icon model (12 shared names → SF Symbols) → Task 3. ✓
- Color model (`Color(hex:)` + 8 hex + default) → Task 2; inheritance → Task 4. ✓
- Tree view (forest, expand/collapse, badges, indentation, search, create-child) → Tasks 4 + 5. ✓
- Edit sheet (name/kind/icon/color) → Task 5. ✓
- Delete-with-note → Task 5. ✓
- Reparent (drag) → intentionally **CP2**, not in this plan. ✓
- Build iOS + macOS, FinchAppTests green → Task 5 steps 4-5. ✓

**Placeholder scan:** No TBD/TODO; every code step has complete code; the two "verify" steps (5.1 data source, 5.3 `.null` clearing) include the concrete fallback to take. ✓

**Type consistency:** `CategoryRow(... icon:color:)` init (Task 1) matches its use in Task 4's test helper and the projection. `effectiveIcon` returns `String?` and `CategoryIcon.symbol(for:)` takes `String?` — composable in Task 5 (`symbol(for: effectiveIcon(...))`). `flattenCategories`/`FlatCategory`/`categoryForest` names match between Task 4 definition and Task 5 use. `CategoryPalette.hexes`/`.defaultHex` consistent across Tasks 2, 4, 5. ✓

---

## Out of scope (CP2 / later)

Drag-to-reparent + "Move to…" fallback; sibling `sort_order` reordering; persisting expand/collapse; bulk ops; merge; usage counts.
