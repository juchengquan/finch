# Tag colors (iOS Power Tools)

**Date:** 2026-06-23
**Status:** Design approved, pending implementation
**Scope:** iOS `TagAdminView` (Settings › Power Tools › Tags) — add a color picker + a color dot. **UI-only**; no engine/model/projection change. iPad/Mac share the view.

## Problem

The web Tags manager lets each tag have a **color** (an 8-swatch palette). iOS `TagAdminView` shows only an icon + name — no color picker, no color display — even though the **engine, schema, model, and projection already fully support tag color** and the web has it too (full parity). The only gap is the iOS UI.

## Goal

- A **color swatch picker** in `TagEditSheet` (create + edit): 8 swatches, tap to select, tap again to clear (→ null).
- A small **color dot** on each tag row in `TagAdminView`.
- Colors mirror the **web tag palette** so a tag colored on either platform looks the same.

## Non-goals

- No engine / schema / `TagRow` / projection change — all already carry `color`.
- No tag **search** (a separate Power-Tools gap, not this task).
- No parity divergence (web already has tag color; this restores parity).

## Key decisions (locked)

1. **Mirror the web tag palette.** Tag colors use the web's tag-chroma palette (`tagHex` at `TAG_L=0.65, TAG_C=0.18`), which differs from the category palette. The 8 hexes (hues `12,40,90,160,200,220,280,320`) computed from `lib/colors`:
   `#e75572 #e65f2a #ba8600 #00af67 #00adba #00a5da #7d7df9 #be64d2`, default `#00a5da`.
2. **UI-only, reusing existing infra** — `Color(hex:)` (already exists) + the `AccountSheet`/category swatch idiom.

## Detailed design

### `TagPalette` (new, tiny)

A namespace mirroring `CategoryPalette` (in `Common/Color+Hex.swift` or a sibling file):
```swift
enum TagPalette {
    static let hexes = ["#e75572", "#e65f2a", "#ba8600", "#00af67",
                        "#00adba", "#00a5da", "#7d7df9", "#be64d2"]
    static let defaultHex = "#00a5da"
}
```

### `TagEditSheet` — color picker

Add a `@State private var color: String` (init from `tag?.color ?? ""`), and a `Section("Color")` with the 8 swatches (the exact `AccountSheet`/`CategoryEditSheet` idiom: `Circle().fill(Color(hex: hex) ?? .gray)` with a selection ring, tap to select / tap again to clear). On save:
- create: include `"color": .string(color)` in the args when non-empty (the engine's `createTag` already accepts `color`).
- update: patch `"color"` — `.string(color)` when set, `.null` when cleared (the engine's `updateTag` already handles `.null` → SQL NULL).

### `TagAdminView` — row color dot

Prepend a small `Circle().fill(Color(hex: tag.color) ?? .secondary).frame(width: 10, height: 10)` to each tag row (neutral secondary dot when `color` is nil).

## Engine facts (already supported — no change)

- `Tags.createTag` accepts `color`; `Tags.updateTag` patches `color` (incl. `.null` → clear). `tags.color TEXT` column exists.
- `TagRow` has `color: String?`; the projection SELECTs `color` (`SELECT id, name, color FROM tags … TagRow(id:name:color:)`).
- Web parity: `TagPatch.color`, web `createTag` color, web `tagHex` palette.

## Testing

- **FinchAppTests (unit):** `TagPalette.hexes.count == 8`, `defaultHex == "#00a5da"`, default ∈ hexes. (`Color(hex:)` already tested.)
- **Build gate:** iOS + macOS (FinchMac); full FinchAppTests green.
- **Manual (sim):** set a color on a tag (create + edit) → dot shows on the row; clear it → neutral dot; relaunch → persists.

## Out of scope

Tag search; tag usage counts; any non-tag screen.
