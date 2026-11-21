// Money rounding to cents, half AWAY from zero: -10.125 → -10.13, 10.125 → 10.13.
//
// The same rule as FinchCore's `r2` (Swift `.rounded()` is
// .toNearestOrAwayFromZero) and as SQLite's ROUND, which the engine also uses.
// `Math.round` alone rounds half toward +∞, so a negative half-cent landed one
// cent away from the native app's figure (-10.12 here, -10.13 there).
export function r2(n: number): number {
  const v = Math.round(Math.abs(n) * 100) / 100;
  return n < 0 && v !== 0 ? -v : v;
}
