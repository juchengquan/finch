#!/usr/bin/env bun
// Builds FinchApp/Sources/FinchShared/Resources/Localizable.xcstrings (zh-Hans) from:
//   1. scripts/extracted-keys.json — the authoritative LocalizedStringKey set the
//      Swift compiler extracted (via `xcodebuild -exportLocalizations`, parsed by
//      scripts/xliff-keys.ts). Interpolations are already %@/%lld/%1$@ specifiers.
//   2. scripts/zh-manual.json — hand-authored zh-Hans (priority).
//   3. an English→Chinese map zipped from the web's messages/en.json + zh-CN.json.
//
// Precedence per key: manual > web-map > untranslated (English fallback at runtime).
// Re-run after adding UI strings (export to a FRESH directory each time and pass it
// through — a reused one lets a failed export leave a stale xliff that yields a wrong
// key set, silently):
//   LOC=$(mktemp -d)
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     xcodebuild -exportLocalizations -project FinchApp.xcodeproj -scheme FinchApp \
//     -localizationPath "$LOC" -exportLanguage zh-Hans
//   bun run scripts/xliff-keys.ts "$LOC" > scripts/extracted-keys.json
//   bun run scripts/build-xcstrings.ts
//
// REMOVING a UI string? The export can't see deletions — it emits the union of
// source strings AND existing catalog entries, so a dead key round-trips
// through the catalog forever. Delete it from extracted-keys.json by hand and
// re-run this script (the rebuilt catalog then drops it, which also removes it
// from future exports). Keep extracted-keys.json in JSON.stringify(_, null, 2)
// format — python's json escapes non-ASCII and churns the whole file.
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const REPO = join(import.meta.dir, "..", "..");
const SRC = join(REPO, "ios", "FinchApp", "Sources", "FinchShared");
const OUT = join(SRC, "Resources", "Localizable.xcstrings");

// ---- inputs ----------------------------------------------------------------
const keys: string[] = JSON.parse(readFileSync(join(import.meta.dir, "extracted-keys.json"), "utf8"));
const manualRaw = JSON.parse(readFileSync(join(import.meta.dir, "zh-manual.json"), "utf8"));
const manual: Record<string, string> = {};
for (const [k, v] of Object.entries(manualRaw)) if (!k.startsWith("_")) manual[k] = v as string;

// English → Chinese from the web messages (same key order → leaf values align).
function leaves(obj: any): string[] {
  const acc: string[] = [];
  const walk = (o: any) => {
    for (const v of Object.values(o)) {
      if (typeof v === "string") acc.push(v);
      else if (v && typeof v === "object") walk(v);
    }
  };
  walk(obj);
  return acc;
}
const en = JSON.parse(readFileSync(join(REPO, "frontend/messages/en.json"), "utf8"));
const zh = JSON.parse(readFileSync(join(REPO, "frontend/messages/zh-CN.json"), "utf8"));
const enLeaves = leaves(en), zhLeaves = leaves(zh);
const norm = (s: string) => s.replace(/\s+/g, " ").trim().replace(/[…\.]+$/, "").toLowerCase();
const e2c = new Map<string, string>();
for (let i = 0; i < enLeaves.length && i < zhLeaves.length; i++) {
  const k = norm(enLeaves[i]);
  if (k && !e2c.has(k)) e2c.set(k, zhLeaves[i]);
}

// ---- build catalog ---------------------------------------------------------
const strings: Record<string, any> = {};
let nManual = 0, nWeb = 0, nFallback = 0;
const fallbacks: string[] = [];
for (const k of [...keys].sort()) {
  let zhVal: string | undefined;
  if (manual[k] !== undefined) { zhVal = manual[k]; nManual++; }
  else if (e2c.has(norm(k)) && !k.includes("%")) { zhVal = e2c.get(norm(k)); nWeb++; }
  if (zhVal) {
    strings[k] = { localizations: { "zh-Hans": { stringUnit: { state: "translated", value: zhVal } } } };
  } else {
    strings[k] = {};          // English fallback at runtime
    nFallback++; fallbacks.push(k);
  }
}
const catalog = { sourceLanguage: "en", strings, version: "1.0" };
writeFileSync(OUT, JSON.stringify(catalog, null, 2) + "\n");

console.log(`keys: ${keys.length}`);
console.log(`  manual zh-Hans:   ${nManual}`);
console.log(`  web-map zh-Hans:  ${nWeb}`);
console.log(`  English fallback: ${nFallback}`);
console.log(`\nEnglish-fallback keys (intentional — numbers/symbols/brand or untranslated):`);
for (const f of fallbacks) console.log("  " + JSON.stringify(f));
console.log(`\nwrote ${OUT}`);
