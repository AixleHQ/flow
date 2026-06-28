import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen } from 'test/renderPage';

import OverviewPage from './OverviewPage';

interface OverviewProps extends Record<string, unknown> {
  project: { id: number; name: string };
  summary: {
    sessionsLaunched: number;
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
    totalSpendCents: 5678,
    workflowsCount: 9,
    boardTasksCount: 17,
  },
  workflowRunStats: {
    completed: 8,
    inProgress: 2,
    failed: 1,
    queued: 3,
    total: 14,
  },
  boardTaskDistribution: {
    columns: [
      { name: 'Backlog', count: 5 },
      { name: 'Doing', count: 3 },
      { name: 'Shipped', count: 9 },
    ],
    total: 17,
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
  it('renders the page header and the project summary stats from seeded props', () => {
    renderAuthedPage(<OverviewPage />, { props: buildProps() });

    expect(screen.getByText('Project Overview')).toBeInTheDocument();
    expect(screen.getByText('Project activity at a glance')).toBeInTheDocument();

    // Stat labels
    expect(screen.getByText('Sessions Launched')).toBeInTheDocument();
    expect(screen.getByText('Board Tasks')).toBeInTheDocument();

    // Stat values: sessionsLaunched is localized, spend is formatted as dollars.
    expect(screen.getByText('1,234')).toBeInTheDocument();
    expect(screen.getByText('$56.78')).toBeInTheDocument();
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

  it('renders the workflow run breakdown with completed/total counts', () => {
    renderAuthedPage(<OverviewPage />, { props: buildProps() });

    expect(screen.getByText('Workflow Runs')).toBeInTheDocument();
    expect(screen.getByText('Completed')).toBeInTheDocument();
    expect(screen.getByText('In Progress')).toBeInTheDocument();
    expect(screen.getByText('Failed')).toBeInTheDocument();
    expect(screen.getByText('Queued')).toBeInTheDocument();
    // The "/ total" suffix appears once per row for total=14.
    expect(screen.getAllByText('/ 14')).toHaveLength(4);
  });

  it('renders the board task distribution columns and the total cell', () => {
    renderAuthedPage(<OverviewPage />, { props: buildProps() });

    const heading = screen.getByText('Board Task Distribution');
    expect(heading).toBeInTheDocument();

    expect(screen.getByText('Backlog')).toBeInTheDocument();
    expect(screen.getByText('Doing')).toBeInTheDocument();
    expect(screen.getByText('Shipped')).toBeInTheDocument();

    // The Total cell renders the board total and the literal "Total" label.
    expect(screen.getByText('Total')).toBeInTheDocument();
    // The total value (17) is rendered both as the "Board Tasks" stat and the
    // board total cell, so assert there are two occurrences rather than one.
    expect(screen.getAllByText('17').length).toBeGreaterThanOrEqual(2);
  });
});
