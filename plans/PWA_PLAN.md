# PWA — scoping / design plan

Status: ⊘ **superseded — do not implement.** Kept as a fork-in-the-road
design record. See `plans/MASTER_PLAN.md §5` "Current open items" for the
chosen direction.

> ⚠️ **Doc predates the data-layer change AND is superseded by the native
> direction.** Two unrelated reasons this plan is no longer the path forward:
>
> 1. **Data layer moved server-side.** This plan was written when the DB ran
>    client-side in the browser (OPFS-backed `sqlite-wasm`). That's no longer
>    true — the database is now **server-side and file-backed**
>    (`better-sqlite3` with WAL; see `plans/done/FILE_BACKED_DB_PLAN.md`,
>    shipped), reached over API routes. "Offline" no longer means "the data
>    is already local"; a true offline PWA would need a cached projection
>    / client mirror on top of shell+asset caching. The §-by-§ caching
>    strategy below would need a rewrite against the server-side model.
>
> 2. **Native iOS / macOS supersedes the install-to-home-screen story.**
>    `plans/ios-macos/IOS_MACOS_PLAN.md §1.1` explicitly supersedes this plan's
>    "PWA is good enough for install-to-home-screen" judgement. The chosen
>    path is real native apps (SwiftUI, GRDB on the verbatim schema,
>    iCloud Drive file-pack sync) — not a wrapped web view.
>
> The sections below are kept as a historical record of the fork in the road.
> Treat as **archived**; do not start implementation.

Turn finch into an installable, offline-capable Progressive Web App. This plan
covers caching the **app shell + assets** so the app loads when the network is
gone, plus the small storage/UI polish that comes with being installable.

## 0. Confirmed product decisions

These are decided going in — anything else is an open question (§6).

1. **No data layer changes.** Schema, queries, hydration, OPFS path,
   export/import — all unchanged. The DB already works offline; PWA only
   changes how the *app* is delivered.
2. **No cross-device sync.** The existing "DB file is source of truth →
   export to file → import on the other device" workflow stays the
   cross-device story. A PWA install is **per-device**.
3. **Persistent storage is requested, not assumed.** We call
   `navigator.storage.persist()` once on first launch. If granted, OPFS
   data is preserved until the user explicitly clears it. If denied (the
   browser decides), the app still works — the DB is just "best effort"
   storage that *could* be evicted under extreme pressure (rare in
   practice; finance data is tiny).
4. **Service worker is a thin precache, not a feature platform.** We use
   it only to cache the build's static assets + the WASM binary, and to
   serve them offline. No background sync, no push notifications, no
   complex runtime caching strategies. (Those are real features in their
   own right and out of scope here.)

## 1. What changes vs. what doesn't

| Layer | Changes? |
|---|---|
| Database schema | No |
| Queries / mutations | No |
| Store / hydration | No |
| Provider tree | No |
| Routes | No |
| Read/write paths | No |
| App shell delivery | **Yes** — cached by a service worker |
| `public/sqlite3.wasm` | **Same file, now precached** |
| Root layout `<head>` | **+ manifest link, + theme-color meta, + apple-touch-icon** |
| New: `public/manifest.webmanifest` | Yes (small JSON) |
| New: `public/icons/icon-192.png`, `icon-512.png`, `apple-touch-icon.png` | Yes |
| New: `app/sw.ts` (or `public/sw.js`) | Yes (~100 lines) |
| New: small Settings line "X.X MB used of Y MB" | Yes |
| Tests | One new — manifest is valid JSON; one optional — Playwright "installable" check |

## 2. Architecture decisions

### 2.1 Library choice: hand-rolled vs. `@serwist/next` vs. `next-pwa`

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| Hand-rolled SW (~100 lines, vanilla) | Zero dependency; full control; reads cleanly | Have to write the precache manifest generator (or hard-code asset URLs and accept stale-on-deploy risk until the build hash is wired in) | **Pick if we want zero deps** |
| `@serwist/next` | Actively maintained, current with Next.js 16, precache-manifest is automatic from the build | One dep; one config file | **Pick if we want the ecosystem path** |
| `next-pwa` | Most popular | Stalled, lags Next.js releases; built on Workbox which is now in maintenance mode | **Avoid** |

