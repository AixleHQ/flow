import '@testing-library/jest-dom/vitest';

import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import AnalyticsPage from './AnalyticsPage';

const summary = {
  totalSessions: 1234,
  totalCostCents: 56789,
  totalTokens: 2_500_000,
  avgCostCentsPerSession: 46,
  workflowsRun: 42,
  projectBreakdowns: [
    { projectId: 11, projectName: 'Quasar Initiative', sessions: 800, costCents: 40000, tokens: 1_800_000 },
    { projectId: 12, projectName: 'Helios Pipeline', sessions: 434, costCents: 16789, tokens: 700_000 },
  ],
};

const sources = {
  sources: [
    { sessionType: 'web', label: 'Web Console', count: 900 },
    { sessionType: 'api', label: 'API', count: 334 },
  ],
};

const agentActivity = {
  agentTypes: ['Planner', 'Coder'],
  sessionsByAgent: [
    { agentType: 'Planner', sessions: 320, costCents: 12000, tokens: 500_000 },
    { agentType: 'Coder', sessions: 210, costCents: 9500, tokens: 410_000 },
  ],
  activityOverTime: [
    { date: '2026-06-01', agentType: 'Planner', sessions: 40 },
    { date: '2026-06-01', agentType: 'Coder', sessions: 25 },
    { date: '2026-06-02', agentType: 'Planner', sessions: 55 },
  ],
};

const costToken = {
  timeSeries: [
    { date: 'Jun 1', costCents: 1200, totalTokens: 80_000 },
    { date: 'Jun 2', costCents: 1800, totalTokens: 95_000 },
  ],
  totals: { totalCostCents: 3000, totalTokens: 175_000, avgCostCentsPerSession: 50 },
};

