import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderAuthedPage, screen, userEvent } from 'test/renderPage';

import { RunWorkflowDrawer, type RunWorkflowOption } from './RunWorkflowDrawer';

const workflows: RunWorkflowOption[] = [
  {
    id: 9,
    name: 'Weekly GA report',
    steps: [
      { id: 1, name: 'Collect data', position: 1, allowNonInteractive: true, dependsOnStepIds: [] },
      { id: 2, name: 'Post to Slack', position: 2, allowNonInteractive: false, dependsOnStepIds: [1] },
    ],
  },
  { id: 10, name: 'Release notes digest', steps: [] },
];

function renderDrawer(overrides: Partial<React.ComponentProps<typeof RunWorkflowDrawer>> = {}) {
  return renderAuthedPage(
    <RunWorkflowDrawer
      opened
      onClose={vi.fn()}
      projectId={7}
      workflows={workflows}
      configuredAgents={['claude_code']}
      defaultAgentRuntime="claude_code"
      repositories={[{ id: 1, name: 'acme/app' }]}
      assets={[{ id: 2, name: 'brand.css' }]}
      {...overrides}
    />,
  );
}

describe('RunWorkflowDrawer', () => {
  it('opens with no workflow chosen and titles itself once one is picked', async () => {
    renderDrawer();

    // The drawer title, before a choice is made (the footer button shares the words).
    expect(screen.getByRole('heading', { name: 'Run workflow' })).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Select a workflow…')).toBeInTheDocument();

    await userEvent.click(screen.getByPlaceholderText('Select a workflow…'));
    await userEvent.click(await screen.findByRole('option', { name: 'Weekly GA report' }));

    expect(await screen.findByText('Run: Weekly GA report')).toBeInTheDocument();
  });

  it('follows the shared drawer order: workflow, runtime, mode, configuration', () => {
    renderDrawer({ initialWorkflowId: 9 });

    const headings = screen
      .getAllByText(/^(Workflow|Fallback agent runtime|Execution mode|Configuration)$/)
      .map((el) => el.textContent);

    expect(headings).toEqual(['Workflow', 'Fallback agent runtime', 'Execution mode', 'Configuration']);
  });

  it('keeps Run disabled until a workflow with steps is selected', async () => {
    renderDrawer();

    expect(screen.getByRole('button', { name: /run workflow/i })).toBeDisabled();

    await userEvent.click(screen.getByPlaceholderText('Select a workflow…'));
    await userEvent.click(await screen.findByRole('option', { name: 'Weekly GA report' }));

    expect(screen.getByRole('button', { name: /run workflow/i })).toBeEnabled();
  });

  it('marks unconnected runtimes as needing setup and does not select them', async () => {
    renderDrawer({ initialWorkflowId: 9, configuredAgents: ['claude_code'] });

    expect(screen.getAllByText('Setup')).toHaveLength(3);

    const codex = screen.getByRole('button', { name: /Codex/ });
    expect(codex).toBeDisabled();
    expect(screen.getByRole('button', { name: /Claude Code/ })).toHaveAttribute('aria-pressed', 'true');
  });

  it('posts the run with the chosen mode and runtime', async () => {
    renderDrawer({ initialWorkflowId: 9 });

    await userEvent.click(screen.getByRole('radio', { name: /Interactive/ }));
    await userEvent.click(screen.getByRole('button', { name: /run workflow/i }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs',
      expect.objectContaining({
        workflowRun: expect.objectContaining({
          workflowId: 9,
          mode: 'interactive',
          agentRuntime: 'claude_code',
        }),
      }),
      expect.any(Object),
    );
  });

  it('sends per-step overrides in Custom mode, seeded from what each step allows', async () => {
    renderDrawer({ initialWorkflowId: 9 });

    await userEvent.click(screen.getByRole('radio', { name: /Custom/ }));

    // A step that requires input cannot be flipped to auto.
    expect(screen.getByLabelText('Run "Post to Slack" automatically')).toBeDisabled();
    expect(screen.getByText('Requires input')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /run workflow/i }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs',
      expect.objectContaining({
        workflowRun: expect.objectContaining({
          mode: 'mixed',
          stepOverrides: { 1: { autoRun: true }, 2: { autoRun: false } },
        }),
      }),
      expect.any(Object),
    );
  });
});
