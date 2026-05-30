import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { getSqlite3, execFor, type OO1DB } from './sqlite';
import { applySchema, migrate } from './schema';
import { seedDatabase } from './seed';
import { projectState } from './state';
import { bumpUpdated, rowCounts, stampExport } from './queries/metadata';
import { computeChecksum } from './checksum';
import type { Exec, ProjectedState } from './repo';

// The authoritative database: a single in-memory SQLite connection held by the
// Node server for the life of the process, loaded from a file on startup and
// written back to that file after every change. The file location comes from
// env vars so it can point at persistent storage:
//   FINCH_DB_DIR   directory (default: <cwd>/.data)
//   FINCH_DB_FILE  filename  (default: finch.sqlite3)

function dbFile(): { dir: string; full: string } {
  const dir = process.env.FINCH_DB_DIR || path.join(process.cwd(), '.data');
  const file = process.env.FINCH_DB_FILE || 'finch.sqlite3';
  return { dir, full: path.join(dir, file) };
}

interface ServerDb {
  exec: Exec;
  persist: () => Promise<void>;
  file: string;
}

let _db: Promise<ServerDb> | null = null;

async function open(): Promise<ServerDb> {
  const sqlite3 = await getSqlite3();
  const { dir, full } = dbFile();
  await fs.mkdir(dir, { recursive: true });

  let bytes: Uint8Array | null = null;
  try {
    const buf = await fs.readFile(full);
    if (buf.byteLength > 0) bytes = new Uint8Array(buf);
  } catch {
    // No file yet — first run.
  }

  let db: OO1DB;
  if (bytes) {
    db = new sqlite3.oo1.DB() as unknown as OO1DB;
    const p = sqlite3.wasm.allocFromTypedArray(bytes);
    const rc = sqlite3.capi.sqlite3_deserialize(
      db.pointer!,
      'main',
      p,
      bytes.length,
      bytes.length,
      sqlite3.capi.SQLITE_DESERIALIZE_FREEONCLOSE | sqlite3.capi.SQLITE_DESERIALIZE_RESIZEABLE,
    );
    if (rc) throw new Error(`Could not open ${full} (code ${rc})`);
    await applySchema(execFor(db)); // ensure newer objects exist on older files
    await migrate(execFor(db), { fresh: false }); // apply column migrations to old files
  } else {
    db = new sqlite3.oo1.DB(':memory:') as unknown as OO1DB;
    const exec = execFor(db);
    await applySchema(exec);
    await seedDatabase(exec);
    await migrate(exec, { fresh: true }); // stamp the version on the new file
  }

  const exec = execFor(db);
  const persist = async () => {
    // Bump the metadata row's updated_at *before* serialising so the file's
    // recorded timestamp matches the bytes on disk.
    await bumpUpdated(exec);
    const out = sqlite3.capi.sqlite3_js_db_export(db as never);
    // Write atomically: temp file then rename, so a crash can't truncate the db.
    const tmp = `${full}.tmp`;
    await fs.writeFile(tmp, Buffer.from(out));
    await fs.rename(tmp, full);
  };
  await persist(); // make sure the file exists from the first boot
  return { exec, persist, file: full };
}

/** The shared server database, opened once per process. */
export function getServerDb(): Promise<ServerDb> {
  if (!_db) _db = open();
  return _db;
}

/** Test-only: drop the cached connection so the next getServerDb() reopens
 *  against (possibly-changed) FINCH_DB_DIR. Never call from app code. */
