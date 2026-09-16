import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { act, renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';

type CableHandlers = {
  connected: () => void;
  disconnected: () => void;
  received: (data: Record<string, unknown>) => void;
};
let lastCableHandlers: CableHandlers | null = null;
vi.mock('shared/lib/actionCableConsumer', () => ({
  getConsumer: () => ({
    subscriptions: {
      create: (_params: unknown, handlers: CableHandlers) => {
        lastCableHandlers = handlers;
        return { unsubscribe: vi.fn() };
      },
    },
  }),
}));

import SessionsIndex from './Index';

type SessionFixture = Parameters<typeof SessionsIndex>[0]['sessions'][number];
type PropsFixture = Parameters<typeof SessionsIndex>[0];

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
    costCents: 250,
    userId: 3,
    userName: 'Ada Lovelace',
    userEmail: 'ada@example.com',
    projectId: 9,
    projectName: 'Analytics Revamp',
    artifactsReviewed: null,
    pendingArtifactsCount: 0,
    initialPrompt: 'Refactor the onboarding status chips',
    viewable: true,
    ...overrides,
  };
}

function seed(overrides: Partial<PropsFixture> = {}): PropsFixture {
  return {
    sessions: [makeSession()],
    filters: { type: 'all' },
    total: 1,
    userOptions: [{ id: 3, name: 'Ada Lovelace' }],
    ...overrides,
  };
}

