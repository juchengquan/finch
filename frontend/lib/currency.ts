// ISO 4217 minor units — mirror of FinchCore's Currencies.minorUnitExceptions.
// The two tables are pinned together by a parity fixture (export-fixtures.ts →
// ios/FinchCore/Tests/ParityTests/Fixtures/currency-minor-units.json); change
// one side without the other and CurrencyParityTests goes red.
//
// Only the exceptions are listed; absence means 2, the ISO default. Codes are
// restricted to the app's pickable set (FinchCore Currencies.iso).
export const MINOR_UNIT_EXCEPTIONS: Record<string, number> = {
  // 0-decimal currencies
  BIF: 0, CLP: 0, DJF: 0, GNF: 0, ISK: 0, JPY: 0, KMF: 0, KRW: 0,
  PYG: 0, RWF: 0, UGX: 0, VND: 0, VUV: 0, XAF: 0, XOF: 0, XPF: 0,
  // 3-decimal currencies
  BHD: 3, IQD: 3, JOD: 3, KWD: 3, LYD: 3, OMR: 3, TND: 3,
};

/** Fraction digits for an ISO 4217 code; absent ⇒ 2 (the ISO default). */
export function minorUnits(currency: string): number {
  return MINOR_UNIT_EXCEPTIONS[currency] ?? 2;
}