**Recommendation: `@serwist/next`** — the precache manifest must be generated
from the actual build output (the `_next/static/chunks/*.js` hash changes per
deploy), and rolling that ourselves is busy-work that's been solved well in
the ecosystem. If the user prefers zero-deps, we can hand-roll it, but expect
the SW config to be ~150 lines instead of ~10.

### 2.2 What the service worker caches

Two cache buckets, both populated on `install`:

1. **App shell (precache)** — versioned by the build hash:
   - `/` (the entry HTML)
   - All `_next/static/**/*.js` and `_next/static/**/*.css` for this build
   - `/sqlite3.mjs` and `/sqlite3.wasm`
   - Fonts (already inlined by `next/font`, served from `_next/static`)
   - The icons + manifest

2. **Runtime cache (network-first, fall back to cache)** — for routes
   visited after install. So if the user navigates to a route the precache
   doesn't have (most routes are client-rendered from the same shell, but
   any `app/(main)/*/page.tsx` lazy bundle counts), it's stored on first
   visit.

The `_next/static/chunks/*.js` hash changes per deploy. The cache name
includes the build hash, so each deploy gets a fresh cache and the old one
is purged on `activate`. No stale-shell risk.

### 2.3 Update flow

When a new SW version is detected:
- **skipWaiting + clients.claim** in `activate` → the new SW takes over
  the next time the user opens the tab.
- A one-time toast on the new version's first paint: "finch updated —
  refresh if anything looks off." (Optional; safe to omit.)

### 2.4 Persistent storage

On app start (after hydration), call:
```ts
if ('storage' in navigator && navigator.storage.persist) {
  navigator.storage.persist();
}
```
Don't await it, don't surface the result to the user — fire-and-forget.
Installed PWAs on Chrome/Edge grant automatically; Safari may prompt.

We could pair this with an `estimate()` reading shown in Settings (§3.3
below) so the user can see how much room they have.

## 3. UX surfaces

### 3.1 Install prompt

