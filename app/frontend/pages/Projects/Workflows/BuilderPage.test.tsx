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
  toolGroups: [],
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
    expect(
      screen.getByText('This is a company-level workflow. Copy it to your project to customize.'),
    ).toBeInTheDocument();

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
    expect(
      screen.getByText('Are you sure you want to delete this step? This action cannot be undone.'),
    ).toBeInTheDocument();

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
    expect(
      screen.getByText('Are you sure you want to delete this step? This action cannot be undone.'),
    ).toBeInTheDocument();

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
      props: projectProps({
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, onFailure: 'retry', maxRetries: 3 })],
      }),
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

  it('offers a tool group as one entry and selects it whole (not each member)', async () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        tools: [
          { id: 10, name: 'Board List Tasks' },
          { id: 11, name: 'Board Move Task' },
          { id: 20, name: 'Echo Greeter' },
        ],
        toolGroups: [{ tag: 'board', label: 'Board management', toolIds: [10, 11] }],
        workflow: makeWorkflow({ inheritAllProjectResources: false }),
      }),
    });

    // Open the base-resources Tools picker.
    await userEvent.click(screen.getAllByLabelText('Tools')[0]);

    // The group shows as an option; its member tools are not listed individually.
    expect((await screen.findAllByText('Board management')).length).toBeGreaterThan(0);
    expect(screen.queryByText('Board List Tasks')).not.toBeInTheDocument();
    expect(screen.queryByText('Board Move Task')).not.toBeInTheDocument();
    // Ungrouped custom tool stays individual.
    expect(screen.getAllByText('Echo Greeter').length).toBeGreaterThan(0);
  });

  it('renders the workflow scope indicator badge in the header', () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ workflow: makeWorkflow({ scopeIndicator: 'Project' }) }),
    });

    // The scope indicator is shown as a badge next to the title.
    expect(screen.getByText('Project')).toBeInTheDocument();
  });

  it('opening the Triggers button reveals the workflow triggers drawer', async () => {
    renderAuthedPage(<BuilderPage />, { props: projectProps() });

    // Drawer is closed initially.
    expect(screen.queryByText('Triggers — how this workflow launches')).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Triggers' }));

    expect(await screen.findByText('Triggers — how this workflow launches')).toBeInTheDocument();
  });

  it('editing the workflow name in the header debounce-PATCHes the workflow endpoint', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, { props: projectProps() });

    // The header workflow-name field is an unlabelled input holding the workflow name.
    await userEvent.type(screen.getByDisplayValue('Release pipeline'), '!');

    await waitFor(
      () =>
        expect(fetchSpy).toHaveBeenCalledWith(
          '/api/v1/projects/7/workflows/3',
          expect.objectContaining({ method: 'PATCH' }),
        ),
      { timeout: 2000 },
    );
    const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/workflows/3');
    const body = JSON.parse((call![1] as RequestInit).body as string);
    expect(body.workflow.name).toBe('Release pipeline!');
  });

  it('editing the workflow description debounce-PATCHes the workflow endpoint', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, { props: projectProps() });

    await userEvent.type(screen.getByPlaceholderText('Add a description...'), 'Ship');

    await waitFor(
      () => expect(fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/workflows/3')).toBeTruthy(),
      { timeout: 2000 },
    );
    const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/workflows/3');
    const body = JSON.parse((call![1] as RequestInit).body as string);
    expect(body.workflow.description).toBe('Ship');
  });

  it('toggling "Inherit all project resources" PATCHes the config-nested field and shows the helper text', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ workflow: makeWorkflow({ inheritAllProjectResources: false }) }),
    });

    // Expand the sidebar Base Resources accordion, then flip the inherit switch. The panel content
    // is revealed asynchronously, so wait for the switch to become queryable by role before clicking.
    await userEvent.click(screen.getByRole('button', { name: /Base Resources/ }));
    await userEvent.click(await screen.findByRole('switch', { name: 'Inherit all project resources' }));

    // Observable state change: the "all resources available" helper text now renders.
    expect(
      await screen.findByText('All project tools, skills, and MCP servers are available in every step.'),
    ).toBeInTheDocument();

    // Config-backed field must be sent nested under `config`.
    await waitFor(
      () => expect(fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/workflows/3')).toBeTruthy(),
      { timeout: 2000 },
    );
    const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/workflows/3');
    const body = JSON.parse((call![1] as RequestInit).body as string);
    expect(body.workflow.config.inheritAllProjectResources).toBe(true);
  });

  it('selecting a base tool group PATCHes config.baseToolIds expanded to its member ids', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        tools: [
          { id: 10, name: 'Board List Tasks' },
          { id: 11, name: 'Board Move Task' },
        ],
        toolGroups: [{ tag: 'board', label: 'Board management', toolIds: [10, 11] }],
        workflow: makeWorkflow({ inheritAllProjectResources: false }),
      }),
    });

    // Expand the base-resources accordion so its Tools picker (and dropdown options) are accessible
    // by role — collapsed accordion content is hidden from the accessibility tree.
    await userEvent.click(screen.getByRole('button', { name: /Base Resources/ }));
    // Open the base-resources Tools picker (first of the two "Tools" pickers) and pick the group.
    await userEvent.click(screen.getAllByLabelText('Tools')[0]);
    await userEvent.click((await screen.findAllByRole('option', { name: 'Board management' }))[0]);

    await waitFor(
      () => expect(fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/workflows/3')).toBeTruthy(),
      { timeout: 2000 },
    );
    const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/workflows/3');
    const body = JSON.parse((call![1] as RequestInit).body as string);
    // The single group token expands to every member tool id.
    expect(body.workflow.config.baseToolIds).toEqual([10, 11]);
  });

  it('toggling "Auto-run available" immediately PATCHes the step and surfaces the "Auto" badge', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, allowNonInteractive: false })],
      }),
    });

    // The Execution accordion is open by default; toggle the auto-run switch. The switch also renders
    // a description inside its label, so match the accessible name by substring (regex).
    await userEvent.click(screen.getByRole('switch', { name: /Auto-run available/ }));

    // The sidebar step card now shows the "Auto" badge.
    expect(await screen.findByText('Auto')).toBeInTheDocument();

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/steps/1',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
    const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/workflows/3/steps/1');
    const body = JSON.parse((call![1] as RequestInit).body as string);
    expect(body.step.allowNonInteractive).toBe(true);
  });

  it('setting On Failure to "Retry" reveals Max Retries and PATCHes the step', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, onFailure: 'fail' })] }),
    });

    // Max Retries is hidden while the policy is not "retry".
    expect(screen.queryByRole('textbox', { name: 'Max Retries' })).not.toBeInTheDocument();

    await userEvent.click(screen.getAllByLabelText('On Failure')[0]);
    await userEvent.click(await screen.findByRole('option', { name: 'Retry' }));

    // The conditional Max Retries input now renders.
    expect(await screen.findByRole('textbox', { name: 'Max Retries' })).toBeInTheDocument();

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/steps/1',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
    const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/workflows/3/steps/1');
    const body = JSON.parse((call![1] as RequestInit).body as string);
    expect(body.step.onFailure).toBe('retry');
  });

  it('choosing a Required Runtime PATCHes the runtime and resets preferredModel, then reveals the model picker', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, requiredAgentRuntime: null })],
      }),
    });

    // Preferred Model picker is absent until a runtime is chosen.
    expect(screen.queryByLabelText('Preferred Model')).not.toBeInTheDocument();

    await userEvent.click(screen.getAllByLabelText('Required Runtime')[0]);
    await userEvent.click(await screen.findByRole('option', { name: 'Cursor CLI' }));

    // Choosing a runtime now shows the Preferred Model select.
    expect((await screen.findAllByLabelText('Preferred Model'))[0]).toBeInTheDocument();

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/steps/1',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
    const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/workflows/3/steps/1');
    const body = JSON.parse((call![1] as RequestInit).body as string);
    expect(body.step.requiredAgentRuntime).toBe('cursor_cli');
    // Switching runtime clears any previously-chosen model.
    expect(body.step.preferredModel).toBeNull();
  });

  it('selecting a Preferred Model for a runtime step PATCHes the step with the model id', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, requiredAgentRuntime: 'claude_code' })],
        agentModels: [{ agentType: 'claude_code', models: [{ modelId: 'opus-9', displayName: 'Opus 9' }] }],
      }),
    });

    await userEvent.click(screen.getAllByLabelText('Preferred Model')[0]);
    await userEvent.click(await screen.findByRole('option', { name: 'Opus 9' }));

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/steps/1',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
    const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/workflows/3/steps/1');
    const body = JSON.parse((call![1] as RequestInit).body as string);
    expect(body.step.preferredModel).toBe('opus-9');
  });

  it('selecting a dependency PATCHes dependsOnStepIds and shows the "after:" badge in the sidebar', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [
          makeStep({ id: 1, name: 'Draft spec', position: 1, dependsOnStepIds: [] }),
          makeStep({ id: 2, name: 'Implement', position: 2, dependsOnStepIds: [] }),
        ],
      }),
    });

    // Open the Dependencies section for the selected (first) step and pick the other step.
    await userEvent.click(screen.getByRole('button', { name: /Dependencies/ }));
    await userEvent.click(screen.getByPlaceholderText('Select steps this step depends on...'));
    await userEvent.click(await screen.findByRole('option', { name: '2. Implement' }));

    // The sidebar card for step 1 now records the dependency.
    expect(await screen.findByText(/after:\s*Implement/)).toBeInTheDocument();

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/steps/1',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
    const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/workflows/3/steps/1');
    const body = JSON.parse((call![1] as RequestInit).body as string);
    expect(body.step.dependsOnStepIds).toEqual([2]);
  });

  it('adding a sub-step PATCHes the step with a new subStepsAttributes entry', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, subSteps: [] })] }),
    });

    await userEvent.click(screen.getByRole('button', { name: /Sub-steps/ }));
    await userEvent.click(await screen.findByRole('button', { name: 'Add Sub-step' }));

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/steps/1',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
    const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/workflows/3/steps/1');
    const body = JSON.parse((call![1] as RequestInit).body as string);
    expect(body.step.subStepsAttributes[0]).toMatchObject({ name: 'Sub-step 1', position: 1, required: true });
  });

  it('editing a sub-step name debounce-PATCHes the step with that sub-step id', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [
          makeStep({
            id: 1,
            name: 'Draft spec',
            position: 1,
            subSteps: [{ id: 11, name: 'Outline', description: null, instructions: null, position: 1, required: true }],
          }),
        ],
      }),
    });

    await userEvent.click(screen.getByRole('button', { name: /Sub-steps/ }));

    // The sub-step name field is the placeholder-only "Name" input (detail Name uses a label instead).
    await userEvent.type(await screen.findByPlaceholderText('Name'), '!');

    await waitFor(
      () =>
        expect(fetchSpy).toHaveBeenCalledWith(
          '/api/v1/projects/7/workflows/3/steps/1',
          expect.objectContaining({ method: 'PATCH' }),
        ),
      { timeout: 2000 },
    );
    const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/workflows/3/steps/1');
    const body = JSON.parse((call![1] as RequestInit).body as string);
    expect(body.step.subStepsAttributes[0].id).toBe(11);
    expect(body.step.subStepsAttributes[0].name).toBe('Outline!');
  });

  it('adding an output asset spec reveals the Match pattern column and PATCHes outputAssetSpecs', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1 })] }),
    });

    await userEvent.click(screen.getByRole('button', { name: /Asset Specs/ }));

    // Second "Add" belongs to the Output editor (Input editor renders first, then a divider).
    const addButtons = await screen.findAllByRole('button', { name: 'Add' });
    await userEvent.click(addButtons[1]);

    // Output specs support a name pattern; the column header + pattern input only render there.
    expect(await screen.findByText('Match pattern')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('e.g. report')).toBeInTheDocument();

    // Typing the path debounce-saves the output specs to the step endpoint.
    await userEvent.type(screen.getByPlaceholderText('e.g. tasks/report.md'), 'out.md');

    // Clicking "Add" and each keystroke both schedule a debounced save, so several
    // PATCHes can land for the step endpoint (the empty spec from "Add", then the
    // partial values) before "out.md" settles. Assert on the LAST such PATCH and
    // poll until the trailing debounced call carries the fully typed value —
    // grabbing the first matching call races the debounce and sees an empty name.
    await waitFor(
      () => {
        const stepCalls = fetchSpy.mock.calls.filter(
          ([url]) => url === '/api/v1/projects/7/workflows/3/steps/1',
        );
        expect(stepCalls.length).toBeGreaterThan(0);
        const body = JSON.parse((stepCalls.at(-1)![1] as RequestInit).body as string);
        expect(Array.isArray(body.step.outputAssetSpecs)).toBe(true);
        expect(body.step.outputAssetSpecs[0].name).toBe('out.md');
      },
      { timeout: 2000 },
    );
  });

  it('renders a read-only project workflow with disabled editing affordances', () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        readOnly: true,
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1 })],
      }),
    });

    // Detail-panel step Name field is present but disabled.
    expect(screen.getByRole('textbox', { name: 'Name' })).toBeDisabled();

    // Run stays rendered (a project is set) but disabled under read-only.
    expect(screen.getByRole('button', { name: 'Run' })).toBeDisabled();

    // Editing affordances are withheld: no Triggers and no Add Step.
    expect(screen.queryByRole('button', { name: 'Triggers' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Add Step' })).not.toBeInTheDocument();
  });
});
