import '@testing-library/jest-dom/vitest';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { renderAuthedPage, screen, userEvent, waitFor } from 'test/renderPage';

import BuilderPage from './BuilderPage';

// --- Inline fixtures (structurally match the page's Props/Step/Workflow shapes) ---

const makeStep = (overrides: Record<string, unknown> = {}) => ({
  id: 1,
  name: 'Draft spec',
  description: null,
  instructions: null,
  position: 1,
  agentId: null,
  requiredAgentRuntime: null,
  preferredModel: null,
  allowNonInteractive: false,
  skipPolicy: 'never',
  onFailure: 'fail',
  maxRetries: 0,
  mountRepositories: false,
  bmadEnabled: false,
  dependsOnStepIds: [] as number[],
  toolIds: [] as number[],
  mcpServerIds: [] as number[],
  skillIds: [] as number[],
  inputAssetSpecs: [] as { name: string; assetType: string; required: boolean; namePattern?: string | null }[],
  outputAssetSpecs: [] as { name: string; assetType: string; required: boolean; namePattern?: string | null }[],
  subSteps: [] as {
    id: number;
    name: string;
    description: string | null;
    instructions: string | null;
    position: number;
    required: boolean;
  }[],
  ...overrides,
});

const makeWorkflow = (overrides: Record<string, unknown> = {}) => ({
  id: 3,
  name: 'Release pipeline',
  description: null,
  scopeType: 'project',
  scopeIndicator: 'Project',
  inheritAllProjectResources: false,
  baseToolIds: [] as number[],
  baseSkillIds: [] as number[],
  baseMCPServerIds: [] as number[],
  baseAssetIds: [] as number[],
  ...overrides,
});

