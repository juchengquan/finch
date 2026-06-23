# Tag colors — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each tag a color — an 8-swatch picker in `TagEditSheet` and a color dot on each tag row — mirroring the web tag palette.

**Architecture:** UI-only. The engine, `tags.color` column, `TagRow.color`, the projection, and the web all already support tag color. Add a `TagPalette` constant + a color picker (reusing `Color(hex:)` and the existing category/account swatch idiom) + a row dot, and pass `color` through the already-color-aware `createTag`/`updateTag`.

**Tech Stack:** Swift / SwiftUI (iOS 17 / macOS 14), FinchCore, XcodeGen, XCTest. FinchApp tests via `xcodebuild … -only-testing:FinchAppTests/…`.

## Global Constraints

- **No engine / schema / `TagRow` / projection change** — all already carry `color`. This is UI only.
- **Mirror the web tag palette** (`tagHex`, chroma 0.18): hexes `#e75572 #e65f2a #ba8600 #00af67 #00adba #00a5da #7d7df9 #be64d2`, default `#00a5da`. (Distinct from `CategoryPalette`.)
- Picker selects one swatch; tapping the selected one again **clears** it (→ null). Create passes `color` only when set; update patches `color` as `.string` when set or `.null` when cleared (the engine's `updateTag` already maps `.null` → SQL NULL).
- **Must build iOS AND macOS (FinchMac).** Sim: `iPhone 17 Pro Max`. New `.swift` files / new tests → `xcodegen generate` before building. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Conventional-commit messages; **no `Co-Authored-By` trailer**.

---

## File Structure

**Modify (FinchApp):**
- `ios/FinchApp/Sources/FinchApp/Common/Color+Hex.swift` — add `enum TagPalette` (after `CategoryPalette`).
- `ios/FinchApp/Sources/FinchApp/PowerTools/TagAdminView.swift` — row color dot + `TagEditSheet` color picker + `color` in save.

**Create (tests):**
- `ios/FinchApp/Tests/FinchAppTests/TagPaletteTests.swift`

**Common run commands:**
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests/<ClassName>
```

---

### Task 1: `TagPalette` constant

**Files:**
- Modify: `ios/FinchApp/Sources/FinchApp/Common/Color+Hex.swift` (append after `CategoryPalette`, ~line 26)
- Test: `ios/FinchApp/Tests/FinchAppTests/TagPaletteTests.swift` (create)

**Interfaces:**
- Produces: `enum TagPalette { static let hexes: [String]; static let defaultHex: String }` — the 8 web tag hexes + default `#00a5da`.

- [ ] **Step 1: Write the failing test**

Create `ios/FinchApp/Tests/FinchAppTests/TagPaletteTests.swift`:

```swift
import XCTest
@testable import FinchApp

final class TagPaletteTests: XCTestCase {
    func test_palette_has_eight_and_default() {
        XCTAssertEqual(TagPalette.hexes.count, 8)
        XCTAssertEqual(TagPalette.defaultHex, "#00a5da")
        XCTAssertTrue(TagPalette.hexes.contains(TagPalette.defaultHex))
    }

    func test_palette_matches_web_tag_hexes() {
        XCTAssertEqual(TagPalette.hexes,
            ["#e75572", "#e65f2a", "#ba8600", "#00af67", "#00adba", "#00a5da", "#7d7df9", "#be64d2"])
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
  -only-testing:FinchAppTests/TagPaletteTests
```
Expected: FAIL to compile — `TagPalette` undefined.

- [ ] **Step 3: Add `TagPalette`**

Append to `ios/FinchApp/Sources/FinchApp/Common/Color+Hex.swift` (after the `CategoryPalette` enum):

```swift

/// The shared 8-swatch tag palette (parity with web `lib/colors.ts` `tagHex`,
/// chroma 0.18 — distinct from `CategoryPalette`).
enum TagPalette {
    static let hexes = ["#e75572", "#e65f2a", "#ba8600", "#00af67",
                        "#00adba", "#00a5da", "#7d7df9", "#be64d2"]
    static let defaultHex = "#00a5da"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests/TagPaletteTests
```
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/Common/Color+Hex.swift \
        ios/FinchApp/Tests/FinchAppTests/TagPaletteTests.swift
git commit -m "feat(ios): add TagPalette (web tag-color swatches)"
```

---

### Task 2: Tag color picker + row dot

**Files:**
- Modify (full rewrite): `ios/FinchApp/Sources/FinchApp/PowerTools/TagAdminView.swift`

**Interfaces:**
- Consumes: `TagPalette` (Task 1); `Color(hex:)` (existing); `createTag`/`updateTag` `color` (engine, existing).
- Produces: the tag color UX. No new public symbols.

- [ ] **Step 1: Replace the view file**

Replace the entire contents of `ios/FinchApp/Sources/FinchApp/PowerTools/TagAdminView.swift` with (current view + a row color dot + the `TagEditSheet` color section + `color` in save):

```swift
import SwiftUI
import FinchCore

/// Phase 4 — tag admin: add / rename / delete tags + per-tag color
/// (create/update/deleteTag). Color uses the shared web tag palette.
struct TagAdminView: View {
    @EnvironmentObject private var store: FinchStore
    @State private var showingAdd = false
    @State private var renaming: TagRow?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if store.tags.isEmpty { Text("No tags yet.").foregroundStyle(.secondary) }
            ForEach(store.tags) { tag in
                Button { renaming = tag } label: {
                    HStack {
                        Circle().fill(Color(hex: tag.color ?? "") ?? .secondary)
                            .frame(width: 12, height: 12)
                        Text(tag.name).foregroundStyle(.primary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { delete(tag) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("Tags")
        .errorAlert($errorMessage)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add tag")
            }
        }
        .sheet(isPresented: $showingAdd) { TagEditSheet(tag: nil) }
        .sheet(item: $renaming) { TagEditSheet(tag: $0) }
    }

    private func delete(_ t: TagRow) {
        do { try store.apply(.deleteTag, Args(["id": .string(t.id)])) }
        catch { errorMessage = i18nMessage(error) }
    }
}

struct TagEditSheet: View {
    @EnvironmentObject private var store: FinchStore
    @Environment(\.dismiss) private var dismiss
    let tag: TagRow?
    @State private var name: String
    @State private var color: String     // "" = none
    @State private var errorMessage: String?

    init(tag: TagRow?) {
        self.tag = tag
        _name = State(initialValue: tag?.name ?? "")
        _color = State(initialValue: tag?.color ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Section("Color") {
                    HStack(spacing: 10) {
                        ForEach(TagPalette.hexes, id: \.self) { hex in
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
            .navigationTitle(tag == nil ? "New Tag" : "Edit Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save").bold()
                }
            }
        }
    }

    private func save() {
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorMessage = "Enter a name."; return }
        do {
            if let t = tag {
                let patch: [String: JSONValue] = [
                    "name": .string(trimmed),
                    "color": color.isEmpty ? .null : .string(color),
                ]
                try store.apply(.updateTag, Args(["id": .string(t.id), "patch": .object(patch)]))
            } else {
                var args: [String: JSONValue] = [
                    "ledgerId": .string(store.activeLedgerId), "name": .string(trimmed),
                ]
                if !color.isEmpty { args["color"] = .string(color) }
                try store.apply(.createTag, Args(args))
            }
            dismiss()
        } catch { errorMessage = i18nMessage(error) }
    }
}
```

- [ ] **Step 2: Build iOS + run the full FinchApp suite**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild test -project FinchApp.xcodeproj -scheme FinchApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:FinchAppTests 2>&1 | grep -iE "error:|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **` (TagPaletteTests + all prior).

- [ ] **Step 3: Build macOS (FinchMac) — CI gate**

Run:
```bash
cd /Users/blackmount8/_repository/finch/ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project FinchApp.xcodeproj -scheme FinchMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verification on the simulator**

Build/install/launch to Tags (Settings › Power Tools › Tags), then:
- **Create** a tag, pick a color → the row shows that color dot.
- **Edit** a tag, change the color → dot updates; tap the selected swatch again to **clear** → dot goes neutral gray.
- **Relaunch** → colors persist.
- The 8 swatches render and look distinct from the category palette.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IPHONE=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(xcodebuild -project /Users/blackmount8/_repository/finch/ios/FinchApp.xcodeproj -scheme FinchApp -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{d=$3}/ FULL_PRODUCT_NAME /{n=$3}END{print d"/"n}')
xcrun simctl install "$IPHONE" "$APP"
xcrun simctl launch "$IPHONE" com.juchengquan.finch -initialTab settings
```

- [ ] **Step 5: Commit**

```bash
cd /Users/blackmount8/_repository/finch
git add ios/FinchApp/Sources/FinchApp/PowerTools/TagAdminView.swift
git commit -m "feat(ios): tag color picker + row color dot"
```

---

## Self-Review

**Spec coverage** (against `2026-06-23-ios-tag-colors-design.md`):
- `TagPalette` (8 web tag hexes + default) → Task 1. ✓
- Color swatch picker in `TagEditSheet` (select/clear) → Task 2. ✓
- Row color dot (neutral when nil) → Task 2. ✓
- `color` through `createTag`/`updateTag` (`.null` clears) → Task 2 `save()`. ✓
- No engine/model/projection change; build iOS+macOS; full tests green → Task 2 steps 2-3. ✓

**Placeholder scan:** No TBD/TODO; every code step has complete code; sim step lists concrete checks. ✓

**Type consistency:** `TagPalette.hexes`/`.defaultHex` used in Task 2 match Task 1. `color.isEmpty ? .null : .string(color)` matches the engine's `updateTag` color handling; create omits `color` when empty. `Color(hex: tag.color ?? "")` returns nil for empty/nil → `?? .secondary` neutral dot. ✓

---

## Out of scope

Tag search; tag usage counts; renaming the screen's "tag" glyph elsewhere; any non-tag screen.
