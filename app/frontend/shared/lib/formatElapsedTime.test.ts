import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { formatElapsedTime } from './formatElapsedTime';

describe('formatElapsedTime', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-25T12:00:00Z'));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('formats the seconds bucket', () => {
    expect(formatElapsedTime('2026-06-25T11:59:30Z')).toBe('30s');
  });

  it('formats the minutes bucket', () => {
    expect(formatElapsedTime('2026-06-25T11:58:00Z')).toBe('2m 0s');
  });

  it('formats the hours bucket', () => {
    expect(formatElapsedTime('2026-06-25T09:30:00Z')).toBe('2h 30m');
  });
});
