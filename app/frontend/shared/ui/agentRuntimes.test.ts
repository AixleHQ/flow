import { describe, expect, it } from 'vitest';

import registry from '../../../../config/agent_runtimes.json';

import { AGENT_RUNTIMES, AGENT_TYPES, agentLabel } from './agentRuntimes';

describe('AGENT_RUNTIMES', () => {
  it('lists the registry runtimes in the registry order', () => {
    expect(AGENT_TYPES).toEqual(registry.runtimes.map((runtime) => runtime.id));
  });

  it('gives every registry runtime a badge color', () => {
    const uncolored = AGENT_TYPES.filter((type) => !AGENT_RUNTIMES[type].mantineColor);

    expect(uncolored).toEqual([]);
  });

  it('labels a runtime from the registry and falls back to the raw id', () => {
    expect(agentLabel('codex')).toBe('Codex');
    expect(agentLabel('retired_cli')).toBe('retired_cli');
  });
});
