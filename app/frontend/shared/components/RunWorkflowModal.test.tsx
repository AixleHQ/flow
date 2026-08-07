import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { RunWorkflowModal } from './RunWorkflowModal';

const steps = [
  { id: 1, name: 'Plan', position: 0, allowNonInteractive: true, dependsOnStepIds: [] },
  { id: 2, name: 'Implement', position: 1, allowNonInteractive: true, dependsOnStepIds: [1] },
  { id: 3, name: 'Review', position: 2, allowNonInteractive: false, dependsOnStepIds: [2] },
];

const repositories = [
  { id: 10, name: 'backend-repo' },
  { id: 11, name: 'frontend-repo' },
];

const assets = [{ id: 20, name: 'spec-doc' }];

function renderModal(overrides: Partial<React.ComponentProps<typeof RunWorkflowModal>> = {}) {
  const onClose = vi.fn();
  renderPage(
    <RunWorkflowModal
      opened
      onClose={onClose}
      workflowId={42}
      workflowName="Delivery Pipeline"
      steps={steps}
      projectId={7}
      configuredAgents={['claude_code', 'codex_cli']}
      repositories={repositories}
      assets={assets}
      {...overrides}
    />,
  );
  return { onClose };
}

describe('RunWorkflowModal', () => {
  it('renders the workflow title and the step wave badges when opened', () => {
    renderModal();

    expect(screen.getByText('Run: Delivery Pipeline')).toBeInTheDocument();
    // Each step name appears as a badge in the wave preview (automatic mode is the default).
    expect(screen.getByText('Plan')).toBeInTheDocument();
    expect(screen.getByText('Implement')).toBeInTheDocument();
    expect(screen.getByText('Review')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Run Workflow' })).toBeEnabled();
  });

  it('clicking Cancel calls onClose without firing a request', async () => {
    const { onClose } = renderModal();

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(onClose).toHaveBeenCalled();
    expect(router.post).not.toHaveBeenCalled();
  });

  it('submitting in the default Automatic mode posts mode=non_interactive to the project workflow_runs path', async () => {
    renderModal();

    await userEvent.click(screen.getByRole('button', { name: 'Run Workflow' }));

    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith(
        '/company/projects/7/workflow_runs',
        expect.objectContaining({
          workflowRun: expect.objectContaining({
            workflowId: 42,
            mode: 'non_interactive',
            agentRuntime: 'claude_code',
          }),
        }),
        expect.any(Object),
      ),
    );
    // Automatic mode does not include per-step overrides.
    const payload = (router.post as ReturnType<typeof vi.fn>).mock.calls[0][1];
    expect(payload.workflowRun.stepOverrides).toBeUndefined();
  });

  it('switching to Interactive mode posts mode=interactive', async () => {
    renderModal();

    // SegmentedControl renders radio inputs labeled by their option text.
    await userEvent.click(screen.getByRole('radio', { name: 'Interactive' }));
    await userEvent.click(screen.getByRole('button', { name: 'Run Workflow' }));

    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith(
        '/company/projects/7/workflow_runs',
        expect.objectContaining({
          workflowRun: expect.objectContaining({ mode: 'interactive' }),
        }),
        expect.any(Object),
      ),
    );
  });

  it('Custom mode reveals per-step switches and flags steps that require input', async () => {
    renderModal();

    await userEvent.click(screen.getByRole('radio', { name: 'Custom' }));

    // Wave labels for the dependency graph (step 1 -> 2 -> 3).
    expect(screen.getByText('Start')).toBeInTheDocument();
    expect(screen.getByText('After Plan')).toBeInTheDocument();
    expect(screen.getByText('After Implement')).toBeInTheDocument();

    // The Review step disallows non-interactive execution -> "requires input" badge.
    expect(screen.getByText('requires input')).toBeInTheDocument();

    // Custom mode payload carries stepOverrides for every step.
    await userEvent.click(screen.getByRole('button', { name: 'Run Workflow' }));
    await waitFor(() => expect(router.post).toHaveBeenCalled());
    const payload = (router.post as ReturnType<typeof vi.fn>).mock.calls[0][1];
    expect(payload.workflowRun.mode).toBe('mixed');
    expect(payload.workflowRun.stepOverrides).toEqual({
      1: { autoRun: true },
      2: { autoRun: true },
      3: { autoRun: false },
    });
  });

  it("preselects the member's default agent runtime rather than the first configured one", async () => {
    renderModal({ configuredAgents: ['cursor_cli', 'claude_code'], defaultAgentRuntime: 'claude_code' });

    await userEvent.click(screen.getByRole('button', { name: 'Run Workflow' }));

    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith(
        '/company/projects/7/workflow_runs',
        expect.objectContaining({
          workflowRun: expect.objectContaining({ agentRuntime: 'claude_code' }),
        }),
        expect.any(Object),
      ),
    );
  });

  it('falls back to the first configured agent when the default runtime has no credential here', async () => {
    renderModal({ configuredAgents: ['cursor_cli'], defaultAgentRuntime: 'gemini_cli' });

    await userEvent.click(screen.getByRole('button', { name: 'Run Workflow' }));

    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith(
        '/company/projects/7/workflow_runs',
        expect.objectContaining({
          workflowRun: expect.objectContaining({ agentRuntime: 'cursor_cli' }),
        }),
        expect.any(Object),
      ),
    );
  });

  it('shows the empty fallback and disables Run when there are no configured agents', () => {
    renderModal({ configuredAgents: [] });

    expect(screen.getByText('No configured agents')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Run Workflow' })).toBeDisabled();
  });

  it('does not render the Fallback Model select unless the chosen runtime has models', async () => {
    renderModal({
      agentModels: [
        {
          agentType: 'claude_code',
          models: [{ modelId: 'opus', displayName: 'Claude Opus' }],
        },
      ],
    });

    // claude_code is the default runtime and has a model -> the Fallback Model select appears.
    const modelSelect = screen.getByPlaceholderText('Default (per-step or credential)');
    expect(modelSelect).toBeInTheDocument();
    // Open the model dropdown and confirm the configured model is offered.
    await userEvent.click(modelSelect);
    expect(await screen.findByText('Claude Opus')).toBeInTheDocument();
  });
});