export function _resetServerDbForTests(): void {
  _db = null;
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
 */
export async function validateImportBytes(bytes: Uint8Array): Promise<ImportValidation> {
  // The SQLite header magic is the literal ASCII "SQLite format 3" followed by
  // a NUL byte. Decode the first 15 bytes as latin1 (1:1 byte→char) and check.
  const header = Buffer.from(bytes.subarray(0, 15)).toString('latin1');
  if (bytes.length < 16 || header !== 'SQLite format 3' || bytes[15] !== 0) {
    return { ok: false, reason: "This doesn't look like a SQLite file." };
  }
  const sqlite3 = await getSqlite3();
  const probe = new sqlite3.oo1.DB() as unknown as OO1DB;
  try {
    const p = sqlite3.wasm.allocFromTypedArray(bytes);
    const rc = sqlite3.capi.sqlite3_deserialize(
      probe.pointer!,
      'main',
      p,
      bytes.length,
      bytes.length,
      sqlite3.capi.SQLITE_DESERIALIZE_FREEONCLOSE | sqlite3.capi.SQLITE_DESERIALIZE_RESIZEABLE,
    );
    if (rc) return { ok: false, reason: `Could not open the file (code ${rc}).` };
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

    // Smoke-check that the canonical tables exist after migrate.
    const requiredTables = ['ledgers', 'accounts', 'categories', 'transactions'];
    for (const t of requiredTables) {
      const info = await exec(`PRAGMA table_info(${t})`);
      if (info.length === 0) return { ok: false, reason: `Required table missing: ${t}` };
    }

    // FK integrity post-migrate. PRAGMA foreign_key_check returns one row per
    // violation; an empty result is the success case.
    const fkRows = await exec('PRAGMA foreign_key_check');
    if (fkRows.length > 0) return { ok: false, reason: 'Foreign-key check failed after migration.' };

    // If the file carries a checksum, recompute and compare.
    if (meta.checksum) {
      const fresh = await computeChecksum(exec);
      if (fresh !== meta.checksum) {
        return { ok: false, reason: 'Checksum mismatch — file may be corrupted or tampered with.' };
      }
    }

    return { ok: true, metadata: meta };
  } finally {
    probe.close();
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

  const backup = await autoBackup({ minIntervalMs: 0 }); // always snapshot
  const { full } = dbFile();
  const incoming = `${full}.incoming`;
  try {
    await fs.writeFile(incoming, Buffer.from(bytes));
    await fs.rename(incoming, full);
  } catch (err) {
    await fs.unlink(incoming).catch(() => {});
    throw err;
  }
  // Drop the cached connection so the next request reopens against the new file.
  _db = null;
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

/** Replace the live DB with the contents of a named backup file. */
export function restoreBackup(name: string): Promise<ImportResult> {
  return serialize(async () => {
    const all = await listBackups();
    const entry = all.find((b) => b.name === name);
    if (!entry) throw new Error('Backup not found');
    const bytes = new Uint8Array(await fs.readFile(entry.path));
    return importDbBytesLocked(bytes);
  });
}

/** Read the full app state from the server database. */
export async function readState(): Promise<ProjectedState> {
  const { exec } = await getServerDb();
  return projectState(exec);
}

/** Run a write against the server database, persist to file, return new state.
 *  Serialised against imports so a mutation can't interleave with a file swap. */
export function withWrite(fn: (exec: Exec) => Promise<void>): Promise<ProjectedState> {
  return serialize(async () => {
    const db = await getServerDb();
    await fn(db.exec);
    await db.persist();
    return projectState(db.exec);
  });
}

// Auto-backup configuration. Backups are siblings of the live DB file with
// timestamped names; retention keeps the most recent N. Tunable via env so a
// deployment can dial up retention without a code change.
const BACKUP_SUFFIX = '.sqlite3.bak';
const BACKUP_PREFIX = 'finch-';
function backupRetention(): number {
  const v = Number(process.env.FINCH_BACKUP_KEEP);
  return Number.isFinite(v) && v > 0 ? Math.floor(v) : 14;
}
function defaultMinInterval(): number {
  const v = Number(process.env.FINCH_BACKUP_MIN_INTERVAL_MS);
  return Number.isFinite(v) && v >= 0 ? Math.floor(v) : 60 * 60 * 1000; // 1h
}

function fsSafeTimestamp(d: Date = new Date()): string {
  // ISO 8601 with colons / dots swapped for filesystem-friendly chars; ends
  // in 'Z' so backups sort chronologically by filename.
  return d.toISOString().replace(/[:.]/g, '-').replace(/-(\d{3})Z$/, 'Z');
}

export interface BackupEntry {
  /** Absolute path to the backup file. */
  path: string;
  /** Just the filename, for display. */
  name: string;
  /** Bytes on disk. */
  size: number;
  /** ISO 8601 mtime. */
  createdAt: string;
}

/** List existing backup files in the data dir, newest first. */
export async function listBackups(): Promise<BackupEntry[]> {
  const { dir } = dbFile();
  let entries: string[];
  try {
    entries = await fs.readdir(dir);
  } catch {
    return [];
  }
  const backups = entries.filter((n) => n.startsWith(BACKUP_PREFIX) && n.endsWith(BACKUP_SUFFIX));
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
 * Copy the live server DB file to a timestamped sibling in the same directory:
 *   <FINCH_DB_DIR>/finch-YYYY-MM-DDTHH-MM-SSZ.sqlite3.bak
 *
 * Throttled: if the most-recent backup is younger than `minIntervalMs`
 * (default 1h, env FINCH_BACKUP_MIN_INTERVAL_MS), this returns that path
 * instead of writing a new one — keeps the disk from filling up when called
 * from a hot path. Retention prunes the oldest backups beyond
 * `FINCH_BACKUP_KEEP` (default 14).
 */
export async function autoBackup(opts?: { minIntervalMs?: number }): Promise<{ path: string }> {
  const minInterval = opts?.minIntervalMs ?? defaultMinInterval();
  const existing = await listBackups();
  if (existing.length > 0 && minInterval > 0) {
    const newest = existing[0];
    const ageMs = Date.now() - new Date(newest.createdAt).getTime();
    if (ageMs < minInterval) return { path: newest.path };
  }
  const db = await getServerDb();
  await db.persist(); // make sure the file on disk reflects the in-memory state
  const { dir } = dbFile();
  await fs.mkdir(dir, { recursive: true });
  const target = path.join(dir, `${BACKUP_PREFIX}${fsSafeTimestamp()}${BACKUP_SUFFIX}`);
  // Write to a .tmp then rename so a crash mid-copy doesn't leave a partial file.
  const tmp = `${target}.tmp`;
  await fs.copyFile(db.file, tmp);
  await fs.rename(tmp, target);
  await pruneBackups(backupRetention());
  return { path: target };
}

function includeHostname(): boolean {
  // Opt-out switch — set FINCH_EXPORT_INCLUDE_HOST=0 to omit hostname from
  // exported files (privacy in shared contexts).
  return process.env.FINCH_EXPORT_INCLUDE_HOST !== '0';
}

/**
 * Export a copy of the DB with provenance stamped into db_metadata
 * (exported_at, exported_from, row_counts, checksum). The live DB is not
 * mutated — stamps are applied to a fresh in-memory clone built from the
 * just-persisted bytes, then re-serialised.
 */
export async function exportDbBytes(): Promise<{ bytes: Uint8Array; filename: string }> {
  const db = await getServerDb();
  await db.persist();
  const liveBytes = new Uint8Array(await fs.readFile(db.file));

  // Open a throwaway clone to stamp metadata without touching the live DB.
  const sqlite3 = await getSqlite3();
  const clone = new sqlite3.oo1.DB() as unknown as OO1DB;
  try {
    const p = sqlite3.wasm.allocFromTypedArray(liveBytes);
    const rc = sqlite3.capi.sqlite3_deserialize(
      clone.pointer!,
      'main',
      p,
      liveBytes.length,
      liveBytes.length,
      sqlite3.capi.SQLITE_DESERIALIZE_FREEONCLOSE | sqlite3.capi.SQLITE_DESERIALIZE_RESIZEABLE,
    );
    if (rc) throw new Error(`Could not clone DB for export (code ${rc})`);
    const cloneExec = execFor(clone);
    const counts = await rowCounts(cloneExec);
    const checksum = await computeChecksum(cloneExec);
    await stampExport(cloneExec, {
      exportedAt: new Date().toISOString(),
      exportedFrom: includeHostname() ? os.hostname() : null,
      rowCounts: counts,
      checksum,
    });
    const stamped = sqlite3.capi.sqlite3_js_db_export(clone as never);
    const ts = new Date().toISOString().replace(/[:.]/g, '-').replace(/Z$/, 'Z');
    return { bytes: new Uint8Array(stamped), filename: `finch-${ts}.sqlite3` };
  } finally {
    clone.close();
  }
}
