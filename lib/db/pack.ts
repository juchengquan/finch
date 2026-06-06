// `.finch` pack format — build + parse + extract. PACK_FORMAT_PLAN §2-§5.
//
// A `.finch` pack is a ZIP container carrying:
//   - manifest.json    (pack metadata + per-file integrity hashes)
//   - finch.sqlite3    (VACUUM INTO'd snapshot of the live DB)
//   - attachments/<transaction_id>/<attachment_id>.<ext>  (the receipt files)
//
// This module is the format primitive. It knows nothing about the live DB or
// the HTTP route; the export/import endpoints feed it inputs and consume its
// outputs. Pure-ish: the only side effects are reading attachment files
// during build and writing extracted files during extract.

import JSZip from 'jszip';
import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';

/** Pack format version. Bumped only on incompatible format changes. */
export const PACK_FORMAT_VERSION = '1';

/** Reserved entry path for the DB inside the pack. */
export const PACK_DB_FILENAME = 'finch.sqlite3';

/** Reserved entry path for the manifest inside the pack. */
export const PACK_MANIFEST_FILENAME = 'manifest.json';

/** Prefix every attachment entry MUST live under. Path-traversal guard. */
export const PACK_ATTACHMENTS_PREFIX = 'attachments/';

// ---------------------------------------------------------------------------
// Manifest schema
// ---------------------------------------------------------------------------

export interface ManifestAttachment {
  id: string;
  /** Entry path inside the zip; mirrored on disk under dbDir on extract.
   *  Always forward-slashed (`path.posix`) for cross-platform interop. */
  rel_path: string;
  byte_size: number;
  sha256: string;
}

export interface PackManifest {
  pack_format_version: string;
  app_name: string;
  app_version: string;
  schema_version: string;
  exported_at: string;
  exported_from?: {
    device: 'web' | 'ios' | 'macos';
    device_id?: string;
    device_name?: string;
  };
  db: {
    filename: string;
    byte_size: number;
    sha256: string;
    row_counts: Record<string, number>;
  };
  attachments: {
    count: number;
    total_bytes: number;
    items: ManifestAttachment[];
  };
}

// ---------------------------------------------------------------------------
// Build
// ---------------------------------------------------------------------------

export interface BuildPackInput {
  /** The SQLite snapshot bytes (typically from VACUUM INTO -> readFile). */
  dbBytes: Uint8Array;
  /** Each attachment that should travel inside the pack: the row id, its
   *  zip-internal rel_path, and the absolute disk path to read bytes from. */
  attachmentFiles: Array<{ id: string; relPath: string; absPath: string }>;
  /** Manifest metadata (everything except `db` + `attachments`, which are
   *  computed from inputs). */
  meta: {
    appVersion: string;
    schemaVersion: string;
    exportedAt: string;
    exportedFrom?: PackManifest['exported_from'];
    rowCounts: Record<string, number>;
  };
}

export interface BuiltPack {
  bytes: Uint8Array;
  manifest: PackManifest;
}

/** Compute the SHA-256 of a byte slice as a lowercase hex string. */
export function sha256Hex(bytes: Uint8Array): string {
  return createHash('sha256').update(bytes).digest('hex');
}

