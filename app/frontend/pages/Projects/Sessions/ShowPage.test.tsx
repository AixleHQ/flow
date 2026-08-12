import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent } from 'test/renderPage';
import type TerminalSession from 'types/generated/TerminalSession';

import ProjectSessionShowPage from './ShowPage';

// Build a TerminalSession fixture inline (structurally matches the generated type).
function makeSession(overrides: Partial<TerminalSession> = {}): TerminalSession {
  return {
    id: 4242,
    sessionType: 'agent',
    agentType: 'claude_code',
    state: 'finished',
    mode: 'interactive',
    startedAt: '2026-06-26T10:00:00Z',
    finishingAt: null,
    finishedAt: '2026-06-26T10:05:00Z',
    createdAt: '2026-06-26T09:59:00Z',
    totalTokens: 0,
    inputTokens: 0,
    outputTokens: 0,
    cacheReadTokens: 0,
    cacheWriteTokens: 0,
    costCents: 0,
    models: [],
    requestedModel: null,
    artifactsReviewed: null,
    initialPrompt: null,
    errorMessage: null,
    containerId: null,
    projectId: 7,
    viewable: true,
    ownedByViewer: true,
    routeToken: null,
    configuredAgentId: null,
    contextMetadata: null,
    metadata: null,
    collectedAt: null,
    updatedAt: '2026-06-26T10:05:00Z',
    sessionConfig: {},
    toolIds: [],
    skillIds: [],
    mcpServerIds: [],
    configItemIds: [],
    inputAssetIds: [],
    repositoryIds: [],
    pendingArtifactsCount: 0,
    sessionLogsCount: 0,
    cloudConnectRequested: false,
    ...overrides,
  };
}

const project = { id: 7, name: 'Falcon Project' };

describe('Projects/Sessions/ShowPage', () => {
  it('renders the shared detail header for a finished session', () => {
    renderAuthedPage(<ProjectSessionShowPage />, {
      props: {
        project,
        session: makeSession({ state: 'finished', initialPrompt: 'Refactor onboarding status chips' }),
        workflowContext: null,
        cableStream: 'stream-token',
      },
    });

    expect(screen.getByRole('heading', { name: 'Refactor onboarding status chips' })).toBeInTheDocument();
    expect(screen.getByText('Finished')).toBeInTheDocument();
    expect(screen.getAllByText('Claude Code').length).toBeGreaterThan(0);
    // The breadcrumb is how you get back to the list now.
    expect(screen.getByRole('link', { name: 'Sessions & Runs' })).toHaveAttribute(
      'href',
      '/company/projects/7/sessions',
    );
  });

  it('offers a Review outputs action when there are pending artifacts', async () => {
    renderAuthedPage(<ProjectSessionShowPage />, {
      props: {
        project,
        session: makeSession({ state: 'finished', pendingArtifactsCount: 3 }),
        workflowContext: null,
        cableStream: 'stream-token',
      },
    });

    await userEvent.click(screen.getByRole('button', { name: /review outputs/i }));
    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/sessions/4242/artifacts');
  });

  it('shows the Finish action and starting state for a non-ready running session', () => {
    renderAuthedPage(<ProjectSessionShowPage />, {
      props: {
        project,
        session: makeSession({ state: 'running', finishedAt: null }),
        workflowContext: null,
        cableStream: 'stream-token',
      },
    });

    expect(screen.getByRole('button', { name: 'Finish session' })).toBeInTheDocument();
    // Running but not ready (no websocket terminal) shows the waiting state.
    expect(screen.getByText('Starting session…')).toBeInTheDocument();
  });

  it('links a workflow-step session back to its run', () => {
    renderAuthedPage(<ProjectSessionShowPage />, {
      props: {
        project,
        session: makeSession({ state: 'finished' }),
        workflowContext: {
          runId: 1443,
          runName: 'Weekly GA report',
          runPath: '/company/projects/7/workflow_runs/1443',
          stepName: 'GA report',
          stepPosition: 1,
          stepsTotal: 1,
        },
        cableStream: 'stream-token',
      },
    });

    expect(screen.getByRole('link', { name: 'Weekly GA report · Run #1443' })).toHaveAttribute(
      'href',
      '/company/projects/7/workflow_runs/1443',
    );
    expect(screen.getByText('Step 1 of 1 · Workflow step')).toBeInTheDocument();
  });

  it('offers a new session from a finished one', async () => {
    renderAuthedPage(<ProjectSessionShowPage />, {
      props: { project, session: makeSession({ state: 'finished' }), workflowContext: null, cableStream: 'stream' },
    });

    await userEvent.click(screen.getByRole('button', { name: /new session/i }));
    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/sessions/new');
  });
});
