import fs from 'node:fs/promises';
import { existsSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { openDb, execFor, applyPragmaBootstrap, type SqliteDriver } from './driver';
import { applySchema, migrate } from './schema';
import { seedDatabase } from './seed';
import { projectState, readBackupConfig } from './state';
import { bumpUpdated, rowCounts, stampExport } from './queries/metadata';
import { computeChecksum } from './checksum';
import { rollBudgetsIfDue } from '@/lib/budgets/rollover';
import type { Exec, ProjectedState } from './repo';

// The authoritative database: a single file-backed SQLite connection held by
// the Node server for the life of the process. WAL is the durability boundary
// (every COMMIT fsyncs frames) — there's no per-mutation full-file snapshot
// any more. See FILE_BACKED_DB_PLAN §3.
//
// File location comes from env vars so it can point at persistent storage:
//   FINCH_DB_DIR   directory (default: <cwd>/.data)
//   FINCH_DB_FILE  filename  (default: finch.sqlite3)
// The sidecar files SQLite manages alongside the main file are
// `${FINCH_DB_FILE}-wal` and `-shm`.

function dbFile(): { dir: string; full: string } {
  const dir = process.env.FINCH_DB_DIR || path.join(process.cwd(), '.data');
  const file = process.env.FINCH_DB_FILE || 'finch.sqlite3';
  return { dir, full: path.join(dir, file) };
}

/** Remove the WAL sidecars alongside `full`, if they exist. Used after we
 *  close a connection prior to swapping the underlying file (import / restore)
 *  so the new file isn't accidentally paired with the old WAL on reopen. */
async function removeSidecars(full: string): Promise<void> {
  await fs.unlink(`${full}-wal`).catch(() => {});
  await fs.unlink(`${full}-shm`).catch(() => {});
}

interface ServerDb {
  exec: Exec;
  driver: SqliteDriver;
  file: string;
}

let _db: Promise<ServerDb> | null = null;

async function open(): Promise<ServerDb> {
  const { dir, full } = dbFile();
  await fs.mkdir(dir, { recursive: true });
  const isFresh = !existsSync(full);

  const driver = await openDb(full);
  applyPragmaBootstrap(driver);
  const exec = execFor(driver);

  // applySchema's CREATE TABLE/INDEX IF NOT EXISTS statements are idempotent —
  // they pick up any tables/indexes added since the file was last opened. Then
  // migrate replays the ordered schema changes the version stamp says are due.
  await applySchema(exec);
  if (isFresh) {
    await seedDatabase(exec);
    await migrate(exec, { fresh: true });
  } else {
    await migrate(exec, { fresh: false });
  }

  return { exec, driver, file: full };
}

/** The shared server database, opened once per process. */
export function getServerDb(): Promise<ServerDb> {
  if (!_db) _db = open();
  return _db;
}

/** Test-only: drop the cached connection so the next getServerDb() reopens
 *  against (possibly-changed) FINCH_DB_DIR. Never call from app code. */
export function _resetServerDbForTests(): void {
  if (_db) {
    _db.then((d) => d.driver.close()).catch(() => {});
  }
  _db = null;
}

// Best-effort graceful-shutdown checkpoint. SQLite auto-checkpoints when the
// WAL grows past ~1000 pages (~4 MB), so the only thing this catches is the
// "process killed before the next auto-checkpoint" case — small but worth a
// few lines. Registered once per process; subsequent module reloads (Next.js
// dev) re-install the handler, so we tag it on globalThis to dedupe.
const SHUTDOWN_FLAG = Symbol.for('finch.db.shutdownRegistered');
function registerShutdownCheckpoint(): void {
  const g = globalThis as Record<symbol, unknown>;
  if (g[SHUTDOWN_FLAG]) return;
  g[SHUTDOWN_FLAG] = true;
  const onExit = () => {
    void closeLiveDb();
  };
  process.once('SIGTERM', onExit);
  process.once('SIGINT', onExit);
  process.once('beforeExit', onExit);
}
registerShutdownCheckpoint();

/** Close the live connection (best-effort checkpoint first) and forget the
 *  cached promise. Used by import/restore before file-swapping, and by the
 *  shutdown hook above. */
async function closeLiveDb(): Promise<void> {
  if (!_db) return;
  const cached = _db;
  _db = null;
  try {
    const d = await cached;
    try {
      d.driver.exec('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch {
      /* a busy/partial checkpoint is harmless; the open() path will recover */
    }
    d.driver.close();
  } catch {
    /* opening failed earlier — nothing live to close */
  }
}

// Process-local mutex around writes + imports so a mutation can't interleave
// with a file swap. Single-process by design; multi-worker is out of scope.
let _writeChain: Promise<unknown> = Promise.resolve();
function serialize<T>(fn: () => Promise<T>): Promise<T> {
  const next = _writeChain.then(fn, fn);
  _writeChain = next.catch(() => {});
  return next;
}

export interface ImportValidation {
  ok: boolean;
  reason?: string;
  metadata?: import('./queries/metadata').DbMetadata;
}

/**
 * Validate a candidate DB file in isolation (no swap). Returns ok + metadata
 * when the file passes every check, otherwise ok=false with a human-readable
 * reason. Checks, in order:
 *   - SQLite magic header
 *   - db_metadata.app_name = 'finch'
 *   - schema_version <= SCHEMA_VERSION (older is fine; newer rejects)
 *   - canonical tables exist
 *   - PRAGMA foreign_key_check passes
 *   - recorded checksum matches a freshly-computed one (catches tampering /
 *     truncation; only when a checksum was stamped)
 *
 * Implementation: writes the bytes to a tmp file (better-sqlite3 opens by
 * path, not by buffer) and opens it with the same driver the live DB uses.
 */
export async function validateImportBytes(bytes: Uint8Array): Promise<ImportValidation> {
  const header = Buffer.from(bytes.subarray(0, 15)).toString('latin1');
  if (bytes.length < 16 || header !== 'SQLite format 3' || bytes[15] !== 0) {
    return { ok: false, reason: "This doesn't look like a SQLite file." };
  }
  const probeFile = path.join(os.tmpdir(), `finch-probe-${Date.now()}-${Math.random().toString(36).slice(2)}.sqlite3`);
  await fs.writeFile(probeFile, Buffer.from(bytes));
  const probe = await openDb(probeFile);
  try {
    applyPragmaBootstrap(probe);
    const exec = execFor(probe);

    // applySchema is a no-op on tables that already exist; this lets us read
    // db_metadata even on pre-bootstrap files so the validator can still
    // produce a useful error.
    await applySchema(exec);

    const { readMetadata } = await import('./queries/metadata');
    let meta = await readMetadata(exec);
    if (!meta) {
      // Pre-bootstrap file: run migrate to populate metadata, then re-read.
      await migrate(exec, { fresh: false });
      meta = await readMetadata(exec);
    }
    if (!meta) return { ok: false, reason: 'Could not read database metadata.' };
    if (meta.appName !== 'finch') {
      return { ok: false, reason: "This doesn't look like a Finch export." };
    }
    const { SCHEMA_VERSION } = await import('./schema');
    if (meta.schemaVersion > SCHEMA_VERSION) {
      return { ok: false, reason: `This backup is from a newer Finch (schema ${meta.schemaVersion}).` };
    }

    const requiredTables = ['ledgers', 'accounts', 'categories', 'entries', 'postings'];
    for (const t of requiredTables) {
      const info = await exec(`PRAGMA table_info(${t})`);
      if (info.length === 0) return { ok: false, reason: `Required table missing: ${t}` };
    }

    const fkRows = await exec('PRAGMA foreign_key_check');
    if (fkRows.length > 0) return { ok: false, reason: 'Foreign-key check failed after migration.' };

    if (meta.checksum) {
      const fresh = await computeChecksum(exec);
      if (fresh !== meta.checksum) {
        return { ok: false, reason: 'Checksum mismatch — file may be corrupted or tampered with.' };
      }
    }

    return { ok: true, metadata: meta };
  } finally {
    probe.close();
    await fs.unlink(probeFile).catch(() => {});
    await removeSidecars(probeFile).catch(() => {});
  }
}

function importMaxMb(): number {
  const v = Number(process.env.FINCH_IMPORT_MAX_MB);
  return Number.isFinite(v) && v > 0 ? Math.floor(v) : 50;
}

export interface ImportResult {
  ok: true;
  metadata: import('./queries/metadata').DbMetadata;
  backupPath: string;
}

// Inner swap — assumes the caller already holds the write-chain mutex.
async function importDbBytesLocked(bytes: Uint8Array): Promise<ImportResult> {
  const cap = importMaxMb();
  if (bytes.byteLength > cap * 1024 * 1024) {
    throw new Error(`Upload too large (max ${cap} MB).`);
  }
  const v = await validateImportBytes(bytes);
  if (!v.ok) throw new Error(v.reason ?? 'Invalid file');

  const backup = await autoBackup({ force: true }); // always snapshot — even if auto-backup is off
  const { full } = dbFile();

  // Close the live connection so the OS file lock + WAL sidecars are released
  // BEFORE we touch the file. Otherwise the rename could leave the old WAL
  // paired with the new main file → corrupted next-open.
  await closeLiveDb();
  await removeSidecars(full);

  const incoming = `${full}.incoming`;
  try {
    await fs.writeFile(incoming, Buffer.from(bytes));
    await fs.rename(incoming, full);
  } catch (err) {
    await fs.unlink(incoming).catch(() => {});
    throw err;
  }
  // _db is already null from closeLiveDb; the next getServerDb() reopens.
  return { ok: true, metadata: v.metadata!, backupPath: backup.path };
}

/**
 * Atomically replace the live DB with `bytes`. autoBackup() runs first so
 * the previous state is recoverable. Validation, backup, and swap are
 * serialized via the write-chain mutex.
 */
export function importDbBytes(bytes: Uint8Array): Promise<ImportResult> {
  return serialize(() => importDbBytesLocked(bytes));
}

// Inner pack-swap — assumes the caller already holds the write-chain mutex.
// PACK_FORMAT_PLAN §5: parse + extract pack to a staging dir (validates the
// manifest + every per-file sha256), validate the extracted DB via the
// existing path, autoBackup the live DB, then atomically swap both the
// DB and the attachments folder.
async function importPackBytesLocked(bytes: Uint8Array): Promise<ImportResult> {
  const cap = importMaxMb();
  if (bytes.byteLength > cap * 1024 * 1024) {
    throw new Error(`Upload too large (max ${cap} MB).`);
  }

  const { parsePack, extractPack } = await import('./pack');

  // Validate the pack format + extract to a staging dir. extractPack
  // verifies the DB + every attachment sha256.
  const parsed = await parsePack(bytes);
  const stagingDir = path.join(
    os.tmpdir(),
    `finch-pack-import-${Date.now()}-${Math.random().toString(36).slice(2)}`,
  );
  let extracted;
  try {
    extracted = await extractPack(parsed, stagingDir);
  } catch (err) {
    await fs.rm(stagingDir, { recursive: true, force: true }).catch(() => {});
    throw err;
  }

  // Validate the EXTRACTED DB via the existing path (schema, FK, checksum).
  const dbBytes = new Uint8Array(await fs.readFile(extracted.dbPath));
  const v = await validateImportBytes(dbBytes);
  if (!v.ok) {
    await fs.rm(stagingDir, { recursive: true, force: true }).catch(() => {});
    throw new Error(v.reason ?? 'Invalid DB inside pack');
  }

  // Snapshot the live DB so the swap is recoverable. (Attachments aren't
  // backed up here — see the rotation below.)
  const backup = await autoBackup({ force: true });

  const { dir, full } = dbFile();
  const liveAttachments = path.join(dir, 'attachments');

  // Close the live connection so the OS file lock + WAL sidecars are
  // released BEFORE we touch the file (same reason as importDbBytesLocked).
  await closeLiveDb();
  await removeSidecars(full);

  const ts = fsSafeTimestamp();
  const oldAttach = `${liveAttachments}.old-${ts}`;
  let attachRotated = false;
  const incoming = `${full}.incoming`;

  try {
    // 1) Stage the new DB bytes next to the live path, then rename in.
    await fs.writeFile(incoming, Buffer.from(dbBytes));
    await fs.rename(incoming, full);

    // 2) Rotate the live attachments folder aside (if any), then move the
    //    extracted one into place. extractPack always creates the
    //    attachments dir even when empty, so the rename is uniform.
    if (existsSync(liveAttachments)) {
      await fs.rename(liveAttachments, oldAttach);
      attachRotated = true;
    }
    await fs.rename(extracted.attachmentsDir, liveAttachments);
  } catch (err) {
    // Best-effort rollback. The DB is also recoverable via the autoBackup
    // we took at the top of the function.
    await fs.unlink(incoming).catch(() => {});
    if (attachRotated) {
      await fs.rm(liveAttachments, { recursive: true, force: true }).catch(() => {});
      await fs.rename(oldAttach, liveAttachments).catch(() => {});
    }
    await fs.rm(stagingDir, { recursive: true, force: true }).catch(() => {});
    throw err;
  }

  // Successful swap — drop the rotated attachments folder. (Plan §5
  // open question #3: "Keep N rotations or one? — one rotation only
  // for v1, disk hygiene over fine-grained history.")
  if (attachRotated) {
    await fs.rm(oldAttach, { recursive: true, force: true }).catch(() => {});
  }
  await fs.rm(stagingDir, { recursive: true, force: true }).catch(() => {});

  return { ok: true, metadata: v.metadata!, backupPath: backup.path };
}

/** Public entry point for `.finch` pack imports. Mirrors `importDbBytes`. */
export function importPackBytes(bytes: Uint8Array): Promise<ImportResult> {
  return serialize(() => importPackBytesLocked(bytes));
}

/** Replace the live DB with the contents of a named backup file. Routes by
 *  magic bytes — `.finch.bak` (zip) goes through importPackBytesLocked
 *  (restores DB + attachments); legacy `.sqlite3.bak` (bare DB) goes through
 *  importDbBytesLocked. Files older than this PR remain restorable. */
export function restoreBackup(name: string): Promise<ImportResult> {
  return serialize(async () => {
    const all = await listBackups();
    const entry = all.find((b) => b.name === name);
    if (!entry) throw new Error('Backup not found');
    const bytes = new Uint8Array(await fs.readFile(entry.path));
    const { detectFileKind } = await import('./pack');
    const kind = detectFileKind(bytes.subarray(0, 16));
    if (kind === 'zip') return importPackBytesLocked(bytes);
    if (kind === 'sqlite') return importDbBytesLocked(bytes);
    throw new Error('Unrecognised backup format');
  });
}

const todayUtc = () => new Date().toISOString().slice(0, 10);

/** Read the full app state from the server database. Catches up any due
 *  budget rollovers (idempotent — no-op when no period boundary has passed
 *  since the last call) before projecting. */
export async function readState(): Promise<ProjectedState> {
  return serialize(async () => {
    const db = await getServerDb();
    await rollBudgetsIfDue(db.exec, todayUtc());
    return projectState(db.exec);
  });
}

/** Run a write against the server database, return new state. The write is
 *  wrapped in a BEGIN/COMMIT pair so a partial mutation rolls back on throw —
 *  WAL handles durability on COMMIT via the synchronous=NORMAL bootstrap. */
export function withWrite(fn: (exec: Exec) => Promise<void>): Promise<ProjectedState> {
  return serialize(async () => {
    const db = await getServerDb();
    await db.exec('BEGIN');
    try {
      await fn(db.exec);
      await rollBudgetsIfDue(db.exec, todayUtc());
      await bumpUpdated(db.exec);
      await db.exec('COMMIT');
    } catch (err) {
      await db.exec('ROLLBACK').catch(() => {});
      throw err;
    }
    return projectState(db.exec);
  });
}

// Auto-backup configuration. Backups are siblings of the live DB file with
// timestamped names; retention keeps the most recent N.
//
// Format: `.finch.bak` packs (DB + receipts + manifest) going forward;
// legacy `.sqlite3.bak` bare-DB backups are still readable on restore for
// users with on-disk history from before this change.
// Frequency + retention are read from app_state via `readBackupConfig`
// (env vars are fallback defaults — see `lib/db/state.ts`).
const BACKUP_NEW_SUFFIX = '.finch.bak';
const BACKUP_LEGACY_SUFFIX = '.sqlite3.bak';
const BACKUP_PREFIX = 'finch-';

function isBackupName(name: string): boolean {
  if (!name.startsWith(BACKUP_PREFIX)) return false;
  return name.endsWith(BACKUP_NEW_SUFFIX) || name.endsWith(BACKUP_LEGACY_SUFFIX);
}

function fsSafeTimestamp(d: Date = new Date()): string {
  // ISO 8601 with colons / dots swapped for filesystem-friendly chars; ends
  // in 'Z' so backups sort chronologically by filename.
  return d.toISOString().replace(/[:.]/g, '-').replace(/-(\d{3})Z$/, 'Z');
}

export interface BackupEntry {
  path: string;
  name: string;
  size: number;
  createdAt: string;
}

/** List existing backup files in the data dir, newest first. Includes both
 *  the new `.finch.bak` packs and any legacy `.sqlite3.bak` bare-DB backups
 *  still on disk. */
export async function listBackups(): Promise<BackupEntry[]> {
  const { dir } = dbFile();
  let entries: string[];
  try {
    entries = await fs.readdir(dir);
  } catch {
    return [];
  }
  const backups = entries.filter(isBackupName);
  const out: BackupEntry[] = [];
  for (const name of backups) {
    const full = path.join(dir, name);
    try {
      const st = await fs.stat(full);
      out.push({ path: full, name, size: st.size, createdAt: st.mtime.toISOString() });
    } catch {
      // race: file vanished between readdir and stat — skip
    }
  }
  out.sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
  return out;
}

async function pruneBackups(keep: number): Promise<void> {
  const all = await listBackups();
  if (all.length <= keep) return;
  for (const old of all.slice(keep)) {
    await fs.unlink(old.path).catch(() => {});
  }
}

/**
 * Snapshot the live server DB to a timestamped sibling:
 *   <FINCH_DB_DIR>/finch-YYYY-MM-DDTHH-MM-SSZ.finch.bak
 *
 * Format is a `.finch` pack (DB + receipts + manifest, PACK_FORMAT_PLAN §3)
 * so restoring brings receipts back too — not just the database. Frequency
 * + retention come from app_state (`readBackupConfig`), env vars are
 * fallback defaults.
 *
 * Gates (highest to lowest priority):
 *   - `opts.force === true` — write a backup unconditionally, bypassing
 *     both throttle and the "off" setting. Used by import-time safety
 *     snapshots and by the user-pressed "Backup now" button.
 *   - frequencyMs === -1 — auto-backup is off; return without writing.
 *     `created: false` in the result.
 *   - throttle: if the newest existing backup is younger than frequencyMs,
 *     return its path with `created: false`.
 *   - else: write a fresh pack; prune oldest beyond retention.
 *
 * Result.path is the file path that should be considered "the current
 * backup," whether we wrote it just now or not. result.created is true
 * iff a new file was just written.
 */
export async function autoBackup(opts?: { force?: boolean }): Promise<{ path: string; created: boolean }> {
  const db = await getServerDb();
  const cfg = await readBackupConfig(db.exec);
  const forced = opts?.force === true;

  if (!forced && cfg.frequencyMs < 0) {
    // Off — return the most recent existing backup (if any), or an empty
    // marker the caller can detect via `created: false`.
    const existing = await listBackups();
    return { path: existing[0]?.path ?? '', created: false };
  }

  const existing = await listBackups();
  if (!forced && existing.length > 0 && cfg.frequencyMs > 0) {
    const newest = existing[0];
    const ageMs = Date.now() - new Date(newest.createdAt).getTime();
    if (ageMs < cfg.frequencyMs) return { path: newest.path, created: false };
  }

  const { dir } = dbFile();
  await fs.mkdir(dir, { recursive: true });
  const target = path.join(dir, `${BACKUP_PREFIX}${fsSafeTimestamp()}${BACKUP_NEW_SUFFIX}`);
  await fs.unlink(target).catch(() => {});

  // Build a .finch pack carrying the DB + every attachment + a manifest.
  // exportPackBytes() handles VACUUM INTO + the metadata stamp + the
  // attachment scan from the cloned DB (consistent snapshot).
  const { bytes } = await exportPackBytes();
  await fs.writeFile(target, Buffer.from(bytes));

  await pruneBackups(cfg.retention);
  return { path: target, created: true };
}

function includeHostname(): boolean {
  // Opt-out switch — set FINCH_EXPORT_INCLUDE_HOST=0 to omit hostname from
  // exported files (privacy in shared contexts).
  return process.env.FINCH_EXPORT_INCLUDE_HOST !== '0';
}

/**
 * Export a copy of the DB with provenance stamped into db_metadata
 * (exported_at, exported_from, row_counts, checksum). The live DB is not
 * mutated — VACUUM INTO writes a clean snapshot to a tmp file, we stamp
 * metadata on it, then read its bytes back.
 */
export async function exportDbBytes(): Promise<{ bytes: Uint8Array; filename: string }> {
  const db = await getServerDb();
  const tmp = path.join(os.tmpdir(), `finch-export-${Date.now()}-${Math.random().toString(36).slice(2)}.sqlite3`);
  db.driver.prepare('VACUUM INTO ?').run(tmp);
  try {
    const clone = await openDb(tmp);
    try {
      applyPragmaBootstrap(clone);
      const cloneExec = execFor(clone);
      const counts = await rowCounts(cloneExec);
      const checksum = await computeChecksum(cloneExec);
      await stampExport(cloneExec, {
        exportedAt: new Date().toISOString(),
        exportedFrom: includeHostname() ? os.hostname() : null,
        rowCounts: counts,
        checksum,
      });
      // Drain the WAL into the snapshot file before reading so the bytes are
      // self-contained and won't carry a stale -wal sidecar with them.
      clone.exec('PRAGMA wal_checkpoint(TRUNCATE)');
    } finally {
      clone.close();
    }
    const bytes = new Uint8Array(await fs.readFile(tmp));
    const ts = new Date().toISOString().replace(/[:.]/g, '-').replace(/Z$/, 'Z');
    return { bytes, filename: `finch-${ts}.sqlite3` };
  } finally {
    await fs.unlink(tmp).catch(() => {});
    await removeSidecars(tmp).catch(() => {});
  }
}

/**
 * Export the server DB + every receipt attachment as a single `.finch` pack
 * (PACK_FORMAT_PLAN §4). The DB snapshot uses the same VACUUM INTO + stamp
 * dance as exportDbBytes; the attachment list is read from the **clone** so
 * the pack is internally consistent (no row references a file we didn't
 * include, no included file lacks a row).
 */
export async function exportPackBytes(): Promise<{ bytes: Uint8Array; filename: string }> {
  const { listAttachmentFiles } = await import('./queries/attachments');
  const { resolveAttachmentPath } = await import('./paths');
  const { buildPack } = await import('./pack');
  const { SCHEMA_VERSION } = await import('./schema');

  const db = await getServerDb();
  const tmp = path.join(os.tmpdir(), `finch-export-${Date.now()}-${Math.random().toString(36).slice(2)}.sqlite3`);
  db.driver.prepare('VACUUM INTO ?').run(tmp);
  try {
    let attachmentRows: { id: string; relPath: string }[] = [];
    let rowCountsOut: Record<string, number> = {};

    const clone = await openDb(tmp);
    try {
      applyPragmaBootstrap(clone);
      const cloneExec = execFor(clone);
      rowCountsOut = await rowCounts(cloneExec);
      const checksum = await computeChecksum(cloneExec);
      await stampExport(cloneExec, {
        exportedAt: new Date().toISOString(),
        exportedFrom: includeHostname() ? os.hostname() : null,
        rowCounts: rowCountsOut,
        checksum,
      });
      // Pull attachment pointers from the clone so the pack is consistent
      // with the DB snapshot it ships with.
      const files = await listAttachmentFiles(cloneExec);
      attachmentRows = files.map((f) => ({ id: f.id, relPath: f.relPath }));
      clone.exec('PRAGMA wal_checkpoint(TRUNCATE)');
    } finally {
      clone.close();
    }
    const dbBytes = new Uint8Array(await fs.readFile(tmp));

    // Resolve each attachment to its absolute disk path under FINCH_DB_DIR.
    // resolveAttachmentPath refuses anything that escapes the attachments
    // root, so a malformed rel_path can't redirect the pack to read elsewhere.
    const attachmentFiles: { id: string; relPath: string; absPath: string }[] = [];
    for (const att of attachmentRows) {
      const abs = resolveAttachmentPath(att.relPath);
      if (!abs) {
        // Defensive: skip rather than throw — the row points outside the
        // attachments root, which would have to be tampering at the DB level.
        console.warn(`exportPackBytes: skipping bad rel_path ${att.relPath}`);
        continue;
      }
      // Skip rows whose file is missing on disk (rare crash window where the
      // DB outlived the file). The receiver would reject the pack on sha256
      // mismatch anyway; better to omit cleanly.
      try {
        await fs.access(abs);
      } catch {
        console.warn(`exportPackBytes: skipping missing file ${att.relPath}`);
        continue;
      }
      attachmentFiles.push({ id: att.id, relPath: att.relPath, absPath: abs });
    }

    const appVersion = await readAppVersion();
    const built = await buildPack({
      dbBytes,
      attachmentFiles,
      meta: {
        appVersion,
        schemaVersion: SCHEMA_VERSION,
        exportedAt: new Date().toISOString(),
        exportedFrom: includeHostname()
          ? { device: 'web', device_name: os.hostname() }
          : { device: 'web' },
        rowCounts: rowCountsOut,
      },
    });

    const ts = new Date().toISOString().replace(/[:.]/g, '-').replace(/Z$/, 'Z');
    return { bytes: built.bytes, filename: `finch-${ts}.finch` };
  } finally {
    await fs.unlink(tmp).catch(() => {});
    await removeSidecars(tmp).catch(() => {});
  }
}

async function readAppVersion(): Promise<string> {
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const pkg = require('@/package.json') as { version?: string };
    return String(pkg.version ?? '0.0.0');
  } catch {
    return '0.0.0';
  }
}
