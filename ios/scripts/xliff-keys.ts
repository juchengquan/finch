#!/usr/bin/env bun
// Parses the exported xliff and prints the authoritative source strings the Swift
// compiler extracted from the app's LocalizedStringKey literals (the
// Localizable.xcstrings <file> group only). These are the catalog keys, with
// interpolation already rendered as %lld/%@/%lf format specifiers.
import { readFileSync } from "node:fs";

const XL = "/tmp/finch-loc/zh-Hans.xcloc/Localized Contents/zh-Hans.xliff";
const xml = readFileSync(XL, "utf8");

// Grab the <file original="...Localizable.xcstrings" ...> ... </file> block.
const start = xml.indexOf('original="FinchApp/Sources/FinchApp/Resources/Localizable.xcstrings"');
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

const uniq = [...new Set(keys)].sort();
console.error(`extracted ${uniq.length} unique app keys`);
process.stdout.write(JSON.stringify(uniq, null, 2) + "\n");
