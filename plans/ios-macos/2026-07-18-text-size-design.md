# Text size setting (in-app Dynamic Type override)

**Date:** 2026-07-18
**Status:** Design approved in discussion (system toggle + slider); plan in
`2026-07-18-text-size-plan.md`.
**Scope:** FinchApp UI only; device-local preference (like the theme). No engine/web change.

## Decisions

1. **Storage:** `finch.textSize.system` (Bool, default true = follow the OS Text Size —
   today's behavior, accessibility sizes included) + `finch.textSize.step` (Int 0–6 over
   [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge], default 3 = .large,
   the iOS default). @AppStorage, mirroring `finch.appearance`.
2. **Application:** one root modifier next to `preferredColorScheme` in `FinchApp.swift`
   (single shared @main serves iOS + macOS): system mode leaves the environment
   untouched; custom mode pins `.dynamicTypeSize(step)`. Zero per-view work.
3. **UI:** new "Text size" section in Settings › Appearance & Language after Theme:
   `Toggle("Use system size")`; when OFF a discrete 7-step slider with small-A/large-A
   end labels + a live preview row ("Sample — $1,234.56") at the chosen size. Footer
   states which mode is active.
4. **Pure mapping** `TextSize.size(forStep:)` clamps out-of-range stored values;
   unit-tested. New strings → zh-Hans batch.