describe('Company/Sessions/Index', () => {
  beforeEach(() => {
    lastCableHandlers = null;
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('renders the Sessions & Runs heading, company subtitle and entry count', () => {
    renderAuthedPage(<SessionsIndex {...seed({ total: 4 })} />);

    expect(screen.getByRole('heading', { name: 'Sessions & Runs' })).toBeInTheDocument();
    expect(
      screen.getByText('Every agent session and workflow run across the company, in one place.'),
    ).toBeInTheDocument();
    expect(screen.getByText('4 entries')).toBeInTheDocument();
  });

  it('offers the three type tabs and navigates on selection', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<SessionsIndex {...seed()} />);

    expect(screen.getByRole('tab', { name: 'All' })).toHaveAttribute('aria-selected', 'true');
    await user.click(screen.getByRole('tab', { name: 'Workflow runs' }));

    expect(router.get).toHaveBeenCalledWith(
      '/company/sessions',
      { type: 'run' },
      expect.objectContaining({ preserveState: true, preserveScroll: true }),
    );
  });

  it('has no create actions', () => {
    renderAuthedPage(<SessionsIndex {...seed()} />);

    expect(screen.queryByRole('button', { name: /new session/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /run workflow/i })).not.toBeInTheDocument();
  });

  it('exposes only the shared status vocabulary in the Status filter', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<SessionsIndex {...seed()} />);

    await user.click(screen.getByPlaceholderText('Status'));
    expect(screen.getByRole('option', { name: 'Running' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Completed' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Failed' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Pending' })).toBeInTheDocument();
    expect(screen.queryByRole('option', { name: 'Starting' })).not.toBeInTheDocument();
    expect(screen.queryByRole('option', { name: 'Finishing' })).not.toBeInTheDocument();
  });

  it('debounces the search input and navigates with the term', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<SessionsIndex {...seed()} />);

    await user.type(screen.getByPlaceholderText('Search by name…'), 'billing');

    await waitFor(() =>
      expect(router.get).toHaveBeenCalledWith(
        '/company/sessions',
        expect.objectContaining({ search: 'billing' }),
        expect.anything(),
      ),
    );
  });

  it('navigates with the chosen agent and user filters', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<SessionsIndex {...seed()} />);

    await user.click(screen.getByPlaceholderText('Agent'));
    await user.click(await screen.findByRole('option', { name: 'Codex' }));
    expect(router.get).toHaveBeenCalledWith('/company/sessions', { agent_type: 'codex' }, expect.anything());

    await user.click(screen.getByPlaceholderText('User'));
    await user.click(await screen.findByRole('option', { name: 'Ada Lovelace' }));
    expect(router.get).toHaveBeenCalledWith('/company/sessions', { user_id: '3' }, expect.anything());
  });

  it('shows the no-sessions empty state, and a filtered one when filters are active', () => {
    const { rerender } = renderAuthedPage(<SessionsIndex {...seed({ sessions: [], total: 0 })} />);
    expect(screen.getByText('No sessions yet')).toBeInTheDocument();
    expect(screen.queryByRole('table')).not.toBeInTheDocument();

    rerender(<SessionsIndex {...seed({ sessions: [], total: 0, filters: { type: 'all', status: 'failed' } })} />);
    expect(screen.getByText('No sessions match these filters.')).toBeInTheDocument();
  });

  it('renders a row with a prompt-based name, #id · type sub-line, agent, user and project', () => {
    renderAuthedPage(
      <SessionsIndex
        {...seed({
          sessions: [
            makeSession({ id: 101, initialPrompt: 'Refactor onboarding chips', sessionType: 'agent_session' }),
            makeSession({
              id: 202,
              agentType: 'codex',
              state: 'failed',
              userName: 'Grace Hopper',
              projectName: 'Billing Service',
              sessionType: 'workflow_step',
              initialPrompt: null,
            }),
          ],
          total: 2,
        })}
      />,
    );

    const table = screen.getByRole('table');
    expect(within(table).getByText('Refactor onboarding chips')).toBeInTheDocument();
    expect(within(table).getByText(/#101.*Standalone session/)).toBeInTheDocument();
    // Promptless session falls back to the generic title, and a step reads "Workflow step".
    expect(within(table).getByText('Interactive session')).toBeInTheDocument();
    expect(within(table).getByText(/#202.*Workflow step/)).toBeInTheDocument();

    expect(within(table).getByText('Claude Code')).toBeInTheDocument();
    expect(within(table).getByText('Codex')).toBeInTheDocument();
    expect(within(table).getByText('Grace Hopper')).toBeInTheDocument();
    expect(within(table).getByText('Billing Service')).toBeInTheDocument();
  });

  it('links the owner name to their organization-visible profile', () => {
    renderAuthedPage(
      <SessionsIndex {...seed({ sessions: [makeSession({ id: 150, userId: 42, userName: 'Ada Lovelace' })] })} />,
    );

    expect(screen.getByRole('link', { name: 'Ada Lovelace' })).toHaveAttribute('href', '/user/42');
  });

  it('links openable rows to the company session show page but not pending ones', () => {
    renderAuthedPage(
      <SessionsIndex
        {...seed({
          sessions: [
            makeSession({ id: 301, state: 'ready' }),
            makeSession({ id: 302, state: 'finished', finishedAt: '2026-06-26T10:05:00Z' }),
            makeSession({ id: 303, state: 'not_started' }),
          ],
          total: 3,
        })}
      />,
    );

    const hrefs = screen
      .getAllByRole('link')
      .map((a) => a.getAttribute('href'))
      .filter((href) => href?.startsWith('/company/sessions/'));
    expect(hrefs).toContain('/company/sessions/301');
    expect(hrefs).toContain('/company/sessions/302');
    expect(hrefs).not.toContain('/company/sessions/303');
  });

  it('locks a private session: no open link, a lock icon, cost still shown', () => {
    renderAuthedPage(
      <SessionsIndex
        {...seed({
          sessions: [makeSession({ id: 401, viewable: false, state: 'ready', costCents: 1234, initialPrompt: null })],
        })}
      />,
    );

    expect(screen.queryByRole('link', { name: 'Open session #401' })).not.toBeInTheDocument();
    expect(screen.getByLabelText('Session #401 is private')).toBeInTheDocument();
    expect(within(screen.getByRole('table')).getByText('$12.34')).toBeInTheDocument();
  });

  it('formats tokens, cost and duration', () => {
    renderAuthedPage(
      <SessionsIndex
        {...seed({
          sessions: [
            makeSession({ id: 501, totalTokens: 2_500_000, costCents: 0 }),
            makeSession({
              id: 502,
              state: 'finished',
              startedAt: '2026-06-26T10:00:00Z',
              finishedAt: '2026-06-26T10:02:05Z',
            }),
          ],
          total: 2,
        })}
      />,
    );

    const table = screen.getByRole('table');
    expect(within(table).getByText('2.5M')).toBeInTheDocument();
    expect(within(table).getByText('2m 5s')).toBeInTheDocument();
    expect(within(table).getAllByText('—').length).toBeGreaterThan(0);
  });

  it('shows a pending-artifacts hint only for finished, unreviewed sessions with pending artifacts', () => {
    renderAuthedPage(
      <SessionsIndex
        {...seed({
          sessions: [
            makeSession({
              id: 601,
              state: 'finished',
              finishedAt: '2026-06-26T10:05:00Z',
              artifactsReviewed: false,
              pendingArtifactsCount: 3,
            }),
            makeSession({
              id: 602,
              state: 'finished',
              finishedAt: '2026-06-26T10:05:00Z',
              artifactsReviewed: true,
              pendingArtifactsCount: 5,
            }),
          ],
          total: 2,
        })}
      />,
    );

    const table = screen.getByRole('table');
    expect(within(table).getByText('3 pending')).toBeInTheDocument();
    expect(within(table).queryByText('5 pending')).not.toBeInTheDocument();
  });

  it('keeps accumulated pages when the sessions prop reverts to page 1 (poll survival)', () => {
    const s1 = makeSession({ id: 701, state: 'finished' });
    const s2 = makeSession({ id: 702, state: 'finished' });

    const { rerender } = renderAuthedPage(<SessionsIndex {...seed({ sessions: [s1, s2], total: 2 })} />);
    expect(screen.getByText(/#702/)).toBeInTheDocument();

    rerender(<SessionsIndex {...seed({ sessions: [s1], total: 2 })} />);
    expect(screen.getByText(/#701/)).toBeInTheDocument();
    expect(screen.getByText(/#702/)).toBeInTheDocument();
  });

  it('clears stale rows when the filter prop changes', async () => {
    const sessions1 = [makeSession({ id: 801, state: 'ready' }), makeSession({ id: 802, state: 'finished' })];
    const sessions2 = [makeSession({ id: 803, state: 'failed' })];

    const { rerender } = renderAuthedPage(<SessionsIndex {...seed({ sessions: sessions1, total: 2 })} />);
    expect(screen.getByText(/#801/)).toBeInTheDocument();

    rerender(
      <SessionsIndex {...seed({ sessions: sessions2, total: 1, filters: { type: 'all', status: 'failed' } })} />,
    );

    await waitFor(() => {
      expect(screen.queryByText(/#801/)).not.toBeInTheDocument();
      expect(screen.getByText(/#803/)).toBeInTheDocument();
    });
  });

  it('patches a session in place via a cable update without discarding accumulated pages', async () => {
    vi.useFakeTimers();
    const s1 = makeSession({ id: 901, state: 'ready' });
    const s2 = makeSession({ id: 902, state: 'finished' });

    renderAuthedPage(<SessionsIndex {...seed({ sessions: [s1, s2], total: 2 })} />);

    await act(async () => {
      vi.advanceTimersByTime(100);
    });
    expect(lastCableHandlers).not.toBeNull();

    await act(async () => {
      lastCableHandlers!.received({ type: 'session_update', session: { ...s1, state: 'finished' } });
    });

    expect(screen.getByText(/#901/)).toBeInTheDocument();
    expect(screen.getByText(/#902/)).toBeInTheDocument();
  });
});
