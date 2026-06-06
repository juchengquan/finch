# Receipt photos — scoping plan

Status: **planning** — no code changes yet.

> Web-app scoping doc for attaching receipt photos / PDFs to transactions.
> The **shape of the data** (pointer-only table + on-disk layout + a portable
> pack format) was decided as part of the native iOS/macOS direction brief
> (`IOS_MACOS_PLAN.md §2.5`); this doc covers the **web-app implementation**
> on top of that schema. The two apps adopt the table together so packs
> round-trip cleanly (see `IOS_MACOS_PLAN.md §8` cross-app implications).

"What was that $42 at Target six months ago?" becomes answerable. Today the
transaction detail sheet has merchant + amount + a free-text note — and the
"Receipt — coming soon" quick-action stub was deleted in the cleanup pass
(`MASTER_PLAN.md §5`). This plan reverses that retreat with a real
implementation: snap or upload a photo/PDF, see it in the detail sheet,
view full-size in a lightbox, delete it cleanly.

Two related features stay out of scope here and live in their own buckets:
**OCR-from-receipt → transaction** (`FEATURE_IDEAS §1.5`, L effort) is a
separate plan layered on top of plain attachments; **searchable notes**
(`FEATURE_IDEAS §4.2`) is unrelated. This plan is the foundation either of
those can build on.

## 0. Confirmed product decisions

These are decided going in — anything else is an open question (§9).

1. **Files live outside the SQLite database.** The DB stores `transaction_
   attachments` **pointer rows** (`rel_path`, `sha256`, mime, size); bytes
   live on the server filesystem next to the DB file. Inherited verbatim
   from `IOS_MACOS_PLAN.md §2.5`. This is the load-bearing decision — it
   keeps the DB small, keeps backups fast, and matches the `.finch` pack
   format (§7) that lets the native apps and the web app share files.
2. **Server-side storage, not OPFS.** The `FEATURE_IDEAS §4.1` note still
   reads "stored in OPFS (no upload)" — that's stale. The OPFS client-DB
   layer was retired in favour of server-side SQLite (`MASTER_PLAN.md §1
   Phase G`); attachments must follow the DB, so they live under
   `${FINCH_DB_DIR}/attachments/` on the server. No third-party cloud, no
   uploads anywhere finch doesn't run.
3. **Image + PDF only.** Allowed mime types: `image/jpeg`, `image/png`,
   `image/webp`, `image/heic`/`heif`, `application/pdf`. Anything else
   rejected at upload with a clear error.
4. **No OCR in this plan.** OCR sits on top — once an attachment exists,
   `FEATURE_IDEAS §1.5` can read it and pre-fill a transaction draft. That
   work has its own plan; this one delivers plain attach/view/delete.
5. **No thumbnail pipeline in v1.** Images are rendered at the requested
   CSS size by the browser; receipts are typically small enough (a few MB
   each) that on-the-fly rendering is fine. Revisit only if a perf
   complaint actually lands.
6. **Path traversal is the security model to guard against.** There's no
   per-user auth (finch is single-user); the safety property is "the server
   only serves files that belong to a row in the projected DB," not "the
   server checks who you are." Server constructs the on-disk path from the
   row's stored `rel_path` and refuses anything that escapes the
   attachments root. Documented in §5.2 + §10.
7. **No EXIF on upload.** Strip EXIF (incl. GPS) server-side before
   writing. Phone photos routinely carry location data the user did not
   intend to log into a personal-finance ledger.

## 1. What changes vs. what doesn't

| Layer | Changes? |
|---|---|
| Schema | One new table (`transaction_attachments`) + 2 indexes + a `SCHEMA_VERSION` bump (see §2). |
| Mutations | New `addAttachment` (called by the upload route) and `removeAttachment`. |
| API routes | New `POST /api/attachments` (multipart upload), `GET /api/attachments/:id` (serve), `DELETE /api/attachments/:id` *or* a `removeAttachment` action through the existing `/api/mutate`. |
| Read path | `ProjectedState` gains an `attachments` array (lightweight rows; the file bytes stay server-side). The store mirrors it like every other slice. |
| Existing UIs | Transaction detail sheet gains an Attachments row (`components/transaction-detail.tsx`). Activity rows MAY get a small paper-clip indicator (deferred — §11). |
| New UIs | A lightbox/viewer dialog for full-size preview + a confirm-delete. |
| Storage | A new `attachments/` directory under `FINCH_DB_DIR` (created on first upload). |
| Exports | `/api/export` learns an opt-in to bundle attachments alongside the `.db` (the `.finch` pack — see §7). |
| Tests | Schema migration + query/mutation tests; route tests for upload/serve/delete; UI smoke. |

