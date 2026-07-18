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

## Follow-up: the pager was suppressing the glass (real root cause)

After the initial fix, the control still didn't *look* glassy in use. Empirical
investigation (rainbow gradient injected as the form's top scroll content, then
scrolled under the toolbar, with vs. without the pager) proved why:

- The Add sheet wrapped its forms in a `TabView(.page)` for interactive swipe-between-
  types. The nav toolbar can only apply Liquid Glass to content that scrolls under it,
  and it tracks a **single** scroll view. A paged TabView gives each form its own inset
  scroll view the toolbar can't follow, so it fell back to an **opaque background band**
  — content stopped at a hard boundary below the bar and never passed beneath the glass.
  The glass therefore always sat over flat white and could never refract.
- Removing the pager (single `formPage(kind)` Form) let the toolbar track the one scroll
  view: form content flows under the bar and the glass refracts for real (verified —
  the ✕/✓ pods and the type capsule pick up colors from content scrolling beneath).

**Decision (user):** remove the pager for real glass; accept losing the interactive
finger-drag swipe between types. Types still switch via `TxTypeControl` (tap +
scrub-anywhere); type changes animate with a **direction-aware slide** (`.transition`
keyed on `kind` via `.id(kind)`; `slideEdge` set from the index delta;
`withAnimation(.snappy)`).

## Verification

- Rainbow-under-toolbar A/B (pager vs. no-pager) proved the mechanism; real form content
  confirmed scrolling under the glass in the shipped single-Form build.
- FinchAppTests + FinchApp + FinchMac builds. Type-switch slide + scrub still work.
