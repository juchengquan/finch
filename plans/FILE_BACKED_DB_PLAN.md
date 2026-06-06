# File-backed SQLite + WAL — scoping plan

Status: **planning** — no code changes yet.

Today finch's database lives entirely in process memory and is persisted to
disk as a whole-file snapshot after every mutation (the
`sqlite3_js_db_export` → `fs.writeFile` → atomic-rename dance in
`lib/db/server.ts`). That model is simple and crash-safe, but it costs O(N
bytes) on every mutation regardless of how small the change was, and the
single in-memory connection holds the entire ledger in RAM. As the DB grows
beyond a few megabytes the per-mutation snapshot cost becomes the dominant
write expense, and the in-memory-only journal mode means there's no
crash-time middle ground between "fully persisted" and "lost".

This doc scopes a move to a **file-backed SQLite database with WAL** (Write-
Ahead Logging). The runtime DB becomes the file on disk; mutations are
incremental at the row level; WAL becomes the durability boundary instead of
a full-file snapshot. Existing snapshot files convert in place — they're
already standard SQLite format — so no data migration is needed.

## 0. Confirmed product decisions

Decided going in; anything else is an open question (§8).

1. **Single-process, single-writer.** No change to the concurrency model.
   The existing `_writeChain` mutex around mutations stays for serialisation;
   WAL's reader-doesn't-block-writer property is a bonus, not a requirement.
2. **WAL is the only journal mode we'll support.** The other modes (`DELETE`,
   `TRUNCATE`, `MEMORY`) lose either crash safety or performance. WAL is the
   standard for server-side SQLite under Node.
3. **`synchronous = NORMAL`.** The right crash-safety / throughput balance
   with WAL (FULL adds an extra fsync per commit; NORMAL only fsyncs on
   checkpoint).
