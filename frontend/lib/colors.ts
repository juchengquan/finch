// OKLCH → hex sRGB conversion.
//
// Categories and tags used to store an OKLCH hue (0–360) at fixed lightness +
// chroma so everything visually rhymed. They now store hex strings directly
// (one consistent `color` column across accounts/categories/tags). This module
// converts hue → hex using the same OKLCH formulas the render code used, so
// migrated seed values look identical to before. New picks go through the same
// helpers when the UI offers a hue/swatch picker.

/** Fixed lightness/chroma used by the category palette (matches the legacy
 *  `oklch(0.65 0.13 ${hue})` formula). */
export const CATEGORY_L = 0.65;
export const CATEGORY_C = 0.13;

/** Fixed lightness/chroma used by the tag palette (matches the legacy
 *  `oklch(0.65 0.18 ${hue})` formula). */
export const TAG_L = 0.65;
export const TAG_C = 0.18;

/** OKLCH (L 0–1, C 0–~0.4, H 0–360) → sRGB hex `#rrggbb`. */
export function oklchToHex(L: number, C: number, Hdeg: number): string {
  const Hrad = (Hdeg * Math.PI) / 180;
  const a = C * Math.cos(Hrad);
  const b = C * Math.sin(Hrad);

  // OKLab → linear sRGB (Björn Ottosson's matrix).
  const l_ = L + 0.3963377774 * a + 0.2158037573 * b;
  const m_ = L - 0.1055613458 * a - 0.0638541728 * b;
  const s_ = L - 0.0894841775 * a - 1.2914855480 * b;
  const l = l_ ** 3;
  const m = m_ ** 3;
  const s = s_ ** 3;
  const rLin =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
  const gLin = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
  const bLin = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;

  // Linear sRGB → gamma-encoded sRGB, then clamp + pack.
  const toGamma = (x: number): number => {
    const c = Math.max(0, Math.min(1, x));
    return c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055;
  };
  const r8 = Math.round(toGamma(rLin) * 255);
  const g8 = Math.round(toGamma(gLin) * 255);
  const b8 = Math.round(toGamma(bLin) * 255);
  const hex = (n: number) => n.toString(16).padStart(2, '0');
  return `#${hex(r8)}${hex(g8)}${hex(b8)}`;
}

/** Category palette colour for a hue (0–360). */
export const categoryHex = (hue: number) => oklchToHex(CATEGORY_L, CATEGORY_C, hue);

/** Tag palette colour for a hue (0–360). */
export const tagHex = (hue: number) => oklchToHex(TAG_L, TAG_C, hue);

/** Fallback hex used when a category/tag has no colour set. */
export const DEFAULT_CATEGORY_HEX = categoryHex(220);
export const DEFAULT_TAG_HEX = tagHex(220);
