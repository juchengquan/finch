# Import / Export overhaul — plan

The DB file is the **only** unit of save / dump / sync. No cloud DB; cloud
file-path drops are fine because they're just files. Export = whole DB.
Import = whole-file replace. This doc covers what we need to add to make
that pair safe, recoverable, and self-describing.

---

## Current state

- **Export** works: `GET /api/export` streams the live server `.sqlite3`
  file (`exportDbBytes()` in `lib/db/server.ts`). Settings has a
  "Download .db" button.
- **Export transactions CSV** also exists at `/api/export/transactions`
  (convenience — not the canonical save format).
- **Import is wired in the UI but disabled** (Settings → Import database
  → Disabled).
- DB is a single file on the server (`FINCH_DB_DIR/finch.sqlite3`),
  loaded into an in-memory sqlite-wasm connection at process start,
  written back atomically (`tmp + rename`) on every write.
- Schema versioning exists today as an **integer** `SCHEMA_VERSION = 6`
  in `lib/db/schema.ts`, stamped via `PRAGMA user_version`;
  `migrate(exec, { fresh })` brings older files up.
- No `db_metadata` table yet. There's a `sync_log` (device sync) and an
  `app_state` (transitional key/value), but nothing about export
  provenance.

## What's missing

1. **Import is a no-op.** The button is disabled. No endpoint, no UI,
   no validation.
2. **Exported files have no provenance.** A user can't tell which Finch
   version produced an export, when, from which device, or whether they
   got a corrupted / half-baked file.
3. **No safety net before import.** Replacing the server DB with a bad
   file would silently lose data.
4. **No reset / clear path** for the server file from the UI (Settings
   only resets the in-memory store via the existing `reset` mutation).
5. **No periodic safety backup** — a single file is the whole world; if
   it's lost we have nothing.

---

## Plan

### 1. Schema version becomes a datetime

Drop the integer `SCHEMA_VERSION = 6`. Replace with an ISO 8601 datetime
string, second precision (UTC), e.g. `"2026-05-30T08:15:30Z"`.

- Sorts lexicographically the same way it sorts chronologically — so
  the migration map can stay an ordinary object keyed by string and
  iterated in order.
- Survives `JSON.stringify` and round-trips through SQLite TEXT
  losslessly.
- New migrations get a key when they're added — no off-by-one renaming.

**Storage**

SQLite's `PRAGMA user_version` only holds a 32-bit integer, so we can't
keep using it for the datetime form. The new source of truth is
`db_metadata.schema_version` (TEXT). We still write `user_version`
once (a small monotonic counter — useful as a fallback / legacy probe
for files that pre-date the metadata table), but the migration loop
reads `db_metadata.schema_version`.

**Migration loop**

```ts
// MIGRATIONS keyed by datetime string. Keys are sorted lexicographically
// to derive ordering (which is the same as chronological because of the
// ISO 8601 format).
export const SCHEMA_VERSION = '2026-05-30T08:15:30Z';
export const MIGRATIONS: Record<string, string[]> = {
  '2026-05-30T08:15:30Z': [
    /* SQL for the db_metadata table itself + backfill */
  ],
  // future:
  // '2026-06-15T12:00:00Z': [...],
};
```

`migrate(exec, { fresh })` walks `Object.keys(MIGRATIONS).sort()` and
applies every entry strictly greater than the current
`db_metadata.schema_version`. Fresh databases just stamp the latest
version without replaying.

**Legacy compatibility**

Older `.db` files (from before this change) only have an integer
`user_version`. The first thing the import / open path does is check
for a `db_metadata` row; if missing, it creates one with
`schema_version = '2026-05-30T08:15:30Z'` (the bootstrap version that
introduced the table), then runs migrations from there.

### 2. New `db_metadata` table

A single-row table — the source of truth for "what is this file?".

```sql
CREATE TABLE db_metadata (
  id              INTEGER PRIMARY KEY CHECK (id = 1),   -- enforce single row
  app_name        TEXT NOT NULL,                        -- 'finch' magic value
  schema_version  TEXT NOT NULL,                        -- ISO 8601 UTC, e.g. '2026-05-30T08:15:30Z'
  app_version     TEXT NOT NULL,                        -- from package.json at build
  created_at      TEXT NOT NULL,                        -- when this file was first initialised
  updated_at      TEXT NOT NULL,                        -- bumped on every persist()
  exported_at     TEXT,                                 -- stamped by GET /api/export at the dump moment
  exported_from   TEXT,                                 -- hostname / device id producing the export
  row_counts      TEXT,                                 -- JSON: { transactions: N, accounts: N, … }
  checksum        TEXT                                  -- SHA-256 over a deterministic row dump (see §4)
);
```

- `getServerDb()` ensures the row exists.
- `persist()` updates `updated_at`.
- Export endpoint additionally stamps `exported_at` / `exported_from` /
  `row_counts` / `checksum` on a **copy** of the DB before reading the
  bytes, so the live DB never carries stale export stamps.

### 3. `autoBackup()` — new function

Per request. Lives in `lib/db/server.ts`:

