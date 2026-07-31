#!/usr/bin/env bun
// Parses the exported xliff and prints the authoritative source strings the Swift
// compiler extracted from the app's LocalizedStringKey literals (the
// Localizable.xcstrings <file> group only). These are the catalog keys, with
// interpolation already rendered as %lld/%@/%lf format specifiers.
//
// POSITIONAL DE-NORMALIZATION: the xliff export rewrites every multi-argument
// string to positional specifiers ("%1$@ of %2$@"), but SwiftUI's runtime
// lookup key for `Text("\(a) of \(b)")` is the NON-positional form
// ("%@ of %@") — a catalog entry stored under the positional key is dead and
// the string silently renders English in every language. So: keys whose
// positions are strictly sequential (1,2,3… in order) are rewritten back to
// the runtime form, UNLESS the exact positional string appears literally in
// the Swift sources (then it IS the runtime key — e.g. a hand-written
// String(localized: "%1$@ …") that reorders args). Translations may still use
// positional specifiers in their VALUES; only the key must match runtime.
//
// USAGE: bun run scripts/xliff-keys.ts <localizationPath>
//
// `<localizationPath>` is the directory given to `xcodebuild -exportLocalizations`;
// it must contain `zh-Hans.xcloc`. Pass a RUN-SCOPED directory (`mktemp -d`), not a
// fixed one.
//
// **Why the path is an argument now.** It used to be hardcoded to /tmp/finch-loc,
// which is shared by every worktree on the machine. When two sessions ran
// `ci-local.sh` at once, one export failed on the DerivedData lock and this script
// silently parsed the xliff the OTHER branch had left behind — reporting four keys
// "missing from the app" that were present, and naming a pre-existing string among
// them. A confident, specific, wrong answer that reads exactly like a real i18n
// regression. Hence also the freshness check below: an xliff older than the newest
// Swift source cannot describe those sources, so this refuses to guess.
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const die = (msg: string): never => {
  console.error(`xliff-keys: ${msg}`);
  process.exit(1);
};

// ---- Swift sources: needed for de-normalization, and for the freshness check ---
const { swiftSource, newestSourceMs, newestSourcePath } = (() => {
  const roots = ["FinchApp/Sources", "Shared", "FinchWidget", "FinchShare", "FinchWatch"]
    .map((d) => join(import.meta.dir, "..", d));
  let all = "";
  let newestMs = 0;
  let newestPath = "";
  const walk = (dir: string) => {
    let entries: string[];
    try { entries = readdirSync(dir); } catch { return; }
    for (const e of entries) {
      const p = join(dir, e);
      const st = statSync(p);
      if (st.isDirectory()) walk(p);
      else if (e.endsWith(".swift")) {
        all += readFileSync(p, "utf8");
        if (st.mtimeMs > newestMs) { newestMs = st.mtimeMs; newestPath = p; }
      }
    }
  };
  roots.forEach(walk);
  return { swiftSource: all, newestSourceMs: newestMs, newestSourcePath: newestPath };
})();

const locPath = process.argv[2] ?? process.env.FINCH_LOCALIZATION_PATH;
if (!locPath) {
  die("no localization path given.\n" +
      "  usage: bun run scripts/xliff-keys.ts <localizationPath>\n" +
      "  where <localizationPath> is what you passed to -exportLocalizations.\n" +
      "  Use a run-scoped directory (mktemp -d), never a fixed one — see the header.");
}

const XL = join(locPath!, "zh-Hans.xcloc", "Localized Contents", "zh-Hans.xliff");
if (!existsSync(XL)) {
  die(`no xliff at ${XL}\n` +
      "  The export did not produce one — re-run -exportLocalizations and read ITS errors.\n" +
      "  (Do not fall back to another directory: a stale xliff yields a wrong key set.)");
}

// An xliff older than the newest Swift source cannot describe those sources. This is
// the failure that motivated the argument above: the export had failed, and the file
// left on disk was another run's.
const xliffMs = statSync(XL).mtimeMs;
if (newestSourceMs > xliffMs) {
  die(`the xliff is STALE — it predates the Swift sources, so its key set is wrong.\n` +
      `  xliff:  ${XL}\n` +
      `          ${new Date(xliffMs).toISOString()}\n` +
      `  newest: ${newestSourcePath}\n` +
      `          ${new Date(newestSourceMs).toISOString()}\n` +
      "  Re-run -exportLocalizations into a fresh directory.");
}

const xml = readFileSync(XL, "utf8");

// Grab the <file original="...Localizable.xcstrings" ...> ... </file> block.
const start = xml.indexOf('original="FinchApp/Sources/FinchShared/Resources/Localizable.xcstrings"');
if (start === -1) {
  die(`no Localizable.xcstrings <file> group in ${XL}\n` +
      "  The export is incomplete — it did not reach the app's string catalog.");
}
const fileOpen = xml.lastIndexOf("<file", start);
const fileClose = xml.indexOf("</file>", start);
const block = xml.slice(fileOpen, fileClose);

const unesc = (s: string) =>
  s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"')
   .replace(/&apos;/g, "'").replace(/&amp;/g, "&");

const keys: string[] = [];
const re = /<source>([\s\S]*?)<\/source>/g;
let m;
while ((m = re.exec(block))) keys.push(unesc(m[1]));

if (keys.length === 0) die(`extracted 0 keys from ${XL} — that is never right.`);

// ---- positional → runtime form (see header) --------------------------------

export function denormalize(key: string, source: string): string {
  const posRe = /%(\d+)\$/g;
  const positions = [...key.matchAll(posRe)].map((x) => Number(x[1]));
  if (positions.length === 0) return key;                    // no positional specifiers
  if (source.includes(key)) return key;                      // literal in source = runtime key
  const sequential = positions.every((p, i) => p === i + 1);
  if (!sequential) {
    console.error(`  WARN non-sequential positional key kept as-is: ${JSON.stringify(key)}`);
    return key;                                              // reordered — cannot be a runtime key
  }
  return key.replace(posRe, "%");
}

const uniq = [...new Set(keys.map((k) => denormalize(k, swiftSource)))].sort();
console.error(`extracted ${uniq.length} unique app keys`);
process.stdout.write(JSON.stringify(uniq, null, 2) + "\n");