## 2. Data model

Mirrors the schema sketched in `IOS_MACOS_PLAN.md §2.5.1`. Restated here so
the implementation doc is self-contained.

```sql
CREATE TABLE transaction_attachments (
  id                TEXT PRIMARY KEY,         -- UUID
  ledger_id         TEXT NOT NULL REFERENCES ledgers(id) ON DELETE CASCADE,
  transaction_id    TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
  kind              TEXT NOT NULL CHECK(kind IN ('image','pdf')),
  -- Server-relative path: 'attachments/<transaction_id>/<id>.<ext>'.
  -- Bytes are NEVER in the DB.
  rel_path          TEXT NOT NULL,
  mime_type         TEXT NOT NULL,
  byte_size         INTEGER NOT NULL,
  sha256            TEXT NOT NULL,            -- integrity check on read
  original_filename TEXT,                     -- preserved for download/UI
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);
CREATE INDEX idx_attach_txn    ON transaction_attachments(transaction_id);
CREATE INDEX idx_attach_ledger ON transaction_attachments(ledger_id);
```

- **Cascades:** deleting a transaction or a ledger removes the rows by FK
  cascade. The handler also unlinks the on-disk files in the same
  transaction (§4) so disk state stays in sync with DB state.
- **No nullable `transaction_id`:** an attachment without a transaction is
  not a concept finch has. (Bank statements as standalone documents would
  be a separate feature.)
- **Migration:** an additive `CREATE TABLE IF NOT EXISTS` + two `CREATE
  INDEX IF NOT EXISTS` under the next `SCHEMA_VERSION` stamp; idempotent
  under the `isAlreadyAppliedError` swallow rule (`schema.ts`).

### 2.1 Projection

`ProjectedState` (`lib/db/repo.ts`) gains:

```ts
attachments: AttachmentRow[];

interface AttachmentRow {
  id: string;
  ledgerId: string;
  transactionId: string;
  kind: 'image' | 'pdf';
  mimeType: string;
  byteSize: number;
  sha256: string;
  originalFilename: string | null;
  createdAt: string;
}
```

`rel_path` is **deliberately omitted** from the projection — clients
reference attachments via `GET /api/attachments/:id`, which looks up the
path server-side. Keeping it server-only reduces the contract surface and
removes any temptation to construct a URL client-side.

## 3. Storage layout + integrity

### 3.1 On-disk layout

```
${FINCH_DB_DIR}/
├── finch.sqlite3
├── finch.sqlite3-wal
├── finch.sqlite3-shm
├── backups/                  (already exists — /api/backups)
└── attachments/
    └── <transaction_id>/
        ├── <attachment_id>.jpg
        └── <attachment_id>.pdf
```

- One directory per transaction keeps an FS listing readable when humans
  go poking. (At a thousand transactions a year, a flat directory works
  too, but per-txn dirs are friendlier to manual recovery.)
- The path inside the DB column is **relative** (`attachments/<txn>/<id>.ext`),
  so the file is portable when `FINCH_DB_DIR` moves and the same layout
  drops straight into the `.finch` pack (§7).

### 3.2 Integrity

- `sha256` is computed at upload time (streaming, no double-read) and
  stored in the row.
