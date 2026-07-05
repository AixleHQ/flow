import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { buildStepRun } from 'test/factories/stepRun';
import { buildSubStepRun } from 'test/factories/subStepRun';
import { buildWorkflowRun } from 'test/factories/workflowRun';
import { buildWorkflowRunAsset } from 'test/factories/workflowRunAsset';
import { renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';
import type WorkflowRun from 'types/generated/WorkflowRun';

import ShowPage from './ShowPage';

const project = { id: 7, name: 'Orbital Migration' };

// Thin typed wrapper: buildWorkflowRun defaults to an empty stepRuns array, but every
// seed()-based test relies on the two-step default the old untyped makeRun provided, so
// re-seed it here (as typed StepRuns) and let callers override any WorkflowRun field.
function makeRun(overrides: Partial<WorkflowRun> = {}) {
  return buildWorkflowRun({
    stepRuns: [
      buildStepRun({ id: 101, stepId: 1, stepName: 'Compile Specs', stepPosition: 1, state: 'completed' }),
      buildStepRun({ id: 102, stepId: 2, stepName: 'Render Output', stepPosition: 2, state: 'pending' }),
    ],
    ...overrides,
  });
}

function seed(props: Record<string, unknown> = {}) {
  return {
    project,
    run: makeRun(),
    assets: [],
    cableStream: 'signed-stream',
    ...props,
  };
}

describe('Projects/WorkflowRuns/ShowPage', () => {
  it('renders the run header with workflow name, state and step progress', () => {
    renderAuthedPage(<ShowPage />, { props: seed() });

    expect(screen.getByText('Nebula Pipeline')).toBeInTheDocument();
    expect(screen.getByText('#42')).toBeInTheDocument();
    expect(screen.getByText('1/3 steps')).toBeInTheDocument();
    // Step names from the sidebar list.
    expect(screen.getByText('Render Output')).toBeInTheDocument();
  });

  it('fires a cancel request when the Cancel button is clicked on an active run', async () => {
    renderAuthedPage(<ShowPage />, { props: seed() });

    await userEvent.click(screen.getByRole('button', { name: /Cancel/i }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs/42/cancel',
      {},
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('shows the no-steps empty state when the run has no step runs', () => {
    renderAuthedPage(<ShowPage />, { props: seed({ run: makeRun({ stepRuns: [] }) }) });

    expect(screen.getByText('No steps')).toBeInTheDocument();
  });

  it('switches to the assets view and shows the empty assets message', async () => {
    // Use a terminal (completed) run so the Assets tab is not disabled with zero assets.
    renderAuthedPage(<ShowPage />, {
      props: seed({ run: makeRun({ state: 'completed' }), assets: [] }),
    });

    await userEvent.click(screen.getByRole('button', { name: /^Assets/ }));

    expect(screen.getByText('No workflow assets')).toBeInTheDocument();
  });

  it('shows the quota banner and re-runs the workflow on a failed quota run', async () => {
    renderAuthedPage(<ShowPage />, {
      props: seed({
        run: makeRun({
          state: 'failed',
          failureReason: 'quota_exceeded',
          failedAccountName: 'Acme Cloud',
        }),
      }),
    });

    const banner =
      screen.getByText('Workflow stopped: account ran out of credits').closest('[role="alert"]') ?? document.body;
    expect(within(banner as HTMLElement).getByText('Acme Cloud')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Re-run Workflow' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs',
      expect.objectContaining({
        workflowRun: expect.objectContaining({ workflowId: 9, mode: 'interactive' }),
      }),
      expect.any(Object),
    );
  });

  it('renders the cost and mode badges in the header', () => {
    renderAuthedPage(<ShowPage />, {
      props: seed({ run: makeRun({ costCents: 1234, mode: 'non_interactive' }) }),
    });

    expect(screen.getByText('$12.34')).toBeInTheDocument();
    // MODE_LABELS maps non_interactive -> Auto-run.
    expect(screen.getByText('Auto-run')).toBeInTheDocument();
  });

  it('shows the run status bar with agent, user and created info', () => {
    renderAuthedPage(<ShowPage />, { props: seed() });

    expect(screen.getByText('codex')).toBeInTheDocument();
    expect(screen.getByText('Dana Operator')).toBeInTheDocument();
    expect(screen.getByText('Created:')).toBeInTheDocument();
  });

  it('does not render a Cancel button for a terminal (completed) run', () => {
    renderAuthedPage(<ShowPage />, { props: seed({ run: makeRun({ state: 'completed' }) }) });

    expect(screen.queryByRole('button', { name: /^Cancel$/ })).not.toBeInTheDocument();
  });

  it('approves a step waiting for input', async () => {
    const waiting = buildStepRun({
      id: 201,
      stepId: 1,
      stepName: 'Review Plan',
      stepPosition: 1,
      state: 'waiting_input',
      startedAt: '2026-01-01T00:00:00Z',
    });
    renderAuthedPage(<ShowPage />, {
      props: seed({ run: makeRun({ stepRuns: [waiting] }) }),
    });

    await userEvent.click(screen.getByRole('button', { name: 'Approve & Continue' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs/42/approve_step',
      {},
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('retries a step waiting for input via the Retry action', async () => {
    const waiting = buildStepRun({
      id: 202,
      stepId: 1,
      stepName: 'Review Plan',
      stepPosition: 1,
      state: 'waiting_input',
    });
    renderAuthedPage(<ShowPage />, {
      props: seed({ run: makeRun({ stepRuns: [waiting] }) }),
    });

    await userEvent.click(screen.getByRole('button', { name: /^Retry$/ }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs/42/retry_step',
      {},
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('opens the skip modal and posts skip_step with a typed reason', async () => {
    const waiting = buildStepRun({
      id: 203,
      stepId: 1,
      stepName: 'Review Plan',
      stepPosition: 1,
      state: 'waiting_input',
    });
    renderAuthedPage(<ShowPage />, {
      props: seed({ run: makeRun({ stepRuns: [waiting] }) }),
    });

    await userEvent.click(screen.getByRole('button', { name: /^Skip$/ }));

    const reason = await screen.findByLabelText('Reason (optional)');
    await userEvent.type(reason, 'Not needed for this run');

    await userEvent.click(screen.getByRole('button', { name: 'Skip Step' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs/42/skip_step',
      { reason: 'Not needed for this run' },
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('shows the failure card and retries a failed step', async () => {
    const failed = buildStepRun({
      id: 204,
      stepId: 1,
      stepName: 'Deploy',
      stepPosition: 1,
      state: 'failed',
      errorMessage: 'Connection refused by registry',
    });
    renderAuthedPage(<ShowPage />, {
      props: seed({ run: makeRun({ stepRuns: [failed] }) }),
    });

    // "Step Failed" header is unique to the failure card; the error message itself
    // also appears in the sidebar row, so allow multiple matches.
    expect(screen.getByText('Step Failed')).toBeInTheDocument();
    expect(screen.getAllByText('Connection refused by registry').length).toBeGreaterThan(0);

    await userEvent.click(screen.getByRole('button', { name: 'Retry Step' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs/42/retry_step',
      {},
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('selecting a pending step shows the waiting-to-start detail', async () => {
    const pending = buildStepRun({
      id: 205,
      stepId: 2,
      stepName: 'Render Output',
      stepPosition: 2,
      state: 'pending',
      dependsOnStepIds: [1],
      dependsOnNames: ['Compile Specs'],
    });
    renderAuthedPage(<ShowPage />, {
      props: seed({
        run: makeRun({
          stepRuns: [
            buildStepRun({ id: 100, stepId: 1, stepName: 'Compile Specs', stepPosition: 1, state: 'completed' }),
            pending,
          ],
        }),
      }),
    });

    // Click the pending step row in the sidebar to select it.
    await userEvent.click(screen.getByText('Render Output'));

    expect(screen.getByText('Waiting to start...')).toBeInTheDocument();
    // Dependency badge in the step info bar.
    expect(screen.getByText('Waiting for:')).toBeInTheDocument();
  });

  it('renders DAG waves with a parallel badge and dependency connector', () => {
    renderAuthedPage(<ShowPage />, {
      props: seed({
        run: makeRun({
          stepRuns: [
            buildStepRun({ id: 301, stepId: 1, stepName: 'Lint', stepPosition: 1, state: 'completed' }),
            buildStepRun({ id: 302, stepId: 2, stepName: 'Typecheck', stepPosition: 2, state: 'completed' }),
            buildStepRun({
              id: 303,
              stepId: 3,
              stepName: 'Build',
              stepPosition: 3,
              state: 'pending',
              dependsOnStepIds: [1, 2],
              dependsOnNames: ['Lint', 'Typecheck'],
            }),
          ],
        }),
      }),
    });

    // Two steps with no deps form a parallel start wave.
    expect(screen.getByText('2 parallel')).toBeInTheDocument();
    // Connector label for the dependent wave.
    expect(screen.getByText(/After Lint, Typecheck/)).toBeInTheDocument();
  });

  it('navigates to a terminal session from the step row chevron', async () => {
    const stepWithSession = buildStepRun({
      id: 401,
      stepId: 1,
      stepName: 'Agent Step',
      stepPosition: 1,
      state: 'completed',
      terminalSessionId: 88,
    });
    const { container } = renderAuthedPage(<ShowPage />, {
      props: seed({ run: makeRun({ stepRuns: [stepWithSession] }) }),
    });

    // The chevron ActionIcon has no accessible name (its Tooltip label is not
    // exposed as one), so locate it by its tabler icon and click the host button.
    const chevron = container.querySelector('.tabler-icon-chevron-right');
    const chevronButton = chevron?.closest('button');
    expect(chevronButton).not.toBeNull();
    await userEvent.click(chevronButton as HTMLButtonElement);

    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/sessions/88');
  });

  it('shows a finished-session banner and views the session', async () => {
    const finishedSession = buildStepRun({
      id: 402,
      stepId: 1,
      stepName: 'Agent Step',
      stepPosition: 1,
      state: 'completed',
      terminalSessionId: 77,
      terminalSessionState: 'finished',
    });
    renderAuthedPage(<ShowPage />, {
      props: seed({ run: makeRun({ state: 'completed', stepRuns: [finishedSession] }) }),
    });

    expect(screen.getByText('Session #77 finished')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /View Session/ }));

    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/sessions/77');
  });

  it('renders sub-step badges and the step note for the selected step', () => {
    const stepWithSubs = buildStepRun({
      id: 501,
      stepId: 1,
      stepName: 'Generate',
      stepPosition: 1,
      state: 'running',
      startedAt: '2026-01-01T00:00:00Z',
      stepNote: 'Heads up: this step is flaky',
      subStepRuns: [
        buildSubStepRun({
          id: 1,
          state: 'completed',
          subStepName: 'Fetch data',
          startedAt: '2026-01-01T00:00:00Z',
          completedAt: '2026-01-01T00:00:30Z',
        }),
        buildSubStepRun({
          id: 2,
          state: 'in_progress',
          subStepName: 'Transform',
          startedAt: '2026-01-01T00:00:30Z',
          completedAt: null,
        }),
      ],
    });
    renderAuthedPage(<ShowPage />, {
      props: seed({ run: makeRun({ stepRuns: [stepWithSubs] }) }),
    });

    expect(screen.getByText('Heads up: this step is flaky')).toBeInTheDocument();
    // Sub-step progress header in the detail panel.
    expect(screen.getByText('Sub-steps (1/2)')).toBeInTheDocument();
    expect(screen.getAllByText('Fetch data').length).toBeGreaterThan(0);
    expect(screen.getAllByText('Transform').length).toBeGreaterThan(0);
  });

  it('lists assets grouped by step with download and promote controls', async () => {
    const assets = [
      buildWorkflowRunAsset({
        id: 11,
        name: 'report.pdf',
        contentType: 'application/pdf',
        fileSize: 2048,
        stepName: 'Compile Specs',
        downloadUrl: 'https://files.example.com/report.pdf',
      }),
    ];
    renderAuthedPage(<ShowPage />, {
      props: seed({ run: makeRun({ state: 'completed' }), assets }),
    });

    await userEvent.click(screen.getByRole('button', { name: /^Assets/ }));

    expect(screen.getByText('report.pdf')).toBeInTheDocument();
    expect(screen.getByText('1 file(s)')).toBeInTheDocument();
    // Download is an anchor with the asset URL.
    const download = screen.getByRole('link', { name: /Download/ });
    expect(download).toHaveAttribute('href', 'https://files.example.com/report.pdf');
    // Both per-asset and promote-all controls exist.
    expect(screen.getByRole('button', { name: 'Promote All to Project' })).toBeInTheDocument();
  });

  it('promotes a single asset through the promote modal via apiFetch', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    // downloadUrl is optional-string (string | undefined), not nullable — omit it for
    // "no download link" instead of passing null.
    const assets = [
      buildWorkflowRunAsset({
        id: 22,
        name: 'artifact.zip',
        contentType: 'application/zip',
        fileSize: null,
        stepName: 'Build',
      }),
    ];
    renderAuthedPage(<ShowPage />, {
      props: seed({ run: makeRun({ state: 'completed' }), assets }),
    });

    await userEvent.click(screen.getByRole('button', { name: /^Assets/ }));
    await userEvent.click(screen.getByRole('button', { name: /^Promote$/ }));

    // Modal opens scoped to the asset name.
    expect(await screen.findByText('Promote "artifact.zip"')).toBeInTheDocument();

    const folder = screen.getByLabelText('Folder (optional)');
    await userEvent.type(folder, 'reports');

    // The modal confirm button is the second Promote action; pick it inside the dialog.
    const dialog = screen.getByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Promote' }));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    const calledUrl = fetchSpy.mock.calls[0][0];
    expect(String(calledUrl)).toContain('/api/v1/projects/7/workflow_runs/42/workflow_run_assets/22/export');
    const calledInit = fetchSpy.mock.calls[0][1] as RequestInit;
    expect(calledInit.method).toBe('POST');
    expect(String(calledInit.body)).toContain('reports');

    await waitFor(() => expect(router.reload).toHaveBeenCalledWith({ only: ['assets'] }));
  });

  it('finishes an interactive agent session and reloads the run', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    const runningInteractive = buildStepRun({
      id: 601,
      stepId: 1,
      stepName: 'Live Agent',
      stepPosition: 1,
      state: 'running',
      startedAt: '2026-01-01T00:00:00Z',
      terminalSessionId: 99,
      terminalSessionState: 'not_started',
    });
    renderAuthedPage(<ShowPage />, {
      props: seed({ run: makeRun({ mode: 'interactive', stepRuns: [runningInteractive] }) }),
    });

    await userEvent.click(screen.getByRole('button', { name: 'Finish Agent Session' }));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    expect(String(fetchSpy.mock.calls[0][0])).toContain('/api/v1/terminal_sessions/99/finish');
    await waitFor(() => expect(router.reload).toHaveBeenCalledWith({ only: ['run'] }));
  });

  it('shows a session-starting loader for a running interactive step', () => {
    const starting = buildStepRun({
      id: 701,
      stepId: 1,
      stepName: 'Booting',
      stepPosition: 1,
      state: 'running',
      startedAt: '2026-01-01T00:00:00Z',
      terminalSessionId: 12,
      terminalSessionState: 'running',
    });
    renderAuthedPage(<ShowPage />, {
      props: seed({ run: makeRun({ stepRuns: [starting] }) }),
    });

    expect(screen.getByText('Session starting...')).toBeInTheDocument();
  });

  it('disables the Assets tab for an active run with no assets', () => {
    renderAuthedPage(<ShowPage />, { props: seed({ run: makeRun({ state: 'running' }), assets: [] }) });

    expect(screen.getByRole('button', { name: /^Assets/ })).toBeDisabled();
  });

  it('links to Manage Accounts in the quota banner', () => {
    renderAuthedPage(<ShowPage />, {
      props: seed({
        run: makeRun({ state: 'failed', failureReason: 'quota_exceeded', failedAccountName: 'Acme Cloud' }),
      }),
    });

    expect(screen.getByRole('link', { name: 'Manage Accounts' })).toHaveAttribute('href', '/profile');
  });
});

afterEach(() => {
  vi.restoreAllMocks();
});
