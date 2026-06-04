/** Shared validation for an installment plan's total payment count.
 *
 *  `null` / missing means "not an installment plan, just an ordinary
 *  recurring template". A real plan needs a positive integer — fractional
 *  values or zero are rejected outright (a "0-payment plan" makes no sense
 *  and silently coercing it to null would mask a typo).
 *
 *  Re-used by both the server mutation handler and the form on the
 *  Scheduled page so the rules can only be wrong in one place. Throws on
 *  malformed input; callers surface the message via toast. */
export function parseInstallmentTotal(raw: unknown): number | null {
  if (raw == null || raw === '') return null;
  const n = Number(raw);
  if (!Number.isInteger(n) || n <= 0) {
    throw new Error('Installment total must be a positive whole number');
  }
  return n;
}
