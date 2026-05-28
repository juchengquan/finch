// Minimal RFC 4180 CSV builder. Fields containing a comma, double-quote, CR or LF
// are wrapped in double-quotes with internal quotes doubled; rows are CRLF-joined
// (Excel/Sheets friendly).

export interface CsvColumn {
  key: string;
  label: string;
}

function escapeField(value: unknown): string {
  if (value == null) return '';
  const s = String(value);
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

export function toCsv(rows: Record<string, unknown>[], columns: CsvColumn[]): string {
  const header = columns.map((c) => escapeField(c.label)).join(',');
  const body = rows.map((r) => columns.map((c) => escapeField(r[c.key])).join(','));
  return [header, ...body].join('\r\n') + '\r\n';
}
