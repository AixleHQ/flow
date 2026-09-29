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

/** e.g. "Feb 28, 2026, 14:20" — the date alone hides an 8-hour token's renewal. */
export function formatDateTimeShort(value: string | null | undefined): string {
  const d = parseDate(value);
  return d
    ? d.toLocaleString(undefined, {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '—';
}

/**
 * When a token expires, relative to `now`: "in 7 h (14:20)", "in 25 min (14:20)",
 * "expired 14:20". Beyond a day the absolute date and time read better.
 */
export function formatExpiry(value: string | null | undefined, now: Date = new Date()): string {
  const d = parseDate(value);
  if (!d) return '—';

  const time = d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
  const diffMin = Math.round((d.getTime() - now.getTime()) / 60_000);
  if (diffMin <= 0) return `expired ${Math.abs(diffMin) < 24 * 60 ? time : formatDateTimeShort(value)}`;
  if (diffMin < 60) return `in ${diffMin} min (${time})`;
  if (diffMin < 24 * 60) return `in ${Math.round(diffMin / 60)} h (${time})`;
  return formatDateTimeShort(value);
}
