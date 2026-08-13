import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import SessionsPage from './SessionsPage';

const project = { id: 7, name: 'Atlas Migration' };

type Session = Parameters<typeof SessionsPage>[0]['sessions'][number];

function makeSession(overrides: Partial<Session> = {}): Session {
  return {
    id: 1,
    sessionType: 'agent_session',
    agentType: 'claude_code',
    state: 'finished',
    mode: null,
    startedAt: '2026-06-20T10:00:00Z',
    finishedAt: '2026-06-20T10:05:00Z',
    createdAt: '2026-06-20T09:59:00Z',
    totalTokens: 12000,
    inputTokens: 8000,
    outputTokens: 4000,
    cacheReadTokens: 0,
    cacheWriteTokens: 0,
    costCents: 250,
    models: ['sonnet-4'],
    userName: 'Dana Vega',
    userEmail: 'dana@vega.test',
    projectName: 'Atlas Migration',
    artifactsReviewed: true,
    pendingArtifactsCount: 0,
    initialPrompt: 'Refactor the importer',
    viewable: true,
    ...overrides,
  };
}

describe('Projects/Sessions/SessionsPage', () => {
  it('shows the no-sessions empty state when the list is empty and no filters are applied', () => {
    renderAuthedPage(<SessionsPage sessions={[]} filters={{}} perPage={20} />, {
      props: { project },
    });

    expect(screen.getByText('No sessions yet')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'New Session' })).toHaveAttribute(
      'href',
      '/company/projects/7/sessions/new',
    );
  });

  it('shows the filtered empty state when filters are applied but nothing matches', () => {
    renderAuthedPage(<SessionsPage sessions={[]} filters={{ state_eq: 'failed' }} perPage={20} />, {
      props: { project },
    });

    expect(screen.getByText('No sessions match filters')).toBeInTheDocument();
    expect(screen.queryByText('No sessions yet')).not.toBeInTheDocument();
  });

  it('renders a populated session table with agent, status, user and id', () => {
    const sessions = [
      makeSession({ id: 42, agentType: 'claude_code', state: 'finished', userName: 'Dana Vega' }),
      makeSession({ id: 43, agentType: 'codex', state: 'failed', userName: 'Lee Park' }),
    ];

    renderAuthedPage(<SessionsPage sessions={sessions} filters={{}} perPage={20} />, {
      props: { project },
    });

    // Scope to the table body: agent/status labels ("Claude Code", "Codex", "Failed") also appear
    // in the filter <Select> option lists, so an unscoped getByText would match multiple nodes.
    const table = screen.getByRole('table');
    const body = within(table);

    expect(body.getByText('#42')).toBeInTheDocument();
    expect(body.getByText('#43')).toBeInTheDocument();
    expect(body.getByText('Claude Code')).toBeInTheDocument();
    expect(body.getByText('Codex')).toBeInTheDocument();
    expect(body.getByText('Dana Vega')).toBeInTheDocument();
    expect(body.getByText('Lee Park')).toBeInTheDocument();
    // Status labels mapped from state.
    expect(body.getByText('Finished')).toBeInTheDocument();
    expect(body.getByText('Failed')).toBeInTheDocument();
  });

  it('navigates to the session when a clickable (finished) row is clicked', async () => {
    const sessions = [makeSession({ id: 99, state: 'finished', userName: 'Dana Vega' })];

    renderAuthedPage(<SessionsPage sessions={sessions} filters={{}} perPage={20} />, {
      props: { project },
    });

    const idCell = screen.getByText('#99');
    const row = idCell.closest('tr') as HTMLElement;
    await userEvent.click(within(row).getByText('Dana Vega'));

    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/sessions/99');
  });

  it('keeps a private session listed but refuses to open it', async () => {
    const sessions = [makeSession({ id: 77, state: 'finished', userName: 'Dana Vega', viewable: false })];

    renderAuthedPage(<SessionsPage sessions={sessions} filters={{}} perPage={20} />, {
      props: { project },
    });

    const row = (screen.getByText('#77').closest('tr') as HTMLElement) ?? document.body;

    // The row stays — cost and tokens are how the team sees what the project
    // spends — but there is no way in and no link to follow.
    expect(within(row).getByText('$2.50')).toBeInTheDocument();
    expect(within(row).getByLabelText('Session #77 is private')).toBeInTheDocument();
    expect(within(row).queryByRole('link', { name: 'Open session #77' })).not.toBeInTheDocument();

    await userEvent.click(within(row).getByText('Dana Vega'));

    expect(router.visit).not.toHaveBeenCalled();
  });

  // --- toolbar filters ---

  it('navigates with an agent_type_eq query when the Agent filter is selected', async () => {
    renderAuthedPage(<SessionsPage sessions={[makeSession({ id: 1 })]} filters={{}} perPage={20} />, {
      props: { project },
    });

    await userEvent.click(screen.getByPlaceholderText('Agent'));
    await userEvent.click(await screen.findByRole('option', { name: 'Cursor CLI' }));

    // perPage === 20 → the query omits per_page and sends only the ransack `q` object.
    expect(router.get).toHaveBeenCalledWith(
      '/company/projects/7/sessions',
      { q: { agent_type_eq: 'cursor_cli' } },
      { preserveState: true, preserveScroll: true },
    );
  });

  it('navigates with a state_eq query when the Status filter is selected', async () => {
    renderAuthedPage(<SessionsPage sessions={[makeSession({ id: 1 })]} filters={{}} perPage={20} />, {
      props: { project },
    });

    await userEvent.click(screen.getByPlaceholderText('Status'));
    await userEvent.click(await screen.findByRole('option', { name: 'Running' }));

    // The "Running" status option maps to the `ready` state value.
    expect(router.get).toHaveBeenCalledWith(
      '/company/projects/7/sessions',
      { q: { state_eq: 'ready' } },
      { preserveState: true, preserveScroll: true },
    );
  });

  it('drops the filter key from the query when an active filter is cleared', async () => {
    const { container } = renderAuthedPage(
      <SessionsPage sessions={[makeSession({ id: 1 })]} filters={{ agent_type_eq: 'codex' }} perPage={20} />,
      { props: { project } },
    );

    // Mantine's clearable Select renders its clear control as an aria-hidden <button> (tabindex -1),
    // so it has no accessible role; reach it through the DOM to interact.
    const clearButton = container.querySelector('button[aria-hidden="true"]');
    expect(clearButton).not.toBeNull();
    await userEvent.click(clearButton as HTMLElement);

    expect(router.get).toHaveBeenCalledWith(
      '/company/projects/7/sessions',
      { q: {} },
      { preserveState: true, preserveScroll: true },
    );
  });

  it('includes per_page in the query when a non-default page size is chosen', async () => {
    renderAuthedPage(<SessionsPage sessions={[makeSession({ id: 1 })]} filters={{}} perPage={20} />, {
      props: { project },
    });

    // The toolbar has three comboboxes (Agent, Status, per-page); the per-page one is last and
    // currently shows "20". Open it and choose 50.
    const comboboxes = screen.getAllByRole('combobox');
    await userEvent.click(comboboxes[comboboxes.length - 1]);
    await userEvent.click(await screen.findByRole('option', { name: '50' }));

    expect(router.get).toHaveBeenCalledWith(
      '/company/projects/7/sessions',
      { q: {}, per_page: 50 },
      { preserveState: true, preserveScroll: true },
    );
  });

  // --- row clickability ---

  it('does not navigate and shows no open link for a non-clickable (running) row', async () => {
    renderAuthedPage(
      <SessionsPage sessions={[makeSession({ id: 55, state: 'running' })]} filters={{}} perPage={20} />,
      {
        props: { project },
      },
    );

    const row = screen.getByText('#55').closest('tr') as HTMLElement;
    // The "Open session" external link only renders for clickable states.
    expect(within(row).queryByRole('link')).not.toBeInTheDocument();

    await userEvent.click(within(row).getByText('#55'));
    expect(router.visit).not.toHaveBeenCalled();
  });

  it('renders an Open session external link on a clickable row pointing at the session', () => {
    renderAuthedPage(
      <SessionsPage sessions={[makeSession({ id: 77, state: 'finished' })]} filters={{}} perPage={20} />,
      {
        props: { project },
      },
    );

    const row = screen.getByText('#77').closest('tr') as HTMLElement;
    expect(within(row).getByRole('link')).toHaveAttribute('href', '/company/projects/7/sessions/77');
  });

  // --- status / badges ---

  it('shows a pending-artifacts badge for a finished, unreviewed session with pending artifacts', () => {
    renderAuthedPage(
      <SessionsPage
        sessions={[makeSession({ id: 88, state: 'finished', artifactsReviewed: false, pendingArtifactsCount: 3 })]}
        filters={{}}
        perPage={20}
      />,
      { props: { project } },
    );

    const row = screen.getByText('#88').closest('tr') as HTMLElement;
    expect(within(row).getByText('3 pending')).toBeInTheDocument();
  });

  it('omits the pending-artifacts badge when artifacts have been reviewed', () => {
    renderAuthedPage(
      <SessionsPage
        sessions={[makeSession({ id: 89, state: 'finished', artifactsReviewed: true, pendingArtifactsCount: 3 })]}
        filters={{}}
        perPage={20}
      />,
      { props: { project } },
    );

    const row = screen.getByText('#89').closest('tr') as HTMLElement;
    expect(within(row).queryByText('3 pending')).not.toBeInTheDocument();
  });

  it('falls back to the raw agent/state strings for unknown values', () => {
    renderAuthedPage(
      <SessionsPage
        sessions={[makeSession({ id: 90, agentType: 'mystery_agent', state: 'quarantined' })]}
        filters={{}}
        perPage={20}
      />,
      { props: { project } },
    );

    const row = screen.getByText('#90').closest('tr') as HTMLElement;
    expect(within(row).getByText('mystery_agent')).toBeInTheDocument();
    expect(within(row).getByText('quarantined')).toBeInTheDocument();
  });

  // --- session type labels ---

  it('maps the session type to a human label and renders model badges', () => {
    renderAuthedPage(
      <SessionsPage
        sessions={[makeSession({ id: 91, sessionType: 'workflow_step', models: ['sonnet-4', 'haiku-3'] })]}
        filters={{}}
        perPage={20}
      />,
      { props: { project } },
    );

    const row = screen.getByText('#91').closest('tr') as HTMLElement;
    expect(within(row).getByText('Workflow step')).toBeInTheDocument();
    expect(within(row).getByText('sonnet-4')).toBeInTheDocument();
    expect(within(row).getByText('haiku-3')).toBeInTheDocument();
  });

  it('renders the raw session type string when it is unknown', () => {
    renderAuthedPage(
      <SessionsPage sessions={[makeSession({ id: 92, sessionType: 'odd_session' })]} filters={{}} perPage={20} />,
      { props: { project } },
    );

    const row = screen.getByText('#92').closest('tr') as HTMLElement;
    expect(within(row).getByText('odd_session')).toBeInTheDocument();
  });

  // --- token / cost / duration formatting (via rendered cells) ---

  it('formats large token totals with k/M suffixes', () => {
    const sessions = [makeSession({ id: 100, totalTokens: 12_345 }), makeSession({ id: 101, totalTokens: 2_500_000 })];
    renderAuthedPage(<SessionsPage sessions={sessions} filters={{}} perPage={20} />, { props: { project } });

    const row100 = screen.getByText('#100').closest('tr') as HTMLElement;
    const row101 = screen.getByText('#101').closest('tr') as HTMLElement;
    expect(within(row100).getByText('12.3k')).toBeInTheDocument();
    expect(within(row101).getByText('2.5M')).toBeInTheDocument();
  });

  it('renders em-dashes for zero tokens and zero cost', () => {
    renderAuthedPage(
      <SessionsPage
        sessions={[
          makeSession({
            id: 102,
            totalTokens: 0,
            inputTokens: 0,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            costCents: 0,
          }),
        ]}
        filters={{}}
        perPage={20}
      />,
      { props: { project } },
    );

    const row = screen.getByText('#102').closest('tr') as HTMLElement;
    // Both the token cell and the cost cell collapse to "—".
    expect(within(row).getAllByText('—').length).toBeGreaterThanOrEqual(2);
  });

  it('formats a non-zero cost as a dollar amount', () => {
    renderAuthedPage(
      <SessionsPage sessions={[makeSession({ id: 103, costCents: 1234 })]} filters={{}} perPage={20} />,
      { props: { project } },
    );

    const row = screen.getByText('#103').closest('tr') as HTMLElement;
    expect(within(row).getByText('$12.34')).toBeInTheDocument();
  });

  it('formats a sub-minute duration in seconds', () => {
    renderAuthedPage(
      <SessionsPage
        sessions={[
          makeSession({
            id: 104,
            state: 'finished',
            startedAt: '2026-06-20T10:00:00Z',
            finishedAt: '2026-06-20T10:00:42Z',
          }),
        ]}
        filters={{}}
        perPage={20}
      />,
      { props: { project } },
    );

    const row = screen.getByText('#104').closest('tr') as HTMLElement;
    expect(within(row).getByText('42s')).toBeInTheDocument();
  });

  it('formats a multi-minute duration as minutes and seconds', () => {
    renderAuthedPage(
      <SessionsPage
        sessions={[
          makeSession({
            id: 105,
            state: 'finished',
            startedAt: '2026-06-20T10:00:00Z',
            finishedAt: '2026-06-20T10:05:30Z',
          }),
        ]}
        filters={{}}
        perPage={20}
      />,
      { props: { project } },
    );

    const row = screen.getByText('#105').closest('tr') as HTMLElement;
    expect(within(row).getByText('5m 30s')).toBeInTheDocument();
  });

  it('renders an em-dash duration when the session never started', () => {
    renderAuthedPage(
      <SessionsPage
        sessions={[makeSession({ id: 106, state: 'not_started', startedAt: null, finishedAt: null })]}
        filters={{}}
        perPage={20}
      />,
      { props: { project } },
    );

    // The duration cell collapses to "—" with no startedAt; assert it appears in the row.
    const row = screen.getByText('#106').closest('tr') as HTMLElement;
    expect(within(row).getAllByText('—').length).toBeGreaterThanOrEqual(1);
  });

  // --- token-breakdown tooltip ---

  it('exposes a token breakdown tooltip built from the per-type token counts', async () => {
    renderAuthedPage(
      <SessionsPage
        sessions={[
          makeSession({
            id: 107,
            totalTokens: 9000,
            inputTokens: 5000,
            outputTokens: 4000,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
          }),
        ]}
        filters={{}}
        perPage={20}
      />,
      { props: { project } },
    );

    const row = screen.getByText('#107').closest('tr') as HTMLElement;
    // Hover the tokens cell to reveal the Mantine Tooltip with the in/out breakdown.
    await userEvent.hover(within(row).getByText('9.0k'));
    await waitFor(() => {
      expect(screen.getByText('in: 5.0k, out: 4.0k')).toBeInTheDocument();
    });
  });

  // --- filter reset ---

  it('clears stale session rows when the filter prop changes', async () => {
    const sessions1 = [makeSession({ id: 201, state: 'ready' }), makeSession({ id: 202, state: 'finished' })];
    const sessions2 = [makeSession({ id: 203, state: 'failed' })];

    const { rerender } = renderAuthedPage(<SessionsPage sessions={sessions1} filters={{}} perPage={20} />, {
      props: { project },
    });

    expect(screen.getByText('#201')).toBeInTheDocument();
    expect(screen.getByText('#202')).toBeInTheDocument();

    rerender(<SessionsPage sessions={sessions2} filters={{ state_eq: 'failed' }} perPage={20} />);

    await waitFor(() => {
      expect(screen.queryByText('#201')).not.toBeInTheDocument();
      expect(screen.queryByText('#202')).not.toBeInTheDocument();
      expect(screen.getByText('#203')).toBeInTheDocument();
    });
  });
});
