import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { buildAssetPicker } from 'test/factories/assetPicker';
import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

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
  {
    id: 11,
    name: 'Nightly triage',
    steps: [
      { id: 3, name: 'Fetch issues', position: 1, allowNonInteractive: true, dependsOnStepIds: [] },
      { id: 4, name: 'Label issues', position: 2, allowNonInteractive: true, dependsOnStepIds: [3] },
    ],
  },
];

function withStepAutoRun(allowNonInteractive: boolean): RunWorkflowOption[] {
  return workflows.map((w) =>
    w.id === 11 ? { ...w, steps: w.steps.map((s) => (s.id === 4 ? { ...s, allowNonInteractive } : s)) } : w,
  );
}

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
      assets={[buildAssetPicker({ id: 2, name: 'brand.css', folder: null })]}
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

    expect(screen.getAllByText('Setup')).toHaveLength(6);

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

  it('asks before closing a run the user has changed, and closes once they discard it', async () => {
    const onClose = vi.fn();
    renderDrawer({ initialWorkflowId: 9, onClose });

    await userEvent.click(screen.getByRole('radio', { name: /Custom/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Close' }));

    const discard = await screen.findByRole('dialog', { name: 'Discard unsaved changes?' });
    expect(onClose).not.toHaveBeenCalled();
    expect(screen.getByRole('dialog', { name: 'Run: Weekly GA report' })).toBeInTheDocument();

    await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('counts picking a workflow as unsaved input', async () => {
    const onClose = vi.fn();
    renderDrawer({ onClose });

    await userEvent.click(screen.getByPlaceholderText('Select a workflow…'));
    await userEvent.click(await screen.findByRole('option', { name: 'Release notes digest' }));
    await userEvent.click(screen.getByRole('button', { name: 'Close' }));

    expect(await screen.findByRole('dialog', { name: 'Discard unsaved changes?' })).toBeInTheDocument();
    expect(onClose).not.toHaveBeenCalled();
  });

  it('closes an untouched drawer opened on a preselected workflow without asking', async () => {
    const onClose = vi.fn();
    renderDrawer({ initialWorkflowId: 9, onClose });

    await userEvent.click(screen.getByRole('button', { name: 'Close' }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });

  it('starts clean again when reopened after a discarded change', async () => {
    const onClose = vi.fn();
    const drawer = (opened: boolean) => (
      <RunWorkflowDrawer
        opened={opened}
        onClose={onClose}
        projectId={7}
        workflows={workflows}
        initialWorkflowId={9}
        configuredAgents={['claude_code']}
        repositories={[]}
        assets={[]}
      />
    );
    const { rerender } = renderAuthedPage(drawer(true));

    await userEvent.click(screen.getByRole('radio', { name: /Custom/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Close' }));
    const discard = await screen.findByRole('dialog', { name: 'Discard unsaved changes?' });
    await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));
    rerender(drawer(false));
    rerender(drawer(true));

    await userEvent.click(screen.getByRole('button', { name: 'Close' }));

    expect(onClose).toHaveBeenCalledTimes(2);
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });

  it('brings the Custom switches back to what each step allows when reopened after a discard', async () => {
    const drawer = (opened: boolean) => (
      <RunWorkflowDrawer
        opened={opened}
        onClose={vi.fn()}
        projectId={7}
        workflows={workflows}
        initialWorkflowId={9}
        configuredAgents={['claude_code']}
        repositories={[]}
        assets={[]}
      />
    );
    const { rerender } = renderAuthedPage(drawer(true));

    await userEvent.click(screen.getByRole('radio', { name: /Custom/ }));
    await userEvent.click(screen.getByLabelText('Run "Collect data" automatically'));
    expect(screen.getByLabelText('Run "Collect data" automatically')).not.toBeChecked();
    await userEvent.click(screen.getByRole('button', { name: 'Close' }));
    const discard = await screen.findByRole('dialog', { name: 'Discard unsaved changes?' });
    await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));
    rerender(drawer(false));
    rerender(drawer(true));

    await userEvent.click(screen.getByRole('radio', { name: /Custom/ }));
    expect(screen.getByLabelText('Run "Collect data" automatically')).toBeChecked();
  });

  it('disables Fully automatic and starts in Interactive when a session has auto-run off', async () => {
    renderDrawer({ initialWorkflowId: 9 });

    const automatic = screen.getByRole('radio', { name: /Fully automatic/ });
    expect(automatic).toHaveAttribute('aria-disabled', 'true');
    expect(automatic).toHaveTextContent('1 session needs input');
    expect(screen.getByRole('radio', { name: /Interactive/ })).toHaveAttribute('aria-checked', 'true');

    await userEvent.click(automatic);
    expect(automatic).toHaveAttribute('aria-checked', 'false');

    await userEvent.click(screen.getByRole('button', { name: /run workflow/i }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs',
      expect.objectContaining({ workflowRun: expect.objectContaining({ mode: 'interactive' }) }),
      expect.any(Object),
    );
  });

  it('names the sessions that keep Fully automatic off', async () => {
    const manual = (id: number, name: string) => ({
      id,
      name,
      position: id,
      allowNonInteractive: false,
      dependsOnStepIds: [],
    });
    renderDrawer({
      initialWorkflowId: 12,
      workflows: [
        {
          id: 12,
          name: 'Release train',
          steps: ['Plan', 'Build', 'Review', 'Ship', 'Announce'].map((name, i) => manual(20 + i, name)),
        },
      ],
    });

    expect(screen.getByRole('radio', { name: /Fully automatic/ })).toHaveTextContent('5 sessions need input');

    await userEvent.hover(screen.getByRole('radio', { name: /Fully automatic/ }));

    expect(await screen.findByRole('tooltip')).toHaveTextContent(
      'Auto-run is off for "Plan", "Build", "Review", and 2 more. Turn on "Auto-run available" for every session to run this workflow fully automatic.',
    );
  });

  it('keeps Fully automatic as the default when every session allows auto-run', async () => {
    renderDrawer({ initialWorkflowId: 11 });

    const automatic = screen.getByRole('radio', { name: /Fully automatic/ });
    expect(automatic).not.toHaveAttribute('aria-disabled');
    expect(automatic).toHaveAttribute('aria-checked', 'true');

    await userEvent.click(screen.getByRole('button', { name: /run workflow/i }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs',
      expect.objectContaining({ workflowRun: expect.objectContaining({ workflowId: 11, mode: 'non_interactive' }) }),
      expect.any(Object),
    );
  });

  it('follows an auto-run setting that changes while the drawer is open', () => {
    const drawer = (list: RunWorkflowOption[]) => (
      <RunWorkflowDrawer
        opened
        onClose={vi.fn()}
        projectId={7}
        workflows={list}
        initialWorkflowId={11}
        configuredAgents={['claude_code']}
        repositories={[]}
        assets={[]}
      />
    );
    const { rerender } = renderAuthedPage(drawer(workflows));

    expect(screen.getByRole('radio', { name: /Fully automatic/ })).toHaveAttribute('aria-checked', 'true');

    rerender(drawer(withStepAutoRun(false)));
    expect(screen.getByRole('radio', { name: /Fully automatic/ })).toHaveAttribute('aria-disabled', 'true');
    expect(screen.getByRole('radio', { name: /Interactive/ })).toHaveAttribute('aria-checked', 'true');

    rerender(drawer(withStepAutoRun(true)));
    expect(screen.getByRole('radio', { name: /Fully automatic/ })).not.toHaveAttribute('aria-disabled');
    expect(screen.getByRole('radio', { name: /Fully automatic/ })).toHaveAttribute('aria-checked', 'true');
  });

  it('never sends auto-run in Custom for a session that turned it off while the drawer was open', async () => {
    const drawer = (list: RunWorkflowOption[]) => (
      <RunWorkflowDrawer
        opened
        onClose={vi.fn()}
        projectId={7}
        workflows={list}
        initialWorkflowId={11}
        configuredAgents={['claude_code']}
        repositories={[]}
        assets={[]}
      />
    );
    const { rerender } = renderAuthedPage(drawer(workflows));

    await userEvent.click(screen.getByRole('radio', { name: /Custom/ }));
    expect(screen.getByLabelText('Run "Label issues" automatically')).toBeChecked();

    rerender(drawer(withStepAutoRun(false)));
    expect(screen.getByLabelText('Run "Label issues" automatically')).toBeDisabled();
    expect(screen.getByLabelText('Run "Label issues" automatically')).not.toBeChecked();

    await userEvent.click(screen.getByRole('button', { name: /run workflow/i }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflow_runs',
      expect.objectContaining({
        workflowRun: expect.objectContaining({
          mode: 'mixed',
          stepOverrides: { 3: { autoRun: true }, 4: { autoRun: false } },
        }),
      }),
      expect.any(Object),
    );
  });

  it('re-evaluates Fully automatic when another workflow is picked', async () => {
    renderDrawer();

    await userEvent.click(screen.getByPlaceholderText('Select a workflow…'));
    await userEvent.click(await screen.findByRole('option', { name: 'Nightly triage' }));
    expect(screen.getByRole('radio', { name: /Fully automatic/ })).toHaveAttribute('aria-checked', 'true');

    await userEvent.click(screen.getByDisplayValue('Nightly triage'));
    await userEvent.click(await screen.findByRole('option', { name: 'Weekly GA report' }));
    expect(screen.getByRole('radio', { name: /Fully automatic/ })).toHaveAttribute('aria-disabled', 'true');
    expect(screen.getByRole('radio', { name: /Interactive/ })).toHaveAttribute('aria-checked', 'true');
  });

  it('closes without asking once the run has started', async () => {
    vi.mocked(router.post).mockImplementationOnce((_url, _data, options) => {
      (options as { onSuccess?: () => void }).onSuccess?.();
    });
    const onClose = vi.fn();
    renderDrawer({ initialWorkflowId: 9, onClose });

    await userEvent.click(screen.getByRole('radio', { name: /Interactive/ }));
    await userEvent.click(screen.getByRole('button', { name: /run workflow/i }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });
});
