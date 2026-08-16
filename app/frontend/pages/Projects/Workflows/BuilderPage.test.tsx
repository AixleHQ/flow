import '@testing-library/jest-dom/vitest';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { renderAuthedPage, screen, userEvent, waitFor } from 'test/renderPage';

import BuilderPage from './BuilderPage';

// --- Inline fixtures (structurally match the page's Props/Step/Workflow shapes) ---

const makeStep = (overrides: Record<string, unknown> = {}) => ({
  id: 1,
  name: 'Draft spec',
  instructions: null,
  position: 1,
  agentId: null,
  requiredAgentRuntime: null,
  preferredModel: null,
  allowNonInteractive: false,
  skipPolicy: 'never',
  onFailure: 'fail',
  maxRetries: 0,
  bmadEnabled: false,
  dependsOnStepIds: [] as number[],
  toolIds: [] as number[],
  mcpServerIds: [] as number[],
  skillIds: [] as number[],
  assetIds: [] as number[],
  repositoryIds: [] as number[],
  configItemIds: [] as number[],
  inputAssetSpecs: [] as { name: string; assetType: string; required: boolean; namePattern?: string | null }[],
  outputAssetSpecs: [] as { name: string; assetType: string; required: boolean; namePattern?: string | null }[],
  subSteps: [] as {
    id: number;
    name: string;
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
  baseRepositoryIds: [] as number[],
  baseConfigItemIds: [] as number[],
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
  configItems: [],
  agentModels: [],
  readOnly: false,
  configuredAgents: [] as string[],
  ...overrides,
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe('Projects/Workflows/BuilderPage', () => {
  it('renders the sessions sidebar and the first session selected in the detail panel', () => {
    renderAuthedPage(<BuilderPage />, { props: projectProps() });

    // Sessions tab is active.
    expect(screen.getByRole('button', { name: 'Sessions' })).toBeInTheDocument();

    // Both sessions listed in the sidebar.
    expect(screen.getAllByText('Draft spec').length).toBeGreaterThan(0);
    expect(screen.getByText('Implement')).toBeInTheDocument();

    // First session is auto-selected: its Name field is populated in the detail panel.
    expect(screen.getByDisplayValue('Draft spec')).toBeInTheDocument();

    // Run button is present because a project is set.
    expect(screen.getByRole('button', { name: 'Run' })).toBeInTheDocument();
  });

  it('shows the empty state when there are no sessions', () => {
    renderAuthedPage(<BuilderPage />, { props: projectProps({ steps: [] }) });

    expect(screen.getByText('No sessions yet')).toBeInTheDocument();
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

  it('creating the first session posts to the workflow steps endpoint', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, { props: projectProps({ steps: [] }) });

    // The "Add a session…" ghost row is a div, not a button — click it to start.
    await userEvent.click(screen.getByText('Add a session…'));

    // The ghost input should now be focused; type a name and confirm.
    const ghostInput = screen.getByPlaceholderText('Session name…');
    await userEvent.type(ghostInput, 'My session{Enter}');

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

    // Name renders as static text (not an editable input) and there is no Run affordance (no project).
    expect(screen.getByRole('heading', { level: 1, name: 'Company onboarding' })).toBeInTheDocument();
    expect(screen.queryByDisplayValue('Company onboarding')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Run' })).not.toBeInTheDocument();
  });

  it('renders status badges (AUTO / BMAD / runtime) for a session in the sidebar', () => {
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

    expect(screen.getByText('AUTO')).toBeInTheDocument();
    expect(screen.getByText('BMAD')).toBeInTheDocument();
    // Runtime value is mapped to its human label (badge + the detail-panel Select option both show it).
    expect(screen.getAllByText('Claude Code').length).toBeGreaterThan(0);
  });

  it('marks a session with no dependencies as "ROOT" and a dependent session with an "↳ AFTER" badge', () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [
          makeStep({ id: 1, name: 'Draft spec', position: 1, dependsOnStepIds: [] }),
          makeStep({ id: 2, name: 'Implement', position: 2, dependsOnStepIds: [1] }),
        ],
      }),
    });

    // Session 1 (root) gets a ROOT badge; session 2 references its dependency by name.
    expect(screen.getByText('ROOT')).toBeInTheDocument();
    expect(screen.getByText(/↳ AFTER\s*Draft spec/)).toBeInTheDocument();
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
      screen.getByText('Are you sure you want to delete this session? This action cannot be undone.'),
    ).toBeInTheDocument();

    // Confirm.
    await userEvent.click(screen.getByRole('button', { name: 'Delete' }));

    expect(fetchSpy).toHaveBeenCalledWith(
      '/api/v1/projects/7/workflows/3/steps/1',
      expect.objectContaining({ method: 'DELETE' }),
    );
  });

  it('cancelling the delete-session modal closes it without any request', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch');

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1 })] }),
    });

    await userEvent.click(document.querySelector('.tabler-icon-trash')!.closest('button')!);
    expect(
      screen.getByText('Are you sure you want to delete this session? This action cannot be undone.'),
    ).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    await waitFor(() =>
      expect(
        screen.queryByText('Are you sure you want to delete this session? This action cannot be undone.'),
      ).not.toBeInTheDocument(),
    );
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('attaching a config item to a step PATCHes configItemIds', async () => {
    const user = userEvent.setup();
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({}),
    } as Response);

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1 })],
        configItems: [
          { id: 11, name: 'STRIPE_KEY', itemType: 'secret' },
          { id: 12, name: 'API_BASE', itemType: 'variable' },
        ],
      }),
    });

    await user.click(screen.getByRole('combobox', { name: /secrets and variables/i }));
    await user.click(await screen.findByText('STRIPE_KEY (secret)'));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    const patch = fetchSpy.mock.calls.find(([, init]) => init?.method === 'PATCH');
    expect(JSON.parse(patch![1]!.body as string).step.configItemIds).toEqual([11]);
  });

  it('renders drag handles for sessions in the tree nav', () => {
    renderAuthedPage(<BuilderPage />, { props: projectProps() });

    // Both sessions have drag handles in the tree nav.
    const dragHandles = screen.getAllByTitle(/Drag to reorder session/);
    expect(dragHandles.length).toBe(2);
  });

  it('renders the session tree nav with both sessions', () => {
    renderAuthedPage(<BuilderPage />, { props: projectProps() });

    // Both session names appear in the tree nav.
    expect(screen.getAllByText('Draft spec').length).toBeGreaterThan(0);
    expect(screen.getByText('Implement')).toBeInTheDocument();
  });

  it('opening the Run modal shows the run dialog titled for the workflow', async () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, instructions: 'Do the thing' })],
      }),
    });

    await userEvent.click(screen.getByRole('button', { name: 'Run' }));

    // The Run modal title is split between "Run: " and workflowName across elements.
    // Use the dialog container accessible name or look for the individual parts.
    const modal = await screen.findByRole('dialog');
    expect(modal).toBeInTheDocument();
    expect(modal.textContent).toMatch(/Run:.*Release pipeline/);
    expect(screen.getByText('Execution Mode')).toBeInTheDocument();
  });

  it('disables the Run button when no session has instructions', () => {
    renderAuthedPage(<BuilderPage />, { props: projectProps() });

    // Default makeStep has no instructions, so Run should be disabled.
    expect(screen.getByRole('button', { name: 'Run' })).toBeDisabled();
  });

  it('editing the session name in the detail panel debounce-PATCHes the step endpoint', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1 })] }),
    });

    // The unlabelled session name input in the detail panel — find by current value.
    const nameInput = screen.getByDisplayValue('Draft spec');
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

    // Open the Agent <Select> (first combobox — the agent picker) and pick the option.
    const comboboxes = screen.getAllByRole('combobox');
    await userEvent.click(comboboxes[0]);
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

  it('shows the On Failure select in the Behavior section', () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, onFailure: 'retry' })],
      }),
    });

    // On Failure select is visible in the Behavior section.
    expect(screen.getByText('Behavior')).toBeInTheDocument();
  });

  it('shows the On Failure select defaulting to Fail', () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, onFailure: 'fail' })] }),
    });

    // Behavior section is always visible.
    expect(screen.getByText('Behavior')).toBeInTheDocument();
  });

  it('adds an asset spec row when "+ Add input" is clicked in the Data Flow section', async () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1 })] }),
    });

    // The Data Flow section is always visible; "None added" is shown by default.
    expect(screen.getAllByText('None added').length).toBeGreaterThan(0);

    // Click the "+ Add input" button to add an input spec.
    await userEvent.click(screen.getByRole('button', { name: '+ Add input' }));

    // A new editable path input (with the placeholder) appears.
    expect(await screen.findByPlaceholderText('e.g. tasks/report.md')).toBeInTheDocument();
  });

  it('renders sub-steps nested under a session in the tree nav', () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [
          makeStep({
            id: 1,
            name: 'Draft spec',
            position: 1,
            subSteps: [
              { id: 11, name: 'Task Alpha', instructions: null, position: 1, required: true },
              { id: 12, name: 'Task Beta', instructions: null, position: 2, required: false },
            ],
          }),
        ],
      }),
    });

    // Both sub-step names appear in the tree nav.
    expect(screen.getByText('Task Alpha')).toBeInTheDocument();
    expect(screen.getByText('Task Beta')).toBeInTheDocument();
  });

  it('shows the no-dependency helper text in the Dependencies section for a root session', () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, dependsOnStepIds: [] })] }),
    });

    expect(
      screen.getByText('No dependencies — this session can run in parallel with other root sessions.'),
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

    // Open the session-level Tools picker (first "None added" MultiSelect in the Resources section).
    await userEvent.click(screen.getAllByPlaceholderText('None added')[0]);

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

  it('opening the Triggers tab reveals the triggers content', async () => {
    renderAuthedPage(<BuilderPage />, { props: projectProps() });

    // Tab is not active initially — triggers content not visible.
    expect(screen.queryByText(/how this workflow launches/)).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Triggers' }));

    // The TriggersTab heading appears (text is split across elements).
    expect(await screen.findByText('Triggers', { selector: 'div' })).toBeInTheDocument();
    expect(await screen.findByText(/how this workflow launches/)).toBeInTheDocument();
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

    await userEvent.type(screen.getByPlaceholderText('Add a description…'), 'Ship');

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

    // Navigate to the Base Resources tab, then flip the inherit switch.
    await userEvent.click(screen.getByRole('button', { name: /Base Resources/ }));
    await userEvent.click(await screen.findByRole('switch'));

    // Observable state change: the helper text is always shown (it's static, not conditional).
    expect(
      await screen.findByText(/Tools, skills, MCP servers, and assets from the project level are included/),
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

    // Navigate to the Base Resources tab so its Tools picker is accessible.
    await userEvent.click(screen.getByRole('button', { name: /Base Resources/ }));
    // Open the base-resources Tools picker by placeholder.
    await userEvent.click(await screen.findByPlaceholderText('Select tools…'));
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

  it('selecting a base repository PATCHes config.baseRepositoryIds', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        repositories: [{ id: 21, name: 'acme/api' }],
        workflow: makeWorkflow({ inheritAllProjectResources: false }),
      }),
    });

    await userEvent.click(screen.getByRole('button', { name: /Base Resources/ }));
    await userEvent.click(await screen.findByPlaceholderText('Select repositories…'));
    await userEvent.click((await screen.findAllByRole('option', { name: 'acme/api' }))[0]);

    await waitFor(
      () => expect(fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/workflows/3')).toBeTruthy(),
      { timeout: 2000 },
    );
    const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/workflows/3');
    const body = JSON.parse((call![1] as RequestInit).body as string);
    expect(body.workflow.config.baseRepositoryIds).toEqual([21]);
  });

  // Repositories narrow the project-wide set rather than adding to it, so this
  // picker must stay usable when the other four are disabled by "inherit all".
  it('keeps the base repository picker enabled while "inherit all project resources" is on', async () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        repositories: [{ id: 21, name: 'acme/api' }],
        workflow: makeWorkflow({ inheritAllProjectResources: true }),
      }),
    });

    await userEvent.click(screen.getByRole('button', { name: /Base Resources/ }));

    expect(await screen.findByPlaceholderText('Select repositories…')).toBeEnabled();
    expect(screen.getByPlaceholderText('Select tools…')).toBeDisabled();
  });

  it('selecting a repository on a session PATCHes the step repositoryIds', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        repositories: [{ id: 21, name: 'acme/api' }],
        steps: [makeStep({ id: 1, name: 'Implement' })],
      }),
    });

    await userEvent.click(await screen.findByText('Implement'));
    // Mantine puts the aria-label on both the search input and the hidden value input.
    await userEvent.click((await screen.findAllByLabelText('Repositories'))[0]);
    await userEvent.click((await screen.findAllByRole('option', { name: 'acme/api' }))[0]);

    await waitFor(() => expect(fetchSpy.mock.calls.find(([url]) => String(url).includes('/steps/1'))).toBeTruthy(), {
      timeout: 2000,
    });
    const call = fetchSpy.mock.calls.find(([url]) => String(url).includes('/steps/1'));
    const body = JSON.parse((call![1] as RequestInit).body as string);
    expect(body.step.repositoryIds).toEqual([21]);
  });

  // step.asset_ids has always been a real column the API and MCP tools accept —
  // the session panel just never rendered a control for it.
  it('selecting an asset on a session PATCHes the step assetIds', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        assets: [{ id: 31, name: 'brand-guide.pdf' }],
        steps: [makeStep({ id: 1, name: 'Implement' })],
      }),
    });

    await userEvent.click(await screen.findByText('Implement'));
    await userEvent.click((await screen.findAllByLabelText('Assets'))[0]);
    await userEvent.click((await screen.findAllByRole('option', { name: 'brand-guide.pdf' }))[0]);

    await waitFor(() => expect(fetchSpy.mock.calls.find(([url]) => String(url).includes('/steps/1'))).toBeTruthy(), {
      timeout: 2000,
    });
    const call = fetchSpy.mock.calls.find(([url]) => String(url).includes('/steps/1'));
    const body = JSON.parse((call![1] as RequestInit).body as string);
    expect(body.step.assetIds).toEqual([31]);
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

    // The Behavior section has the auto-run switch; find all switches and click the first one
    // (Auto-run available is the first switch in the Behavior section).
    const switches = screen.getAllByRole('switch');
    const autoRunSwitch =
      switches.find((s) => {
        const row = s.closest('[class*=togRow]') ?? s.parentElement?.parentElement;
        return row?.textContent?.includes('Auto-run available');
      }) ?? switches[0];
    await userEvent.click(autoRunSwitch);

    // The sidebar session card now shows the "AUTO" badge.
    expect(await screen.findByText('AUTO')).toBeInTheDocument();

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

  it('setting On Failure to "Retry" PATCHes the step with the new value', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, onFailure: 'fail' })] }),
    });

    // Open the On Failure select by finding the combobox that currently shows "Fail".
    const allComboboxes = screen.getAllByRole('combobox');
    const onFailureCombobox = allComboboxes.find((cb) => cb.getAttribute('value') === 'Fail') ?? allComboboxes[3];
    await userEvent.click(onFailureCombobox);
    const retryOption = await screen.findByRole('option', { name: 'Retry' });
    await userEvent.click(retryOption);

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

  it('choosing an Execution Environment PATCHes the runtime and resets preferredModel', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, requiredAgentRuntime: null })],
      }),
    });

    // Execution Environment is the 2nd Select/combobox in the session editor (Agent is first).
    const comboboxes = screen.getAllByRole('combobox');
    const envCombobox = comboboxes[1];
    await userEvent.click(envCombobox);
    await userEvent.click(await screen.findByRole('option', { name: 'Cursor CLI' }));

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/steps/1',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
    const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/workflows/3/steps/1');
    const body = JSON.parse((call![1] as RequestInit).body as string);
    expect(body.step.requiredAgentRuntime).toBe('cursor_cli');
  });

  it('selecting an agent immediately PATCHes the step with the chosen agentId and runtime', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, requiredAgentRuntime: 'claude_code' })],
        agentModels: [{ agentType: 'claude_code', models: [{ modelId: 'opus-9', displayName: 'Opus 9' }] }],
      }),
    });

    // Claude Code is shown as the runtime value.
    expect(screen.getAllByText('Claude Code').length).toBeGreaterThan(0);

    await waitFor(() => expect(fetchSpy).not.toHaveBeenCalled());
  });

  it("choosing a Preferred Model PATCHes preferredModel, scoped to the runtime's models", async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, requiredAgentRuntime: 'claude_code' })],
        agentModels: [{ agentType: 'claude_code', models: [{ modelId: 'opus-9', displayName: 'Opus 9' }] }],
      }),
    });

    const preferredModelCombobox = screen.getAllByLabelText('Preferred model')[0];
    await userEvent.click(preferredModelCombobox);
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

  it('selecting a dependency PATCHes dependsOnStepIds and shows the "↳ AFTER" badge in the sidebar', async () => {
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

    // The Dependencies section is always visible — pick the other session.
    await userEvent.click(screen.getByPlaceholderText('Select sessions this session depends on…'));
    await userEvent.click(await screen.findByRole('option', { name: '2. Implement' }));

    // The sidebar card for session 1 now records the dependency.
    expect(await screen.findByText(/↳ AFTER\s*Implement/)).toBeInTheDocument();

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

  it('adding a sub-step via the tree nav ghost row PATCHes the step endpoint', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(
        JSON.stringify({
          data: { id: 1, name: 'Draft spec', subSteps: [{ id: 99, name: 'New step', position: 1, required: true }] },
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      ),
    );

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, subSteps: [] })] }),
    });

    // Click "Add a step…" ghost row inside the session.
    await userEvent.click(screen.getByText('Add a step…'));

    // Type a step name in the ghost input and confirm.
    const ghostInput = screen.getByPlaceholderText('Step name…');
    await userEvent.type(ghostInput, 'New step{Enter}');

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/steps/1',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
    const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/workflows/3/steps/1');
    const body = JSON.parse((call![1] as RequestInit).body as string);
    expect(body.step.subStepsAttributes[0]).toMatchObject({ name: 'New step', position: 1, required: true });
  });

  it('confirming a blank step name does not PATCH', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch');

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, subSteps: [] })] }),
    });

    await userEvent.click(screen.getByText('Add a step…'));
    const ghostInput = screen.getByPlaceholderText('Step name…');
    // Whitespace-only entry is treated as empty — the ghost row just closes.
    await userEvent.type(ghostInput, '   {Enter}');

    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('clicking a sub-step in the tree nav opens the StepEditorPanel', async () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [
          makeStep({
            id: 1,
            name: 'Draft spec',
            position: 1,
            subSteps: [{ id: 11, name: 'Task Alpha', instructions: null, position: 1, required: true }],
          }),
        ],
      }),
    });

    // The sub-step label "a" appears in the tree nav; click to select it.
    await userEvent.click(screen.getByText('Task Alpha'));

    // StepEditorPanel renders with the "Step name…" placeholder input.
    expect(await screen.findByPlaceholderText('Step name…')).toBeInTheDocument();
  });

  it('adding an output asset spec reveals the Match pattern input and PATCHes outputAssetSpecs', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1 })] }),
    });

    // Click "+ Add output" to add an output spec.
    await userEvent.click(screen.getByRole('button', { name: '+ Add output' }));

    // Output specs support a name pattern; the pattern input only renders there.
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
        const stepCalls = fetchSpy.mock.calls.filter(([url]) => url === '/api/v1/projects/7/workflows/3/steps/1');
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

    // Detail-panel session name input is present but disabled (no label — find by placeholder).
    expect(screen.getByPlaceholderText('Session name…')).toBeDisabled();

    // Run button is not shown in read-only mode.
    expect(screen.queryByRole('button', { name: 'Run' })).not.toBeInTheDocument();
  });
});
