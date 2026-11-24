import { describe, expect, it } from 'vitest';

import { sessionStatusTone, statusTone } from './StatusBadge';

describe('sessionStatusTone', () => {
  it('reads a ready session as running, the same tone as a running workflow run', () => {
    expect(sessionStatusTone('ready')).toBe('running');
    expect(sessionStatusTone('ready')).toBe(statusTone('running'));
  });

  it('keeps ready as success outside sessions', () => {
    expect(statusTone('ready')).toBe('success');
  });

  it('resolves every other session state through the shared map', () => {
    expect(sessionStatusTone('running')).toBe('running');
    expect(sessionStatusTone('queued')).toBe('info');
    expect(sessionStatusTone('finished')).toBe('success');
    expect(sessionStatusTone('failed')).toBe('danger');
    expect(sessionStatusTone(null)).toBe('neutral');
  });
});
