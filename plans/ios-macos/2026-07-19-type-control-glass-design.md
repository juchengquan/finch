# Liquid Glass for the transaction-type switcher (Add + Edit sheets)

**Date:** 2026-07-19
**Status:** Executed inline (bug fix).

## Problem

On iOS 26 the Add/Edit sheets' nav-bar type switcher didn't get Liquid Glass:
- Add used a native segmented `Picker` in `.principal` — UIKit's flat gray control,
  which does not adopt the toolbar's glass treatment.
- Edit used the custom `EditTypeControl` with no background at all.
Both sat visibly flat next to the ✕/✓ toolbar buttons' glass pods.

## Fix

- `EditTypeControl` → **`TxTypeControl`** (git mv), now shared by BOTH sheets:
  icon segments, per-segment enable/disable, selected pill + accent glyph, and the
  Add sheet's scrub-anywhere drag folded in (enabled-aware).
- `.glassCapsule()` helper: `glassEffect(.regular.interactive(), in: .capsule)` under
  `#available(iOS 26.0, macOS 26.0, *)` — earlier systems render exactly as before
  (their toolbars have no glass pods either). Deployment targets stay iOS 17 / current.
- Add sheet drops its `Picker` + duplicate gesture + `typeControlWidth`.
- DEBUG launch arg `-openAdd YES` added beside `-initialTab` (opens the Add sheet on
  launch via the same flag as finch://add) so sim screenshots can reach the sheet.

## Verification

Screenshot before/after on ios-finch2 via `-openAdd`: control now renders as a glass
capsule matching the ✕/✓ pods. FinchAppTests + both platform builds. Edit sheet is the
same shared control (human pass).
