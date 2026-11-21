// Applying the server's state after every mutation replaced every slice with a
// new object, so every component reading the store re-rendered, whatever had
// changed. `share` returns `next`, but with every part that is deeply equal to
// `prev` swapped for prev's own object: an unchanged slice (or transaction,
// account…) keeps its identity, and zustand's selectors skip the re-render.

type Obj = Record<string, unknown>;
const isPlainObject = (v: unknown): v is Obj =>
  v !== null && typeof v === 'object' && !Array.isArray(v) && Object.getPrototypeOf(v) === Object.prototype;
const idOf = (v: unknown): unknown => (isPlainObject(v) ? v.id : undefined);

export function share<T>(prev: unknown, next: T): T {
  if (Object.is(prev, next)) return next;

  if (Array.isArray(prev) && Array.isArray(next)) {
    // Match items by id when they have one (a row moved, or one was inserted
    // ahead of it), else by position.
    const byId = new Map<unknown, unknown>();
    for (const p of prev) if (idOf(p) !== undefined) byId.set(idOf(p), p);
    let same = prev.length === next.length;
    const out = next.map((item, i) => {
      const id = idOf(item);
      const shared = share(id !== undefined && byId.has(id) ? byId.get(id) : prev[i], item);
      if (shared !== prev[i]) same = false;
      return shared;
    });
    return (same ? prev : out) as T;
  }

  if (isPlainObject(prev) && isPlainObject(next)) {
    const keys = Object.keys(next);
    let same = keys.length === Object.keys(prev).length;
    const out: Obj = {};
    for (const k of keys) {
      out[k] = share(prev[k], next[k]);
      if (out[k] !== prev[k] || !(k in prev)) same = false;
    }
    return (same ? prev : out) as T;
  }

  return next;
}

/** The store update for a fresh server state: each top-level slice shared
 *  against the store's current one. */
export function sharedSlices<S extends Obj>(current: S, incoming: Partial<S>): Partial<S> {
  const out: Partial<S> = {};
  for (const k of Object.keys(incoming) as (keyof S)[]) out[k] = share(current[k], incoming[k]) as S[keyof S];
  return out;
}