```ts
/**
 * Copies the live server DB file to a timestamped sibling in the same
 * directory: <FINCH_DB_DIR>/finch-YYYY-MM-DDTHH-MM-SSZ.sqlite3.bak.
 * Resolves to the absolute path of the new backup file. No-op (returns
 * the most recent existing backup) if the last backup is younger than
 * `minIntervalMs` — defaults to 1h so the disk doesn't fill up if it's
 * called from a hot path.
 */
export async function autoBackup(opts?: { minIntervalMs?: number }): Promise<{ path: string }>;
```

**Behaviour**

- Flushes the in-memory DB first (`persist()`), then copies
  `finch.sqlite3` → `finch-<timestamp>.sqlite3.bak` in the same dir.
- Uses the OS-level copy (`fs.copyFile`) — atomic per POSIX on the
  same filesystem.
- Filename uses the same datetime format as `schema_version`, with
  `:` swapped to `-` so it's filesystem-safe.

**Invoked from**

- Before every `POST /api/import` (so the prior state is recoverable).
- Before every `reset` mutation.
- Once on server startup, throttled to one per day, so even a
  long-running server keeps a recent snapshot.
- A new manual button in Settings ("Back up now").

**Retention**

Keep the **N most recent** backups (default `N = 14`); older ones
deleted. Configurable via `FINCH_BACKUP_KEEP` env var.

### 4. Deterministic checksum

In a new `lib/db/checksum.ts`:

```ts
/**
 * SHA-256 over a stable column dump from each canonical table, sorted by
 * id. Excludes `db_metadata` itself (otherwise the checksum would depend
 * on its own value).
 */
export async function computeChecksum(exec: Exec): Promise<string>;
```

- Tables included: `ledgers`, `account_groups`, `accounts`, `categories`,
  `counterparties`, `transactions`, `transaction_tags`,
  `transaction_splits`, `transfer_groups`, `budgets`, `goals`, `tags`,
  `subscriptions`, `scheduled_items`, `recurring_templates`,
  `recurring_splits`, `exchange_rates`, `account_balance_snapshots`,
  `app_state`.
- Stamped on **export**; verified on **import**.
- Mismatch on import = hard reject (file is corrupted / tampered).

### 5. Import endpoint + UI

**`POST /api/import`** (multipart upload of a `.db`):

