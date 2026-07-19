# Shared MerchantLabel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract one shared `MerchantLabel` (name + verified seal) and use it in the Settings Merchants list, its merge picker, and the transaction merchant picker — so verified badges render consistently (newly in both pickers) and the rendering has a single definition.

**Architecture:** A new pure SwiftUI view in `Common/`, the merchant analog of `TagSwatch`. Three call sites swap their inline name(+badge) for it. UI-only.

**Tech Stack:** Swift / SwiftUI.

## Global Constraints

- **UI-only.** No engine, projection, merge/verify, or `frontend/` changes.
- The badge styling must **match the existing Settings row verbatim** (inherits the ambient/body font — do NOT add an explicit `.font`), so the Settings list has no size change; the two pickers simply gain the same badge.
- Design doc: `plans/ios-macos/2026-07-19-merchant-label-design.md`.

---

### Task 1: Shared `MerchantLabel` + wire the three call sites

**Files:**
- Create: `ios/FinchApp/Sources/FinchApp/Common/MerchantLabel.swift`
- Modify: `ios/FinchApp/Sources/FinchApp/PowerTools/MerchantsView.swift` (rowLabel + merge picker)
- Modify: `ios/FinchApp/Sources/FinchApp/WriteScreens/MerchantPickerRow.swift` (sheet rows)

**Interfaces:**
- Produces: `MerchantLabel(name: String, isVerified: Bool)` — a leading name+badge view; callers add their own trailing accessories.

- [ ] **Step 1: Create the component**

Create `ios/FinchApp/Sources/FinchApp/Common/MerchantLabel.swift`:

```swift
import SwiftUI

/// A merchant's name + verified-seal badge — one definition so the Settings
/// Merchants list, its merge picker, and the transaction merchant picker render
/// verified merchants identically and can't drift. Trailing accessories (count
/// pill, chevron, selection checkmark) are added by each caller. The badge
/// inherits the ambient font, matching the existing Settings row verbatim.
struct MerchantLabel: View {
    let name: String
    let isVerified: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(name).foregroundStyle(.primary)
            if isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Verified")
            }
        }
    }
}
```

- [ ] **Step 2: Use it in `MerchantsView.rowLabel`**

In `ios/FinchApp/Sources/FinchApp/PowerTools/MerchantsView.swift`, replace the inline name + conditional badge:

```swift
        HStack(spacing: 8) {
            Text(cp.name).foregroundStyle(.primary)
            if cp.isVerified {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.tint).accessibilityLabel("Verified")
            }
            Spacer(minLength: 8)
```

with:

```swift
        HStack(spacing: 8) {
            MerchantLabel(name: cp.name, isVerified: cp.isVerified)
            Spacer(minLength: 8)
```

(Leave the count pill + chevron that follow untouched.)

- [ ] **Step 3: Use it in the `MerchantsView` merge target-picker**

In the same file, replace the merge picker's plain label:

```swift
                        } label: { Text(t.name).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
```

with:

```swift
                        } label: { MerchantLabel(name: t.name, isVerified: t.isVerified).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
```

- [ ] **Step 4: Use it in `MerchantPickerRow` sheet rows**

In `ios/FinchApp/Sources/FinchApp/WriteScreens/MerchantPickerRow.swift`, replace the plain name in the counterparty rows:

```swift
                ForEach(filtered) { cp in
                    Button { pick(cp.name) } label: {
                        HStack {
                            Text(cp.name).foregroundStyle(.primary)
                            Spacer()
```

with:

```swift
                ForEach(filtered) { cp in
                    Button { pick(cp.name) } label: {
                        HStack {
                            MerchantLabel(name: cp.name, isVerified: cp.isVerified)
                            Spacer()
```

(The "None" row and the "Use ‹text›" create row are unchanged — they have no counterparty behind them.)

- [ ] **Step 5: Build both platforms**

Run from `ios/` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`:
- `xcodegen generate`
- iOS: `xcodebuild -project FinchApp.xcodeproj -scheme FinchApp -destination 'generic/platform=iOS Simulator' build` → expect `BUILD SUCCEEDED`
- macOS: `xcodebuild -project FinchApp.xcodeproj -scheme FinchMac -destination 'platform=macOS' build` → expect `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add ios/FinchApp/Sources/FinchApp/Common/MerchantLabel.swift \
        ios/FinchApp/Sources/FinchApp/PowerTools/MerchantsView.swift \
        ios/FinchApp/Sources/FinchApp/WriteScreens/MerchantPickerRow.swift
git commit -m "feat(ios): shared MerchantLabel (name + verified badge) across list + pickers"
```

---

## Manual verification (for the PR body)

1. Settings → Merchants: verified merchants still show the seal (unchanged size).
2. Add/Edit transaction → Merchant picker: verified merchants now show the seal.
3. Settings → Merchants → ⋯ → Merge → target picker: verified merchants now show the seal.
4. "None" and "Use ‹text›" rows render plain (no badge).
5. macOS builds.

## Self-Review

- **Spec coverage:** shared `MerchantLabel` (Step 1) used at all three sites (Steps 2–4); verified badge now consistent in both pickers; Settings unchanged (badge inherits ambient font per Global Constraints). UI-only, no engine/web (Global Constraints). ✓
- **Type consistency:** `MerchantLabel(name:isVerified:)` signature matches all three call sites (`cp.name`/`cp.isVerified`, `t.name`/`t.isVerified`). ✓
- **Placeholders:** none — every step carries concrete before/after code. ✓