describe('Company/Analytics/AnalyticsPage', () => {
  it('renders the heading and section landmarks for the seeded scope/period', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { scope: 'company' as const, period: '30d' as const },
    });

    // "Analytics" also appears in the sidebar nav, so the page title is not unique; assert the
    // unique subtitle copy and the section landmarks instead.
    expect(
      screen.getByText('Company-wide agent activity, costs, and session insights'),
    ).toBeInTheDocument();
    expect(screen.getByText('Projects Overview')).toBeInTheDocument();
    expect(screen.getByText('Agent Activity')).toBeInTheDocument();
    expect(screen.getByText('Cost & Token Usage')).toBeInTheDocument();
    expect(screen.getByText('Session Source Breakdown')).toBeInTheDocument();
  });

  it('renders the summary stat values once the deferred summary prop is present', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { scope: 'company' as const, period: '30d' as const, summary },
    });

    expect(screen.getByText('Total Sessions')).toBeInTheDocument();
    // 1234 -> toLocaleString()
    expect(screen.getByText('1,234')).toBeInTheDocument();
    // 56789 cents -> $567.89
    expect(screen.getByText('$567.89')).toBeInTheDocument();
    // 2,500,000 tokens -> 2.5M
    expect(screen.getByText('2.5M')).toBeInTheDocument();
    expect(screen.getByText('Workflows Run')).toBeInTheDocument();
  });

  it('renders the per-project breakdown rows when the summary carries project data', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { scope: 'company' as const, period: '30d' as const, summary },
    });

    expect(screen.getByText('Per-Project Breakdown')).toBeInTheDocument();
    expect(screen.getByText('Quasar Initiative')).toBeInTheDocument();
    expect(screen.getByText('Helios Pipeline')).toBeInTheDocument();
  });

  it('lists each session origin in the sources panel when sources are present', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { scope: 'company' as const, period: '30d' as const, sources },
    });

    const panel = screen.getByText('Sessions by Origin').closest('div') as HTMLElement;
    expect(within(panel).getByText('Web Console')).toBeInTheDocument();
    expect(within(panel).getByText('API')).toBeInTheDocument();
    expect(within(panel).getByText('900 sessions')).toBeInTheDocument();
  });

  it('shows fallback skeletons and no data panels while every deferred prop is absent', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { scope: 'company' as const, period: '30d' as const },
    });

    // None of the deferred panels' bodies should be present yet.
    expect(screen.queryByText('Total Sessions')).not.toBeInTheDocument();
    expect(screen.queryByText('Per-Project Breakdown')).not.toBeInTheDocument();
    expect(screen.queryByText('Sessions per Agent — Trend')).not.toBeInTheDocument();
    expect(screen.queryByText('Daily Cost')).not.toBeInTheDocument();
    expect(screen.queryByText('Sessions by Origin')).not.toBeInTheDocument();
    // The section headers (rendered outside Deferred) remain visible.
    expect(screen.getByText('Projects Overview')).toBeInTheDocument();
  });

  it('navigates with the seeded scope and the chosen period when the period select changes', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<AnalyticsPage />, {
      props: { scope: 'user' as const, period: '30d' as const },
    });

    // Mantine Select renders the current label; open it and pick a different period.
    const select = screen.getByDisplayValue('Last 30 days');
    await user.click(select);
    await user.click(await screen.findByText('Last 7 days'));

    expect(router.get).toHaveBeenCalledWith(
      window.location.pathname,
      { scope: 'user', period: '7d' },
      { preserveState: true, preserveScroll: true },
    );
  });

  it('formats large costs in thousands and tokens in thousands in the per-project rows', () => {
    const bigSummary = {
      ...summary,
      // 250_000 cents -> $2500 -> formatCostCents >= 1000 branch -> "$2.5k"
      totalCostCents: 250_000,
      projectBreakdowns: [
        { projectId: 21, projectName: 'Andromeda Build', sessions: 5000, costCents: 250_000, tokens: 1_500 },
      ],
    };

    renderAuthedPage(<AnalyticsPage />, {
      props: { scope: 'company' as const, period: '90d' as const, summary: bigSummary },
    });

    // Total Cost stat + per-project cost both render the thousands format.
    expect(screen.getAllByText('$2.5k').length).toBeGreaterThan(0);
    // 5000 sessions -> toLocaleString -> "5,000"
    expect(screen.getByText('5,000')).toBeInTheDocument();
    // 1_500 tokens -> formatTokens -> "1.5k"
    expect(screen.getByText('1.5k')).toBeInTheDocument();
  });

  it('hides the per-project breakdown panel when the summary has no project rows', () => {
    const noProjects = { ...summary, projectBreakdowns: [] };

    renderAuthedPage(<AnalyticsPage />, {
      props: { scope: 'company' as const, period: '30d' as const, summary: noProjects },
    });

    // Summary stats still render, but the breakdown panel returns null.
    expect(screen.getByText('Total Sessions')).toBeInTheDocument();
    expect(screen.queryByText('Per-Project Breakdown')).not.toBeInTheDocument();
  });

  it('renders the agent activity legend with sessions and formatted cost per agent type', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { scope: 'company' as const, period: '30d' as const, agentActivity },
    });

    expect(screen.getByText('Sessions per Agent — Trend')).toBeInTheDocument();
    expect(screen.getByText('Usage Breakdown by Agent Type')).toBeInTheDocument();

    const planner = screen.getByText('Planner').closest('div')?.parentElement as HTMLElement;
    expect(within(planner).getByText('320 sessions')).toBeInTheDocument();
    // 12000 cents -> $120.00
    expect(within(planner).getByText('$120.00')).toBeInTheDocument();
    // Coder row
    expect(screen.getByText('Coder')).toBeInTheDocument();
    expect(screen.getByText('210 sessions')).toBeInTheDocument();
  });

  it('renders both cost-and-token chart panels when costToken data is present', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { scope: 'company' as const, period: '7d' as const, costToken },
    });

    expect(screen.getByText('Daily Cost')).toBeInTheDocument();
    expect(screen.getByText('Daily Token Consumption')).toBeInTheDocument();
  });

  it('renders the zero token format when total tokens is zero', () => {
    const zeroSummary = { ...summary, totalTokens: 0 };

    renderAuthedPage(<AnalyticsPage />, {
      props: { scope: 'company' as const, period: '30d' as const, summary: zeroSummary },
    });

    expect(screen.getByText('Total Tokens')).toBeInTheDocument();
    // formatTokens(0) -> "0"
    expect(screen.getByText('0')).toBeInTheDocument();
  });
});
