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
  it('renders the completion card for a finished session', () => {
    renderAuthedPage(<ProjectSessionShowPage />, {
      props: { project, session: makeSession({ state: 'finished' }), cableStream: 'stream-token' },
    });

    // Agent label and a "Completed" badge appear in the completion card.
    expect(screen.getAllByText('Claude Code').length).toBeGreaterThan(0);
    expect(screen.getByText('Completed')).toBeInTheDocument();
    // Terminal-state navigation buttons.
    expect(screen.getByRole('button', { name: 'All Sessions' })).toBeInTheDocument();
  });

  it('navigates back to all sessions when the completion card button is clicked', async () => {
    renderAuthedPage(<ProjectSessionShowPage />, {
      props: { project, session: makeSession({ state: 'finished' }), cableStream: 'stream-token' },
    });

    await userEvent.click(screen.getByRole('button', { name: 'All Sessions' }));
    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/sessions');
  });

  it('offers a Review Outputs action when there are pending artifacts', async () => {
    renderAuthedPage(<ProjectSessionShowPage />, {
      props: {
        project,
        session: makeSession({ state: 'finished', pendingArtifactsCount: 3 }),
        cableStream: 'stream-token',
      },
    });

    const reviewBtn = screen.getByRole('button', { name: /Review Outputs \(3 files\)/ });
    await userEvent.click(reviewBtn);
    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/sessions/4242/artifacts');
  });

  it('shows the Finish action and starting state for a non-ready running session', () => {
    renderAuthedPage(<ProjectSessionShowPage />, {
      props: { project, session: makeSession({ state: 'running', finishedAt: null }), cableStream: 'stream-token' },
    });

    // Non-terminal, non-finishing sessions expose a Finish button in the header.
    expect(screen.getByRole('button', { name: 'Finish' })).toBeInTheDocument();
    // Running but not ready (no websocket terminal) shows the waiting state.
    expect(screen.getByText('Starting session...')).toBeInTheDocument();
  });

  it('navigates to a new session from the header New Session button', async () => {
    renderAuthedPage(<ProjectSessionShowPage />, {
      props: { project, session: makeSession({ state: 'running', finishedAt: null }), cableStream: 'stream-token' },
    });

    // Running (non-terminal) state has a single "New Session" button in the header.
    await userEvent.click(screen.getByRole('button', { name: /New Session/ }));
    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/sessions/new');
  });
});
