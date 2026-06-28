import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';
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
    routeToken: null,
    configuredAgentId: null,
    contextMetadata: null,
    metadata: null,
    collectedAt: null,
    updatedAt: '2026-06-26T10:00:00Z',
    sessionConfig: null,
    toolIds: [],
    skillIds: [],
    mcpServerIds: [],
    inputAssetIds: [],
    repositoryIds: [],
    pendingArtifactsCount: 0,
    sessionLogsCount: 0,
    ...overrides,
  };
}

describe('Company/Sessions/Show', () => {
  it('renders the header with the agent label, live state badge and primary actions for an active session', () => {
    renderAuthedPage(<SessionShowPage />, {
      props: { session: buildSession({ state: 'running' }), cableStream: 'stream-token' },
    });

    expect(screen.getByText('Claude Code')).toBeInTheDocument();
    // The raw state string can surface in both the header badge and the waiting panel.
    expect(screen.getAllByText('running').length).toBeGreaterThan(0);
    expect(screen.getByText('#4242')).toBeInTheDocument();
    // An active, non-finishing session exposes the Finish action.
    expect(screen.getByRole('button', { name: 'Finish' })).toBeInTheDocument();
    // Company-level session creation was removed; the header omits the "New Session" button.
    expect(screen.queryByRole('button', { name: 'New Session' })).not.toBeInTheDocument();
  });

  it('renders the completion card with cost summary and review action for a finished session with pending outputs', () => {
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

    expect(screen.getByText('Completed')).toBeInTheDocument();
    expect(screen.getByText('Cost')).toBeInTheDocument();
    expect(screen.getByText('$12.34')).toBeInTheDocument();
    expect(screen.getByText('claude-opus')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Review Outputs \(3 files\)/ })).toBeInTheDocument();
    // Finished sessions do not offer the Finish action.
    expect(screen.queryByRole('button', { name: 'Finish' })).not.toBeInTheDocument();
  });

  it('navigates back to all sessions from the completion card', async () => {
    renderAuthedPage(<SessionShowPage />, {
      props: {
        session: buildSession({ state: 'finished', finishedAt: '2026-06-26T10:05:00Z' }),
        cableStream: 'stream-token',
      },
    });

    await userEvent.click(screen.getByRole('button', { name: 'All Sessions' }));
    expect(router.visit).toHaveBeenCalledWith('/company/sessions');
  });

  it('shows a failed badge and the error message for a failed session', () => {
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

    const card = screen.getByText('Failed').closest('div') as HTMLElement;
    expect(within(card).getByText('Failed')).toBeInTheDocument();
    expect(screen.getByText('Container exited unexpectedly')).toBeInTheDocument();
  });
});