4. **File format stays SQLite-canonical.** Today's snapshot is already a
   standard `.db` file (that's what `sqlite3_serialize` produces); after the
   switch the live file is the same format. Existing dev DBs open as-is.
5. **No change to the data model.** Schema, queries, mutations, the engine
   under `lib/rules/`, the projection in `lib/db/state.ts` — all unchanged.
   This is a swap of the persistence engine, not a redesign.

## 1. What changes vs. what doesn't

| Layer | Changes? |
|---|---|
| Persistence runtime | **Yes.** `@sqlite.org/sqlite-wasm` (wasm in Node) → `better-sqlite3` (native binding). |
| `Exec` signature in `lib/db/repo.ts` | **Optionally yes.** better-sqlite3 is sync; we can keep the async wrapper for compatibility or peel it back (decision in §8). |
| Schema (`lib/db/schema.ts`) | Two PRAGMAs added to `applySchema` (WAL + NORMAL). The rest is unchanged. |
| Open / persist path (`lib/db/server.ts`) | **Yes.** `open()` opens the file directly via better-sqlite3; `persist()` becomes a WAL checkpoint instead of a full-file rewrite. |
| Export / import (`/api/export`, `/api/import`) | **Yes.** Export is a `VACUUM INTO` to a temp file (atomic snapshot), then a stream; import swaps the live file (closes conn → swap → reopen). |
| All other queries / mutations / migrations | Unchanged. |

## 2. Library choice

### 2.1 The three credible options

- **`better-sqlite3`** (native binding). Sync API, single-statement reuse via
  prepared statements, mature WAL support, the de-facto Node SQLite library.
  Source: <https://github.com/WiseLibs/better-sqlite3>.
- **`node:sqlite`** (built-in, Node 22+). Bundled with Node; sync API similar
  to better-sqlite3. **Still experimental as of Node 22**; stability and
  feature parity vs better-sqlite3 are open questions.
- **Stay on `@sqlite.org/sqlite-wasm`, switch the VFS to a file backend.**
  Possible via emscripten's POSIX FS or the `sahpool` VFS, but the documentation
  is thin and every read/write crosses the wasm boundary.

### 2.2 Recommendation: `better-sqlite3`

- Mature (10+ years of production use), well-documented.
- Sync API maps cleanly onto our `Exec` wrapper (or lets us simplify it).
- WAL + online-backup support are first-class.
- Prebuilds for common Linux / macOS / Windows targets; no compile step on
  the typical CI / local-dev path.

### 2.3 Verified findings from the step-1 probe (run 2026-06-06)

The probe (PR landing this section) ran `better-sqlite3@12.10.0` under
Bun 1.3.11 and Node 22.22.2. Two surprises worth recording so the next
person doesn't repeat the investigation:

- 🚫 **Bun cannot load `better-sqlite3` today.** `new Database(...)` throws
  `ERR_DLOPEN_FAILED`, tracked in [`oven-sh/bun#4290`][bun4290]. This
  contradicts the original "works under Bun's Node-compat mode" claim
  above. **The fallback shape is**: tests under Bun use **`bun:sqlite`**
  (built in, exposes the same sync `prepare/run/all` shape, drives the
  existing `Exec` shim unchanged); the **production server runs under
  Node** with `better-sqlite3`. Both runtimes share the same shim, so the
  query layer is engine-agnostic at the source level. This isn't the
  runtime-coupling §2.2 worried about — the Node server is the
  authoritative DB consumer; Bun is the test runner that happens to need
  a sibling driver.
- ✅ **Native module is no concern on prebuild-supported platforms.**
  `prebuild-install` resolved the binary in ~540 ms with no compile step.
  Linux/macOS/Windows × x64/arm64 all have prebuilds for this release.
- ✅ **Everything else in §2.2's promise held**: WAL engaged on a file-
  backed DB; the recommended PRAGMA bootstrap (`journal_mode`,
  `synchronous`, `foreign_keys`, `temp_store`, `cache_size`) applied
  cleanly; `db.transaction(fn)` wraps with correct rollback on throw;
  WAL recovery survives a close-without-checkpoint (the SIGKILL shape);
  `VACUUM INTO` produces a portable snapshot; `wal_checkpoint(TRUNCATE)`
  drains the WAL to zero.
- 📊 **Per-mutation latency on file-backed WAL: 0.022 ms/op** (1000 raw
  inserts on a fresh DB, Node 22, Linux). Comfortably below the §10
  budget of "single-digit ms on a 10 MB DB". For comparison the same
  query layer under the existing wasm + snapshot path runs in the
  10-100 ms range per mutation, dominated by the full-DB rewrite.

The probe is split across two artefacts in the repo:

- `lib/db/probe.test.ts` — runs under `bun test`. Uses `bun:sqlite` to
  prove the existing `applySchema` + `seedDatabase` + `insertTxRow`
  + `listAccounts` path survives a swap to a sync SQLite engine via the
  shared `Exec` shim.
- `scripts/probe-bs3.mjs` — runs under Node (`bun run db:probe` /
  `node scripts/probe-bs3.mjs`). The nine `better-sqlite3`-specific
  checks above. Not in CI; rerun by hand when bumping
  `better-sqlite3` / Node.

[bun4290]: https://github.com/oven-sh/bun/issues/4290

`node:sqlite` is worth revisiting once it stabilises (Node 24 LTS?); the
migration is small relative to the rest of this plan.

## 3. The new DB lifecycle

### 3.1 Open

```ts
import Database from 'better-sqlite3';

const db = new Database(full, { fileMustExist: false });
db.pragma('journal_mode = WAL');
db.pragma('synchronous = NORMAL');
db.pragma('foreign_keys = ON');
db.pragma('temp_store = MEMORY');
db.pragma('cache_size = -8000');           // 8 MB page cache; tune later.

await applySchema(execFor(db));
await migrate(execFor(db), { fresh: isFirstBoot });
```

`fileMustExist: false` means a missing file is auto-created. The schema +
migration code is unchanged; the only difference is which engine receives
those SQL strings.

### 3.2 Mutation path

```ts
export async function withWrite<T>(fn: (exec: Exec) => Promise<T>): Promise<T> {
  return serialiseWithWriteChain(async () => {
    return db.transaction((tx) => fn(execFor(tx)))();
  });
}
```

Wrapping `fn` in `db.transaction(...)` gives us atomicity (a partial mutation
rolls back on throw) and durability (the WAL frame for the txn is fsynced on
commit when `synchronous = NORMAL`). The existing `_writeChain` mutex stays
in front of this so writes are serialised at the application level.

Key change vs. today: **no `persist()` after every mutation**. The COMMIT
is the persist. The wholesale `sqlite3_js_db_export` + `fs.writeFile` +
atomic rename is gone; in its place, every COMMIT appends frames to the
`*-wal` file and SQLite fsyncs them.

### 3.3 Checkpoint

The WAL grows until a checkpoint is run; SQLite auto-checkpoints when the
WAL reaches ~1000 pages (~4 MB). For a personal ledger this is essentially
never an issue, but we'll add a **best-effort checkpoint on graceful
shutdown** and one **after a successful import** so the post-import state
is reflected in the main file before any backup is taken:

```ts
db.pragma('wal_checkpoint(TRUNCATE)');
```

`TRUNCATE` is the strongest checkpoint mode; it truncates the WAL after
copying frames into the main DB file. Safe to call on a quiet connection.

### 3.4 The two new sidecar files

WAL produces two extra files alongside `finch.db`:

- `finch.db-wal` — the journal.
- `finch.db-shm` — shared memory mapping for connection coordination.

These are normal: every WAL-mode SQLite database carries them. The
file-management code (export, backup, import) must understand that the
"database" is the triple, not just `finch.db`.

## 4. Operational concerns

### 4.1 Crash safety

The today story: every mutation is a full-DB rewrite via `tmp` + atomic
rename — crash mid-write leaves the old file intact, but the in-progress
mutation is lost. The crash window is small but real (between in-memory
commit and `fs.rename`).

The new story: every COMMIT fsyncs WAL frames. A crash after COMMIT but
before checkpoint loses nothing — on next open SQLite replays the WAL.
A crash mid-mutation rolls back via the WAL's normal recovery semantics.
**The crash window for committed data is zero**; the cost is a small
per-commit fsync (the `synchronous=NORMAL` mode amortises this).

### 4.2 Backups

The existing "download backup" path in `/api/export` reads the entire DB
bytes and streams them. With a file-backed DB the equivalent is
`VACUUM INTO` to a tmp file, then a stream:

```ts
db.prepare(`VACUUM INTO ?`).run(tmpPath);
return Readable.from(fs.createReadStream(tmpPath));
```

`VACUUM INTO` produces a clean, single-file snapshot atomically; it works
on a live WAL connection without quiescing other writes (better-sqlite3
exposes it directly). Cleaner than today's `sqlite3_js_db_export`.

### 4.3 Foreign keys

Already on via `PRAGMA foreign_keys = ON` in the canonical schema; needs to
be re-asserted on every connection (the pragma is per-connection in
SQLite, not per-database). The new `open()` sets it explicitly.

### 4.4 Memory footprint

Today: the full DB lives in process RAM. New: SQLite holds an LRU page cache
(default ~2 MB; we'll bump to 8 MB) plus connection bookkeeping. **Memory
becomes O(working set), not O(DB)** — a 100 MB ledger that's been used to
look up the last month's transactions only holds those pages in RAM.

## 5. Export / import workflow

### 5.1 Export

`/api/export` (`.db` download) becomes:

```ts
const tmp = await mktmp();
db.prepare('VACUUM INTO ?').run(tmp);
return streamFile(tmp, { onClose: () => fs.unlink(tmp) });
```

`/api/export/transactions` (CSV) is unchanged.

### 5.2 Import

`/api/import` is the trickier path because the live DB file is open. The
flow becomes:

1. Accept the upload to `*.tmp`.
2. Validate it opens as SQLite + carries our `db_metadata` table.
3. Take the write mutex.
4. `db.pragma('wal_checkpoint(TRUNCATE)')` to drain the live WAL.
5. `db.close()` — releases the OS file locks.
6. `fs.rename(*.tmp, finch.db)` — atomic swap.
7. Delete the now-stale `finch.db-wal` and `finch.db-shm` (they belonged to
   the old DB).
8. Reopen via the standard `open()` path; the cached `_db` promise resets.

Steps 5-8 are the only behavioural change; the rest is the same shape as
today.

### 5.3 Snapshot for download (Settings → Database)

Unchanged from the user's perspective; the underlying call swaps to
`VACUUM INTO`. The "snapshot button" semantics ("create a point-in-time
copy I can keep around") match exactly.

## 6. Migrating existing dev databases

Because today's snapshot file is already in SQLite-canonical format
(`sqlite3_serialize` output is a standard `.db`), **no data migration is
needed**. On first boot under the new code:

1. `new Database(full)` opens the existing file directly.
2. The opening PRAGMA sequence (§3.1) enables WAL — SQLite handles the
   journal-mode switch on a quiescent DB transparently.
3. `applySchema` + `migrate` run as they do today and pick up where the
   stamped `schema_version` left off.

The two sidecar files (`*-wal`, `*-shm`) materialise on first commit.

The migration is forward-only by happy accident: any older snapshot opens
under the new engine, but a user who downgrades to an older finch build
would need to reconstitute the snapshot (the older code can't read a WAL).
For a pre-release single-user app this is acceptable; we'll note it in the
release notes.

## 7. Shipping order

Each step is independently mergeable:

1. **`better-sqlite3` integration probe.** A throwaway branch that swaps
   the runtime in `lib/db/server.ts`, runs the existing test suite, and
   surfaces any incompatibilities (Bun loading, prebuild availability,
   `Exec` signature mismatches). No app behaviour change yet — discoverable
   risk before committing to the architecture.
2. **`Exec` wrapper unification.** Settle whether `Exec` stays async or
   collapses to sync (better-sqlite3 is sync; the wasm-async wrapper is no
   longer needed). Probably a separate refactor PR.
3. **The swap.** Replace the in-memory + snapshot lifecycle in
   `lib/db/server.ts` with file-backed + WAL. Tests use a tmp-path file
   instead of `:memory:` (or use better-sqlite3's `:memory:` mode, which
   exists and works the same way for our purposes). Carries the PRAGMA
   bootstrap + `withWrite` `db.transaction` wrapping.
4. **Export / import rewrite.** `VACUUM INTO` for export; close-and-swap
   for import. Backups (Settings → Database) get the same treatment.
5. **Operational polish.** Shutdown checkpoint, post-import checkpoint,
   doc updates (CLAUDE.md, README.md).

PR slice for early value: **3** is the load-bearing one. Steps 1+2 derisk
it; step 3 is where the user-visible behaviour changes (faster startup,
no per-mutation file write); steps 4+5 are post-swap cleanup.

## 8. Open questions

1. **Sync vs. async `Exec`?** better-sqlite3 is sync. We can keep the
   async `Exec` shape (every query wrapped in `Promise.resolve`) so the
   rest of the code doesn't move — pure mechanical simplicity. Or we can
   collapse it: every query layer becomes sync, every mutation handler
   stays async only where it does real async work (no `await exec(...)`).
   The collapse is cleaner long-term; the wrap is a one-PR option.
   **Recommendation**: keep async for the migration PR (minimise diff),
   collapse in a follow-up.
2. ~~**Bun version pin?**~~ **Resolved by the probe.** No current Bun loads
   `better-sqlite3` (oven-sh/bun#4290 is open as of 1.3.11). The settled
   approach: keep Bun as the test runner, use **`bun:sqlite`** for the
   test DB (same sync API as better-sqlite3, drives the existing `Exec`
   shim unchanged); ship **`better-sqlite3`** as the production runtime
   under Node. See §2.3 for the verified fallback.
3. **`cache_size`?** 8 MB is a starting point. For a personal-finance
   ledger of ~10k transactions the working set comfortably fits in
   memory; we can revisit if monitoring shows page churn.
4. **Auto-checkpoint cadence?** SQLite's default of 1000 pages is fine
   for a single-user app; the WAL never grows beyond a few MB in practice.
   No explicit override needed.
5. **WAL files in `.gitignore` / backup tooling?** Ensure the user's
   `FINCH_DB_DIR` housekeeping (in `README.md` and ops docs) calls out
   the `*-wal` / `*-shm` sidecars so they aren't accidentally
   left behind on a restore.

## 9. Out of scope

- **Multi-process or multi-host writes.** Single-writer stays; if we ever
  need this, WAL gets us partway but a real concurrency story (separate
  doc) is the right place to take it on.
- **A streaming changelog / CDC.** WAL exposes the change stream in
  principle (SQLite session/extension APIs), but no feature needs it today.
- **Moving back to wasm.** This plan commits to native bindings; reverting
  would be a follow-on doc.
- **Encrypted DB at rest.** SQLite's SQLCipher / better-sqlite3-multiple-
  ciphers exist but are a separate threat-model conversation.

## 10. Acceptance criteria

For the integration probe (step 1):

- `bun test lib` runs to completion against a `better-sqlite3` backend
  with no test changes. (May require a thin compat shim on `Exec`.)
- A 10 MB seeded DB opens in under 100 ms on a typical dev laptop.

For the swap (step 3):

- After every mutation, the live `finch.db-wal` carries the new frames;
  no `finch.db.tmp` is ever written.
- A `SIGKILL` mid-mutation, followed by a re-open, recovers the
  pre-mutation state cleanly (existing FK-checked schema passes
  `PRAGMA foreign_key_check`).
- Per-mutation latency drops to single-digit ms on a 10 MB DB (it's
  ~tens of ms today, dominated by the snapshot rewrite).
- Settings → Database still surfaces the same status / export / import
  affordances; "Connect backup file" continues to work.

For export/import (step 4):

- `/api/export` returns a single-file snapshot that opens cleanly in a
  fresh better-sqlite3 instance.
- `/api/import` round-trip (export → re-import) yields a byte-identical
  database (compared via `VACUUM INTO` then SHA-256).

For operational polish (step 5):

- Graceful shutdown leaves a checkpointed `finch.db` with a near-empty
  `-wal` sidecar.
- CLAUDE.md's "Data layer" section is updated; README's setup script
  no longer references the old serialise/deserialise path.
