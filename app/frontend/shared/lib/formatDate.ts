/**
 * Parse a date value from the server (Ruby Time#to_json format or ISO8601)
 * and return a JS Date. Handles Ruby's default "2026-02-28 13:41:06 UTC" format
 * which new Date() cannot parse directly.
 */
export function parseDate(value: string | null | undefined): Date | null {
  if (!value) return null;
  const d = new Date(value);
  if (!isNaN(d.getTime())) return d;

  // Ruby default: "2026-02-28 13:41:06 UTC"
  const withT = value.replace(' ', 'T').replace(' UTC', 'Z');
  const fallback = new Date(withT);
  return isNaN(fallback.getTime()) ? null : fallback;
}

export function formatDateTime(value: string | null | undefined): string {
  const d = parseDate(value);
  return d ? d.toLocaleString() : '—';
}

export function formatDate(value: string | null | undefined): string {
  const d = parseDate(value);
  return d ? d.toLocaleDateString() : '—';
}

export function formatTime(value: string | null | undefined): string {
  const d = parseDate(value);
  return d ? d.toLocaleTimeString() : '—';
}

/** e.g. "Feb 28, 2026" */
export function formatDateMedium(value: string | null | undefined): string {
  const d = parseDate(value);
  return d ? d.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' }) : '—';
}
