import '@testing-library/jest-dom/vitest';

import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent } from 'test/renderPage';

import AnalyticsPage from './AnalyticsPage';

const project = { id: 7, name: 'Quasar Initiative' };

const summary = {
  totalSessions: 1234,
  totalCostCents: 56789,
  totalTokens: 2_500_000,
  avgCostCentsPerSession: 46,
  workflowsRun: 42,
};

const workflowCosts = {
  workflows: [
    {
      workflowId: 1,
      workflowName: 'Nightly Triage',
      totalCostCents: 4500,
      inputTokens: 100000,
      outputTokens: 50000,
      totalTokens: 150000,
      runCount: 12,
      totalDurationSeconds: 720,
      avgDurationSeconds: 60,
    },
  ],
  timeSeries: [{ date: '2026-06-01', costCents: 4500, totalTokens: 150000 }],
  totals: {
    totalCostCents: 4500,
    inputTokens: 100000,
    outputTokens: 50000,
    totalTokens: 150000,
    workflowCount: 1,
    avgCostCentsPerWorkflow: 4500,
  },
};

const emptyWorkflowCosts = {
  workflows: [],
  timeSeries: [],
  totals: {
    totalCostCents: 0,
    inputTokens: 0,
    outputTokens: 0,
    totalTokens: 0,
    workflowCount: 0,
    avgCostCentsPerWorkflow: 0,
  },
};

const agentActivity = {
  agentTypes: ['planner', 'coder'],
  sessionsByAgent: [
    { agentType: 'planner', sessions: 120, costCents: 3400, tokens: 90000 },
    { agentType: 'coder', sessions: 80, costCents: 2100, tokens: 60000 },
  ],
  activityOverTime: [
    { date: '2026-06-01', agentType: 'planner', sessions: 5 },
    { date: '2026-06-02', agentType: 'coder', sessions: 3 },
  ],
};

const sources = {
  sources: [
    { sessionType: 'cli', label: 'Command Line', count: 300 },
    { sessionType: 'web', label: 'Web Dashboard', count: 150 },
  ],
};

const duration = {
  buckets: [
    { range: '0-1m', count: 40 },
    { range: '1-5m', count: 25 },
  ],
};

const costToken = {
  timeSeries: [
    { date: '2026-06-01', costCents: 1200, totalTokens: 80000 },
    { date: '2026-06-02', costCents: 800, totalTokens: 40000 },
  ],
  totals: { totalCostCents: 2000, totalTokens: 120000, avgCostCentsPerSession: 12 },
};