const projectProps = (overrides: Record<string, unknown> = {}) => ({
  project: { id: 7, name: 'Apollo' },
  workflow: makeWorkflow(),
  steps: [makeStep({ id: 1, name: 'Draft spec', position: 1 }), makeStep({ id: 2, name: 'Implement', position: 2 })],
  agents: [],
  tools: [],
  skills: [],
  mcpServers: [],
  assets: [],
  repositories: [],
  agentModels: [],
  readOnly: false,
  configuredAgents: [] as string[],
  ...overrides,
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe('Projects/Workflows/BuilderPage', () => {
  it('renders the steps sidebar, count, and the first step selected in the detail panel', () => {
    renderAuthedPage(<BuilderPage />, { props: projectProps() });

    // Sidebar landmark + step count.
    expect(screen.getByText('Steps')).toBeInTheDocument();
    expect(screen.getByText('2 steps')).toBeInTheDocument();

    // Both steps listed in the sidebar.
    expect(screen.getAllByText('Draft spec').length).toBeGreaterThan(0);
    expect(screen.getByText('Implement')).toBeInTheDocument();

    // First step is auto-selected: its Name field is populated in the detail panel.
    expect(screen.getByDisplayValue('Draft spec')).toBeInTheDocument();

    // Run button is present because a project is set.
    expect(screen.getByRole('button', { name: 'Run' })).toBeInTheDocument();
  });

  it('shows the empty state with an "Add First Step" CTA when there are no steps', () => {
    renderAuthedPage(<BuilderPage />, { props: projectProps({ steps: [] }) });

    expect(screen.getByText('No steps yet')).toBeInTheDocument();
    expect(screen.getByText('0 steps')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add First Step' })).toBeInTheDocument();
  });

  it('selecting a different step swaps the detail panel to that step', async () => {
    renderAuthedPage(<BuilderPage />, { props: projectProps() });

    // Initially the first step's name is the editable Name input value.
    expect(screen.getByDisplayValue('Draft spec')).toBeInTheDocument();
    expect(screen.queryByDisplayValue('Implement')).not.toBeInTheDocument();

    // Click the second step card in the sidebar.
    await userEvent.click(screen.getByText('Implement'));

    expect(screen.getByDisplayValue('Implement')).toBeInTheDocument();
  });

  it('creating the first step posts to the workflow steps endpoint', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, { props: projectProps({ steps: [] }) });

    await userEvent.click(screen.getByRole('button', { name: 'Add First Step' }));

    expect(fetchSpy).toHaveBeenCalledWith(
      '/api/v1/projects/7/workflows/3/steps',
      expect.objectContaining({ method: 'POST' }),
    );
  });

  it('renders a read-only company workflow without editing affordances', () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        project: null,
        readOnly: true,
        workflow: makeWorkflow({ name: 'Company onboarding', scopeIndicator: 'Company' }),
      }),
    });

    // Company-level read-only banner.
    expect(screen.getByText('This is a company-level workflow. Copy it to your project to customize.')).toBeInTheDocument();

    // Name renders as static text (not an editable input) and there is no Add Step / Run affordance.
    expect(screen.getByText('Company onboarding')).toBeInTheDocument();
    expect(screen.queryByDisplayValue('Company onboarding')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Add Step' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Run' })).not.toBeInTheDocument();
  });

  it('renders status badges (Auto / BMAD / runtime) for a step in the sidebar', () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [
          makeStep({
            id: 1,
            name: 'Draft spec',
            position: 1,
            allowNonInteractive: true,
            bmadEnabled: true,
            requiredAgentRuntime: 'claude_code',
          }),
        ],
      }),
    });

    expect(screen.getByText('Auto')).toBeInTheDocument();
    expect(screen.getByText('BMAD')).toBeInTheDocument();
    // Runtime value is mapped to its human label (badge + the detail-panel Select option both show it).
    expect(screen.getAllByText('Claude Code').length).toBeGreaterThan(0);
  });

  it('marks a step with no dependencies as "Root" and a dependent step with an "after:" badge', () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [
          makeStep({ id: 1, name: 'Draft spec', position: 1, dependsOnStepIds: [] }),
          makeStep({ id: 2, name: 'Implement', position: 2, dependsOnStepIds: [1] }),
        ],
      }),
    });

    // Step 1 (root) gets a Root badge; step 2 references its dependency by name.
    expect(screen.getByText('Root')).toBeInTheDocument();
    expect(screen.getByText(/after:\s*Draft spec/)).toBeInTheDocument();
  });

  it('shows the assigned agent name under a step card in the sidebar', () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        agents: [{ id: 42, name: 'Builder Bot' }],
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, agentId: 42 })],
      }),
    });

    // Sidebar card sub-label + the Agent <Select> option both surface the name.
    expect(screen.getAllByText('Builder Bot').length).toBeGreaterThan(0);
  });

  it('opening the delete-step modal and confirming fires a DELETE to the step endpoint', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1 })] }),
    });

    // The only trash icon on screen (no sub-steps / specs) is the detail-panel "Delete step" control.
    const deleteIcon = document.querySelector('.tabler-icon-trash');
    expect(deleteIcon).not.toBeNull();
    await userEvent.click(deleteIcon!.closest('button')!);

    // Confirmation modal appears.
    expect(screen.getByText('Are you sure you want to delete this step? This action cannot be undone.')).toBeInTheDocument();

    // Confirm.
    await userEvent.click(screen.getByRole('button', { name: 'Delete' }));

    expect(fetchSpy).toHaveBeenCalledWith(
      '/api/v1/projects/7/workflows/3/steps/1',
      expect.objectContaining({ method: 'DELETE' }),
    );
  });

  it('cancelling the delete-step modal closes it without any request', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch');

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1 })] }),
    });

    await userEvent.click(document.querySelector('.tabler-icon-trash')!.closest('button')!);
    expect(screen.getByText('Are you sure you want to delete this step? This action cannot be undone.')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    await waitFor(() =>
      expect(
        screen.queryByText('Are you sure you want to delete this step? This action cannot be undone.'),
      ).not.toBeInTheDocument(),
    );
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('reordering a step down PATCHes the reorder endpoint with swapped positions', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, { props: projectProps() });

    // First step card holds the up/down reorder controls; its down-arrow is enabled.
    const downButtons = screen.getAllByRole('button').filter((b) => b.querySelector('.tabler-icon-chevron-down'));
    expect(downButtons.length).toBeGreaterThan(0);
    await userEvent.click(downButtons[0]);

    expect(fetchSpy).toHaveBeenCalledWith(
      '/api/v1/projects/7/workflows/3/steps/reorder',
      expect.objectContaining({ method: 'PATCH' }),
    );
    const body = JSON.parse((fetchSpy.mock.calls[0][1] as RequestInit).body as string);
    // Step 1 (pos 1) and step 2 (pos 2) swap positions.
    expect(body.positions).toEqual({ '1': 2, '2': 1 });
  });

  it('disables the up-arrow on the first step and the down-arrow on the last step', () => {
    renderAuthedPage(<BuilderPage />, { props: projectProps() });

    const upButtons = screen.getAllByRole('button').filter((b) => b.querySelector('.tabler-icon-chevron-up'));
    const downButtons = screen.getAllByRole('button').filter((b) => b.querySelector('.tabler-icon-chevron-down'));

    // First step's up arrow is disabled; last step's down arrow is disabled.
    expect(upButtons[0]).toBeDisabled();
    expect(downButtons[downButtons.length - 1]).toBeDisabled();
  });

  it('opening the Run modal shows the run dialog titled for the workflow', async () => {
    renderAuthedPage(<BuilderPage />, { props: projectProps() });

    await userEvent.click(screen.getByRole('button', { name: 'Run' }));

    expect(await screen.findByText('Run: Release pipeline')).toBeInTheDocument();
    expect(screen.getByText('Execution Mode')).toBeInTheDocument();
  });

  it('disables the Run button when the workflow has no steps', () => {
    renderAuthedPage(<BuilderPage />, { props: projectProps({ steps: [] }) });

    expect(screen.getByRole('button', { name: 'Run' })).toBeDisabled();
  });

  it('editing the step Name in the detail panel debounce-PATCHes the step endpoint', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1 })] }),
    });

    // The labelled "Name" input in the detail panel.
    const nameInput = screen.getByRole('textbox', { name: 'Name' });
    await userEvent.type(nameInput, '!');

    await waitFor(
      () =>
        expect(fetchSpy).toHaveBeenCalledWith(
          '/api/v1/projects/7/workflows/3/steps/1',
          expect.objectContaining({ method: 'PATCH' }),
        ),
      { timeout: 2000 },
    );
  });

  it('selecting an agent immediately PATCHes the step with the chosen agentId', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        agents: [{ id: 42, name: 'Builder Bot' }],
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, agentId: null })],
      }),
    });

    // Open the Agent <Select> (Mantine renders it as an input labelled "Agent") and pick the option.
    await userEvent.click(screen.getAllByLabelText('Agent')[0]);
    const option = await screen.findByRole('option', { name: 'Builder Bot' });
    await userEvent.click(option);

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/steps/1',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
    const body = JSON.parse((fetchSpy.mock.calls.at(-1)![1] as RequestInit).body as string);
    expect(body.step.agentId).toBe(42);
  });

  it('shows "Max Retries" only when On Failure is set to retry', () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, onFailure: 'retry', maxRetries: 3 })] }),
    });

    // The execution accordion is open by default; Max Retries is visible for retry policy.
    expect(screen.getByRole('textbox', { name: 'Max Retries' })).toBeInTheDocument();
  });

  it('hides "Max Retries" when On Failure is not retry', () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, onFailure: 'fail' })] }),
    });

    expect(screen.queryByRole('textbox', { name: 'Max Retries' })).not.toBeInTheDocument();
  });

  it('adds an asset spec row when "Add" is clicked in the Asset Specs section', async () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1 })] }),
    });

    // Open the Asset Specs accordion section (click its control button).
    await userEvent.click(screen.getByRole('button', { name: /Asset Specs/ }));

    // Initially each (input + output) editor reports no specs.
    expect(await screen.findAllByText('No asset specs defined')).not.toHaveLength(0);

    // The Input editor's "Add" button is the first one in the panel.
    const addButtons = await screen.findAllByRole('button', { name: 'Add' });
    await userEvent.click(addButtons[0]);

    // A new editable path input (with the placeholder) appears.
    expect(await screen.findByPlaceholderText('e.g. tasks/report.md')).toBeInTheDocument();
  });

  it('renders the per-step sub-step count in the Sub-steps accordion label', () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [
          makeStep({
            id: 1,
            name: 'Draft spec',
            position: 1,
            subSteps: [
              { id: 11, name: 'a', description: null, instructions: null, position: 1, required: true },
              { id: 12, name: 'b', description: null, instructions: null, position: 2, required: false },
            ],
          }),
        ],
      }),
    });

    expect(screen.getByText('Sub-steps (2)')).toBeInTheDocument();
  });

  it('shows the no-dependency helper text in the Dependencies section for a root step', async () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, dependsOnStepIds: [] })] }),
    });

    await userEvent.click(screen.getByText('Dependencies'));

    expect(
      screen.getByText('No dependencies — this step can run in parallel with other root steps'),
    ).toBeInTheDocument();
  });

  it('renders the workflow scope indicator badge in the header', () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ workflow: makeWorkflow({ scopeIndicator: 'Project' }) }),
    });

    // The scope indicator is shown as a badge next to the title.
    expect(screen.getByText('Project')).toBeInTheDocument();
  });
});
