import { describe, expect, it } from 'vitest';

import { buildBoard } from './board';
import { buildBoardColumn } from './boardColumn';
import { buildBoardPreset } from './boardPreset';
import { buildBoardTask } from './boardTask';
import { buildIntegration } from './integration';
import { buildProject } from './project';
import { buildRepository } from './repository';
import { buildSessionArtifact } from './sessionArtifact';
import { buildStepRun } from './stepRun';
import { buildSubStepRun } from './subStepRun';
import { buildTaskComment } from './taskComment';
import { buildTaskStatistics } from './taskStatistics';
import { buildTaskWorkflowRun } from './taskWorkflowRun';
import { buildWorkflowRun } from './workflowRun';
import { buildWorkflowRunAsset } from './workflowRunAsset';

describe('typed factories', () => {
  it('buildProject applies overrides over typed defaults', () => {
    expect(buildProject().name).toBe('Acme');
    expect(buildProject({ name: 'X', state: 'archived' })).toMatchObject({
      name: 'X',
      state: 'archived',
      slug: 'acme',
    });
  });

  it('buildBoardTask applies overrides', () => {
    expect(buildBoardTask().title).toBe('Task');
    expect(buildBoardTask({ title: 'Bug', priority: 'high' }).priority).toBe('high');
  });

  it('buildIntegration applies overrides', () => {
    expect(buildIntegration().provider).toBe('github');
    expect(buildIntegration({ provider: 'gitlab' }).provider).toBe('gitlab');
  });

  it('buildRepository nests a full Integration and applies overrides', () => {
    expect(buildRepository().integration?.provider).toBe('github');
    expect(buildRepository({ sourceBranch: 'develop' }).sourceBranch).toBe('develop');
    // Public repositories carry no integration at all.
    expect(buildRepository({ integration: null, publicSource: true }).integration).toBeNull();
  });

  it('buildBoard applies overrides', () => {
    expect(buildBoard().presetOrigin).toBeNull();
    expect(buildBoard({ name: 'Sprint' }).name).toBe('Sprint');
  });

  it('buildBoardColumn defaults an empty binding and applies overrides', () => {
    expect(buildBoardColumn().workflowBinding).toBeNull();
    expect(buildBoardColumn({ name: 'In Progress', position: 1 }).name).toBe('In Progress');
  });

  it('buildBoardPreset applies overrides', () => {
    expect(buildBoardPreset().columns).toContain('Todo');
    expect(buildBoardPreset({ key: 'scrum' }).key).toBe('scrum');
  });

  it('buildTaskComment applies overrides', () => {
    expect(buildTaskComment().authorType).toBe('human');
    expect(buildTaskComment({ tags: ['release-blocker'] }).tags).toEqual(['release-blocker']);
  });

  it('buildTaskWorkflowRun applies overrides', () => {
    expect(buildTaskWorkflowRun().state).toBe('completed');
    expect(buildTaskWorkflowRun({ mode: 'interactive' }).mode).toBe('interactive');
  });

  it('buildTaskStatistics applies overrides', () => {
    expect(buildTaskStatistics().costTotals.totalCostCents).toBe(250);
    expect(buildTaskStatistics({ tokenTotals: { totalTokens: 5 } }).tokenTotals.totalTokens).toBe(5);
  });

  it('buildWorkflowRun defaults empty stepRuns and applies overrides', () => {
    expect(buildWorkflowRun().stepRuns).toEqual([]);
    expect(buildWorkflowRun({ state: 'completed' }).state).toBe('completed');
  });

  it('buildStepRun applies overrides', () => {
    expect(buildStepRun().state).toBe('pending');
    expect(buildStepRun({ state: 'completed' }).state).toBe('completed');
  });

  it('buildSubStepRun applies overrides', () => {
    expect(buildSubStepRun().subStepName).toBe('Fetch data');
    expect(buildSubStepRun({ state: 'in_progress' }).state).toBe('in_progress');
  });

  it('buildWorkflowRunAsset applies overrides', () => {
    expect(buildWorkflowRunAsset().name).toBe('report.pdf');
    expect(buildWorkflowRunAsset({ fileSize: null }).fileSize).toBeNull();
  });

  it('buildSessionArtifact applies overrides', () => {
    expect(buildSessionArtifact().status).toBe('pending');
    expect(buildSessionArtifact({ status: 'active' }).status).toBe('active');
  });
});