- `GET /api/attachments/:id` MAY verify on serve behind an opt-in query
  param (e.g. `?verify=1` for an explicit "check this hasn't been
  tampered with" UI). Verifying every serve is overkill; the hash exists
  primarily for pack-import validation (§7).
- A future "vacuum" command (out of scope here) walks the directory and
  reports orphan files (on disk but no row) and dangling rows (row but no
  file). Not needed for v1 because mutations keep disk + DB in lockstep.

### 3.3 Atomicity

- **Upload:** write to a `.tmp` sibling first, fsync, then rename into
  place; only after rename succeeds does the handler insert the DB row.
  A crash mid-upload leaves an orphan `.tmp` the next upload can sweep.
- **Delete:** drop the DB row first, then unlink the file. If the unlink
  fails (disk error, EBUSY on Windows in dev), the file is orphaned —
  the next vacuum sweeps it. The user-visible model is "the receipt is
  gone" regardless.

## 4. Mutations

```ts
// Inserted by the upload route after the file is on disk. Not callable
// from /api/mutate (no way to ship binary bytes through JSON).
addAttachment({
  id: string,                 // UUID generated server-side
  ledgerId: string,
  transactionId: string,
  kind: 'image' | 'pdf',
  relPath: string,            // server-built; never client-provided
  mimeType: string,
  byteSize: number,
  sha256: string,
  originalFilename: string | null,
}): void

// Standard mutation; callable from the client.
removeAttachment({ id: string }): void
```

- `removeAttachment` runs inside the existing `withWrite` transaction:
  SELECT the row → DELETE → unlink the file. Failed unlinks log and
  continue; the DB row is gone (the user-visible truth).
- `addAttachment` is **never called from the client directly** — it's an
  internal helper the upload route invokes after the file is durably on
  disk. That keeps the "DB row implies file on disk" invariant intact.
- A transaction or ledger delete fires the FK cascade; the cascade
  handler (a query, not a trigger) collects the affected `rel_path`s
  before the DELETE and unlinks them after the COMMIT. Cleaner than a
  SQL trigger that would have to run an external side effect.

## 5. API surface

### 5.1 `POST /api/attachments` — upload

- Body: `multipart/form-data` with parts:
  - `transactionId` (text)
  - `file` (the binary part; original filename preserved)
- Server validation, in order:
  1. `transactionId` belongs to a real transaction in the projected DB
     (and the txn's ledger is in scope).
  2. `Content-Length` ≤ **per-file cap** (default 25 MB; §9 open).
  3. Mime type in the allowlist (§0.3). For HEIC, accept and store as-is
     (modern Safari + Chrome render it natively; §9 open).
  4. Per-transaction count ≤ **cap** (default 10; §9 open).
- Pipeline: stream the body → tmp file → strip EXIF if image → compute
  sha256 → rename into `attachments/<txn>/<uuid>.<ext>` → `addAttachment`
  → return the fresh `ProjectedState` (same shape as `/api/mutate`).
- Errors: 400 (bad mime / oversize / over-count), 404 (txn not found),
  413 (body bigger than `Content-Length` said), 500 (disk / fs). Body
  is `{ error: string }` to match the rest of the API.

### 5.2 `GET /api/attachments/:id` — serve

- Look up the row in the live projection. 404 if no row.
- Build the on-disk path as `${FINCH_DB_DIR}/${rel_path}`. Refuse to
  serve if the resolved path doesn't start with
  `${FINCH_DB_DIR}/attachments/` (path-traversal guard). Refuse if the
  file is missing (the row will have been dropped on the next vacuum).
- Stream the file with:
  - `Content-Type: <mime_type>`
  - `Content-Length: <byte_size>`
  - `Content-Disposition: inline; filename="<original_filename>"`
  - `Cache-Control: private, max-age=0, must-revalidate` (receipts are
    personal; never let an intermediate cache hold them).
- Optional `?verify=1` query → compute sha256 while streaming and compare
  with the stored value; on mismatch, abort the response with a 5xx and
  log a tamper warning.

### 5.3 Delete

Two paths; pick one (recommend the mutate action, for consistency):

- `POST /api/mutate { action: 'removeAttachment', args: { id } }` — fits
  the existing pattern, response is `ProjectedState`. **Recommended.**
- `DELETE /api/attachments/:id` — RESTful but a one-off; would need its
  own response shape. Skip unless we add similar REST endpoints elsewhere.

## 6. UI surfaces

### 6.1 Transaction detail sheet — attachments row

`components/transaction-detail.tsx`. Place the row directly below the
existing Review row (which sits below Account / Status / Note); the
ordering is: identification → context → triage flags (review, cleared,
attachments).

**Empty state:**
```
Receipts                                            [ Attach receipt + ]
```
- Button opens the native file picker: `<input type="file"
  accept="image/jpeg,image/png,image/webp,image/heic,application/pdf">`.
  On mobile, set `capture="environment"` so tapping launches the camera.
- Drop target on desktop (the whole row): drag a file onto it.

**Non-empty state:**
```
Receipts                                                       [ + ]
+----------+ +----------+ +----------+
|  thumb   | |  thumb   | |  thumb   |   (horizontal scroll on overflow)
+----------+ +----------+ +----------+
```
- Square 56–64 px thumbnails, rounded, hairline border. Images render
  via the serve route; PDFs render a paper icon + the original filename.
- Tap a thumbnail → opens the lightbox (§6.2).
- Long-press / right-click → context menu: View · Download · Delete.

**Toasts:** `sonner` success/error toasts on upload, delete, and any
size/mime rejection.

### 6.2 Lightbox / viewer

A shadcn `Dialog` (full-screen on mobile).

- **Images:** an `<img>` sized to fit, with click-to-zoom on desktop and
  pinch-to-zoom on mobile (CSS `touch-action: pinch-zoom`). Keyboard
  nav (← →) when the transaction has multiple attachments.
- **PDFs:** `<embed type="application/pdf" src="…" />`. Modern browsers
  render PDFs in-place; on browsers that don't, fall back to a "Download"
  button.
- Header: original filename + size (e.g. "receipt.pdf · 412 KB").
- Footer: Delete (with confirm) + Download.

### 6.3 List-level indicator (deferred)

A small paper-clip badge on Activity rows when the transaction has ≥1
attachment. Computable from the projected `attachments` array in O(1)
per row. Out of scope for v1 to keep the diff focused — added when the
attachments are actually being used.

## 7. Export / pack integration

The web app's current `/api/export` returns a bare `.db` (`VACUUM INTO`).
This is fine for users who only want the database, but it silently leaves
receipts behind. Two changes:

1. **`/api/export?withAttachments=true`** returns a `.finch` zip — the
   format defined in `IOS_MACOS_PLAN.md §2.5.3`:
   ```
   <ledger>.finch                  (ZIP container)
   ├── manifest.json               -- pack metadata + checksums
   ├── finch.sqlite3               -- VACUUM INTO'd before packing
   └── attachments/
       └── <transaction_id>/
           └── <attachment_id>.<ext>
   ```
   `manifest.json` carries: pack-format version, `app_name`, `app_version`,
   `schema_version`, `exported_at`, `db_sha256`, `row_counts` (mirrors
   `db_metadata`), per-attachment `{ id, sha256, byte_size }`. The
   existing `lib/db/checksum.ts` integrity guard generalises into this.
2. **`/api/import`** learns to detect a zip pack vs a bare `.db`. On a
   pack: validate the manifest, validate every attachment's sha256 against
   `manifest.json`, drop the DB into place (existing path), then mirror
   the `attachments/` folder into `${FINCH_DB_DIR}/attachments/`. On a
   bare `.db`: existing behaviour (the attachments table will simply be
   empty).

Settings UI: under Database, add an "Include receipts" checkbox next to
the existing "Download .db" button. The default is off (back-compat); a
saved per-device preference toggles it on.

This makes the web app a fully-fledged member of the file-portability
loop the iOS/macOS plan describes — the same pack format flows in any
direction.

## 8. Implementation order (one PR, sequenced commits)

Each step ends with a green `bun run typecheck`, `bun run lint`,
`bun test lib`, `bun run build`.

1. **Schema + migration.** Add `transaction_attachments` + indexes to
   `lib/db/schema.ts`; bump `SCHEMA_VERSION`; migration entry.
2. **Query layer.** `lib/db/queries/attachments.ts` — `listAttachments`,
   `getAttachment`, `insertAttachment`, `deleteAttachment` (the last two
   are the file-aware ones; SELECT rel_path before DELETE for the unlink).
3. **Projection.** `ProjectedState.attachments` + the store slice +
   the optimistic patch shapes.
4. **Mutations.** `addAttachment` (server-only helper) and
   `removeAttachment` (dispatched from `/api/mutate`). Cascade handlers
   for transaction + ledger delete pull `rel_path`s and unlink after
   COMMIT.
5. **Upload route.** `POST /api/attachments`. Multipart parse, validation
   ladder (§5.1), EXIF strip for images, sha256, tmp-rename, then
   `addAttachment`. Returns `ProjectedState`.
6. **Serve route.** `GET /api/attachments/:id`. Lookup, path-traversal
   guard, stream. Optional `?verify=1`.
7. **Transaction detail UI.** Attachments row in
   `components/transaction-detail.tsx` (empty + non-empty states, file
   picker, drop target, toasts).
8. **Lightbox.** New `components/attachment-viewer.tsx` (Dialog with
   image vs PDF rendering, keyboard nav, delete + download).
9. **Export/import .finch.** `/api/export?withAttachments=true` builds
   the zip; `/api/import` detects pack vs bare `.db`; Settings UI gains
   the checkbox.
10. **Tests** + a manual pass on mobile + desktop (Safari iOS for HEIC,
    Chrome for drag-drop, Firefox for PDF embed).

## 9. Open questions

1. **Per-file cap** — 25 MB feels right for photos; a multipage PDF can
   blow past it. Bump to 50 MB? Configurable via env var?
2. **Per-transaction count cap** — 10 items? A multi-vendor receipt at a
   shopping centre easily hits 5+. Recommend 20.
3. **HEIC handling** — accept as-is (modern browsers render it; older
   ones don't) or transcode to JPEG at upload (small server-side dep)?
   Recommend accept-as-is + document the older-browser limitation. (iOS
   Safari and macOS Safari render HEIC; desktop Chrome/Firefox don't
   yet, as of writing — they get a broken image. Transcoding fixes
   that at the cost of a build dep.)
4. **EXIF policy** — strip everything, or keep "useful" tags (orientation,
   timestamp)? Recommend strip *all*, then rotate-correct based on the
   orientation tag before stripping so the photo doesn't render sideways.
5. **Thumbnail pipeline** — build at upload (Sharp/Vips) for instant
   Activity-level rendering later, or stay JIT and revisit? Recommend
   defer — see §0.5.
6. **Verify-on-serve UI** — surface a "Verify integrity" action on each
   attachment in the detail view? Or keep `?verify=1` as an
   import-time-only check, never user-triggered? Lean toward
   import-time-only; a per-attachment button is busywork.
7. **Inline preview on Activity** — when the paper-clip badge is added
   (out of scope here), hover-preview on desktop? Or click-to-open only?
   Defer with the indicator.
8. **Cross-ledger move (future)** — if a transaction is ever moved
   between ledgers, do attachments follow? Not a thing today (no such
   mutation), but worth flagging.

## 10. Risks + mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Disk fill from many large receipts | Medium | Per-file cap + per-txn cap (§9); Settings shows total attachment bytes; a future "vacuum" cleans orphans |
| Path traversal via crafted upload | Low | UUIDs for filenames, server-built paths, resolve-and-check-startsWith guard on serve (§5.2) |
| EXIF leaks GPS/device info | Medium | Strip server-side at upload (§0.7) |
| Mime spoofing (renamed `.exe` to `.jpg`) | Low | mime check is paired with a magic-byte check (e.g. `file-type`) before persisting |
| Forgotten orphan files on crash | Low | `.tmp` sweep at startup; future vacuum command |
| Pack zip bombs on import | Low | Cap declared `byte_size` against the actual file size on extract; refuse mismatch |
| HEIC unrenderable in some browsers | Medium | Document the limitation; revisit transcoding (§9) |
| Backup size balloons | Low (expected) | `/api/backups` already streams; pack format includes only what's referenced |
| FK cascade vs file unlink race | Low | Collect paths before DELETE, unlink after COMMIT (§4) |

## 11. Out of scope

- **OCR / auto-extract** — `FEATURE_IDEAS §1.5`. A separate plan; layers
  on top of attachments.
- **Image search / "find receipts like this"** — needs OCR + indexing.
- **Annotations on receipts** (drawing, highlights) — niche.
- **Cloud-hosted attachments** — never; finch's promise is "your data,
  your machine."
- **Attachment thumbnails as a precomputed pipeline** — see §0.5; defer.
- **Activity-list paper-clip indicator** — see §6.3; defer.
- **Receipt sharing** (a public URL) — never; receipts are personal and
  there's no auth.
- **Statements as a distinct kind of attachment** — for v1, statements
  are just PDFs attached to whichever transaction the user picks. A
  first-class "statement document" entity (with a date range and an
  account, not a single transaction) is a separate feature.

## 12. Acceptance criteria

The PR is mergeable when:

- [ ] Schema migration applied + idempotent on re-run (verified by the
      existing migration runner's `isAlreadyAppliedError` path).
- [ ] `POST /api/attachments` accepts multipart, enforces size + mime +
      count caps, strips EXIF, computes sha256, writes file via
      tmp-then-rename, inserts the row, returns the full projection.
- [ ] `GET /api/attachments/:id` serves with the correct content-type
      and disposition; refuses 404 / 5xx on missing row, missing file,
      or path traversal.
- [ ] `removeAttachment` drops the row + unlinks the file; deleting the
      parent transaction cascades the row and unlinks the file.
- [ ] Transaction detail shows the Attachments row: empty state +
      non-empty state with thumbnails + add + lightbox view + delete.
- [ ] Lightbox renders images (with zoom) and PDFs; keyboard ← → cycles
      attachments on the same transaction.
- [ ] `/api/export?withAttachments=true` produces a valid `.finch` pack
      that `/api/import` round-trips back into an identical state.
- [ ] `bun test lib` covers the schema, queries, and mutations; new
      route tests cover upload validation + serve guards.
- [ ] `bun run typecheck`, `bun run lint`, `bun run build` all green.
- [ ] No regression in existing transaction-detail flows (review,
      cleared, splits, refund).
