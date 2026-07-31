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

const workflowCosts = {
  timeSeries: [{ date: '2026-06-01', costCents: 900, totalTokens: 60_000 }],
};

const emptyWorkflowCosts = {
  timeSeries: [] as { date: string; costCents: number; totalTokens: number }[],
};

describe('Company/Analytics/AnalyticsPage', () => {
  it('renders the heading and section landmarks for the seeded scope/period', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { scope: 'company' as const, period: '30d' as const },
    });

    // "Analytics" also appears in the sidebar nav, so the page title is not unique; assert the
    // unique subtitle copy and the section landmarks instead.
    expect(screen.getByText('Company-wide agent activity, costs, and session insights')).toBeInTheDocument();
    expect(screen.getByText('Projects Overview')).toBeInTheDocument();
    expect(screen.getByText('Agent activity')).toBeInTheDocument();
    expect(screen.getByText('Cost & token usage')).toBeInTheDocument();
    expect(screen.getByText('Session insights')).toBeInTheDocument();
    expect(screen.getByText('Company')).toBeInTheDocument();
    expect(screen.getByText('My activity')).toBeInTheDocument();
  });

  it('shows the personal subtitle when scope is user', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { scope: 'user' as const, period: '30d' as const },
    });

    expect(screen.getByText('Your agent activity, costs, and session insights across the company')).toBeInTheDocument();
  });

  it('navigates with updated filters when the scope segmented control is changed', async () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { scope: 'company' as const, period: '30d' as const },
    });

    await userEvent.click(screen.getByText('My activity'));

    expect(router.get).toHaveBeenCalledWith(
      window.location.pathname,
      { scope: 'user', period: '30d' },
      { preserveState: true, preserveScroll: true },
    );
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

  it('lists each session origin in the sources panel as a donut with a center share and percentages', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { scope: 'company' as const, period: '30d' as const, sources },
    });

    const panel = screen.getByText('Sessions by origin').closest('div') as HTMLElement;
    // "Web Console" is the dominant source, so it renders both as the donut center label and the legend row name.
    expect(within(panel).getAllByText('Web Console')).toHaveLength(2);
    expect(within(panel).getByText('API')).toBeInTheDocument();
    expect(within(panel).getByText('900 sessions')).toBeInTheDocument();
    // 900 of 1234 -> 73% (donut center + legend row); 334 of 1234 -> 27% (legend row only).
    expect(within(panel).getAllByText('73%')).toHaveLength(2);
    expect(within(panel).getByText('27%')).toBeInTheDocument();
  });

  it('shows fallback skeletons and no data panels while every deferred prop is absent', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { scope: 'company' as const, period: '30d' as const },
    });

    // None of the deferred panels' bodies should be present yet.
    expect(screen.queryByText('Total Sessions')).not.toBeInTheDocument();
    expect(screen.queryByText('Per-Project Breakdown')).not.toBeInTheDocument();
    expect(screen.queryByText('Sessions per agent — trend')).not.toBeInTheDocument();
    expect(screen.queryByText('Daily cost')).not.toBeInTheDocument();
    expect(screen.queryByText('Sessions by origin')).not.toBeInTheDocument();
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

    expect(screen.getByText('Sessions per agent — trend')).toBeInTheDocument();
    expect(screen.getByText('Usage breakdown by agent type')).toBeInTheDocument();

    // "Planner"/"Coder" also render in the trend-chart legend, so scope to the breakdown panel.
    const breakdownPanel = screen.getByText('Usage breakdown by agent type').closest('div') as HTMLElement;
    const planner = within(breakdownPanel).getByText('Planner').closest('div')?.parentElement as HTMLElement;
    // 320 of 530 total -> 60%.
    expect(within(planner).getByText('320 sessions · 60%')).toBeInTheDocument();
    // 12000 cents -> $120.00
    expect(within(planner).getByText('$120.00')).toBeInTheDocument();
    // Coder row: 210 of 530 total -> 40%.
    expect(within(breakdownPanel).getByText('Coder')).toBeInTheDocument();
    expect(within(breakdownPanel).getByText('210 sessions · 40%')).toBeInTheDocument();
    // Donut center shows the total across all agents.
    expect(within(breakdownPanel).getByText('530')).toBeInTheDocument();
    expect(within(breakdownPanel).getByText('sessions')).toBeInTheDocument();
  });

  it('renders both cost-and-token chart panels and default scope badges when costToken data is present', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: {
        scope: 'company' as const,
        period: '7d' as const,
        costToken,
        workflowCosts: emptyWorkflowCosts,
      },
    });

    expect(screen.getByText('Daily cost')).toBeInTheDocument();
    expect(screen.getByText('Daily token consumption')).toBeInTheDocument();
    // Segmented control option + two card corner badges default to "All sessions".
    expect(screen.getAllByText('All sessions').length).toBeGreaterThanOrEqual(2);
    expect(screen.getByTestId('daily-cost-panel')).toHaveAttribute('data-first-cost-cents', '1200');
  });

  it('switches the cost & token charts and corner badges to workflows-only when toggled', async () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { scope: 'company' as const, period: '7d' as const, costToken, workflowCosts },
    });

    expect(screen.getByTestId('daily-cost-panel')).toHaveAttribute('data-first-cost-cents', '1200');

    await userEvent.click(screen.getByText('Workflows only'));

    // Segmented control keeps both option labels mounted for its animated indicator,
    // so only the two card corner badges are new "Workflows only" occurrences.
    expect(screen.getAllByText('Workflows only').length).toBeGreaterThanOrEqual(2);
    expect(screen.getByTestId('daily-cost-panel')).toHaveAttribute('data-first-cost-cents', '900');
  });

  it('renders agent logos for known production agent types', () => {
    const productionAgents = {
      agentTypes: ['claude_code', 'codex', 'gemini_cli'],
      sessionsByAgent: [
        { agentType: 'claude_code', sessions: 10, costCents: 500, tokens: 20_000 },
        { agentType: 'codex', sessions: 5, costCents: 250, tokens: 10_000 },
        { agentType: 'gemini_cli', sessions: 2, costCents: 100, tokens: 4_000 },
      ],
      activityOverTime: [{ date: '2026-06-01', agentType: 'claude_code', sessions: 10 }],
    };

    renderAuthedPage(<AnalyticsPage />, {
      props: { scope: 'company' as const, period: '30d' as const, agentActivity: productionAgents },
    });

    expect(screen.getAllByTestId('agent-logo').length).toBeGreaterThanOrEqual(3);
    const breakdownPanel = screen.getByText('Usage breakdown by agent type').closest('div') as HTMLElement;
    expect(within(breakdownPanel).getByText('claude_code')).toBeInTheDocument();
    expect(within(breakdownPanel).getByText('codex')).toBeInTheDocument();
    expect(within(breakdownPanel).getByText('gemini_cli')).toBeInTheDocument();
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