/** Build a `.finch` pack as a single in-memory Uint8Array. */
export async function buildPack(input: BuildPackInput): Promise<BuiltPack> {
  const zip = new JSZip();
  const dbSha = sha256Hex(input.dbBytes);

  // DB compresses well (lots of repeated structure); use DEFLATE.
  zip.file(PACK_DB_FILENAME, input.dbBytes, { compression: 'DEFLATE' });

  // Attachments: read each, compute sha256, STORE (no compression — receipts
  // are already JPEG / PDF). Sort by rel_path so the pack is deterministic.
  const sorted = [...input.attachmentFiles].sort((a, b) =>
    a.relPath.localeCompare(b.relPath),
  );
  const items: ManifestAttachment[] = [];
  let totalBytes = 0;
  for (const att of sorted) {
    if (!att.relPath.startsWith(PACK_ATTACHMENTS_PREFIX)) {
      throw new Error(`Attachment relPath outside ${PACK_ATTACHMENTS_PREFIX}: ${att.relPath}`);
    }
    const bytes = new Uint8Array(await readFile(att.absPath));
    const sha = sha256Hex(bytes);
    zip.file(att.relPath, bytes, { compression: 'STORE' });
    items.push({ id: att.id, rel_path: att.relPath, byte_size: bytes.length, sha256: sha });
    totalBytes += bytes.length;
  }

  const manifest: PackManifest = {
    pack_format_version: PACK_FORMAT_VERSION,
    app_name: 'finch',
    app_version: input.meta.appVersion,
    schema_version: input.meta.schemaVersion,
    exported_at: input.meta.exportedAt,
    exported_from: input.meta.exportedFrom,
    db: {
      filename: PACK_DB_FILENAME,
      byte_size: input.dbBytes.length,
      sha256: dbSha,
      row_counts: input.meta.rowCounts,
    },
    attachments: {
      count: items.length,
      total_bytes: totalBytes,
      items,
    },
  };

  // Manifest LAST in zip order — it depends on the other entries' hashes.
  // (JSZip writes entries in insertion order.)
  zip.file(PACK_MANIFEST_FILENAME, JSON.stringify(manifest, null, 2), {
    compression: 'DEFLATE',
  });

  const bytes = await zip.generateAsync({
    type: 'uint8array',
    compression: 'DEFLATE',
    compressionOptions: { level: 6 },
  });

  return { bytes, manifest };
}

// ---------------------------------------------------------------------------
// Parse + extract
// ---------------------------------------------------------------------------

export class PackError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PackError';
  }
}

export interface ParsedPack {
  manifest: PackManifest;
  /** Underlying handle, retained for `extractPack`. */
  zip: JSZip;
}

/** Open a pack and read + sanity-check the manifest. Does NOT validate
 *  per-file sha256s — that's `extractPack`'s job (it needs to decompress
 *  each entry anyway). */
export async function parsePack(zipBytes: Uint8Array): Promise<ParsedPack> {
  let zip: JSZip;
  try {
    zip = await JSZip.loadAsync(zipBytes);
  } catch (err) {
    throw new PackError(`Not a valid zip: ${(err as Error).message}`);
  }

  const manifestEntry = zip.file(PACK_MANIFEST_FILENAME);
  if (!manifestEntry) throw new PackError('Missing manifest.json');
  let manifest: PackManifest;
  try {
    const text = await manifestEntry.async('string');
    manifest = JSON.parse(text) as PackManifest;
  } catch (err) {
    throw new PackError(`manifest.json is not valid JSON: ${(err as Error).message}`);
  }

  // Schema sanity checks. The receiver refuses a future format version it
  // doesn't understand — the contract between writer and reader.
  if (typeof manifest.pack_format_version !== 'string') {
    throw new PackError('manifest.pack_format_version missing');
  }
  if (manifest.pack_format_version !== PACK_FORMAT_VERSION) {
    throw new PackError(
      `Unsupported pack format version ${manifest.pack_format_version} ` +
        `(this app understands ${PACK_FORMAT_VERSION})`,
    );
  }
  if (manifest.app_name !== 'finch') {
    throw new PackError(`Not a Finch pack (app_name=${manifest.app_name})`);
  }
  if (!manifest.db || typeof manifest.db.sha256 !== 'string') {
    throw new PackError('manifest.db.sha256 missing');
  }
  if (!manifest.attachments || !Array.isArray(manifest.attachments.items)) {
    throw new PackError('manifest.attachments.items missing');
  }
  if (!zip.file(PACK_DB_FILENAME)) {
    throw new PackError(`Pack missing ${PACK_DB_FILENAME}`);
  }

  // Path-traversal guard: every attachment entry MUST start with the
  // attachments/ prefix and contain no '..' segments.
  for (const item of manifest.attachments.items) {
    if (typeof item.rel_path !== 'string' || !item.rel_path.startsWith(PACK_ATTACHMENTS_PREFIX)) {
      throw new PackError(`Bad attachment rel_path: ${item.rel_path}`);
    }
    if (item.rel_path.includes('..')) {
      throw new PackError(`Attachment rel_path contains ..: ${item.rel_path}`);
    }
    if (typeof item.sha256 !== 'string' || item.sha256.length !== 64) {
      throw new PackError(`Bad attachment sha256: ${item.id}`);
    }
    if (typeof item.byte_size !== 'number' || item.byte_size < 0) {
      throw new PackError(`Bad attachment byte_size: ${item.id}`);
    }
    if (!zip.file(item.rel_path)) {
      throw new PackError(`Pack manifest references missing entry: ${item.rel_path}`);
    }
  }

  return { manifest, zip };
}

