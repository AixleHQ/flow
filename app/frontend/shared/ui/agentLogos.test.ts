import { describe, expect, it } from 'vitest';

import { agentLogoSrc } from './agentLogos';
import { AGENT_TYPES } from './agentRuntimes';

describe('agentLogoSrc', () => {
  it('gives every registry runtime its own logo', () => {
    const sources = AGENT_TYPES.map((type) => agentLogoSrc(type));

    expect(sources.filter((src) => !src)).toEqual([]);
    expect(new Set(sources).size).toBe(AGENT_TYPES.length);
  });

  it('has no logo for an agent type outside the registry', () => {
    expect(agentLogoSrc('retired_cli')).toBeUndefined();
    expect(agentLogoSrc(null)).toBeUndefined();
  });
});
