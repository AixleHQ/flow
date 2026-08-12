import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

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
  it('renders the shared detail header: breadcrumb, name, status, id and stats', () => {
    renderAuthedPage(<ShowPage />, { props: seed({ run: makeRun({ costCents: 1234 }) }) });

    expect(screen.getByRole('heading', { name: 'Nebula Pipeline' })).toBeInTheDocument();
    expect(screen.getByText('Run #42')).toBeInTheDocument();
    expect(screen.getByText('Running')).toBeInTheDocument();
    // Sessions, not "steps" — the run's units are sessions now, in the tab and
    // in the first stat card.
    expect(screen.getByRole('tab', { name: /^Sessions/ })).toBeInTheDocument();
    expect(screen.getByText('1/3')).toBeInTheDocument();
    expect(screen.getByText('$12.34')).toBeInTheDocument();
    // Runtime and user moved into the meta line the session detail also uses.
    expect(screen.getByText('Codex')).toBeInTheDocument();
    expect(screen.getByText('Dana Operator')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Sessions & Runs' })).toHaveAttribute(
      'href',
      '/company/projects/7/sessions',
    );
  });

  it('renders one session card per step run', () => {
    renderAuthedPage(<ShowPage />, { props: seed() });

    expect(screen.getByText('Session 1')).toBeInTheDocument();
    expect(screen.getByText('Session 2')).toBeInTheDocument();
    expect(screen.getByText('Compile Specs')).toBeInTheDocument();
    expect(screen.getByText('Render Output')).toBeInTheDocument();
  });

  it("links a session card to the step's terminal session", () => {
    renderAuthedPage(<ShowPage />, {
      props: seed({
        run: makeRun({
          stepRuns: [buildStepRun({ id: 401, stepName: 'Agent Step', stepPosition: 1, terminalSessionId: 88 })],
        }),
      }),
    });

    expect(screen.getByRole('link', { name: /open session/i })).toHaveAttribute(
      'href',
      '/company/projects/7/sessions/88',
    );
  });

  it('expands a session card to its prompt, steps and result note', async () => {
    const step = buildStepRun({
      id: 501,
      stepName: 'Generate',
      stepPosition: 1,
      state: 'completed',
      stepNote: 'Heads up: this step is flaky',
      initialPrompt: 'Generate the weekly deck',
      subStepRuns: [
        buildSubStepRun({ id: 1, state: 'completed', subStepName: 'Fetch data' }),
        buildSubStepRun({ id: 2, state: 'in_progress', subStepName: 'Transform' }),
      ],
    });
    renderAuthedPage(<ShowPage />, { props: seed({ run: makeRun({ stepRuns: [step] }) }) });

    await userEvent.click(screen.getByRole('button', { name: /expand generate/i }));

    expect(screen.getByText('Generate the weekly deck')).toBeInTheDocument();
    // Inside a session the checklist items are Steps, and the counter is x/y.
    expect(screen.getByText('1/2')).toBeInTheDocument();
    expect(screen.getByText('Fetch data')).toBeInTheDocument();
    expect(screen.getByText('Heads up: this step is flaky')).toBeInTheDocument();
  });

  it('fires a cancel request when Cancel run is clicked on an active run', async () => {
    renderAuthedPage(<ShowPage />, { props: seed() });

    await userEvent.click(screen.getByRole('button', { name: /cancel run/i }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs/42/cancel',
      {},
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('does not offer Cancel on a terminal run', () => {
    renderAuthedPage(<ShowPage />, { props: seed({ run: makeRun({ state: 'completed' }) }) });

    expect(screen.queryByRole('button', { name: /cancel run/i })).not.toBeInTheDocument();
  });

  it('shows the empty state when the run has no sessions yet', () => {
    renderAuthedPage(<ShowPage />, { props: seed({ run: makeRun({ stepRuns: [] }) }) });

    expect(screen.getByText('This run has no sessions yet.')).toBeInTheDocument();
  });

  it('switches to the Assets tab and shows the empty message', async () => {
    renderAuthedPage(<ShowPage />, { props: seed({ run: makeRun({ state: 'completed' }), assets: [] }) });

    await userEvent.click(screen.getByRole('tab', { name: /^Assets/ }));

    expect(screen.getByText(/No assets yet/)).toBeInTheDocument();
  });

  it('shows the quota banner and re-runs the workflow on a failed quota run', async () => {
    renderAuthedPage(<ShowPage />, {
      props: seed({
        run: makeRun({ state: 'failed', failureReason: 'quota_exceeded', failedAccountName: 'Acme Cloud' }),
      }),
    });

    const banner =
      screen.getByText('Workflow stopped: account ran out of credits').closest('[role="alert"]') ?? document.body;
    expect(within(banner as HTMLElement).getByText('Acme Cloud')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /re-run workflow/i }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs',
      expect.objectContaining({
        workflowRun: expect.objectContaining({ workflowId: 9, mode: 'interactive' }),
      }),
      expect.any(Object),
    );
  });

  it('names where a failed run stopped instead of when it started', () => {
    renderAuthedPage(<ShowPage />, {
      props: seed({
        run: makeRun({
          state: 'failed',
          stepRuns: [buildStepRun({ id: 601, stepName: 'Post to Slack', stepPosition: 2, state: 'failed' })],
        }),
      }),
    });

    expect(screen.getByText('Failed at')).toBeInTheDocument();
    expect(screen.getAllByText('Post to Slack').length).toBeGreaterThan(0);
  });

  it('approves a session waiting for input', async () => {
    const waiting = buildStepRun({ id: 201, stepName: 'Review Plan', stepPosition: 1, state: 'waiting_input' });
    renderAuthedPage(<ShowPage />, { props: seed({ run: makeRun({ stepRuns: [waiting] }) }) });

    expect(screen.getByText(/is waiting for your approval/)).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /approve & continue/i }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs/42/approve_step',
      {},
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('retries a session waiting for input', async () => {
    const waiting = buildStepRun({ id: 202, stepName: 'Review Plan', stepPosition: 1, state: 'waiting_input' });
    renderAuthedPage(<ShowPage />, { props: seed({ run: makeRun({ stepRuns: [waiting] }) }) });

    await userEvent.click(screen.getByRole('button', { name: /^Retry$/ }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs/42/retry_step',
      {},
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('opens the skip modal and posts skip_step with a typed reason', async () => {
    const waiting = buildStepRun({ id: 203, stepName: 'Review Plan', stepPosition: 1, state: 'waiting_input' });
    renderAuthedPage(<ShowPage />, { props: seed({ run: makeRun({ stepRuns: [waiting] }) }) });

    await userEvent.click(screen.getByRole('button', { name: /^Skip$/ }));

    const reason = await screen.findByLabelText('Reason (optional)');
    await userEvent.type(reason, 'Not needed for this run');

    await userEvent.click(screen.getByRole('button', { name: 'Skip session' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs/42/skip_step',
      { reason: 'Not needed for this run' },
      expect.objectContaining({ preserveScroll: true }),
    );

    // Let the modal's open-transition lifecycle timer drain while still mounted,
    // so it doesn't setState on the unmounted tree after RTL cleanup (Mantine
    // Transition schedules a ~200ms timer even under env="test").
    await new Promise((resolve) => setTimeout(resolve, 250));
  });

  it('retries a failed session from the action bar and shows its error in the card', async () => {
    const failed = buildStepRun({
      id: 204,
      stepName: 'Deploy',
      stepPosition: 1,
      state: 'failed',
      errorMessage: 'Connection refused by registry',
    });
    renderAuthedPage(<ShowPage />, {
      props: seed({ run: makeRun({ state: 'failed', stepRuns: [failed] }) }),
    });

    // A failed session card opens expanded, so the error is visible without a click.
    expect(screen.getByText('Connection refused by registry')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /retry session/i }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs/42/retry_step',
      {},
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('shows the live console beside the session list while a session is running', () => {
    const running = buildStepRun({
      id: 701,
      stepName: 'Collect data',
      stepPosition: 1,
      state: 'running',
      terminalUrl: 'https://host.test/t/abc/tty',
    });
    renderAuthedPage(<ShowPage />, { props: seed({ run: makeRun({ stepRuns: [running] }) }) });

    expect(screen.getByText('Live')).toBeInTheDocument();
    expect(screen.getByText('Session 1 · Collect data')).toBeInTheDocument();
    expect((screen.getByTitle('Terminal') as HTMLIFrameElement).getAttribute('src')).toBe(
      'https://host.test/t/abc/tty',
    );
  });

  it('hides the console on the Assets tab', async () => {
    const running = buildStepRun({
      id: 702,
      stepName: 'Collect data',
      stepPosition: 1,
      state: 'running',
      terminalUrl: 'https://host.test/t/abc/tty',
    });
    renderAuthedPage(<ShowPage />, { props: seed({ run: makeRun({ stepRuns: [running] }) }) });

    await userEvent.click(screen.getByRole('tab', { name: /^Assets/ }));

    expect(screen.queryByTitle('Terminal')).not.toBeInTheDocument();
  });

  it('lists assets with download and promote controls', async () => {
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
    renderAuthedPage(<ShowPage />, { props: seed({ run: makeRun({ state: 'completed' }), assets }) });

    await userEvent.click(screen.getByRole('tab', { name: /^Assets/ }));

    expect(screen.getByText('report.pdf')).toBeInTheDocument();
    expect(screen.getByText('1 file')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Download/ })).toHaveAttribute(
      'href',
      'https://files.example.com/report.pdf',
    );
    expect(screen.getByRole('button', { name: /promote all to project/i })).toBeInTheDocument();
  });

  it('promotes a single asset through the promote modal via apiFetch', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    const assets = [
      buildWorkflowRunAsset({ id: 22, name: 'artifact.zip', contentType: 'application/zip', fileSize: null }),
    ];
    renderAuthedPage(<ShowPage />, { props: seed({ run: makeRun({ state: 'completed' }), assets }) });

    await userEvent.click(screen.getByRole('tab', { name: /^Assets/ }));
    await userEvent.click(screen.getByRole('button', { name: /^Promote$/ }));

    expect(await screen.findByText('Promote "artifact.zip"')).toBeInTheDocument();

    const folder = screen.getByLabelText('Folder (optional)');
    await userEvent.type(folder, 'reports');
    // Two buttons read "Promote" once the modal is open — confirm inside it.
    const dialog = screen.getByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: /^Promote$/ }));

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflow_runs/42/workflow_run_assets/22/export',
        expect.objectContaining({ method: 'POST', body: JSON.stringify({ folder: 'reports' }) }),
      );
    });

    fetchSpy.mockRestore();
    await new Promise((resolve) => setTimeout(resolve, 250));
  });
});
