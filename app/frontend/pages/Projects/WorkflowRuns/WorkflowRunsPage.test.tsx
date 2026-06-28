import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import WorkflowRunsPage from './WorkflowRunsPage';

const project = { id: 7, name: 'Apollo' };

type WorkflowRun = Parameters<typeof WorkflowRunsPage>[0]['runs'][number];

function makeRun(overrides: Partial<WorkflowRun> = {}): WorkflowRun {
  return {
    id: 101,
    workflowId: 1,
    workflowName: 'Deploy Workflow',
    state: 'completed',
    mode: 'interactive',
    stepsCompleted: 3,
    stepsTotal: 3,
    startedAt: '2026-06-26T10:00:00Z',
    completedAt: '2026-06-26T10:01:30Z',
    createdAt: '2026-06-26T10:00:00Z',
    ...overrides,
  };
}

describe('Projects/WorkflowRuns/WorkflowRunsPage', () => {
  it('shows the empty state when there are no runs and no filters', () => {
    renderAuthedPage(<WorkflowRunsPage runs={[]} filters={{}} perPage={20} />, {
      props: { project },
    });

    expect(screen.getByText('No workflow runs yet')).toBeInTheDocument();
  });

  it('shows a filtered empty state when filters are active but no runs match', () => {
    renderAuthedPage(<WorkflowRunsPage runs={[]} filters={{ state_eq: 'failed' }} perPage={20} />, {
      props: { project },
    });

    expect(screen.getByText('No runs match filter')).toBeInTheDocument();
    expect(screen.queryByText('No workflow runs yet')).not.toBeInTheDocument();
  });

  it('renders a table row for each run with its workflow name, id and status label', () => {
    const runs = [
      makeRun({ id: 101, workflowName: 'Deploy Workflow', state: 'completed' }),
      makeRun({ id: 202, workflowName: 'Lint Workflow', state: 'running' }),
    ];

    renderAuthedPage(<WorkflowRunsPage runs={runs} filters={{}} perPage={20} />, {
      props: { project },
    });

    expect(screen.getByText('Deploy Workflow')).toBeInTheDocument();
    expect(screen.getByText('Lint Workflow')).toBeInTheDocument();
    expect(screen.getByText('#101')).toBeInTheDocument();
    expect(screen.getByText('#202')).toBeInTheDocument();

    // State badge labels mapped from STATE_CONFIG. Scope to each row because the Status filter
    // <Select> also renders option labels ("Completed", "Running") in its (closed) dropdown.
    const deployRow = screen.getByText('#101').closest('tr') as HTMLElement;
    const lintRow = screen.getByText('#202').closest('tr') as HTMLElement;
    expect(within(deployRow).getByText('Completed')).toBeInTheDocument();
    expect(within(lintRow).getByText('Running')).toBeInTheDocument();
  });

  it('navigates to the run detail page when a row is clicked', async () => {
    const runs = [makeRun({ id: 555, workflowName: 'Release Workflow' })];

    renderAuthedPage(<WorkflowRunsPage runs={runs} filters={{}} perPage={20} />, {
      props: { project },
    });

    const idCell = screen.getByText('#555');
    const row = idCell.closest('tr') as HTMLElement;
    await userEvent.click(within(row).getByText('Release Workflow'));

    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/workflow_runs/555');
  });

  it('applies a status filter via the Status select, requesting the filtered list', async () => {
    renderAuthedPage(<WorkflowRunsPage runs={[makeRun()]} filters={{}} perPage={20} />, {
      props: { project },
    });

    const statusSelect = screen.getByPlaceholderText('Status');
    await userEvent.click(statusSelect);
    await userEvent.click(await screen.findByRole('option', { name: 'Failed' }));

    expect(router.get).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs',
      { q: { state_eq: 'failed' } },
      { preserveState: true, preserveScroll: true },
    );
  });

  it('reflects the active status filter as the Status select value', () => {
    renderAuthedPage(<WorkflowRunsPage runs={[makeRun()]} filters={{ state_eq: 'running' }} perPage={20} />, {
      props: { project },
    });

    // The two comboboxes are, in source order, the Status select then the per-page select.
    const [statusSelect] = screen.getAllByRole('combobox');
    expect(statusSelect).toHaveValue('Running');
  });

  it('switching to a different status replaces the existing filter value', async () => {
    renderAuthedPage(<WorkflowRunsPage runs={[makeRun()]} filters={{ state_eq: 'running' }} perPage={20} />, {
      props: { project },
    });

    await userEvent.click(screen.getByPlaceholderText('Status'));
    await userEvent.click(await screen.findByRole('option', { name: 'Completed' }));

    expect(router.get).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs',
      { q: { state_eq: 'completed' } },
      { preserveState: true, preserveScroll: true },
    );
  });

  it('changing per-page to a non-default value includes per_page in the request', async () => {
    renderAuthedPage(<WorkflowRunsPage runs={[makeRun()]} filters={{}} perPage={20} />, {
      props: { project },
    });

    // Second combobox in source order is the per-page Select (current value "20").
    const perPageSelect = screen.getAllByRole('combobox')[1];
    await userEvent.click(perPageSelect);
    await userEvent.click(await screen.findByRole('option', { name: '50' }));

    expect(router.get).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs',
      { q: {}, per_page: 50 },
      { preserveState: true, preserveScroll: true },
    );
  });

  it('changing per-page back to the default of 20 omits per_page from the request', async () => {
    renderAuthedPage(<WorkflowRunsPage runs={[makeRun()]} filters={{ state_eq: 'failed' }} perPage={50} />, {
      props: { project },
    });

    const perPageSelect = screen.getAllByRole('combobox')[1];
    await userEvent.click(perPageSelect);
    await userEvent.click(await screen.findByRole('option', { name: '20' }));

    expect(router.get).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs',
      { q: { state_eq: 'failed' } },
      { preserveState: true, preserveScroll: true },
    );
  });

  it('maps known run modes to human labels and passes unknown modes through verbatim', () => {
    const runs = [
      makeRun({ id: 1, workflowName: 'Auto WF', mode: 'non_interactive' }),
      makeRun({ id: 2, workflowName: 'Custom WF', mode: 'mixed' }),
      makeRun({ id: 3, workflowName: 'Weird WF', mode: 'experimental' }),
    ];

    renderAuthedPage(<WorkflowRunsPage runs={runs} filters={{}} perPage={20} />, {
      props: { project },
    });

    expect(within(screen.getByText('#1').closest('tr') as HTMLElement).getByText('Auto-run')).toBeInTheDocument();
    expect(within(screen.getByText('#2').closest('tr') as HTMLElement).getByText('Custom')).toBeInTheDocument();
    expect(within(screen.getByText('#3').closest('tr') as HTMLElement).getByText('experimental')).toBeInTheDocument();
  });

  it('falls back to the raw state string for an unknown state', () => {
    const runs = [makeRun({ id: 9, workflowName: 'Mystery WF', state: 'archived' })];

    renderAuthedPage(<WorkflowRunsPage runs={runs} filters={{}} perPage={20} />, {
      props: { project },
    });

    const row = screen.getByText('#9').closest('tr') as HTMLElement;
    expect(within(row).getByText('archived')).toBeInTheDocument();
  });

  it('renders the steps completed / total counter for a run', () => {
    const runs = [makeRun({ id: 42, stepsCompleted: 2, stepsTotal: 5 })];

    renderAuthedPage(<WorkflowRunsPage runs={runs} filters={{}} perPage={20} />, {
      props: { project },
    });

    const row = screen.getByText('#42').closest('tr') as HTMLElement;
    expect(within(row).getByText('2/5')).toBeInTheDocument();
  });

  it('shows a dash for the duration when the run never started', () => {
    const runs = [makeRun({ id: 70, startedAt: null, completedAt: null })];

    renderAuthedPage(<WorkflowRunsPage runs={runs} filters={{}} perPage={20} />, {
      props: { project },
    });

    const row = screen.getByText('#70').closest('tr') as HTMLElement;
    expect(within(row).getByText('—')).toBeInTheDocument();
  });

  it('formats a sub-minute duration in seconds', () => {
    const runs = [makeRun({ id: 71, startedAt: '2026-06-26T10:00:00Z', completedAt: '2026-06-26T10:00:45Z' })];

    renderAuthedPage(<WorkflowRunsPage runs={runs} filters={{}} perPage={20} />, {
      props: { project },
    });

    const row = screen.getByText('#71').closest('tr') as HTMLElement;
    expect(within(row).getByText('45s')).toBeInTheDocument();
  });

  it('formats a multi-minute duration as minutes and seconds', () => {
    const runs = [makeRun({ id: 72, startedAt: '2026-06-26T10:00:00Z', completedAt: '2026-06-26T10:02:30Z' })];

    renderAuthedPage(<WorkflowRunsPage runs={runs} filters={{}} perPage={20} />, {
      props: { project },
    });

    const row = screen.getByText('#72').closest('tr') as HTMLElement;
    expect(within(row).getByText('2m 30s')).toBeInTheDocument();
  });

  it('offers every selectable state in the Status filter dropdown', async () => {
    renderAuthedPage(<WorkflowRunsPage runs={[makeRun()]} filters={{}} perPage={20} />, {
      props: { project },
    });

    await userEvent.click(screen.getByPlaceholderText('Status'));

    for (const label of ['Running', 'Completed', 'Failed', 'Cancelled', 'Pending']) {
      expect(await screen.findByRole('option', { name: label })).toBeInTheDocument();
    }
  });
});
