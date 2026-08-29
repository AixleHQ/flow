import '@testing-library/jest-dom/vitest';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { act, renderAuthedPage, screen, userEvent } from 'test/renderPage';

import OverviewPage from './OverviewPage';

interface OverviewProps extends Record<string, unknown> {
  project: { id: number; name: string };
  summary: {
    sessionsLaunched: number;
    sessionsRunning: number;
    totalSpendCents: number;
    workflowsCount: number;
    boardTasksCount: number;
  };
  workflowRunStats: {
    completed: number;
    inProgress: number;
    failed: number;
    queued: number;
    total: number;
  };
  boardTaskDistribution: {
    columns: { name: string; count: number }[];
    total: number;
  };
  allBoardTaskDistribution: {
    columns: { name: string; count: number }[];
    total: number;
  };
  recentActivity: {
    eventType: string;
    description: string;
    actorName: string;
    occurredAt: string;
  }[];
}

const buildProps = (overrides: Partial<OverviewProps> = {}): OverviewProps => ({
  project: { id: 42, name: 'Falcon Initiative' },
  summary: {
    sessionsLaunched: 1234,
    sessionsRunning: 2,
    totalSpendCents: 5678,
    workflowsCount: 9,
    boardTasksCount: 17,
  },
  workflowRunStats: {
    completed: 25,
    inProgress: 6,
    failed: 4,
    queued: 10,
    total: 45,
  },
  boardTaskDistribution: {
    columns: [
      { name: 'Backlog', count: 12 },
      { name: 'Doing', count: 14 },
      { name: 'Shipped', count: 20 },
    ],
    total: 46,
  },
  allBoardTaskDistribution: {
    columns: [
      { name: 'Backlog', count: 15 },
      { name: 'Doing', count: 18 },
      { name: 'Shipped', count: 27 },
    ],
    total: 60,
  },
  recentActivity: [
    {
      eventType: 'workflow_completed',
      description: 'Render pipeline finished successfully',
      actorName: 'Ada Lovelace',
      occurredAt: new Date(Date.now() - 5 * 60 * 1000).toISOString(),
    },
    {
      eventType: 'task_created',
      description: 'Created task "Polish onboarding"',
      actorName: 'Grace Hopper',
      occurredAt: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(),
    },
  ],
  ...overrides,
});

