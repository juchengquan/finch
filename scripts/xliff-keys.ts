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
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const XL = "/tmp/finch-loc/zh-Hans.xcloc/Localized Contents/zh-Hans.xliff";
const xml = readFileSync(XL, "utf8");

// Grab the <file original="...Localizable.xcstrings" ...> ... </file> block.
const start = xml.indexOf('original="FinchApp/Sources/FinchShared/Resources/Localizable.xcstrings"');
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

// ---- positional → runtime form (see header) --------------------------------
const swiftSource = (() => {
  const roots = ["FinchApp/Sources", "Shared", "FinchWidget", "FinchShare", "FinchWatch"]
    .map((d) => join(import.meta.dir, "..", d));
  let all = "";
  const walk = (dir: string) => {
    let entries: string[];
    try { entries = readdirSync(dir); } catch { return; }
    for (const e of entries) {
      const p = join(dir, e);
      if (statSync(p).isDirectory()) walk(p);
      else if (e.endsWith(".swift")) all += readFileSync(p, "utf8");
    }
  };
  roots.forEach(walk);
  return all;
})();

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
