// Today as a local 'YYYY-MM-DD', so "due" and "today" match the user's calendar
// day. `new Date().toISOString()` is UTC: before 08:00 in UTC+8 it is yesterday.
export function localToday(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** Now as a local `datetime-local` value (YYYY-MM-DDTHH:mm). */
export function localDateTime(): string {
  const d = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${localToday()}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
