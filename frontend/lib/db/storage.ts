// Browser helper to download a point-in-time copy of the database as a file.
// (The authoritative database is the server-side file; see lib/db/server.ts.)

export function downloadBytes(bytes: Uint8Array, filename = 'finch.sqlite3', type = 'application/x-sqlite3'): void {
  const blob = new Blob([bytes as BufferSource], { type });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