1. Receive the upload into a temp file.
2. Open it as a sqlite-wasm DB (don't touch the server file yet).
3. **Validate** in this order — fail fast with a clear error:
   - File magic: starts with `SQLite format 3\0`.
   - `db_metadata.app_name = 'finch'`.
   - `db_metadata.schema_version <= SCHEMA_VERSION` (older OK — we'll
     `migrate`; newer = reject).
   - Required tables exist (smoke list: `transactions`, `accounts`,
     `categories`, `ledgers`, `db_metadata`).
   - Foreign-key integrity passes (`PRAGMA foreign_key_check`).
   - `db_metadata.checksum` matches a freshly-recomputed checksum.
4. If valid: run `migrate(exec, { fresh: false })` to bring it up to
   `SCHEMA_VERSION`.
5. **autoBackup() first** (so the prior live state is preserved).
6. **Atomic swap** of the server file: write the validated bytes to
   `finch.sqlite3.incoming`, `rename(incoming → finch.sqlite3)`. Drop
   the cached `_db` so the next request reopens it.
7. Return `{ status: 'ok', metadata: { schema_version, app_version,
   exported_at, row_counts } }`.

**Settings UI**

- Replace the disabled button with an enabled "Import .db" → opens a
  file picker.
- Modal: shows extracted metadata (`app_version`, `exported_at`,
  `schema_version`, row counts) before the user confirms. Big warning:
  "This will replace your current database. A backup of your current
  data was saved to `<backup-path>`."
- On success: toast + force-reload to pick up the new state.

### 6. Export endpoint upgrades

Update `GET /api/export`:

- Stamp `db_metadata` (`exported_at`, `exported_from = os.hostname()`,
  `row_counts`, `checksum`) on a **copy** of the DB before serialising.
- Filename gets a date stamp:
  `finch-2026-05-30T08-15-30Z.sqlite3` (consistent with the schema /
  backup format; better than the current static `finch.sqlite3`).

New endpoint **`GET /api/export/metadata`** — returns just the metadata
as JSON. Settings shows it ("schema v2026-05-30…", "X transactions",
"last exported on…").

### 7. Settings UI cleanup

In `app/(main)/settings/page.tsx`:

- Group rows under a clear "Backup & restore" heading (currently mixed
  in with the "Database" group).
- Add a small metadata panel: "Schema v2026-05-30T08:15:30Z · X
  transactions · Y accounts · last exported {date}".
- Enable "Import .db" → file picker → confirm dialog with metadata
  preview.
- New **"Back up now"** button → calls `autoBackup()` and toasts the
  resulting path.
- New **"Restore last backup"** dropdown → lists the most recent
  backups (returned by a new `GET /api/backups` endpoint) and swaps
  the chosen one back in via a new `POST /api/restore-backup` endpoint
  that runs the same validation + atomic-swap path as import.

---

## Edge cases (added per request)

### Concurrency & atomicity

- **In-flight writes during import**: hold a process-local mutex around
  `withWrite` + the import handler so they don't interleave. Without
  this, a mutation mid-import could clobber the swap.
- **Concurrent imports**: same mutex covers it.
- **Multiple Next.js workers**: out of scope — we run single-process. A
  defensive `O_EXCL` lock file in `FINCH_DB_DIR` would catch a misuse.

### File-system failures

- **Disk full during write**: the atomic `tmp → rename` pattern means
  a half-written file never replaces the good one. Same goes for
  backups (write to `*.bak.tmp`, then rename).
- **`FINCH_DB_DIR` missing on a restored host**: `getServerDb()`
  already runs `fs.mkdir(..., { recursive: true })`. autoBackup() must
  too.
- **Read-only mount**: import / autoBackup fail with a clear error and
  surface "the data directory is read-only" — don't crash the server.

### Upload boundaries

- **Upload size limit**: 50 MB cap on `POST /api/import` to prevent a
  hostile / accidental huge upload from OOMing the process. Configurable
  via `FINCH_IMPORT_MAX_MB`.
- **Wrong content-type or empty body**: rejected with 400 before we try
  to open it.
- **Browser disconnect mid-upload**: the temp file is unlinked in a
  `finally` block so we don't accumulate orphans.

### Validation correctness

- **Forward-compat reject**: `schema_version > SCHEMA_VERSION` ⇒ HTTP
  409 with "this backup is from a newer Finch version". Don't try to
  downgrade.
- **Reset mutation**: the existing `reset` handler wipes and re-seeds
  tables; it must re-stamp `db_metadata` (`schema_version`,
  `created_at`, `updated_at`). Without this the seeded DB looks
  invalid to the validator.
- **Foreign-key violations after migrate**: run `PRAGMA
  foreign_key_check` post-migration and reject if anything fails — a
  buggy older migration could leave dangling references.
- **Non-Finch SQLite file**: caught by the `app_name = 'finch'` probe.
  We return a clean message ("This doesn't look like a Finch export")
  instead of a sqlite-wasm error.

### Privacy & info-leak

- **`exported_from` is a hostname** — fine on a personal machine, may
  leak in shared contexts. Make it opt-out via `FINCH_EXPORT_INCLUDE_HOST=0`.

### Tests

- Round-trip: export → import on a fresh process → identical projected
  state.
- Tampering: flip one byte in an exported file → import fails with
  checksum mismatch.
- Non-Finch SQLite file → reject with the expected error.
- File from a newer `SCHEMA_VERSION` → reject.
- File from an older `SCHEMA_VERSION` → migrate then accept.
- autoBackup() round-trip: create backup, mutate, restore → state
  matches pre-mutation.
- autoBackup() throttle: two calls within `minIntervalMs` return the
  same path.
- autoBackup() retention: writing > N backups prunes the oldest.

---

## Out of scope

- ❌ Cloud database backends — the DB file remains the only sync unit.
- ❌ Selective import (per-ledger, per-table). Whole-file replace only.
- ❌ Merge / diff between two files. Last-write-wins via swap.
- ❌ Encrypted-at-rest backups. We don't have a passphrase flow yet;
  add later if needed.

---

## File touch list

| Path | Change |
|---|---|
| `lib/db/schema.ts` | New `db_metadata` table; switch `SCHEMA_VERSION` to ISO datetime string; bootstrap migration |
| `lib/db/queries/metadata.ts` *(new)* | `readMetadata`, `stampExport`, `bumpUpdated` |
| `lib/db/checksum.ts` *(new)* | `computeChecksum(exec)` over canonical tables |
| `lib/db/server.ts` | Init/maintain metadata row; write mutex; `autoBackup()`; `replaceFile(bytes)` helper; backup retention |
| `app/api/export/route.ts` | Stamp metadata on a copy before dump; date-stamped filename |
| `app/api/export/metadata/route.ts` *(new)* | Returns DB metadata as JSON |
| `app/api/import/route.ts` *(new)* | Validate + autoBackup + swap |
| `app/api/backups/route.ts` *(new)* | Lists existing backups in `FINCH_DB_DIR` |
| `app/api/restore-backup/route.ts` *(new)* | Validate + swap from a named backup file |
| `components/sqlite-backup-provider.tsx` | `importFile(File)`, `metadata`, `backupNow`, `listBackups`, `restoreBackup` |
| `app/(main)/settings/page.tsx` | "Backup & restore" section, metadata panel, import dialog, backup-now / restore-backup affordances |
| `lib/db/import.test.ts` *(new)* | Round-trip / checksum / schema-version / autoBackup tests |

**Suggested commits**

1. Schema datetime + `db_metadata` table + `checksum` + export upgrades.
2. `autoBackup()` + retention + backups listing endpoint.
3. Import endpoint + Settings UI (`Import .db`, `Back up now`,
   `Restore last backup`).
