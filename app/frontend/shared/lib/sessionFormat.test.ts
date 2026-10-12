import { describe, expect, it } from 'vitest';

import { formatDuration } from './sessionFormat';

const now = new Date('2026-06-23T10:30:00Z').getTime();

describe('formatDuration', () => {
  it('measures from start to finish', () => {
    expect(formatDuration('2026-06-23T10:10:00Z', '2026-06-23T10:15:00Z', 'finished', now)).toBe('5m 0s');
  });

  it('shows nothing for a record that has not started yet', () => {
    expect(formatDuration(null, null, 'queued', now)).toBe('—');
  });

  it('keeps counting a run that already worked while a later step waits in the queue', () => {
    expect(formatDuration('2026-06-23T10:00:00Z', null, 'queued', now)).toBe('30m 0s');
  });

  it('does not count to now for a record that ended without a finish time', () => {
    expect(formatDuration('2026-06-23T10:00:00Z', null, 'cancelled', now)).toBe('—');
  });
});
