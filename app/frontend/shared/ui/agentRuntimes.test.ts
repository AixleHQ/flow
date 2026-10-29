import { describe, expect, it } from 'vitest';

import registry from '../../../../config/agent_runtimes.json';

import {
  AGENT_RUNTIMES,
  AGENT_TYPES,
  agentLabel,
  reasoningEffortLevels,
  reasoningEffortUnavailableReason,
} from './agentRuntimes';

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

describe('reasoningEffortLevels', () => {
  it("offers a runtime's levels for its default model", () => {
    expect(reasoningEffortLevels('claude_code', null)).toEqual(['low', 'medium', 'high', 'xhigh', 'max']);
    expect(reasoningEffortLevels('gemini_cli', null)).toEqual(['low', 'high']);
  });

  it('lets a model rule replace them, first match wins', () => {
    expect(reasoningEffortLevels('kiro_cli', 'claude-sonnet-4.6')).toEqual(['low', 'medium', 'high', 'max']);
    expect(reasoningEffortLevels('kiro_cli', 'auto')).toEqual([]);
    expect(reasoningEffortLevels('codex', 'gpt-6-sol')).toContain('ultra');
    expect(reasoningEffortLevels('gemini_cli', 'gemini-2.5-pro')).toEqual([]);
  });

  it('offers nothing without a runtime, or without a model where the runtime needs one', () => {
    expect(reasoningEffortLevels(null)).toEqual([]);
    expect(reasoningEffortLevels('cursor_cli', null)).toEqual([]);
    expect(reasoningEffortLevels('cursor_cli', 'claude-opus-4-8')).toEqual(['low', 'medium', 'high']);
  });

  it('says why a runtime offers no level', () => {
    expect(reasoningEffortUnavailableReason('claude_code', null)).toBeNull();
    expect(reasoningEffortUnavailableReason('cursor_cli', null)).toBe(
      'Cursor CLI sets a reasoning effort only on a model you choose.',
    );
    expect(reasoningEffortUnavailableReason('kiro_cli', 'auto')).toBe('Kiro CLI has no reasoning-effort setting for auto.');
  });
});
