// Browser-only persistence sinks for the exported SQLite `.db` bytes.
// localStorage stays the primary store (see lib/store.ts); these are mirrors:
//  - OPFS: an origin-private `finch.db` written automatically on every change.
//  - File System Access: an optional real file the user picks once, then we
//    auto-write to it on every change for the session.

const DB_NAME = 'finch.db';

// `showSaveFilePicker` is not yet in lib.dom; declare the slice we use.
declare global {
  interface Window {
    showSaveFilePicker?: (options?: {
      suggestedName?: string;
      types?: { description?: string; accept: Record<string, string[]> }[];
    }) => Promise<FileSystemFileHandle>;
  }
}

export function opfsSupported(): boolean {
  return (
    typeof navigator !== 'undefined' &&
    !!navigator.storage &&
    typeof navigator.storage.getDirectory === 'function'
  );
}

export function fsAccessSupported(): boolean {
  return typeof window !== 'undefined' && typeof window.showSaveFilePicker === 'function';
}

export async function writeOpfs(bytes: Uint8Array): Promise<void> {
  const dir = await navigator.storage.getDirectory();
  const fh = await dir.getFileHandle(DB_NAME, { create: true });
  const w = await fh.createWritable();
  await w.write(bytes as BufferSource);
  await w.close();
}

export async function readOpfs(): Promise<Uint8Array | null> {
  try {
    const dir = await navigator.storage.getDirectory();
    const fh = await dir.getFileHandle(DB_NAME);
    const file = await fh.getFile();
    if (file.size === 0) return null;
    return new Uint8Array(await file.arrayBuffer());
  } catch {
    // File-not-found (the common first-run case) and any access error.
    return null;
  }
}

export async function pickBackupFile(): Promise<FileSystemFileHandle> {
  if (!window.showSaveFilePicker) throw new Error('File System Access API unavailable');
  return window.showSaveFilePicker({
    suggestedName: DB_NAME,
    types: [{ description: 'SQLite database', accept: { 'application/x-sqlite3': ['.db', '.sqlite'] } }],
  });
}

export async function writeHandle(handle: FileSystemFileHandle, bytes: Uint8Array): Promise<void> {
  const w = await handle.createWritable();
  await w.write(bytes as BufferSource);
  await w.close();
}

export function downloadBytes(bytes: Uint8Array, filename = DB_NAME): void {
  const blob = new Blob([bytes as BufferSource], { type: 'application/x-sqlite3' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

export async function readFileBytes(file: Blob): Promise<Uint8Array> {
  return new Uint8Array(await file.arrayBuffer());
}
