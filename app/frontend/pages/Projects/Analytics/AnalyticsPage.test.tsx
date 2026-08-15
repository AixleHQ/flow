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
    expect(screen.getByText('Agent activity')).toBeInTheDocument();
    expect(screen.getByText('Cost & token usage')).toBeInTheDocument();
    expect(screen.getByText('Workflow costs')).toBeInTheDocument();
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

    expect(screen.getByText('Sessions per agent — trend')).toBeInTheDocument();
    expect(screen.getByText('Usage breakdown by agent type')).toBeInTheDocument();
    // "planner"/"coder" render in both the trend-chart legend and the breakdown legend.
    expect(screen.getAllByText('planner')).toHaveLength(2);
    expect(screen.getAllByText('coder')).toHaveLength(2);
    // 120 of 200 total -> 60%; 80 of 200 -> 40%.
    expect(screen.getByText('120 sessions · 60%')).toBeInTheDocument();
    expect(screen.getByText('80 sessions · 40%')).toBeInTheDocument();
    // costCents 3400 -> $34.00
    expect(screen.getByText('$34.00')).toBeInTheDocument();
    // Donut center shows the total across all agents.
    expect(screen.getByText('200')).toBeInTheDocument();
    expect(screen.getByText('sessions')).toBeInTheDocument();
  });

  it('renders the cost & token usage panel headings and default scope badges when costToken data is present', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: {
        project,
        scope: 'project' as const,
        period: '90d' as const,
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
      props: { project, scope: 'project' as const, period: '90d' as const, costToken, workflowCosts },
    });

    expect(screen.getByTestId('daily-cost-panel')).toHaveAttribute('data-first-cost-cents', '1200');

    await userEvent.click(screen.getByText('Workflows only'));

    // Segmented control keeps both option labels mounted for its animated indicator,
    // so only the two card corner badges are new "Workflows only" occurrences.
    expect(screen.getAllByText('Workflows only').length).toBeGreaterThanOrEqual(2);
    expect(screen.getByTestId('daily-cost-panel')).toHaveAttribute('data-first-cost-cents', '4500');
  });

  it('renders the sources panel as a donut with a center share, per-origin labels/counts, and percentages', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { project, scope: 'project' as const, period: '30d' as const, sources },
    });

    expect(screen.getByText('Sessions by origin')).toBeInTheDocument();
    // "Command Line" is the dominant source, so it renders both as the donut center label and the legend row name.
    expect(screen.getAllByText('Command Line')).toHaveLength(2);
    expect(screen.getByText('Web Dashboard')).toBeInTheDocument();
    expect(screen.getByText('300 sessions')).toBeInTheDocument();
    expect(screen.getByText('150 sessions')).toBeInTheDocument();
    // 300 of 450 -> 67% (donut center + legend row); 150 of 450 -> 33% (legend row only).
    expect(screen.getAllByText('67%')).toHaveLength(2);
    expect(screen.getByText('33%')).toBeInTheDocument();
  });

  it('renders the session duration histogram heading when duration data is present', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { project, scope: 'project' as const, period: '30d' as const, duration },
    });

    expect(screen.getByText('Session duration distribution')).toBeInTheDocument();
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
    expect(screen.getByText('Workflow costs')).toBeInTheDocument();
    expect(screen.queryByText('Workflow Breakdown')).not.toBeInTheDocument();
  });

  it('renders the contribution heatmap when activityHeatmap is present', () => {
    const isoToday = new Date().toISOString().slice(0, 10);
    renderAuthedPage(<AnalyticsPage />, {
      props: {
        project,
        scope: 'project' as const,
        period: '30d' as const,
        activityHeatmap: { days: [{ date: isoToday, count: 6 }] },
      },
    });

    const cells = screen.getAllByTestId('heatmap-cell');
    const seeded = cells.find((c) => c.getAttribute('data-date') === isoToday);
    expect(seeded?.getAttribute('data-count')).toBe('6');
  });

  it('renders a participant select and navigates with participant_id when a participant is chosen', async () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: {
        project,
        scope: 'project' as const,
        period: '30d' as const,
        participants: [
          { id: 3, name: 'Alice', email: 'alice@acme.test' },
          { id: 4, name: 'Bob', email: 'bob@acme.test' },
        ],
      },
    });

    // The scope SegmentedControl remains (protects the "My Activity" AC).
    expect(screen.getByText('My Activity')).toBeInTheDocument();

    const participantSelect = screen.getByPlaceholderText('All participants');
    await userEvent.click(participantSelect);
    await userEvent.click(await screen.findByText('Alice'));

    expect(router.get).toHaveBeenCalledWith(
      window.location.pathname,
      { scope: 'project', period: '30d', participant_id: '3' },
      expect.objectContaining({ preserveState: true, preserveScroll: true }),
    );
  });

  it('renders the merged Session insights section with both origin and duration panels', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { project, scope: 'project' as const, period: '30d' as const, sources, duration },
    });

    expect(screen.getByText('Session insights')).toBeInTheDocument();
    expect(screen.getByText('Sessions by origin')).toBeInTheDocument();
    expect(screen.getByText('Session duration distribution')).toBeInTheDocument();
  });

  it('renders an agent logo chip alongside each agent label in the legend', () => {
    renderAuthedPage(<AnalyticsPage />, {
      props: { project, scope: 'project' as const, period: '30d' as const, agentActivity },
    });

    // One chip per agent in the trend-chart legend, plus one per agent in the breakdown legend.
    expect(screen.getAllByTestId('agent-logo')).toHaveLength(
      agentActivity.agentTypes.length + agentActivity.sessionsByAgent.length,
    );
    expect(screen.getAllByText('planner')).toHaveLength(2);
    expect(screen.getAllByText('coder')).toHaveLength(2);
  });

  it('renders agent logos for known production agent types', () => {
    const productionAgents = {
      agentTypes: ['claude_code', 'codex', 'gemini_cli', 'grok'],
      sessionsByAgent: [
        { agentType: 'claude_code', sessions: 10, costCents: 500, tokens: 20_000 },
        { agentType: 'codex', sessions: 5, costCents: 250, tokens: 10_000 },
        { agentType: 'gemini_cli', sessions: 2, costCents: 100, tokens: 4_000 },
        // No xAI artwork ships in this repo, so Grok renders the neutral colour chip
        // the logo lookup falls back to — still a chip, still labelled.
        { agentType: 'grok', sessions: 1, costCents: 50, tokens: 2_000 },
      ],
      activityOverTime: [{ date: '2026-06-01', agentType: 'claude_code', sessions: 10 }],
    };

    renderAuthedPage(<AnalyticsPage />, {
      props: { project, scope: 'project' as const, period: '30d' as const, agentActivity: productionAgents },
    });

    expect(screen.getAllByTestId('agent-logo').length).toBeGreaterThanOrEqual(3);
    const breakdownPanel = screen.getByText('Usage breakdown by agent type').closest('div') as HTMLElement;
    expect(breakdownPanel).toHaveTextContent('claude_code');
    expect(breakdownPanel).toHaveTextContent('codex');
    expect(breakdownPanel).toHaveTextContent('gemini_cli');
    expect(breakdownPanel).toHaveTextContent('grok');
  });
});
