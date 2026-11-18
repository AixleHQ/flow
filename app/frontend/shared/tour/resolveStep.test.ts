import { describe, expect, it } from 'vitest';

import { nextStepId, projectIdFrom, resolveStep, stepsFor } from './resolveStep';

const withAgent = { projectId: '7', hasAgent: true };
const noAgent = { projectId: '7', hasAgent: false };

describe('resolveStep', () => {
  it('shows the current step on its own page', () => {
    expect(resolveStep('first-run', 'A2', '/templates', withAgent)?.step.id).toBe('A2');
  });

  it('waits while the person is on a page no nearby step belongs to', () => {
    expect(resolveStep('first-run', 'A2', '/company/projects/7/agents', withAgent)).toBeNull();
  });

  it('moves on one step when the current step was on a page the person has already left', () => {
    // The install landed on the project instead of its checklist.
    expect(resolveStep('first-run', 'A6', '/company/projects/7/overview', withAgent)?.step.id).toBe('A7');
  });

  it('never skips ahead past the run when the person wanders to the board', () => {
    expect(resolveStep('first-run', 'A8', '/company/projects/7/board', withAgent)).toBeNull();
  });

  it('numbers steps among the ones this person gets', () => {
    const resolved = resolveStep('first-run', 'A9', '/company/projects/7/workflows', withAgent);
    expect(resolved).toMatchObject({ index: 8, total: stepsFor('first-run', withAgent).length });
  });
});

describe('without a connected agent', () => {
  it('replaces Run with the step that sends the person to connect one', () => {
    const ids = stepsFor('first-run', noAgent).map((step) => step.id);
    expect(ids).toContain('A9-no-agent');
    expect(ids).not.toContain('A9');
    expect(ids).not.toContain('A10');
    expect(stepsFor('first-run', withAgent).map((step) => step.id)).not.toContain('A9-no-agent');
  });
});

describe('nextStepId', () => {
  it('returns the following step, and null after the last', () => {
    expect(nextStepId('first-run', 'A1', withAgent)).toBe('A2');
    expect(nextStepId('viewer', 'B4', withAgent)).toBeNull();
  });
});

describe('projectIdFrom', () => {
  it('reads the project out of a project path', () => {
    expect(projectIdFrom('/company/projects/42/workflows')).toBe('42');
    expect(projectIdFrom('/templates')).toBeNull();
  });
});
