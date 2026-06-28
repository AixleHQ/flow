import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import SessionsIndex from './Index';

type SessionFixture = Parameters<typeof SessionsIndex>[0]['sessions'][number];

function makeSession(overrides: Partial<SessionFixture> = {}): SessionFixture {
  return {
    id: 101,
    sessionType: 'agent_session',
    agentType: 'claude_code',
    state: 'ready',
    mode: null,
    startedAt: '2026-06-26T10:00:00Z',
    finishedAt: null,
    createdAt: '2026-06-26T09:59:00Z',
    totalTokens: 12000,
    inputTokens: 8000,
    outputTokens: 4000,
    cacheReadTokens: 0,
    cacheWriteTokens: 0,
    costCents: 250,
    models: ['sonnet-4'],
    userName: 'Ada Lovelace',
    userEmail: 'ada@example.com',
    projectName: 'Analytics Revamp',
    artifactsReviewed: null,
    pendingArtifactsCount: 0,
    initialPrompt: null,
    ...overrides,
  };
}

describe('Company/Sessions/Index', () => {
  it('renders the page heading and subtitle when sessions exist', () => {
    renderAuthedPage(<SessionsIndex sessions={[makeSession()]} filters={{}} perPage={20} />);

    // 'Sessions' also appears in the layout sidebar nav, so scope by the unique subtitle.
    const subtitle = screen.getByText('Agent session history across the company');
    expect(subtitle).toBeInTheDocument();
    expect(screen.getAllByText('Sessions').length).toBeGreaterThan(0);
  });

  it('shows the no-sessions empty state when the list is empty and no filters are applied', () => {
    renderAuthedPage(<SessionsIndex sessions={[]} filters={{}} perPage={20} />);

    expect(screen.getByText('No sessions yet')).toBeInTheDocument();
    expect(screen.queryByRole('table')).not.toBeInTheDocument();
  });

  it('shows the filtered empty state when the list is empty but filters are active', () => {
    renderAuthedPage(<SessionsIndex sessions={[]} filters={{ state_eq: 'failed' }} perPage={20} />);

    expect(screen.getByText('No sessions match filters')).toBeInTheDocument();
    expect(screen.queryByText('No sessions yet')).not.toBeInTheDocument();
  });

  it('renders a row per session with agent label, derived status, user and project', () => {
    renderAuthedPage(
      <SessionsIndex
        sessions={[
          makeSession({ id: 101, agentType: 'claude_code', state: 'ready', userName: 'Ada Lovelace' }),
          makeSession({
            id: 202,
            agentType: 'codex',
            state: 'failed',
            userName: 'Grace Hopper',
            projectName: 'Billing Service',
            models: ['gpt-5'],
          }),
        ]}
        filters={{}}
        perPage={20}
      />,
    );

    const table = screen.getByRole('table');

    // IDs rendered with a leading '#'.
    expect(within(table).getByText('#101')).toBeInTheDocument();
    expect(within(table).getByText('#202')).toBeInTheDocument();

    // Agent labels mapped from agentType.
    expect(within(table).getByText('Claude Code')).toBeInTheDocument();
    expect(within(table).getByText('Codex')).toBeInTheDocument();

    // State labels are derived from STATE_CONFIG (ready -> Running, failed -> Failed).
    expect(within(table).getByText('Running')).toBeInTheDocument();
    expect(within(table).getByText('Failed')).toBeInTheDocument();

    // User + project values surfaced.
    expect(within(table).getByText('Ada Lovelace')).toBeInTheDocument();
    expect(within(table).getByText('Grace Hopper')).toBeInTheDocument();
    expect(within(table).getByText('Billing Service')).toBeInTheDocument();
  });

  it('exposes an external open link only for sessions in the ready state', () => {
    renderAuthedPage(
      <SessionsIndex
        sessions={[
          makeSession({ id: 301, state: 'ready' }),
          makeSession({ id: 302, state: 'finished', finishedAt: '2026-06-26T10:05:00Z' }),
        ]}
        filters={{}}
        perPage={20}
      />,
    );

    // Only the ready session (#301) gets the "Open session" tooltip link to its show page.
    const openLinks = screen.getAllByRole('link', { name: '' }).filter((a) => a.getAttribute('target') === '_blank');
    const hrefs = openLinks.map((a) => a.getAttribute('href'));
    expect(hrefs).toContain('/company/sessions/301');
    expect(hrefs).not.toContain('/company/sessions/302');
  });

  it('formats large token counts with k/M suffixes and a dash for zero', () => {
    renderAuthedPage(
      <SessionsIndex
        sessions={[
          makeSession({ id: 401, totalTokens: 12000 }), // 12.0k
          makeSession({ id: 402, totalTokens: 2_500_000 }), // 2.5M
          makeSession({ id: 403, totalTokens: 0, inputTokens: 0, outputTokens: 0, costCents: 0 }),
        ]}
        filters={{}}
        perPage={20}
      />,
    );

    const table = screen.getByRole('table');
    expect(within(table).getByText('12.0k')).toBeInTheDocument();
    expect(within(table).getByText('2.5M')).toBeInTheDocument();
    // The zero-token / zero-cost row renders dashes for both totals and cost.
    expect(within(table).getAllByText('—').length).toBeGreaterThan(0);
  });

  it('formats cost in dollars and dashes a zero cost', () => {
    renderAuthedPage(
      <SessionsIndex sessions={[makeSession({ id: 501, costCents: 1234 })]} filters={{}} perPage={20} />,
    );

    expect(within(screen.getByRole('table')).getByText('$12.34')).toBeInTheDocument();
  });

  it('renders a finished session duration computed from started and finished timestamps', () => {
    renderAuthedPage(
      <SessionsIndex
        sessions={[
          makeSession({
            id: 601,
            state: 'finished',
            startedAt: '2026-06-26T10:00:00Z',
            finishedAt: '2026-06-26T10:02:05Z',
          }),
        ]}
        filters={{}}
        perPage={20}
      />,
    );

    // 125 seconds -> "2m 5s".
    expect(within(screen.getByRole('table')).getByText('2m 5s')).toBeInTheDocument();
  });

  it('maps session type values to friendly labels and falls back to the raw value', () => {
    renderAuthedPage(
      <SessionsIndex
        sessions={[
          makeSession({ id: 701, sessionType: 'workflow_step' }),
          makeSession({ id: 702, sessionType: 'auth_setup' }),
          makeSession({ id: 703, sessionType: 'something_custom' }),
        ]}
        filters={{}}
        perPage={20}
      />,
    );

    const table = screen.getByRole('table');
    expect(within(table).getByText('Workflow step')).toBeInTheDocument();
    expect(within(table).getByText('Auth setup')).toBeInTheDocument();
    // Unknown session types fall through to the raw string.
    expect(within(table).getByText('something_custom')).toBeInTheDocument();
  });

  it('falls back to the raw agent and state values when they are not in the config maps', () => {
    renderAuthedPage(
      <SessionsIndex
        sessions={[makeSession({ id: 801, agentType: 'mystery_agent', state: 'paused' })]}
        filters={{}}
        perPage={20}
      />,
    );

    const table = screen.getByRole('table');
    expect(within(table).getByText('mystery_agent')).toBeInTheDocument();
    expect(within(table).getByText('paused')).toBeInTheDocument();
  });

  it('renders a dash for a missing user name', () => {
    renderAuthedPage(
      <SessionsIndex
        sessions={[makeSession({ id: 901, userName: null, userEmail: null, projectName: null })]}
        filters={{}}
        perPage={20}
      />,
    );

    // userName, projectName and the (lack of) duration each render '—'.
    expect(within(screen.getByRole('table')).getAllByText('—').length).toBeGreaterThan(0);
  });

  it('shows a pending-artifacts badge only for finished, unreviewed sessions with pending artifacts', () => {
    renderAuthedPage(
      <SessionsIndex
        sessions={[
          makeSession({
            id: 1001,
            state: 'finished',
            finishedAt: '2026-06-26T10:05:00Z',
            artifactsReviewed: false,
            pendingArtifactsCount: 3,
          }),
          makeSession({
            id: 1002,
            state: 'finished',
            finishedAt: '2026-06-26T10:05:00Z',
            artifactsReviewed: true,
            pendingArtifactsCount: 5,
          }),
        ]}
        filters={{}}
        perPage={20}
      />,
    );

    const table = screen.getByRole('table');
    // Only the unreviewed session surfaces the pending count badge.
    expect(within(table).getByText('3 pending')).toBeInTheDocument();
    expect(within(table).queryByText('5 pending')).not.toBeInTheDocument();
  });

  it('renders one badge per model on a session', () => {
    renderAuthedPage(
      <SessionsIndex sessions={[makeSession({ id: 1101, models: ['opus-4', 'haiku-3'] })]} filters={{}} perPage={20} />,
    );

    const table = screen.getByRole('table');
    expect(within(table).getByText('opus-4')).toBeInTheDocument();
    expect(within(table).getByText('haiku-3')).toBeInTheDocument();
  });

  it('reflects the active filter values in the agent and status selects', () => {
    renderAuthedPage(
      <SessionsIndex
        sessions={[makeSession()]}
        filters={{ agent_type_eq: 'cursor_cli', state_eq: 'failed' }}
        perPage={50}
      />,
    );

    // The visible Select inputs surface the human label of the seeded filter values.
    expect(screen.getByPlaceholderText('Agent')).toHaveValue('Cursor CLI');
    expect(screen.getByPlaceholderText('Status')).toHaveValue('Failed');
    // Per-page select (the only combobox without a placeholder) reflects 50.
    const perPageInput = screen.getAllByRole('combobox').find((el) => !el.getAttribute('placeholder'));
    expect(perPageInput).toHaveValue('50');
  });

  it('navigates with the chosen agent filter when an agent option is selected', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<SessionsIndex sessions={[makeSession()]} filters={{}} perPage={20} />);

    const agentSelect = screen.getByPlaceholderText('Agent');
    await user.click(agentSelect);
    await user.click(await screen.findByRole('option', { name: 'Codex' }));

    expect(router.get).toHaveBeenCalledWith(
      '/company/sessions',
      { q: { agent_type_eq: 'codex' } },
      expect.objectContaining({ preserveState: true, preserveScroll: true }),
    );
  });

  it('navigates with per_page included when a non-default page size is selected', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<SessionsIndex sessions={[makeSession()]} filters={{ state_eq: 'ready' }} perPage={20} />);

    // The per-page select is the only combobox without a placeholder.
    const perPageSelect = screen.getAllByRole('combobox').find((el) => !el.getAttribute('placeholder'));
    expect(perPageSelect).toBeDefined();
    await user.click(perPageSelect as HTMLElement);
    await user.click(await screen.findByRole('option', { name: '100' }));

    expect(router.get).toHaveBeenCalledWith(
      '/company/sessions',
      { q: { state_eq: 'ready' }, per_page: 100 },
      expect.objectContaining({ preserveState: true, preserveScroll: true }),
    );
  });
});
