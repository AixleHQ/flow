import { describe, expect, it } from 'vitest';

import { isWaitingForCluster, isWaitingForSlot, launchWaitMessage } from './launchStatus';

describe('launchWaitMessage', () => {
  it('blames the queue only when the session is actually behind others', () => {
    expect(launchWaitMessage('queued_for_slot')).toBe('Waiting for a free session slot');
    expect(isWaitingForSlot('queued_for_slot')).toBe(true);
  });

  // The bug: a granted slot coming up is still `queued`, and both screens read
  // that as a full pool.
  it('says a granted slot is starting rather than waiting for capacity', () => {
    expect(launchWaitMessage('starting')).toBe('Starting session…');
    expect(launchWaitMessage('starting', 'authentication')).toBe('Starting authentication session…');
    expect(isWaitingForSlot('starting')).toBe(false);
  });

  it('names the cluster when the cluster is what has no room', () => {
    expect(launchWaitMessage('cluster_capacity')).toBe('Waiting for cluster capacity');
    expect(launchWaitMessage('namespace_quota')).toBe('Waiting for cluster capacity');
    expect(isWaitingForCluster('namespace_quota')).toBe(true);
  });

  it('does not invent a queue for a session with no admission at all', () => {
    expect(launchWaitMessage(null)).toBe('Starting session…');
    expect(isWaitingForSlot(null)).toBe(false);
    expect(isWaitingForCluster(undefined)).toBe(false);
  });
});
