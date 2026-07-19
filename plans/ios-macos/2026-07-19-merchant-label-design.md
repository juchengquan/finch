# Shared MerchantLabel — design

**Date:** 2026-07-19
**Status:** approved (brainstormed with user)
**Scope:** iOS/macOS app only (`ios/`), UI-only. No engine, projection, or web changes.

## Problem

The tags page consolidation (#522) gave every tag surface one shared display
element (`TagSwatch`) so the Settings list and the transaction picker can't
drift. Merchants have no equivalent: a `Counterparty` has only `name` +
`isVerified` (no color), and its name-plus-verified-badge rendering is
**duplicated and inconsistent** across three places:

- `MerchantsView.rowLabel` (Settings list) — shows the name **and** a
  `checkmark.seal.fill` verified badge.
- `MerchantsView` merge target-picker — shows a plain `Text(t.name)`, **no badge**.
- `MerchantPickerRow` sheet rows (the transaction merchant picker) — shows a
  plain `Text(cp.name)`, **no badge**.

So a verified merchant looks verified in the Settings list but not in either
picker, and the rendering lives in three copies.

## Decision

Extract one shared **`MerchantLabel`** view (name + verified seal) — the
merchant analog of `TagSwatch` — and use it in all three places. Verified
badges then render consistently everywhere (newly visible in both pickers), and
the rendering has a single definition.

The other half of the tags work — the picker's "Create" opening the full editor
— is **out of scope**: the merchant editor (`CounterpartyNameSheet`) is
name-only, and the picker already captures the name as free text, so there is
nothing extra to set on create.

## Changes

### 1. New `FinchApp/Sources/FinchApp/Common/MerchantLabel.swift`

The leading label only (name + badge); each row supplies its own trailing
accessory (count pill / chevron / selection checkmark), exactly as `TagSwatch`
is just the dot.

```swift
import SwiftUI

/// A merchant's name plus a verified-seal badge — one definition so the Settings
/// Merchants list, its merge picker, and the transaction merchant picker render
/// verified merchants identically and can't drift. Trailing accessories
/// (count pill, chevron, selection checkmark) are added by each caller.
struct MerchantLabel: View {
    let name: String
    let isVerified: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(name).foregroundStyle(.primary)
            if isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption).foregroundStyle(.tint)
                    .accessibilityLabel("Verified")
            }
        }
    }
}
```

### 2. `MerchantsView.rowLabel` (Settings list)

Replace the inline `Text(cp.name)` + conditional `checkmark.seal.fill`
(lines ~148–150) with `MerchantLabel(name: cp.name, isVerified: cp.isVerified)`,
leaving the surrounding count pill + chevron untouched. No visible change here
(it already showed the badge) — it now shares the definition.

### 3. `MerchantsView` merge target-picker

Replace the plain `Text(t.name)…` (line ~177) with `MerchantLabel(name: t.name,
isVerified: t.isVerified)`, preserving the row's `frame(maxWidth: .infinity,
alignment: .leading)` + `contentShape(Rectangle())`. **Gains the badge.**

### 4. `MerchantPickerRow` sheet rows

Replace the plain `Text(cp.name)` (line ~92) with `MerchantLabel(name: cp.name,
isVerified: cp.isVerified)`, keeping the trailing selection checkmark. **Gains
the badge.** The "None" row and the "Use ‹text›" create row stay plain (no
counterparty behind them).

## Non-goals (explicit)

- No editor-on-create for the merchant picker (name-only editor — nothing to add).
- No engine, projection, merge, verify, or web changes.
- No new icon/glyph/color for merchants (they have none).

## Testing

`MerchantLabel` is a pure view with a single boolean branch and no logic to
unit-test (unlike the tags work's `selectedRows` pure function). The gate is the
build:

- `xcodebuild` FinchApp (iOS Simulator) **and** FinchMac — both `BUILD SUCCEEDED`.

**Manual checklist (PR body):**
1. Settings → Merchants: verified merchants still show the seal (unchanged).
2. Add/Edit transaction → Merchant picker: verified merchants now show the seal.
3. Settings → Merchants → ⋯ Merge → target picker: verified merchants now show the seal.
4. "None" and "Use ‹text›" rows render plain (no badge). macOS builds.
