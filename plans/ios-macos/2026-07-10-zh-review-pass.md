# zh-Hans review pass — all 457 translated strings

**Date:** 2026-07-10
**Status:** Done (review + fixes).
**Scope:** Systematic bilingual QA of every zh-Hans string (314 `zh-manual.json` + 143 web-map),
fixing **errors + terminology consistency** only (pure style left alone). Addresses the standing
"AI-authored, native review advised" caveat from #350/#377.

## Method

1. Extracted all 457 en→zh pairs from the built catalog with their source (manual vs web-map).
2. **Programmatic format-specifier check** (`%@`/`%lld`/positional) over all pairs.
3. Full manual read-through of all 457 pairs, checking mistranslation, terminology drift,
   register, and punctuation-width conventions.
4. Fixes written as `zh-manual.json` entries (manual > web-map precedence), catalog rebuilt,
   iOS build verified.

## Findings & fixes (19)

**Rendering bugs (2)** — `%2$@` is the English plural-"s" slot (`transaction%2$@`); two strings
kept it, which renders a literal "s" in Chinese:
- `Applies to %1$lld selected transaction%2$@.` → 应用于 %1$lld 笔所选交易。
- `Marked %1$lld transaction%2$@ as cleared.` → 已将 %1$lld 笔交易标记为已清算。
(The catalog now has exactly 4 *intentional* plural-slot drops, all verified.)

**Wrong / unnatural (5):** 下一月→下个月, 上一月→上个月, `Recategorize` 改类别…→重新归类
(spurious ellipsis + drift), `Settings…`/`Contribute…` missing ellipses.

**Terminology unification (8):** Actions 动作→操作 (matches Action/Add action); Verify 核验→验证
(matches Verified/Unverify); Receipt/Receipts 票据→收据 (matches all other receipt strings);
reviewed 审阅/审核→复核 (Unmark reviewed, Cleared·To review); audit 审核→审计 ×2 (the DB
integrity audit; matches the Audit screen).

**Punctuation / brand (4):** half-width `?` ×2 → ？, half-width parens → （可选）, `finch` brand
kept lowercase (was Finch).

## Verified-OK notables (no change)
- 好 for OK (Apple zh convention), 显示 for the View menu (Apple convention), 百分之 %lld
  (spoken/a11y form), the ` 且 ` joiner's deliberate spaces, 贡献 for Contribute (web-parity term).

## Caveat downgrade

The catalog is now **systematically reviewed and terminology-consistent** (457/472 keys; the 15
untranslated are pure format tokens). This replaces the "unreviewed machine output" caveat —
though it is still AI-reviewed AI translation; a human native spot-check remains best practice
before a commercial release.
