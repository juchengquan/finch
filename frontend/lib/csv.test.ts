import { test, expect } from 'bun:test';
import { toCsv } from '@/lib/csv';

test('toCsv writes a header + CRLF rows', () => {
  const out = toCsv(
    [{ a: '1', b: 'x' }, { a: '2', b: 'y' }],
    [{ key: 'a', label: 'A' }, { key: 'b', label: 'B' }],
  );
  expect(out).toBe('A,B\r\n1,x\r\n2,y\r\n');
});

test('toCsv escapes commas, quotes and newlines; blanks null/undefined', () => {
  const out = toCsv(
    [{ name: 'Doe, John', note: 'say "hi"', extra: 'line1\nline2', missing: null }],
    [
      { key: 'name', label: 'Name' },
      { key: 'note', label: 'Note' },
      { key: 'extra', label: 'Extra' },
      { key: 'missing', label: 'Missing' },
    ],
  );
  expect(out).toBe('Name,Note,Extra,Missing\r\n"Doe, John","say ""hi""","line1\nline2",\r\n');
});
