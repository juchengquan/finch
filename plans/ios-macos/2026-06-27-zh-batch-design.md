# zh-Hans batch top-up for newly-added strings

**Date:** 2026-06-27
**Status:** Done (chore).
**Scope:** Re-run the localization pipeline so the catalog covers UI strings added since the #349 refresh, and hand-author zh for the real ones. Regenerated artifacts + zh-manual additions; no code change.

## Why

Strings added since #349 (recurring detector #359, add-to-scheduled #363, flat-feed /
relative dates #371, feed display prefs #375, guided reconcile #355/#358, budget cycle
edit #366) weren't in `extracted-keys.json`, so they fell back to English. "Today" was
already localized; "Yesterday" is covered by the web map (昨天).

## What

Ran the documented pipeline (`build-xcstrings.ts` header):
`xcodebuild -exportLocalizations` → `xliff-keys.ts` → `extracted-keys.json` (**456 → 472**)
→ `build-xcstrings.ts`. Then added **10** entries to `zh-manual.json` for the real
English-fallback strings; rebuilt. Result: **472 keys, 457 translated**, **15 fallback —
all pure format/symbol tokens** (`%lld`, `%lld×`, …), 0 real strings.

New translations (terminology-matched to the catalog):
- `Activity feed` → 动态 · `Group by month` → 按月分组 · `Relative dates` → 相对日期
- `Detected · not scheduled` → 检测到 · 未加入计划 · `%1$@ · next ~%2$@` → %1$@ · 下次 ~%2$@ · `~%1$@/mo · %2$lld` → ~%1$@/月 · %2$lld
- `Cleared %1$lld · To review %2$lld` → 已清算 %1$lld · 待审核 %2$lld · `Adjust %@` → 调整 %@ · `Balance after` → 调整后余额
- the budget cycle-change note → 更改开始日期或频率会重置周期…

Only `extracted-keys.json` + `Localizable.xcstrings` + `zh-manual.json` change (Xcode's
incidental `AppShortcuts.xcstrings` build churn reverted).

## Caveat

AI-authored Simplified Chinese — terminology-matched, but a native review is advised
before a real release.

## Testing
- **Build:** FinchApp (iOS) `** BUILD SUCCEEDED **` with the regenerated catalog.
- Catalog check: English-fallback = 15 (format tokens only).

PR targets `feat/frontend`.
