// Structured error type for the client localisation pipeline (I18N_PLAN §4.4).
//
// The mutation layer throws English Error today; those messages bubble through
// /api/mutate as { error: string } and land in a toast. To localise without
// shipping a full Accept-Language sniffer or a per-locale server runtime, we
// change the wire format to a code + params triple and translate client-side.
//
// Authoring on the server:
//   throw new I18nError(
//     'error.budget.duplicate',
//     { name: 'Groceries' },
//     `A budget named "Groceries" with this cycle already exists.`,
//   );
//
// The third arg is the English fallback. It serves two roles:
//   1. Server logs see something human-readable, not a key string.
//   2. Unmigrated client callers (still doing `toast.error(err.message)`
//      before the localisation sweep lands at their surface) surface the
//      English text — no UX regression during the rollout.
//
// On the wire:
//   { error: { code, params, message } }
//
// On the client (lib/api-client.ts::mutate):
//   - Rethrows as an `Error` whose `.message` is the English fallback so
//     existing `toast.error(err.message)` calls keep working unchanged.
//   - Attaches `.code` + `.params` so migrated callers can opt into
//     localisation: `t((err as ErrorWithI18n).code, err.params)`.

export type I18nErrorParams = Record<string, string | number>;

/** Error subclass that carries a translation key + params + English fallback. */
export class I18nError extends Error {
  readonly code: string;
  readonly params: I18nErrorParams;
  constructor(code: string, params: I18nErrorParams = {}, fallbackEnglish?: string) {
    super(fallbackEnglish ?? code);
    this.code = code;
    this.params = params;
    this.name = 'I18nError';
  }
}

/** Wire shape for a translatable server error. */
export interface I18nWireError {
  code: string;
  params: I18nErrorParams;
  /** English fallback so unmigrated `toast.error(err.message)` calls work. */
  message: string;
}

/** Detected error shape on the client. */
export interface ErrorWithI18n extends Error {
  code: string;
  params: I18nErrorParams;
}

export function isI18nWireError(v: unknown): v is I18nWireError {
  return (
    !!v && typeof v === 'object' &&
    typeof (v as I18nWireError).code === 'string' &&
    typeof (v as I18nWireError).message === 'string'
  );
}

/** Every API error body is `{ error: WireError }`: a message always, and the
 *  code + params when the error is translatable. (Routes used to send a bare
 *  string for some errors and this object for others.) */
export interface WireError {
  message: string;
  code?: string;
  params?: I18nErrorParams;
}

/** Serialise a thrown value to the route's `error` field. */
export function toWireError(err: unknown): WireError {
  if (err instanceof I18nError) {
    return { code: err.code, params: err.params, message: err.message };
  }
  return { message: err instanceof Error ? err.message : 'Unknown error' };
}

/** Decode the wire shape into a client `Error` carrying the i18n metadata.
 *  Existing `toast.error(err.message)` callers see the English fallback;
 *  callers that want to localise check `(err as ErrorWithI18n).code`. */
export function fromWireError(wire: unknown): Error {
  if (isI18nWireError(wire)) {
    const e = new Error(wire.message) as ErrorWithI18n;
    e.code = wire.code;
    e.params = wire.params ?? {};
    return e;
  }
  if (wire && typeof wire === 'object' && typeof (wire as WireError).message === 'string') {
    return new Error((wire as WireError).message);
  }
  // A bare string: an older server, or a body that isn't JSON.
  return new Error(typeof wire === 'string' ? wire : 'Server error');
}
