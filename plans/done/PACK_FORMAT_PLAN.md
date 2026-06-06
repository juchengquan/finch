# `.finch` pack format — scoping plan

Status: **shipped** (PR #107, 2026-06-06). This doc is kept as the design
record. Every section below was implemented as designed; an end-to-end
smoke confirmed byte-identical round-trip (`MASTER_PLAN.md` "Done since
(post-PR-#82)").

Companion plan: `plans/done/RECEIPT_PHOTOS_PLAN.md` (PR #106). Packs
carry the attachments that work introduced — both apps adopt the same
on-disk shape and the same pack manifest.

> **Postscript (follow-up PR, 2026-06-06):** the Settings UI was
> standardised on `.finch` after this plan shipped — a single
> "Download .finch" button (the bare-`.db` checkbox affordance was hard
> to discover), and the import file picker narrowed to `accept=".finch"`.
> Auto-backups also moved to **`.finch.bak`** packs (DB + receipts +
> manifest) so a restore brings receipts back too — not just the
> database. Frequency + retention became user-settable in Settings,
> persisted in `app_state['backupConfig']` so they travel with the
> database (every pack carries them). Env vars
> `FINCH_BACKUP_MIN_INTERVAL_MS` / `FINCH_BACKUP_KEEP` became fallback
> defaults, no longer the primary mechanism. Back-compat preserved:
> `restoreBackup` still reads legacy `.sqlite3.bak` files on disk via
> magic-byte detection. The server's `/api/export` route still accepts
> the `?withAttachments=0` query for the bare-DB path so external
> tooling isn't broken; no in-app caller uses it.

> Cross-platform file-portability unit for finch: a single zip carrying the
> SQLite database, its attachments folder, and a self-describing manifest.
> The **shape** of the pack was decided in `IOS_MACOS_PLAN.md §2.5.3` as the
> sync unit for iCloud Drive file-pack sync; this doc covers the **web-app
> export/import implementation** so packs round-trip between the web app
> and the future native apps.
>
> Spun out of `RECEIPT_PHOTOS_PLAN.md §7` so the receipts feature stays
> focused on "attach, view, delete" and the cross-app interop story lives
> in its own scope. Implement after `RECEIPT_PHOTOS_PLAN.md` ships — packs
> need the attachments table + on-disk folder layout the receipts work
> introduces.

Today the web app's `/api/export` returns a bare `.db` (`VACUUM INTO`) and
`/api/import` reads a bare `.db`. That round-trips the database but silently
leaves receipts behind. The pack format closes that gap and makes the web
app a first-class member of the file-portability loop the iOS/macOS plan
describes.

## 0. Confirmed product decisions

Decided going in — anything else is an open question (§7).

1. **Zip container with the `.finch` extension** registered as a document
   type. The container is plain zip (no compression of already-compressed
   formats like JPEG/PNG/PDF; deflate for the SQLite file and manifest).
2. **One pack = the whole DB** (all ledgers) + every attachment + a
   manifest. There's no concept of a per-ledger pack in v1; the DB is a
   single file holding all ledgers anyway, and attachments are
   ledger-tagged via their FK.
3. **Manifest is the integrity contract.** `manifest.json` carries
   schema version, app metadata, the DB's sha256, and a per-attachment
   inventory with sha256s. Receivers MUST validate the manifest + every
   sha256 before atomically swapping in the contents.
4. **Atomic on receive.** Unpack to a tmp directory, validate, then
   rename into place. A failed validation leaves the receiver's current
   data untouched.
5. **Bare `.db` interop still works.** Users who only want the database
   (no attachments) can keep exporting/importing raw `.db`. The
   transaction_attachments table is simply empty after a bare-db import.
6. **Reuses the existing integrity guard.** `lib/db/checksum.ts` already
   computes the row-counts + DB checksum that `db_metadata` stores; the
   pack manifest is its generalisation, not a new mechanism.

## 1. What changes vs. what doesn't

| Layer | Changes? |
|---|---|
| Schema | No. (Receipts plan already adds the attachments table.) |
| Mutations | No. |
| Read path | No. |
| Existing `/api/export` | Gains an opt-in `?withAttachments=true` query → returns a `.finch` zip instead of a bare `.db`. Default behaviour (no query) is unchanged. |
| Existing `/api/import` | Gains zip detection: `.zip`/`.finch` magic bytes → unpack-and-swap; otherwise existing raw-`.db` path. |
| New helpers | `lib/db/pack.ts` — build + validate + extract a pack. |
| Settings UI | New "Include receipts" checkbox next to the existing "Download .db" button. |
| Tests | Pack build → extract round-trip; manifest validation; tampered-file rejection. |

## 2. Pack layout

Restated from `IOS_MACOS_PLAN.md §2.5.3` for self-containment.

```
my-ledger.finch       (ZIP container; .finch extension)
├── manifest.json
├── finch.sqlite3     -- VACUUM INTO'd before packing
└── attachments/
    └── <transaction_id>/
        └── <attachment_id>.<ext>
```

- Filename convention: `<app-or-user-chosen-name>.finch`. The web app
  defaults to `finch-<exported_at>.finch` (e.g. `finch-2026-06-11.finch`).
- ZIP entries are stored in the order: `manifest.json` first (so a
  streaming reader can validate before pulling files), then the DB, then
  attachments grouped by transaction.

## 3. Manifest schema

```jsonc
{
  "pack_format_version": "1",         // bumps on incompatible format changes
  "app_name": "finch",
  "app_version": "0.x.y",             // package.json version at export time
  "schema_version": "2026-06-11T00:00:00Z", // db_metadata.schema_version
  "exported_at": "2026-06-11T14:32:01.000Z",
  "exported_from": {                  // optional; helps with conflict-copy UX
    "device": "web",                  // 'web' | 'ios' | 'macos'
    "device_id": "<opaque>",
    "device_name": "<user-friendly>"
  },
  "db": {
    "filename": "finch.sqlite3",
    "byte_size": 1234567,
    "sha256": "<hex>",
    "row_counts": {                   // matches db_metadata.row_counts
      "transactions": 4321,
      "accounts": 14,
      // …
    }
  },
  "attachments": {
    "count": 87,
    "total_bytes": 12345678,
    "items": [
      {
        "id": "<uuid>",
        "rel_path": "attachments/<txn>/<id>.jpg",
        "byte_size": 142357,
        "sha256": "<hex>"
      }
      // …
    ]
  }
}
```

- `pack_format_version` is the contract between writers and readers. v1
  is the only version that exists today; future incompatible changes
  bump it and the receiver refuses higher versions it doesn't understand.
- `schema_version` is the SQLite-side version (the existing migration
  lineage). On import, the receiver runs migrations forward if its
  schema is older; it refuses a pack whose schema is *newer* than the
  receiver knows about — "can't read a future format."
- `exported_from` is informational; never used for security decisions
  (there's no signing).

## 4. Build (export)

`POST /api/export` (or `GET /api/export?withAttachments=true`):

1. Acquire the write-lock (no mutations during pack).
2. `VACUUM INTO` a temp sqlite file (existing pattern; gives a clean DB
   without WAL/shm).
3. Compute sha256 of the temp DB; gather row counts (reuse
   `lib/db/checksum.ts`).
4. List every `transaction_attachments` row + its on-disk file; compute
   each sha256 (streaming, no double-read).
5. Build `manifest.json`.
6. Write a zip: manifest first, then DB, then attachments.
7. Stream the zip to the response with `Content-Type: application/zip`
   (or a registered `application/vnd.finch+zip` if we add one) and
   `Content-Disposition: attachment; filename="finch-<date>.finch"`.
8. Release the lock.

## 5. Import

`POST /api/import` with a body that may be either:
- a raw `.db` (existing behaviour — keep it), or
- a `.zip`/`.finch` pack.

Detection: read the first 4 bytes — `PK\x03\x04` (zip) → pack path;
`SQLite format 3\0` → raw DB path; anything else → 400.

Pack path:

1. Unpack to a tmp directory under `${FINCH_DB_DIR}/.import-tmp/<job_id>/`.
2. Read `manifest.json`. Validate:
   - `pack_format_version` is supported.
   - `schema_version` is ≤ the receiver's known version (run migrations
     forward later if older).
   - `db.sha256` matches the actual DB file.
   - For each attachment in `items`: file exists, `byte_size` matches,
     `sha256` matches.
3. Acquire the write-lock; close the live DB connection.
4. Atomic swap:
   - Rename the existing `finch.sqlite3` to `finch.sqlite3.old-<ts>` (and
     `attachments/` to `attachments.old-<ts>/`) — keep one rotation so a
     bad import is reversible.
   - Rename the tmp DB into place; rename the tmp attachments folder
     into place.
5. Reopen the DB connection; run migrations forward if needed.
6. Verify post-swap: connection opens; `db_metadata.schema_version` reads
   correctly.
7. Release the lock; return the fresh `ProjectedState`.

If any step fails, restore the `.old-<ts>` rotation and return a 5xx
with a clear error.

## 6. UI surfaces

### 6.1 Export (Settings → Database)

- Existing "Download .db" button stays as the default action.
- New checkbox above the button: **"Include receipts (`.finch` pack)"**.
  - Unchecked → existing `.db` download.
  - Checked → `.finch` download.
- Per-device preference persisted via `useSyncExternalStore` +
  `localStorage` (same pattern as saved searches).

### 6.2 Import (Settings → Database)

- Existing "Import" file picker accepts `.db,.sqlite,.sqlite3` today.
  Extend `accept` to also include `.finch,.zip`.
- After file pick, show a one-step confirm dialog with what we read from
  the manifest: "Replace your database with this pack? (N transactions,
  M receipts, exported {date} from {device_name})." Cancel / Replace.
- On replace, lock the UI with a progress indicator; the import runs as
  one POST.

### 6.3 No conflict-copy UX in v1

iCloud-Drive-style conflict copies are an iOS concern (`IOS_MACOS_PLAN
§4.3`); the web app's single-user / single-process model doesn't
encounter them. If we ever add a "what's in this pack vs my current DB"
preview before replace, that's a v2 feature.

## 7. Open questions

1. **MIME type registration.** `application/zip` works but isn't
   distinctive; a custom `application/vnd.finch+zip` would let browsers
   route `.finch` openly to the right handler. Worth registering? For v1,
   `application/zip` is enough.
2. **Compression level.** Default zip-deflate level for the SQLite file
   (which compresses well) vs `store` for already-compressed images.
   Recommend: deflate for `manifest.json` + the DB; `store` for everything
   under `attachments/`.
3. **Rotation policy for `.old-<ts>` folders.** Keep N rotations, then
   sweep? Or one rotation only (overwritten on next import)? Recommend
   one rotation only for v1 — disk hygiene over fine-grained history.
4. **Streaming vs buffered build.** A pack with many attachments can be
   tens of MB. Stream to the response, or build in tmp first then stream?
   Recommend stream-as-you-build (lower memory) but accept the
   complication of needing the manifest before the entries.
5. **Schema-version mismatch policy.** Today: refuse a newer pack.
   Future: allow opening read-only? Out of scope for v1.
6. **Cross-platform path separators.** ZIP entries use forward slashes
   universally; ensure the builder doesn't accidentally write
   backslashes on Windows. (Not a concern for the Linux/macOS dev
   targets but worth a test.)

## 8. Risks + mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Pack format drifts between web and native | Medium | Single shared manifest schema; pack-format-version contract; cross-app round-trip test (web → native → web) |
| Tampered/corrupted pack imported | Medium | Manifest's per-file sha256 validated before swap; any mismatch aborts with 5xx |
| Mid-import crash leaves DB in tmp state | Low | Atomic rename; `.old-<ts>` rotation enables recovery |
| Zip bomb (declared 1 MB → expands to 10 GB) | Low | Validate `byte_size` against actual extracted size; refuse mismatch |
| Schema-version mismatch | Medium | Manifest carries `schema_version`; receiver refuses newer; migrates older forward |
| Concurrent mutation during build | Low | Hold the write-lock during `VACUUM INTO` + manifest build |
| Native app writes a pack the web can't read | Low | Pack-format-version is the contract; receivers refuse unknown versions cleanly |
| Disk full mid-export | Low | Stream to response; failed writes are picked up by the user (no partial download is saved) |

## 9. Out of scope

- **Signed packs / verification of origin.** No PKI in finch. The pack
  is integrity-checked but not authenticated.
- **Encrypted packs.** Tracks the decision in
  `IOS_MACOS_PLAN.md §10` — file-protection only in v1.
- **Selective/partial packs** (one ledger, or one date range). Out of
  scope; the pack is "the whole DB + everything attached."
- **Conflict-copy UX.** iCloud-Drive concern; not relevant on the web.
- **Incremental sync.** Packs are wholesale, not diffs. Row-level sync
  is the full `IOS_MACOS_PLAN.md §4.3-C`, not on the roadmap.

## 10. Acceptance criteria

The PR is mergeable when:

- [ ] `GET /api/export?withAttachments=true` returns a valid `.finch`
      zip with a correct manifest, DB sha256, and per-attachment sha256s.
- [ ] `GET /api/export` (no query) still returns a bare `.db`
      (back-compat).
- [ ] `POST /api/import` detects pack vs bare `.db` by magic bytes;
      rejects unknown bodies with 400.
- [ ] Pack import validates the manifest, every attachment sha256, and
      the DB sha256; rejects a tampered file with a clear error.
- [ ] Atomic swap on success; on failure, the live DB + attachments
      are untouched and the `.old-<ts>` rotation is recoverable.
- [ ] Round-trip test: export → import → export produces the same
      logical state (DB row counts + attachment ids + sha256s).
- [ ] Cross-app round-trip: a pack written by the web app validates
      against the manifest schema declared here (and is opened cleanly
      by the future native app — verified when that lands).
- [ ] Settings → Database has the "Include receipts" toggle + import
      accepts `.finch`.
- [ ] `bun test lib` covers pack build + extract + validation cases.
- [ ] `bun run typecheck`, `bun run lint`, `bun run build` all green.