describe('Projects/Overview/OverviewPage', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it('reloads both the default and all-task board distributions on the 60s poll', async () => {
    vi.useFakeTimers();
    renderAuthedPage(<OverviewPage />, { props: buildProps() });
    const { router } = await import('@inertiajs/react');

    await act(async () => {
      vi.advanceTimersByTime(60_000);
    });

    expect(vi.mocked(router.reload)).toHaveBeenCalledWith(
      expect.objectContaining({
        only: [
          'summary',
          'workflow_run_stats',
          'board_task_distribution',
          'all_board_task_distribution',
          'recent_activity',
        ],
      }),
    );
  });

  it('renders the page header and the KPI cards from seeded props', () => {
    renderAuthedPage(<OverviewPage />, { props: buildProps() });

    expect(screen.getByText('Project Overview')).toBeInTheDocument();
    expect(screen.getByText('Current and overall project activity')).toBeInTheDocument();

    // KPI labels
    expect(screen.getByText('Sessions Launched')).toBeInTheDocument();
    expect(screen.getByText('Total Spend')).toBeInTheDocument();
    expect(screen.getByText('Workflows')).toBeInTheDocument();
    expect(screen.getByText('Board Tasks')).toBeInTheDocument();

    // KPI values: sessionsLaunched is localized, spend is formatted as dollars.
    expect(screen.getByText('1,234')).toBeInTheDocument();
    expect(screen.getByText('$56.78')).toBeInTheDocument();
    expect(screen.getByText('9')).toBeInTheDocument();
    expect(screen.getByText('17')).toBeInTheDocument();

    // KPI deltas
    expect(screen.getByText(/2 running now/)).toBeInTheDocument();
    expect(screen.getByText('All active')).toBeInTheDocument();
  });

  it('shows the avg-per-session delta when sessions have been launched', () => {
    renderAuthedPage(<OverviewPage />, { props: buildProps() });
    expect(screen.getByText(/avg per session/)).toBeInTheDocument();
  });

  it('omits the avg-per-session delta when no sessions have launched', () => {
    renderAuthedPage(<OverviewPage />, {
      props: buildProps({ summary: { ...buildProps().summary, sessionsLaunched: 0, totalSpendCents: 0 } }),
    });
    expect(screen.queryByText(/avg per session/)).not.toBeInTheDocument();
  });

  it('lists recent activity items when there is activity', () => {
    renderAuthedPage(<OverviewPage />, { props: buildProps() });

    expect(screen.getByText('Recent Activity')).toBeInTheDocument();
    expect(screen.getByText('Render pipeline finished successfully')).toBeInTheDocument();
    expect(screen.getByText('Created task "Polish onboarding"')).toBeInTheDocument();
    expect(screen.queryByText('No recent activity found.')).not.toBeInTheDocument();
  });

  it('shows the empty state when there is no recent activity', () => {
    renderAuthedPage(<OverviewPage />, { props: buildProps({ recentActivity: [] }) });

    expect(screen.getByText('No recent activity found.')).toBeInTheDocument();
  });

  it('renders the workflow run donut with success rate, total and legend counts', () => {
    renderAuthedPage(<OverviewPage />, { props: buildProps() });

    expect(screen.getByText('Workflow Runs')).toBeInTheDocument();
    // completed=25, failed=4 -> success rate = round(25/29 * 100) = 86%.
    expect(screen.getByText('86%')).toBeInTheDocument();
    expect(screen.getByText('Success')).toBeInTheDocument();
    expect(screen.getByText('45')).toBeInTheDocument();
    expect(screen.getByText(/total runs/)).toBeInTheDocument();
    expect(screen.getByText(/4 failures need review/)).toBeInTheDocument();

    expect(screen.getByText('Completed')).toBeInTheDocument();
    expect(screen.getByText('In Progress')).toBeInTheDocument();
    expect(screen.getByText('Failed')).toBeInTheDocument();
    expect(screen.getByText('Queued')).toBeInTheDocument();
  });

  it('omits the failures-need-review note when there are no failures', () => {
    renderAuthedPage(<OverviewPage />, {
      props: buildProps({
        workflowRunStats: { completed: 8, inProgress: 2, failed: 0, queued: 3, total: 13 },
      }),
    });

    expect(screen.queryByText(/need review/)).not.toBeInTheDocument();
  });

  it("navigates to the project's workflow runs page from the Open Runs button", async () => {
    renderAuthedPage(<OverviewPage />, { props: buildProps() });
    const { router } = await import('@inertiajs/react');

    await userEvent.click(screen.getByRole('button', { name: /open runs/i }));

    expect(vi.mocked(router.visit)).toHaveBeenCalledWith('/company/projects/42/workflow_runs');
  });

  it('renders the board task distribution as a horizontal bar list', () => {
    renderAuthedPage(<OverviewPage />, { props: buildProps() });

    expect(screen.getByText('Board Task Distribution')).toBeInTheDocument();
    expect(screen.getByText('Backlog')).toBeInTheDocument();
    expect(screen.getByText('Doing')).toBeInTheDocument();
    expect(screen.getByText('Shipped')).toBeInTheDocument();
    expect(screen.getByText('12')).toBeInTheDocument();
    expect(screen.getByText('14')).toBeInTheDocument();
    expect(screen.getByText('20')).toBeInTheDocument();
    expect(screen.getByRole('switch', { name: 'Include archived' })).not.toBeChecked();
    expect(screen.queryByText('27')).not.toBeInTheDocument();
  });

  it('includes archived tasks when the distribution toggle is enabled', async () => {
    renderAuthedPage(<OverviewPage />, { props: buildProps() });

    await userEvent.click(screen.getByRole('switch', { name: 'Include archived' }));

    expect(screen.getByText('15')).toBeInTheDocument();
    expect(screen.getByText('18')).toBeInTheDocument();
    expect(screen.getByText('27')).toBeInTheDocument();
    expect(screen.queryByText('12')).not.toBeInTheDocument();
  });

  it("navigates to the project's board from the Open board button", async () => {
    renderAuthedPage(<OverviewPage />, { props: buildProps() });
    const { router } = await import('@inertiajs/react');

    await userEvent.click(screen.getByRole('button', { name: /open board/i }));

    expect(vi.mocked(router.visit)).toHaveBeenCalledWith('/company/projects/42/board');
  });
});
