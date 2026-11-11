import { describe, expect, it } from 'vitest';

import { runOwnerLabel } from './runOwner';

describe('runOwnerLabel', () => {
  it('names the team the owner was picked from', () => {
    expect(runOwnerLabel('Planner', 'Anna')).toBe('Planner → Anna');
  });

  it('is the person alone for a run without a team', () => {
    expect(runOwnerLabel(null, 'Anna')).toBe('Anna');
  });

  it('falls back to the team, then to nothing, when the person is unknown', () => {
    expect(runOwnerLabel('Planner', null)).toBe('Planner');
    expect(runOwnerLabel(undefined, undefined)).toBeNull();
  });
});
