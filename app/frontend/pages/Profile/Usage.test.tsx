import '@testing-library/jest-dom/vitest';

import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import UsagePage from './Usage';

const targetUser = { id: 7, name: 'Maria Sokolova', email: 'maria@acme.test' };

const summary = {
  totalSessions: 1234,
  totalCostCents: 56789,
  totalTokens: 2_500_000,
  avgCostCentsPerSession: 46,
  workflowsRun: 42,
  projectBreakdowns: [
    { projectId: 11, projectName: 'Quasar Initiative', sessions: 800, costCents: 40000, tokens: 1_800_000 },
    { projectId: null, projectName: '(No project)', sessions: 434, costCents: 16789, tokens: 700_000 },
  ],
};

const agentActivity = {
  sessionsByAgent: [
    { agentType: 'claude_code', sessions: 320, costCents: 12000, tokens: 500_000 },
    { agentType: 'cursor_cli', sessions: 210, costCents: 9500, tokens: 410_000 },
  ],
};

const costToken = {
  timeSeries: [
    { date: '2026-06-01', costCents: 1200, totalTokens: 80_000 },
    { date: '2026-06-02', costCents: 1800, totalTokens: 95_000 },
  ],
};

const isoToday = new Date().toISOString().slice(0, 10);
const activityHeatmap = { days: [{ date: isoToday, count: 4 }] };

const sessions = [
  {
    id: 501,
    sessionType: 'agent_session',
    agentType: 'claude_code',
    state: 'finished',
    startedAt: '2026-06-01T10:00:00Z',
    finishedAt: '2026-06-01T10:05:00Z',
    createdAt: '2026-06-01T10:00:00Z',
    totalTokens: 12_000,
    costCents: 340,
    models: ['claude-sonnet'],
    projectName: 'Quasar Initiative',
  },
];

const selfProps = { period: '30d' as const, viewerIsSelf: true, targetUser };

describe('Profile/Usage', () => {
  it('renders summary stat values once the summary prop is present', () => {
    renderAuthedPage(<UsagePage />, { props: { ...selfProps, summary } });

    expect(screen.getByText('Total Sessions')).toBeInTheDocument();
    expect(screen.getByText('1,234')).toBeInTheDocument();
    expect(screen.getByText('$567.89')).toBeInTheDocument();
    expect(screen.getByText('2.5M')).toBeInTheDocument();
    expect(screen.getByText('Workflows Run')).toBeInTheDocument();
  });

  it('renders the per-project breakdown including a "(No project)" row without crashing', () => {
    renderAuthedPage(<UsagePage />, { props: { ...selfProps, summary } });

    expect(screen.getByText('Per-Project Breakdown')).toBeInTheDocument();
    expect(screen.getByText('Quasar Initiative')).toBeInTheDocument();
    expect(screen.getByText('(No project)')).toBeInTheDocument();
  });

  it('hides the breakdown panel when there are no project rows', () => {
    renderAuthedPage(<UsagePage />, {
      props: { ...selfProps, summary: { ...summary, projectBreakdowns: [] } },
    });
    expect(screen.getByText('Total Sessions')).toBeInTheDocument();
    expect(screen.queryByText('Per-Project Breakdown')).not.toBeInTheDocument();
  });

  it('renders the agent pie legend with sessions and formatted cost', () => {
    renderAuthedPage(<UsagePage />, { props: { ...selfProps, agentActivity } });

    expect(screen.getByText('Usage Breakdown by Agent Type')).toBeInTheDocument();
    const claude = screen.getByText('claude_code').closest('div')?.parentElement as HTMLElement;
    expect(within(claude).getByText('320 sessions')).toBeInTheDocument();
    expect(within(claude).getByText('$120.00')).toBeInTheDocument();
  });

  it('renders the contribution heatmap when activityHeatmap is present', () => {
    renderAuthedPage(<UsagePage />, { props: { ...selfProps, activityHeatmap } });

    const cells = screen.getAllByTestId('heatmap-cell');
    const seeded = cells.find((c) => c.getAttribute('data-date') === isoToday);
    expect(seeded?.getAttribute('data-count')).toBe('4');
  });

  it('renders both cost & token chart panels when costToken is present', () => {
    renderAuthedPage(<UsagePage />, { props: { ...selfProps, costToken } });

    expect(screen.getByText('Daily Cost')).toBeInTheDocument();
    expect(screen.getByText('Daily Token Consumption')).toBeInTheDocument();
  });

  it('renders the sessions table rows from the sessions prop', () => {
    renderAuthedPage(<UsagePage />, { props: { ...selfProps, sessions } });

    expect(screen.getByText('#501')).toBeInTheDocument();
    expect(screen.getByText('Quasar Initiative')).toBeInTheDocument();
    expect(screen.getByText('$3.40')).toBeInTheDocument();
  });

  it('renders a ready session with the Running label via StatusBadge migration', () => {
    const runningSessions = [{ ...sessions[0], id: 502, state: 'ready' as const, finishedAt: null }];
    renderAuthedPage(<UsagePage />, { props: { ...selfProps, sessions: runningSessions } });

    // State `ready` maps to "Running" in STATE_CONFIG; StatusBadge replaces raw Badge.
    expect(screen.getByText('Running')).toBeInTheDocument();
  });

  it('shows the cross-person banner when viewing another user', () => {
    renderAuthedPage(<UsagePage />, {
      props: { period: '30d' as const, viewerIsSelf: false, targetUser },
    });
    expect(screen.getByText(/Viewing Maria Sokolova's usage/)).toBeInTheDocument();
  });

  it('hides the banner for the self view', () => {
    renderAuthedPage(<UsagePage />, { props: selfProps });
    expect(screen.queryByText(/'s usage/)).not.toBeInTheDocument();
  });

  it('shows skeletons and no panels while deferred props are absent', () => {
    renderAuthedPage(<UsagePage />, { props: selfProps });
    expect(screen.queryByText('Total Sessions')).not.toBeInTheDocument();
    expect(screen.queryByText('Per-Project Breakdown')).not.toBeInTheDocument();
    expect(screen.queryByText('Usage Breakdown by Agent Type')).not.toBeInTheDocument();
    // Page chrome (outside Deferred) remains.
    expect(screen.getByRole('heading', { name: 'My Profile' })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: 'Usage' })).toBeInTheDocument();
  });

  it('navigates back to the Account tab when Account is clicked', async () => {
    renderAuthedPage(<UsagePage />, { props: selfProps });

    await userEvent.click(screen.getByRole('tab', { name: 'Account' }));
    expect(router.visit).toHaveBeenCalledWith('/profile');
  });

  it('navigates with the chosen period when the period select changes (self)', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<UsagePage />, { props: selfProps });

    const select = screen.getByDisplayValue('Last 30 days');
    await user.click(select);
    await user.click(await screen.findByText('Last 7 days'));

    expect(router.get).toHaveBeenCalledWith(
      window.location.pathname,
      { period: '7d' },
      { preserveState: true, preserveScroll: true },
    );
  });

  it('keeps the target user_id in the query when viewing another user', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<UsagePage />, {
      props: { period: '30d' as const, viewerIsSelf: false, targetUser },
    });

    const select = screen.getByDisplayValue('Last 30 days');
    await user.click(select);
    await user.click(await screen.findByText('Last 7 days'));

    expect(router.get).toHaveBeenCalledWith(
      window.location.pathname,
      { period: '7d', user_id: 7 },
      { preserveState: true, preserveScroll: true },
    );
  });
});
