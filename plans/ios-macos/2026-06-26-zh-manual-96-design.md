# zh-Hans coverage — translate the 96 fallback strings (step 2)

**Date:** 2026-06-26
**Status:** Approved, pending execution.
**Scope:** Hand-author Simplified Chinese for the ~95 real English-fallback UI strings (in `ios/scripts/zh-manual.json`), rebuild the catalog, and fix the one visible `String`-variable nav-title bypass. Translation content + a regenerated catalog + one small code edit.

## Background

After the pipeline refresh (#349) the catalog has 456 keys; 112 are English-fallback —
**~16 are format/symbol tokens** (`%@`, `%lld`, `0`, `i`, `v`, `∞`, separators) that stay
as-is, and **~95 are real UI strings** (mostly this session's features). The web en→zh
map skips any key containing `%`, so interpolated strings (`%lld`, `%@`) **must** be
hand-authored. `zh-manual.json` is highest precedence in `build-xcstrings.ts`.

## Plan

1. **Add ~95 entries to `ios/scripts/zh-manual.json`** (key → zh), preserving the existing
   207. Format specifiers are kept compatible (positional `%1$…` where reordered);
   pure-token keys are intentionally **not** added (English/symbol fallback is correct).
2. **Rebuild** `Localizable.xcstrings` via `build-xcstrings.ts` → English-fallback drops
   from 112 to ~16 (the tokens).
3. **Fix the nav-title bypass:** `ActivityFeedView` passes `navTitle: String` to
   `.navigationTitle(navTitle)`, so the "Ledger" / "Activity" nav title stays English even
   though the keys exist. Wrap it: `.navigationTitle(LocalizedStringKey(navTitle))` so it
   localizes (账本 / 动态) with no new keys.

## Translation-quality note

These are AI-authored Simplified Chinese. They're idiomatic but **should get a native
review before a real release** — the PR notes this. (Marking each `needs_review` would
require build-script changes; out of scope — flagged in the PR instead.)

## Out of scope
- The ~90 `Text(variable)` sites that render **user data** (tag/merchant/account names,
  dates, amounts) — those correctly stay untranslated.
- Other `String`-variable bypass sites beyond the nav title (assess case-by-case later).
- Any engine change; new catalog keys (the set is fixed by #349's extraction).

## Testing
- **Build:** FinchApp (iOS) + FinchMac (macOS) with the regenerated catalog.
- **Manual (sim):** zh-Hans → previously-English UI now Chinese — e.g. the filter sheet
  (排序/匹配/任意标签/清除筛选和搜索), "全部交易", "外观与语言", "在动态中查看",
  "此账本暂无交易。", and the Ledger/Activity **nav title** (账本/动态).
- Catalog check: English-fallback count ≈ 16 (tokens only).

## Notes
- Re-run `bun run scripts/build-xcstrings.ts` after editing `zh-manual.json`. PR → `feat/frontend`.
