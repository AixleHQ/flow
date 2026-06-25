import { describe, expect, it } from 'vitest';

import { formatDate, parseDate } from './formatDate';

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