The browser handles this on its own once the manifest + SW are in place
(Chrome shows an install button in the omnibox; iOS Safari surfaces "Add
to Home Screen" in the share sheet). We do **not** build a custom install
banner — those are pestilential. If we ever do, it would live in Settings
("Install finch on this device"), not as a popup.

### 3.2 Offline indicator

A small badge in the desktop top bar / mobile header when `navigator.onLine
=== false`: `OFFLINE`. The app works fully offline anyway — this is a
status cue, not a blocker.

### 3.3 Settings › Storage row (small)

In `app/(main)/settings/page.tsx`, under the existing database section:

```
Storage
  Used    12.4 MB
  Quota   ~ 5,000 MB
  Persistent storage: granted
```

Numbers come from `navigator.storage.estimate()` and
`navigator.storage.persisted()`. Both are async, both feature-detect
gracefully. Pure read; no settings to change here.

## 4. Files affected

```
frontend/
  app/
    layout.tsx                 ← + manifest link, + theme-color, + apple-touch-icon
    (main)/settings/
      page.tsx                 ← + Storage row (§3.3)
    sw.ts                      ← NEW — service worker entry (if using @serwist/next)
  components/
    pwa-init.tsx               ← NEW — calls navigator.storage.persist() on mount;
                                  also renders the OFFLINE badge (§3.2)
  public/
    manifest.webmanifest       ← NEW
    icons/
      icon-192.png             ← NEW
      icon-512.png             ← NEW
      apple-touch-icon.png     ← NEW (180x180)
      maskable-icon-512.png    ← NEW (for Android adaptive)
  next.config.ts               ← + serwist wrapping (if using @serwist/next)
  package.json                 ← + @serwist/next, + serwist
plans/
  PWA_PLAN.md                  ← this file
```

No changes to `lib/`, `lib/db/`, or any test file beyond an optional
Playwright "installable" check.

## 5. Implementation order (one PR, ~half a day)

1. **Manifest + icons.** Drop the JSON + 3 PNG files. Link from
   `layout.tsx`. The app is now "installable but not offline" — Chrome will
   show the install button.
2. **`@serwist/next` setup.** Add the package, the config in
   `next.config.ts`, and the `app/sw.ts` entry. Precache the build's
   static assets + `/sqlite3.mjs` + `/sqlite3.wasm`. The app is now
   offline-capable.
3. **PWA init component.** A client component mounted from
   `layout.tsx` that:
   - Calls `navigator.storage.persist()` once on mount.
   - Listens to `online` / `offline` events and exposes the OFFLINE badge.
4. **Settings storage row.** A small read-only card showing `usage / quota /
   persisted` from `navigator.storage.*`.
5. **Manual test pass** (browser DevTools + a real phone):
   - DevTools → Application → Manifest: no errors, icons render
   - DevTools → Application → Service Workers: SW active, controlling page
   - Reload with "Offline" checked: page loads, DB hydrates, all reads work
   - Mobile: Add to Home Screen on iOS, Install on Android — launches
     standalone, no browser chrome
   - Settings: Storage row shows reasonable usage figure

## 6. Open questions

1. **Icon design.** Do we have a finch logo PNG at 512×512, or do we
   render one from a font/SVG? (Easy to generate from the existing finch
   wordmark; the maskable variant needs extra safe-area padding.)
2. **Offline badge wording.** `OFFLINE`, `Offline mode`, `No connection` —
   minor copy choice.
3. **Install prompt timing.** Default browser-handled (recommended) or do
   we add a "Install" button in Settings as a discoverability aid?
4. **Library: `@serwist/next` (recommended) vs. hand-rolled?** This is the
   only decision that meaningfully changes the diff size.
5. **Update toast on new SW activation?** A "finch updated, refresh if
   anything looks off" toast — useful, or noisy?

## 7. Risks + mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| SW serves a stale shell after a deploy | Low | Cache name includes build hash; old caches purged on `activate`; `skipWaiting` + `clients.claim` |
| iOS Safari refuses to install | Low | Manifest must be valid + served at the right path; tested before merge |
| WASM not cached, offline cold-start fails | Medium | Explicitly include `/sqlite3.wasm` + `/sqlite3.mjs` in the precache list; covered by the offline test |
| `persist()` denied silently | Low (cosmetic) | App still works; we just show "Persistent: not granted" in Settings. Users can re-prompt by uninstalling/reinstalling. |
| Service worker breaks dev mode (HMR conflicts) | Low | `@serwist/next` is dev-aware; disable SW in `NODE_ENV !== 'production'` |
| Browser quota too small for users with huge ledgers | Very low | Tens of MB at worst; surfaced in Settings so it's visible if it ever happens |

## 8. Out of scope (explicit non-goals)

- **Cross-device sync.** Same as today — export/import the DB file.
- **Push notifications.** Would need a server; we don't have one.
- **Background sync.** Same reason.
- **Native wrappers** (Capacitor, Tauri). PWA is "good enough" for the
  install-to-home-screen story; a native shell adds a release pipeline and
  app-store friction without changing what the app does.
- **Pre-rendering routes for offline.** Routes are client-rendered from
  the cached shell; the runtime cache picks up lazy bundles on first
  visit. No SSR-of-static-content concerns here.

## 9. Acceptance criteria

The PR is mergeable when:

- [ ] Lighthouse PWA audit passes (Installable: yes, Service Worker: yes,
      Manifest: valid)
- [ ] DevTools → Application → Service Worker shows the SW as active and
      controlling the page on the production build
- [ ] Reloading with DevTools "Offline" checked: the app loads, OPFS
      hydrates, all reads work
- [ ] iOS Safari: "Add to Home Screen" shows finch's icon + name; launches
      standalone with no browser chrome
- [ ] Android Chrome: install prompt appears in the omnibox; once
      installed, launches standalone
- [ ] Settings shows the Storage row with non-NaN numbers + a persisted
      status
- [ ] `bun run build`, `bun run lint`, `bun run typecheck`, `bun test lib`
      all pass
- [ ] No regression: existing routes load and DB writes still mirror to
      OPFS the same way they did before
