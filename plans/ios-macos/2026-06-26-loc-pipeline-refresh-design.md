# Localization pipeline refresh (zh-Hans coverage — step 1)

**Date:** 2026-06-26
**Status:** Approved approach (refresh-first), pending execution.
**Scope:** Re-run the documented xcstrings build pipeline so the catalog captures every current `LocalizedStringKey` literal (not just the 2026-06-14 snapshot), and rebuild zh-Hans from the web map. Then **measure + report** the remaining English-fallback set to decide hand-translation. Regenerated artifacts only — no app-code change.

## Root cause

`ios/scripts/extracted-keys.json` is **frozen at 2026-06-14** (#190); ~2 weeks of feature
work added literal UI strings (`Text("This month")`, `Text("No transactions in this
ledger yet.")`, …) that were never extracted, so they're absent from
`Localizable.xcstrings` and fall back to English. The catalog *looks* complete (325/325)
only because it's pinned to the stale key set. The web en→zh map already covers many of
the new strings — they just need to be re-extracted and rebuilt.

## Steps (the documented pipeline — see `build-xcstrings.ts` header)

```bash
cd ios && xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -exportLocalizations -project FinchApp.xcodeproj -scheme FinchApp \
  -localizationPath /tmp/finch-loc -exportLanguage zh-Hans          # → /tmp/finch-loc/zh-Hans.xcloc
bun run scripts/xliff-keys.ts > scripts/extracted-keys.json          # refresh the key set
bun run scripts/build-xcstrings.ts                                   # rebuild catalog (prints manual/web/fallback stats)
```
`build-xcstrings.ts` precedence per key: `zh-manual.json` > web en→zh map > English
fallback. It prints `keys / manual / web-map / English-fallback` counts + the
fallback-key list — that list is the **assessment output** for the next step.

## Deliverable

- Regenerated `ios/scripts/extracted-keys.json` + `ios/FinchApp/.../Localizable.xcstrings`
  committed.
- A report: total keys (was 325 → N), how many auto-translated via the web map, and the
  **English-fallback list** (the candidates for hand-translation in a follow-up).

## Out of scope (this step)
- Hand-authoring `zh-manual.json` for the fallback strings (the assess-then-decide
  follow-up).
- Fixing `Text(stringVariable)` bypass sites that hold UI labels (separate; most of the
  ~97 `Text(var)` sites are dynamic user data and correctly stay untranslated).
- Any app-code or engine change.

## Testing
- **Build:** FinchApp (iOS) + FinchMac (macOS) — the regenerated catalog must still build.
- **Manual (sim):** spot-check that previously-English literals (e.g. "This month") now
  render in Chinese under zh-Hans **if** the web map covered them.

## Notes
- The export step is heavy (full build + export) — expect a few minutes.
- The `.xcloc` lands under `/tmp/finch-loc` (gitignored / not committed). PR → `feat/frontend`.
