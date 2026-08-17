import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, within } from 'test/renderPage';
import type TerminalSession from 'types/generated/TerminalSession';

import SessionShowPage from './Show';

function buildSession(overrides: Partial<TerminalSession> = {}): TerminalSession {
  return {
    id: 4242,
    sessionType: 'terminal',
    agentType: 'claude_code',
    state: 'running',
    mode: 'interactive',
    startedAt: '2026-06-26T10:00:00Z',
    finishingAt: null,
    finishedAt: null,
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
    projectId: null,
    viewable: true,
    ownedByViewer: true,
    routeToken: null,
    configuredAgentId: null,
    contextMetadata: null,
    metadata: null,
    collectedAt: null,
    updatedAt: '2026-06-26T10:00:00Z',
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

describe('Company/Sessions/Show', () => {
  it('renders the detail header with runtime, live status and the Finish action', () => {
    renderAuthedPage(<SessionShowPage />, {
      props: { session: buildSession({ state: 'running' }), cableStream: 'stream-token' },
    });

    expect(screen.getByText('Claude Code')).toBeInTheDocument();
    // "running" is the container starting; the agent is not working yet, so the
    // header chip and the waiting panel agree.
    expect(screen.getAllByText('Starting').length).toBeGreaterThan(0);
    expect(screen.getByText('#4242')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Finish session' })).toBeInTheDocument();
    // Company-level session creation was removed; the header omits it.
    expect(screen.queryByRole('button', { name: /new session/i })).not.toBeInTheDocument();
    // The company list keeps its own breadcrumb label (the sidebar has a
    // same-named link, so scope the query to the breadcrumb).
    const breadcrumb = screen.getByRole('navigation', { name: 'Breadcrumb' });
    expect(within(breadcrumb).getByRole('link', { name: 'Sessions' })).toHaveAttribute('href', '/company/sessions');
  });

  it('reports cost, models and pending outputs for a finished session', () => {
    renderAuthedPage(<SessionShowPage />, {
      props: {
        session: buildSession({
          state: 'finished',
          finishedAt: '2026-06-26T10:05:00Z',
          costCents: 1234,
          totalTokens: 5200,
          inputTokens: 4000,
          outputTokens: 1200,
          models: ['claude-opus'],
          pendingArtifactsCount: 3,
        }),
        cableStream: 'stream-token',
      },
    });

    expect(screen.getByText('Finished')).toBeInTheDocument();
    expect(screen.getByText('Cost')).toBeInTheDocument();
    expect(screen.getByText('$12.34')).toBeInTheDocument();
    expect(screen.getByText('claude-opus')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /review outputs/i })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Finish session' })).not.toBeInTheDocument();
  });

  it('shows a failed status and the error message for a failed session', () => {
    renderAuthedPage(<SessionShowPage />, {
      props: {
        session: buildSession({
          state: 'failed',
          finishedAt: '2026-06-26T10:05:00Z',
          errorMessage: 'Container exited unexpectedly',
        }),
        cableStream: 'stream-token',
      },
    });

    expect(screen.getAllByText('Failed').length).toBeGreaterThan(0);
    expect(screen.getByText('Container exited unexpectedly')).toBeInTheDocument();
  });
});