describe('Projects/Analytics/AnalyticsPage', () => {
  it('renders the heading and section landmarks for the seeded project', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { project, scope: 'project' as const, period: '30d' as const },
    });

    // The page title is a styled Text, not a semantic heading; the subtitle is unique copy.
    expect(screen.getByText('Analytics')).toBeInTheDocument();
    expect(screen.getByText('Agent activity, costs, and session insights')).toBeInTheDocument();
    expect(screen.getByText('Agent Activity')).toBeInTheDocument();
    expect(screen.getByText('Cost & Token Usage')).toBeInTheDocument();
    expect(screen.getByText('Workflow Costs')).toBeInTheDocument();
  });

  it('renders the summary stat values once the deferred summary prop is present', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { project, scope: 'project' as const, period: '30d' as const, summary },
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

  it('renders a populated workflow breakdown row when workflow data is present', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { project, scope: 'project' as const, period: '30d' as const, workflowCosts },
    });

    expect(screen.getByText('Workflow Breakdown')).toBeInTheDocument();
    expect(screen.getByText('Nightly Triage')).toBeInTheDocument();
    expect(screen.queryByText('No workflow runs in the selected period.')).not.toBeInTheDocument();
  });

  it('shows the empty workflow state when there are no workflow runs', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { project, scope: 'project' as const, period: '30d' as const, workflowCosts: emptyWorkflowCosts },
    });

    expect(screen.getByText('No workflow runs in the selected period.')).toBeInTheDocument();
  });

  it('navigates with updated filters when the scope segmented control is changed', async () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { project, scope: 'project' as const, period: '30d' as const },
    });

    // SegmentedControl renders radio inputs labeled by their option text.
    await userEvent.click(screen.getByText('My Activity'));

    expect(router.get).toHaveBeenCalledWith(
      window.location.pathname,
      { scope: 'user', period: '30d' },
      expect.objectContaining({ preserveState: true, preserveScroll: true }),
    );
  });

  it('navigates with the new period (keeping current scope) when the period Select is changed', async () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { project, scope: 'user' as const, period: '30d' as const },
    });

    // Mantine Select must be opened before its options can be clicked.
    await userEvent.click(screen.getByDisplayValue('Last 30 days'));
    await userEvent.click(await screen.findByText('Last 7 days'));

    expect(router.get).toHaveBeenCalledWith(
      window.location.pathname,
      { scope: 'user', period: '7d' },
      expect.objectContaining({ preserveState: true, preserveScroll: true }),
    );
  });

  it('renders the summary skeleton fallback while the summary prop is absent', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { project, scope: 'project' as const, period: '30d' as const },
    });

    // No summary prop seeded -> the deferred panel shows its skeleton, so the stat labels are absent.
    expect(screen.queryByText('Total Sessions')).not.toBeInTheDocument();
    expect(screen.queryByText('Workflows Run')).not.toBeInTheDocument();
  });

  it('formats large costs with a k suffix and zero tokens in the summary panel', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: {
        project,
        scope: 'project' as const,
        period: '30d' as const,
        summary: {
          totalSessions: 0,
          totalCostCents: 250000, // $2500 -> $2.5k
          totalTokens: 0, // -> '0'
          avgCostCentsPerSession: 0, // -> $0.00
          workflowsRun: 0,
        },
      },
    });

    expect(screen.getByText('$2.5k')).toBeInTheDocument();
    // 0 tokens renders as '0'; 0 sessions and 0 workflows both render as '0' too.
    expect(screen.getAllByText('0').length).toBeGreaterThan(0);
    expect(screen.getByText('$0.00')).toBeInTheDocument();
  });

  it('renders the agent activity panel with per-agent session rows and costs', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { project, scope: 'project' as const, period: '30d' as const, agentActivity },
    });

    expect(screen.getByText('Sessions per Agent — Trend')).toBeInTheDocument();
    expect(screen.getByText('Usage Breakdown by Agent Type')).toBeInTheDocument();
    expect(screen.getByText('planner')).toBeInTheDocument();
    expect(screen.getByText('coder')).toBeInTheDocument();
    expect(screen.getByText('120 sessions')).toBeInTheDocument();
    expect(screen.getByText('80 sessions')).toBeInTheDocument();
    // costCents 3400 -> $34.00
    expect(screen.getByText('$34.00')).toBeInTheDocument();
  });

  it('renders the cost & token usage panel headings when costToken data is present', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { project, scope: 'project' as const, period: '90d' as const, costToken },
    });

    expect(screen.getByText('Daily Cost')).toBeInTheDocument();
    expect(screen.getByText('Daily Token Consumption')).toBeInTheDocument();
  });

  it('renders the sources panel with per-origin labels and counts', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { project, scope: 'project' as const, period: '30d' as const, sources },
    });

    expect(screen.getByText('Sessions by Origin')).toBeInTheDocument();
    expect(screen.getByText('Command Line')).toBeInTheDocument();
    expect(screen.getByText('Web Dashboard')).toBeInTheDocument();
    expect(screen.getByText('300 sessions')).toBeInTheDocument();
    expect(screen.getByText('150 sessions')).toBeInTheDocument();
  });

  it('renders the session duration histogram heading when duration data is present', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { project, scope: 'project' as const, period: '30d' as const, duration },
    });

    expect(screen.getByText('Session Duration Histogram')).toBeInTheDocument();
  });

  it('renders workflow stat blocks and formats duration with an hours component', () => {
    const longRunningWorkflow = {
      workflows: [
        {
          workflowId: 9,
          workflowName: 'Marathon Pipeline',
          totalCostCents: 120000, // $1.2k in the per-workflow cost cell
          inputTokens: 1_200_000, // 1.2M
          outputTokens: 800_000, // 800.0k
          totalTokens: 2_000_000, // 2.0M
          runCount: 1,
          totalDurationSeconds: 7320, // 2h 2m
          avgDurationSeconds: 7320, // 2h 2m
        },
      ],
      timeSeries: [{ date: '2026-06-01', costCents: 120000, totalTokens: 2_000_000 }],
      totals: {
        totalCostCents: 120000,
        inputTokens: 1_200_000,
        outputTokens: 800_000,
        totalTokens: 2_000_000,
        workflowCount: 1,
        avgCostCentsPerWorkflow: 120000,
      },
    };

    renderAuthedPage(<AnalyticsPage />, {
      props: { project, scope: 'project' as const, period: '30d' as const, workflowCosts: longRunningWorkflow },
    });

    // Workflow stat-block labels.
    expect(screen.getByText('Avg Time / Workflow')).toBeInTheDocument();
    expect(screen.getByText('Avg Cost / Workflow')).toBeInTheDocument();
    // 'Input/Output Tokens' appear both as stat-block labels and as breakdown column headers.
    expect(screen.getAllByText('Input Tokens').length).toBeGreaterThanOrEqual(1);
    expect(screen.getAllByText('Output Tokens').length).toBeGreaterThanOrEqual(1);
    // 7320s -> formatDuration hours branch '2h 2m', shown in stat block + breakdown row avg/total.
    expect(screen.getAllByText('2h 2m').length).toBeGreaterThanOrEqual(1);
    // Breakdown row content.
    expect(screen.getByText('Marathon Pipeline')).toBeInTheDocument();
    // 800k output tokens render in both the stat block and the breakdown row cell.
    expect(screen.getAllByText('800.0k').length).toBeGreaterThanOrEqual(1);
  });

  it('renders the workflow skeleton fallback while workflowCosts is absent', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { project, scope: 'project' as const, period: '30d' as const },
    });

    // Section heading is always present, but the deferred panel body (and its breakdown) is not.
    expect(screen.getByText('Workflow Costs')).toBeInTheDocument();
    expect(screen.queryByText('Workflow Breakdown')).not.toBeInTheDocument();
  });
});
