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
    queuedAt: null,
    waitReason: null,
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
    websocketUrl: 'wss://example.test/ttyd/abc/ws',
    watcherUrl: undefined,
    ideUrl: undefined,
    cableStream: undefined,
    sessionConfig: {},
    toolIds: [],
    skillIds: [],
    mcpServerIds: [],
    configItemIds: [],
    inputAssetIds: [],
    repositoryIds: [],
    userName: undefined,
    userEmail: undefined,
    projectName: undefined,
    pendingArtifactsCount: 0,
    sessionLogsCount: 0,
    cloudConnectRequested: false,
    ...overrides,
  };
}

const ctx: SessionShowContext = {
  backPath: '/sessions',
  newSessionPath: '/sessions/new',
  artifactsPath: '/sessions/7/artifacts',
};

describe('SessionShowContent', () => {
  it('shows queue waiting and cancellation without mounting a terminal', () => {
    renderPage(
      <SessionShowContent
        session={makeSession({ state: 'queued', startedAt: null })}
        cableStream="signed-stream"
        context={ctx}
      />,
    );
    expect(screen.getByText('Waiting for an available session slot')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Cancel session' })).toBeInTheDocument();
    expect(screen.queryByTitle('Terminal')).not.toBeInTheDocument();
  });

  it('treats cancelled sessions as terminal without finish controls', () => {
    renderPage(
      <SessionShowContent session={makeSession({ state: 'cancelled' })} cableStream="signed-stream" context={ctx} />,
    );
    expect(screen.getByText('Cancelled')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Finish session' })).not.toBeInTheDocument();
    expect(screen.queryByTitle('Terminal')).not.toBeInTheDocument();
  });
  it('renders the shared detail header: breadcrumb, title, status, id and runtime', () => {
    renderPage(
      <SessionShowContent
        session={makeSession({ id: 42, state: 'ready', initialPrompt: 'Audit the GA4 property', userName: 'Ada' })}
        cableStream="signed-stream"
        context={ctx}
      />,
    );

    // The title is the session's own first prompt line, not the runtime name —
    // the runtime moved to the meta line where runs put it too.
    expect(screen.getByRole('heading', { name: 'Audit the GA4 property' })).toBeInTheDocument();
    expect(screen.getByText('Running')).toBeInTheDocument();
    expect(screen.getByText('#42')).toBeInTheDocument();
    expect(screen.getByText('Claude Code')).toBeInTheDocument();
    expect(screen.getByText('Ada')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Sessions & Runs' })).toHaveAttribute('href', '/sessions');
  });

  it('labels a standalone session as such and a workflow-step session by its position', () => {
    const { unmount } = renderPage(
      <SessionShowContent session={makeSession()} cableStream="signed-stream" context={ctx} />,
    );
    expect(screen.getByText('Standalone session')).toBeInTheDocument();
    unmount();

    renderPage(
      <SessionShowContent
        session={makeSession()}
        cableStream="signed-stream"
        context={ctx}
        workflowContext={{
          runId: 1702,
          runName: 'Release notes digest',
          runPath: '/runs/1702',
          stepName: 'Post to Slack',
          stepPosition: 2,
          stepsTotal: 2,
        }}
      />,
    );

    expect(screen.getByRole('heading', { name: 'Post to Slack' })).toBeInTheDocument();
    expect(screen.getByText('Step 2 of 2 · Workflow step')).toBeInTheDocument();
    // The run sits between the list and the session in the breadcrumb.
    expect(screen.getByRole('link', { name: 'Release notes digest · Run #1702' })).toHaveAttribute(
      'href',
      '/runs/1702',
    );
  });

  it('shows the Finish action for an active session and POSTs to finish then reloads', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 200 }));

    renderPage(
      <SessionShowContent
        session={makeSession({ id: 99, state: 'running' })}
        cableStream="signed-stream"
        context={ctx}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: /finish session/i }));

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

    await userEvent.click(screen.getByRole('button', { name: /copy session link/i }));

    expect(writeText).toHaveBeenCalledWith(window.location.href);
    expect(await screen.findByText('Session link copied')).toBeInTheDocument();
  });

  it('reports cost, tokens and models in the header stats for a finished session', () => {
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
        })}
        cableStream="signed-stream"
        context={ctx}
      />,
    );

    expect(screen.getByText('Finished')).toBeInTheDocument();
    expect(screen.getByText('$2.50')).toBeInTheDocument();
    expect(screen.getByText('12.0k')).toBeInTheDocument();
    expect(screen.getByText('claude-sonnet')).toBeInTheDocument();
    // The token line breaks the total down rather than hiding it in a tooltip.
    expect(screen.getByText('8.0k')).toBeInTheDocument();
  });

  it('offers a Review outputs action when a finished session left files pending', async () => {
    renderPage(
      <SessionShowContent
        session={makeSession({ state: 'finished', finishedAt: '2026-06-26T10:05:00Z', pendingArtifactsCount: 3 })}
        cableStream="signed-stream"
        context={ctx}
      />,
    );

    expect(screen.getByText('3 files are waiting for review.')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: /review outputs/i }));
    expect(router.visit).toHaveBeenCalledWith('/sessions/7/artifacts');
  });

  it('renders a finished session in the same read-only console frame', () => {
    renderPage(
      <SessionShowContent
        session={makeSession({ state: 'finished', finishedAt: '2026-06-26T10:05:00Z', costCents: 478 })}
        cableStream="signed-stream"
        context={ctx}
      />,
    );

    expect(screen.getByText(/read-only/)).toBeInTheDocument();
    // No live terminal for a terminal session.
    expect(screen.queryByTitle('Terminal')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /finish session/i })).not.toBeInTheDocument();
  });

  it('keeps the workflow prompt collapsed until requested', async () => {
    renderPage(
      <SessionShowContent
        session={makeSession({ state: 'finished', initialPrompt: 'Generate a detailed release report' })}
        cableStream="signed-stream"
        context={ctx}
        workflowContext={{
          runId: 12,
          runName: 'Release workflow',
          runPath: '/runs/12',
          stepName: 'Generate report',
          stepPosition: 1,
          stepsTotal: 2,
        }}
      />,
    );

    const disclosure = screen.getByText('Prompt').closest('details');
    expect(disclosure).not.toHaveAttribute('open');

    await userEvent.click(screen.getByText('Prompt'));

    expect(disclosure).toHaveAttribute('open');
    expect(screen.getByText('Generate a detailed release report')).toBeInTheDocument();
  });

  it('renders the error message for a failed session', () => {
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

    expect(screen.getAllByText('Failed').length).toBeGreaterThan(0);
    expect(screen.getByText('Container exploded')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /finish session/i })).not.toBeInTheDocument();
  });

  it('shows the starting state when the session is not yet ready', () => {
    renderPage(
      <SessionShowContent
        session={makeSession({ state: 'not_started', websocketUrl: undefined })}
        cableStream="signed-stream"
        context={ctx}
      />,
    );

    expect(screen.getByText('Starting session…')).toBeInTheDocument();
    // Header chip plus waiting chip both render the humanized state.
    expect(screen.getAllByText('Pending').length).toBeGreaterThan(0);
  });

  it('renders the finishing overlay while the session is finishing', () => {
    renderPage(
      <SessionShowContent session={makeSession({ state: 'finishing' })} cableStream="signed-stream" context={ctx} />,
    );

    expect(screen.getByText(/finishing session/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /finish session/i })).not.toBeInTheDocument();
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

  it("presents someone else's shared session as watch-only", () => {
    renderPage(
      <SessionShowContent
        session={makeSession({
          state: 'ready',
          ownedByViewer: false,
          userName: 'Dana Vega',
          websocketUrl: 'wss://host.test/sess/ws',
          ideUrl: 'https://host.test/ide',
        })}
        cableStream="signed-stream"
        context={ctx}
      />,
    );

    // The terminal is still shown — watching is the point — but behind a shield
    // that takes the clicks, so the iframe never gets focus.
    expect(screen.getByTitle('Terminal')).toBeInTheDocument();
    expect(screen.getByLabelText("Read-only view of another user's session")).toBeInTheDocument();
    expect(screen.getByText('View only')).toBeInTheDocument();
    // No editor: an overlay on VS Code is just a broken editor.
    expect(screen.queryByTitle('VS Code Editor')).not.toBeInTheDocument();
    // Finish is owner-only at the API, so it is not offered here.
    expect(screen.queryByRole('button', { name: /finish session/i })).not.toBeInTheDocument();
  });

  it('leaves the owner able to type and to finish their own session', () => {
    renderPage(
      <SessionShowContent
        session={makeSession({ state: 'ready', ownedByViewer: true, websocketUrl: 'wss://host.test/sess/ws' })}
        cableStream="signed-stream"
        context={ctx}
      />,
    );

    expect(screen.queryByLabelText("Read-only view of another user's session")).not.toBeInTheDocument();
    expect(screen.queryByText('View only')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /finish session/i })).toBeInTheDocument();
  });
});
