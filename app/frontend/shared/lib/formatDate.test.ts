import { describe, expect, it } from 'vitest';

import { formatDate, formatExpiry, parseDate } from './formatDate';

describe('parseDate', () => {
  it('parses ISO8601', () => {
    expect(parseDate('2026-02-28T13:41:06Z')?.getUTCFullYear()).toBe(2026);
  });

  it('parses Ruby default format "YYYY-MM-DD HH:MM:SS UTC"', () => {
    const d = parseDate('2026-02-28 13:41:06 UTC');
    expect(d).not.toBeNull();
    expect(d?.getUTCFullYear()).toBe(2026);
  });

  it('returns null for null/undefined/garbage', () => {
    expect(parseDate(null)).toBeNull();
    expect(parseDate(undefined)).toBeNull();
    expect(parseDate('nonsense')).toBeNull();
  });
});

describe('formatDate', () => {
  it('returns an em dash for null', () => {
    expect(formatDate(null)).toBe('—');
  });
});

describe('formatExpiry', () => {
  const now = new Date('2026-09-29T10:00:00Z');

  it('says how long an 8-hour token has left, so a renewal is visible the same day', () => {
    expect(formatExpiry('2026-09-29T17:00:00Z', now)).toMatch(/^in 7 h \(.+\)$/);
    expect(formatExpiry('2026-09-29T10:25:00Z', now)).toMatch(/^in 25 min \(.+\)$/);
  });

  it('says a lapsed token has expired', () => {
    expect(formatExpiry('2026-09-29T09:00:00Z', now)).toMatch(/^expired /);
  });

  it('falls back to date and time beyond a day, and an em dash for nothing', () => {
    expect(formatExpiry('2026-11-02T02:16:00Z', now)).toMatch(/2026/);
    expect(formatExpiry(null, now)).toBe('—');
  });
});