export interface ExtractedPack {
  /** Where the DB was written inside destDir. */
  dbPath: string;
  /** Where the attachments folder was written inside destDir. */
  attachmentsDir: string;
  /** The validated manifest. */
  manifest: PackManifest;
}

/** Extract a parsed pack to destDir, validating the DB sha256 + every
 *  attachment sha256 along the way. Throws (after best-effort cleanup) on
 *  any mismatch — the caller can swap into place only on success. */
export async function extractPack(parsed: ParsedPack, destDir: string): Promise<ExtractedPack> {
  await mkdir(destDir, { recursive: true });

  // DB
  const dbBytes = await mustRead(parsed.zip, PACK_DB_FILENAME);
  const dbSha = sha256Hex(dbBytes);
  if (dbSha !== parsed.manifest.db.sha256) {
    throw new PackError(`DB sha256 mismatch: expected ${parsed.manifest.db.sha256}, got ${dbSha}`);
  }
  if (dbBytes.length !== parsed.manifest.db.byte_size) {
    throw new PackError(
      `DB byte_size mismatch: expected ${parsed.manifest.db.byte_size}, got ${dbBytes.length}`,
    );
  }
  const dbPath = path.join(destDir, PACK_DB_FILENAME);
  await writeFile(dbPath, dbBytes);

  // Attachments
  const attachmentsRoot = path.join(destDir, 'attachments');
  await mkdir(attachmentsRoot, { recursive: true });
  for (const item of parsed.manifest.attachments.items) {
    const bytes = await mustRead(parsed.zip, item.rel_path);
    const sha = sha256Hex(bytes);
    if (sha !== item.sha256) {
      throw new PackError(`Attachment ${item.id} sha256 mismatch`);
    }
    if (bytes.length !== item.byte_size) {
      throw new PackError(
        `Attachment ${item.id} byte_size mismatch: expected ${item.byte_size}, got ${bytes.length}`,
      );
    }
    // rel_path inside the manifest is forward-slashed; join with destDir.
    const absPath = path.join(destDir, ...item.rel_path.split('/'));
    // Defense-in-depth: the result MUST live under destDir.
    const resolved = path.resolve(absPath);
    if (!resolved.startsWith(path.resolve(destDir) + path.sep)) {
      throw new PackError(`Attachment escapes destDir: ${item.rel_path}`);
    }
    await mkdir(path.dirname(absPath), { recursive: true });
    await writeFile(absPath, bytes);
  }

  return { dbPath, attachmentsDir: attachmentsRoot, manifest: parsed.manifest };
}

async function mustRead(zip: JSZip, name: string): Promise<Uint8Array> {
  const entry = zip.file(name);
  if (!entry) throw new PackError(`Missing entry: ${name}`);
  return new Uint8Array(await entry.async('uint8array'));
}

/** Recognise the first 4 bytes of a stream as either a ZIP local-file header
 *  (`PK\x03\x04`) or a SQLite file header. Used by the import route to
 *  route raw `.db` vs `.finch` pack bodies. */
export function detectFileKind(head: Uint8Array): 'zip' | 'sqlite' | 'unknown' {
  if (head.length >= 4 && head[0] === 0x50 && head[1] === 0x4b && head[2] === 0x03 && head[3] === 0x04) {
    return 'zip';
  }
  if (head.length >= 16) {
    const magic = Buffer.from(head.subarray(0, 15)).toString('latin1');
    if (magic === 'SQLite format 3' && head[15] === 0) return 'sqlite';
  }
  return 'unknown';
}
