import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';
import type TerminalSession from 'types/generated/TerminalSession';

import { SessionShowContent, type SessionShowContext } from './SessionShowContent';

function makeSession(overrides: Partial<TerminalSession> = {}): TerminalSession {
  return {
    id: 7,
    sessionType: 'terminal',
    agentType: 'claude_code',
    state: 'ready',
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
    websocketUrl: 'wss://example.test/ttyd/abc/ws',
    watcherUrl: undefined,
    ideUrl: undefined,
    cableStream: undefined,
    sessionConfig: {},
    toolIds: [],
    skillIds: [],
    mcpServerIds: [],
    inputAssetIds: [],
    repositoryIds: [],
    userName: undefined,
    userEmail: undefined,
    projectName: undefined,
    pendingArtifactsCount: 0,
    sessionLogsCount: 0,
    ...overrides,
  };
}

const ctx: SessionShowContext = {
  backPath: '/sessions',
  newSessionPath: '/sessions/new',
  artifactsPath: '/sessions/7/artifacts',
};

describe('SessionShowContent', () => {
  it('renders the header with agent label, state badge and session id', () => {
    renderPage(
      <SessionShowContent
        session={makeSession({ id: 42, agentType: 'claude_code', state: 'ready' })}
        cableStream="signed-stream"
        context={ctx}
      />,
    );

    expect(screen.getByText('Claude Code')).toBeInTheDocument();
    expect(screen.getByText('ready')).toBeInTheDocument();
    expect(screen.getByText('#42')).toBeInTheDocument();
    // Active session also shows the "New Session" action in the header.
    expect(screen.getByRole('button', { name: /new session/i })).toBeInTheDocument();
  });

  it('navigates back when the back arrow is clicked', async () => {
    renderPage(<SessionShowContent session={makeSession()} cableStream="signed-stream" context={ctx} />);

    // The back ActionIcon is the first button (icon-only); find via its Tabler icon SVG.
    const backIcon = document.querySelector('svg.tabler-icon-arrow-left');
    const backBtn = backIcon?.closest('button');
    if (!backBtn) throw new Error('back button not found');
    await userEvent.click(backBtn);

    expect(router.visit).toHaveBeenCalledWith('/sessions');
  });

  it('shows the Finish button for an active session and POSTs to finish then reloads', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 200 }));

    renderPage(
      <SessionShowContent
        session={makeSession({ id: 99, state: 'running' })}
        cableStream="signed-stream"
        context={ctx}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: /^finish$/i }));

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/terminal_sessions/99/finish',
        expect.objectContaining({ method: 'POST' }),
      );
    });
    await waitFor(() => expect(router.reload).toHaveBeenCalled());

    fetchSpy.mockRestore();
  });

  it('copies the session link and shows a notification', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.assign(navigator, { clipboard: { writeText } });

    renderPage(<SessionShowContent session={makeSession()} cableStream="signed-stream" context={ctx} />);

    const copyIcon = document.querySelector('svg.tabler-icon-copy');
    const copyBtn = copyIcon?.closest('button');
    if (!copyBtn) throw new Error('copy button not found');
    await userEvent.click(copyBtn);

    expect(writeText).toHaveBeenCalledWith(window.location.href);
    expect(await screen.findByText('Session link copied')).toBeInTheDocument();
  });

  it('renders the completion card with cost, duration and a Review Outputs action for a finished session', async () => {
    renderPage(
      <SessionShowContent
        session={makeSession({
          state: 'finished',
          finishedAt: '2026-06-26T10:05:00Z',
          costCents: 250,
          totalTokens: 12000,
          inputTokens: 8000,
          outputTokens: 4000,
          models: ['claude-sonnet'],
          pendingArtifactsCount: 3,
          initialPrompt: 'Build me a feature',
        })}
        cableStream="signed-stream"
        context={ctx}
      />,
    );

    // Completion summary: "Completed" badge, cost formatted, models badge, prompt text.
    expect(screen.getByText('Completed')).toBeInTheDocument();
    expect(screen.getByText('$2.50')).toBeInTheDocument();
    expect(screen.getByText('claude-sonnet')).toBeInTheDocument();
    expect(screen.getByText('Build me a feature')).toBeInTheDocument();

    // Review Outputs button routes to the artifacts path.
    const review = screen.getByRole('button', { name: /review outputs \(3 files\)/i });
    await userEvent.click(review);
    expect(router.visit).toHaveBeenCalledWith('/sessions/7/artifacts');
  });

  it('renders the error message in the completion card for a failed session', () => {
    renderPage(
      <SessionShowContent
        session={makeSession({
          state: 'failed',
          finishedAt: '2026-06-26T10:05:00Z',
          errorMessage: 'Container exploded',
        })}
        cableStream="signed-stream"
        context={ctx}
      />,
    );

    expect(screen.getByText('Failed')).toBeInTheDocument();
    expect(screen.getByText('Container exploded')).toBeInTheDocument();
    // A failed/finished session is terminal: no Finish button.
    expect(screen.queryByRole('button', { name: /^finish$/i })).not.toBeInTheDocument();
  });

  it('shows the starting/waiting state when the session is not yet ready', () => {
    renderPage(
      <SessionShowContent
        session={makeSession({ state: 'not_started', websocketUrl: undefined })}
        cableStream="signed-stream"
        context={ctx}
      />,
    );

    expect(screen.getByText('Starting session...')).toBeInTheDocument();
    // The header state badge plus the waiting badge both read the raw state.
    expect(screen.getAllByText('not_started').length).toBeGreaterThan(0);
  });

  it('renders the finishing overlay while the session is finishing', () => {
    renderPage(
      <SessionShowContent session={makeSession({ state: 'finishing' })} cableStream="signed-stream" context={ctx} />,
    );

    expect(screen.getByText(/finishing session/i)).toBeInTheDocument();
    // Finishing is non-terminal but the Finish button is hidden.
    expect(screen.queryByRole('button', { name: /^finish$/i })).not.toBeInTheDocument();
  });

  it('renders a terminal iframe when ready and a websocket url is present', () => {
    renderPage(
      <SessionShowContent
        session={makeSession({ state: 'ready', websocketUrl: 'wss://host.test/sess/ws' })}
        cableStream="signed-stream"
        context={ctx}
      />,
    );

    const iframe = screen.getByTitle('Terminal') as HTMLIFrameElement;
    // ttydUrl rewrites the wss:// ws endpoint to an https:// base, stripping the trailing /ws.
    expect(iframe.getAttribute('src')).toBe('https://host.test/sess');
  });
});
