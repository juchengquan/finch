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

## Correction: revert to the native segmented Picker (not a custom glass control)

Two further findings changed the fix:

1. **The custom `.glassEffect` control renders flat over the white form.** Its glass is
   the "refract what's behind me" kind — over a white sheet there's nothing to refract,
   so it looks like a plain white pill (identical to the system ✕/✓ pods, which are also
   plain white here and only tinted when a rainbow was scrolled under them). A tint would
   force a glassy look, but that's a colored chip, not the system treatment.
2. **The Edit sheet has no pager and already showed working glass with the same custom
   control** — proving the *component* was never the blocker; only the Add sheet's
   **pager** was. And a **native `.pickerStyle(.segmented)`** carries the system's own
   Liquid Glass selection thumb (the morphing/sliding selector) that the custom control
   replaced with a static highlight — that native selector is the "liquid glass" the
   original request was about (it was working before the Add sheet swapped it out in the
   #499 change, and before the #471 pager blocked content from scrolling under the bar).

**Final decision (user):** Add sheet → **native segmented Picker** (system Liquid Glass
selection thumb) **+ no pager** (single Form, so content scrolls under the bar). This is
the pre-#471 + pre-#499 Add-sheet state the user identified as having working glass. The
interactive page-drag between types is dropped (accepted); the Picker keeps tap +
scrub-anywhere. The **Edit sheet keeps the custom `TxTypeControl`** — it has no pager
(glass already works) and needs per-segment enable/disable (native Pickers can't disable
individual segments), matching its own pre-#499 state (`EditTypeControl`).

## Verification

- Rainbow-under-toolbar A/B (pager vs. no-pager) proved the pager was the blocker; the
  Edit sheet (no pager) proved the component wasn't. Native picker restored in Add.
- FinchAppTests 185/185; FinchApp + FinchMac builds clean.
