import '@testing-library/jest-dom/vitest';
import { notifications } from '@mantine/notifications';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { answerFetch } from 'test/fetchStub';
import { renderAuthedPage, screen, userEvent, waitFor } from 'test/renderPage';

import type { aggregatePayload } from './builderDraft';
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
  currentVersionNumber: 1,
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

// --- Save: PUT …/aggregate, answered with the saved state the way the server echoes it ---

const SAVE_ROUTE = 'PUT /api/v1/projects/7/workflows/3/aggregate';

type Aggregate = ReturnType<typeof aggregatePayload>;
interface SaveBody {
  baseVersion: number;
  aggregate: Aggregate;
}

const CONFIG_FIELDS: Record<string, string> = {
  inherit_all_project_resources: 'inheritAllProjectResources',
  base_tool_ids: 'baseToolIds',
  base_skill_ids: 'baseSkillIds',
  base_mcp_server_ids: 'baseMCPServerIds',
  base_asset_ids: 'baseAssetIds',
  base_repository_ids: 'baseRepositoryIds',
  base_config_item_ids: 'baseConfigItemIds',
};

function savedState({ aggregate }: SaveBody, workflow: ReturnType<typeof makeWorkflow>) {
  const idByKey = new Map(aggregate.steps.map((step, i) => [step.key, step.id ?? 100 + i]));
  const steps = aggregate.steps.map(({ key, dependsOnStepIds, subSteps, ...fields }, i) =>
    makeStep({
      ...fields,
      id: idByKey.get(key),
      position: i + 1,
      dependsOnStepIds: dependsOnStepIds.map((depKey) => idByKey.get(depKey)),
      subSteps: subSteps.map((sub, j) => ({ ...sub, id: sub.id ?? 1000 + 10 * i + j, position: j + 1 })),
    }),
  );
  const config = Object.fromEntries(
    Object.entries(aggregate.config).map(([key, value]) => [CONFIG_FIELDS[key], value]),
  );
  return {
    workflow: {
      ...workflow,
      name: aggregate.name,
      description: aggregate.description,
      ...config,
      currentVersionNumber: 2,
    },
    steps,
    currentVersionNumber: 2,
    versionCreated: true,
  };
}

/** Answers the Save request, recording each body it was sent. */
function answerSave(workflow = makeWorkflow()) {
  const bodies: SaveBody[] = [];
  const fetchSpy = answerFetch({
    [SAVE_ROUTE]: (init?: RequestInit) => {
      const body = JSON.parse(String(init?.body)) as SaveBody;
      bodies.push(body);
      return savedState(body, workflow);
    },
  });
  return { fetchSpy, bodies };
}

/** Clicks Save and returns the aggregate it sent. */
async function save(bodies: SaveBody[]): Promise<Aggregate> {
  await userEvent.click(screen.getByRole('button', { name: 'Save' }));
  await waitFor(() => expect(bodies).toHaveLength(1));
  return bodies[0].aggregate;
}

afterEach(() => {
  vi.restoreAllMocks();
  notifications.clean();
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

  it('a session added from the ghost row is sent on Save as a new step and shows under its saved name', async () => {
    const { fetchSpy, bodies } = answerSave();
    renderAuthedPage(<BuilderPage />, { props: projectProps({ steps: [] }) });

    // The "Add a session…" ghost row is a div, not a button — click it to start.
    await userEvent.click(screen.getByText('Add a session…'));
    await userEvent.type(screen.getByPlaceholderText('Session name…'), 'My session{Enter}');
    expect(fetchSpy).not.toHaveBeenCalled();

    const aggregate = await save(bodies);

    expect(aggregate.steps).toHaveLength(1);
    expect(aggregate.steps[0]).toMatchObject({ id: null, name: 'My session' });
    expect(aggregate.steps[0].key).toMatch(/^new/);
    expect(await screen.findByDisplayValue('My session')).toBeInTheDocument();
    expect(screen.getByText('My session')).toBeInTheDocument();
  });

  it('a new session that an existing session depends on is sent with the dependency as the new step key', async () => {
    const { bodies } = answerSave();
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1 })] }),
    });

    // The ghost row focuses its input; the detail panel holds a second "Session name…" field.
    await userEvent.click(screen.getByText('Add a session…'));
    await userEvent.keyboard('Research{Enter}');

    // Back on the existing session, make it wait for the new one.
    await userEvent.click(screen.getByText('Draft spec'));
    await userEvent.click(screen.getByPlaceholderText('Select sessions this session depends on…'));
    await userEvent.click(await screen.findByRole('option', { name: '2. Research' }));

    const aggregate = await save(bodies);

    const [existing, added] = aggregate.steps;
    expect(added).toMatchObject({ id: null, name: 'Research' });
    expect(existing).toMatchObject({ id: 1, dependsOnStepIds: [added.key] });
    expect(await screen.findByText(/↳ AFTER\s*Research/)).toBeInTheDocument();
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

  it('removing a session through the modal drops it, and the dependencies on it, from the Save', async () => {
    const { fetchSpy, bodies } = answerSave();
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [
          makeStep({ id: 1, name: 'Draft spec', position: 1 }),
          makeStep({ id: 2, name: 'Implement', position: 2, dependsOnStepIds: [1] }),
        ],
      }),
    });

    await userEvent.click(screen.getByRole('button', { name: 'Delete session "Draft spec"' }));
    expect(await screen.findByRole('dialog', { name: 'Remove Session' })).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Remove' }));

    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Remove Session' })).not.toBeInTheDocument());
    expect(screen.queryByText('Draft spec')).not.toBeInTheDocument();
    expect(fetchSpy).not.toHaveBeenCalled();

    const aggregate = await save(bodies);

    expect(aggregate.steps).toHaveLength(1);
    expect(aggregate.steps[0]).toMatchObject({ id: 2, name: 'Implement', dependsOnStepIds: [] });
  });

  it('cancelling the remove-session modal closes it and keeps the session', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch');

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1 })] }),
    });

    await userEvent.click(screen.getByRole('button', { name: 'Delete session "Draft spec"' }));
    expect(await screen.findByRole('dialog', { name: 'Remove Session' })).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Remove Session' })).not.toBeInTheDocument());
    expect(screen.getByDisplayValue('Draft spec')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled();
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('a config item attached to a step is sent in its configItemIds on Save', async () => {
    const { fetchSpy, bodies } = answerSave();
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1 })],
        configItems: [
          { id: 11, name: 'STRIPE_KEY', itemType: 'secret' },
          { id: 12, name: 'API_BASE', itemType: 'variable' },
        ],
      }),
    });

    await userEvent.click(screen.getByRole('combobox', { name: /secrets and variables/i }));
    await userEvent.click(await screen.findByText('STRIPE_KEY (secret)'));
    expect(fetchSpy).not.toHaveBeenCalled();

    const aggregate = await save(bodies);

    expect(aggregate.steps[0].configItemIds).toEqual([11]);
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

  it('opening the Run drawer shows it titled for the workflow', async () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, instructions: 'Do the thing' })],
      }),
    });

    await userEvent.click(screen.getByRole('button', { name: 'Run' }));

    const drawer = await screen.findByRole('dialog');
    expect(drawer.textContent).toMatch(/Run:.*Release pipeline/);
    expect(screen.getByText('Execution mode')).toBeInTheDocument();
  });

  it('disables the Run button when no session has instructions', () => {
    renderAuthedPage(<BuilderPage />, { props: projectProps() });

    // Default makeStep has no instructions, so Run should be disabled.
    expect(screen.getByRole('button', { name: 'Run' })).toBeDisabled();
  });

  it('an edited session name is sent on Save', async () => {
    const { fetchSpy, bodies } = answerSave();
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1 })] }),
    });

    await userEvent.type(screen.getByRole('textbox', { name: 'Session name' }), '!');
    expect(fetchSpy).not.toHaveBeenCalled();

    const aggregate = await save(bodies);

    expect(aggregate.steps[0]).toMatchObject({ id: 1, key: '1', name: 'Draft spec!' });
  });

  it('an edit shows the unsaved-changes notice until Save succeeds, then reports the new version', async () => {
    const { bodies } = answerSave();
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, instructions: 'Do the thing' })],
      }),
    });

    expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled();
    expect(screen.queryByText('Unsaved changes — press Save to keep them')).not.toBeInTheDocument();

    await userEvent.type(screen.getByRole('textbox', { name: 'Session name' }), '!');

    expect(screen.getByText('Unsaved changes — press Save to keep them')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Save' })).toBeEnabled();
    // A run uses the saved workflow, so it waits for the save.
    expect(screen.getByRole('button', { name: 'Run' })).toBeDisabled();

    const aggregate = await save(bodies);

    expect(bodies[0].baseVersion).toBe(1);
    expect(aggregate.steps[0].name).toBe('Draft spec!');
    expect(await screen.findByText('Saved as version 2')).toBeInTheDocument();
    expect(screen.queryByText('Unsaved changes — press Save to keep them')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Run' })).toBeEnabled();
  });

  it('a Save refused with a conflict keeps the edit on screen and says how to recover it', async () => {
    answerFetch({
      [SAVE_ROUTE]: new Response(
        JSON.stringify({
          error: 'Someone else saved a newer version (v2). Reload to see their changes before saving.',
          currentVersionNumber: 2,
        }),
        { status: 409, headers: { 'Content-Type': 'application/json' } },
      ),
    });
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1 })] }),
    });

    await userEvent.type(screen.getByRole('textbox', { name: 'Session name' }), '!');
    await userEvent.click(screen.getByRole('button', { name: 'Save' }));

    expect(
      await screen.findByText(
        'Someone else saved a newer version (v2). Reload to see their changes before saving. Your edits are still here — copy what you need, then reload.',
      ),
    ).toBeInTheDocument();
    expect(screen.getByDisplayValue('Draft spec!')).toBeInTheDocument();
    expect(screen.getByText('Unsaved changes — press Save to keep them')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Save' })).toBeEnabled();
  });

  it('the chosen agent is sent in the step agentId on Save', async () => {
    const { fetchSpy, bodies } = answerSave();
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        agents: [{ id: 42, name: 'Builder Bot' }],
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, agentId: null })],
      }),
    });

    await userEvent.click(screen.getByRole('combobox', { name: 'Agent' }));
    await userEvent.click(await screen.findByRole('option', { name: 'Builder Bot' }));
    expect(fetchSpy).not.toHaveBeenCalled();

    const aggregate = await save(bodies);

    expect(aggregate.steps[0].agentId).toBe(42);
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

  it('offers a tool group as a section whose members open individually', async () => {
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

    // Open the session-level Tools picker (first "None added" field in the Resources section).
    await userEvent.click(screen.getAllByPlaceholderText('None added')[0]);

    // The group shows as a section header; its members stay folded away until asked for.
    expect(await screen.findByRole('checkbox', { name: /Board management/ })).toBeInTheDocument();
    expect(screen.queryByRole('option', { name: 'Board List Tasks' })).not.toBeInTheDocument();
    // Ungrouped custom tool stays individual.
    expect(screen.getByRole('option', { name: 'Echo Greeter' })).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Expand Board management' }));

    expect(screen.getByRole('option', { name: 'Board List Tasks' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Board Move Task' })).toBeInTheDocument();
  });

  it('renders the workflow scope indicator badge in the header', () => {
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ workflow: makeWorkflow({ scopeIndicator: 'Project' }) }),
    });

    // The scope indicator is shown as a badge next to the title.
    expect(screen.getByText('Project')).toBeInTheDocument();
  });

  it('opening the Triggers tab reveals the triggers content', async () => {
    answerFetch({ 'GET /api/v1/projects/7/workflows/:workflow/triggers': { triggers: [] } });
    renderAuthedPage(<BuilderPage />, { props: projectProps() });

    // Tab is not active initially — triggers content not visible.
    expect(screen.queryByText(/how this workflow launches/)).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Triggers' }));

    // The TriggersTab heading appears (text is split across elements).
    expect(await screen.findByText('Triggers', { selector: 'div' })).toBeInTheDocument();
    expect(await screen.findByText(/how this workflow launches/)).toBeInTheDocument();
  });

  it('an edited workflow name is sent on Save', async () => {
    const { fetchSpy, bodies } = answerSave();
    renderAuthedPage(<BuilderPage />, { props: projectProps() });

    await userEvent.type(screen.getByRole('textbox', { name: 'Workflow name' }), '!');
    expect(fetchSpy).not.toHaveBeenCalled();

    const aggregate = await save(bodies);

    expect(aggregate.name).toBe('Release pipeline!');
    expect(await screen.findByDisplayValue('Release pipeline!')).toBeInTheDocument();
  });

  it('an edited workflow description is sent on Save', async () => {
    const { fetchSpy, bodies } = answerSave();
    renderAuthedPage(<BuilderPage />, { props: projectProps() });

    await userEvent.type(screen.getByPlaceholderText('Add a description…'), 'Ship');
    expect(fetchSpy).not.toHaveBeenCalled();

    const aggregate = await save(bodies);

    expect(aggregate.description).toBe('Ship');
  });

  it('toggling "Inherit all project resources" shows the helper text and is sent in the config on Save', async () => {
    const workflow = makeWorkflow({ inheritAllProjectResources: false });
    const { fetchSpy, bodies } = answerSave(workflow);
    renderAuthedPage(<BuilderPage />, { props: projectProps({ workflow }) });

    // Navigate to the Base Resources tab, then flip the inherit switch.
    await userEvent.click(screen.getByRole('button', { name: /Base Resources/ }));
    await userEvent.click(await screen.findByRole('switch'));

    expect(
      await screen.findByText(/Tools, skills, MCP servers, and assets from the project level are included/),
    ).toBeInTheDocument();
    expect(fetchSpy).not.toHaveBeenCalled();

    const aggregate = await save(bodies);

    expect(aggregate.config.inherit_all_project_resources).toBe(true);
  });

  it('attaching a base tool group from its header sends every member in base_tool_ids on Save', async () => {
    const workflow = makeWorkflow({ inheritAllProjectResources: false });
    const { bodies } = answerSave(workflow);
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        tools: [
          { id: 10, name: 'Board List Tasks' },
          { id: 11, name: 'Board Move Task' },
        ],
        toolGroups: [{ tag: 'board', label: 'Board management', toolIds: [10, 11] }],
        workflow,
      }),
    });

    await userEvent.click(screen.getByRole('button', { name: /Base Resources/ }));
    await userEvent.click(await screen.findByPlaceholderText('Select tools…'));
    await userEvent.click(await screen.findByRole('checkbox', { name: /Board management/ }));

    const aggregate = await save(bodies);

    // One click on the header attaches the whole family.
    expect(aggregate.config.base_tool_ids).toEqual([10, 11]);
  });

  it('attaching one tool out of a base group sends that id alone in base_tool_ids on Save', async () => {
    const workflow = makeWorkflow({ inheritAllProjectResources: false });
    const { bodies } = answerSave(workflow);
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        tools: [
          { id: 10, name: 'Board List Tasks' },
          { id: 11, name: 'Board Move Task' },
        ],
        toolGroups: [{ tag: 'board', label: 'Board management', toolIds: [10, 11] }],
        workflow,
      }),
    });

    await userEvent.click(screen.getByRole('button', { name: /Base Resources/ }));
    await userEvent.click(await screen.findByPlaceholderText('Select tools…'));
    await userEvent.click(await screen.findByRole('button', { name: 'Expand Board management' }));
    await userEvent.click(screen.getByRole('option', { name: 'Board Move Task' }));

    const aggregate = await save(bodies);

    // A subset stays a subset — no silent expansion to the whole group.
    expect(aggregate.config.base_tool_ids).toEqual([11]);
  });

  it('a selected base repository is sent in base_repository_ids on Save', async () => {
    const workflow = makeWorkflow({ inheritAllProjectResources: false });
    const { bodies } = answerSave(workflow);
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ repositories: [{ id: 21, name: 'acme/api' }], workflow }),
    });

    await userEvent.click(screen.getByRole('button', { name: /Base Resources/ }));
    await userEvent.click(await screen.findByPlaceholderText('Select repositories…'));
    await userEvent.click((await screen.findAllByRole('option', { name: 'acme/api' }))[0]);

    const aggregate = await save(bodies);

    expect(aggregate.config.base_repository_ids).toEqual([21]);
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

  it('a repository selected on a session is sent in the step repositoryIds on Save', async () => {
    const { bodies } = answerSave();
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

    const aggregate = await save(bodies);

    expect(aggregate.steps[0].repositoryIds).toEqual([21]);
  });

  it('an asset selected on a session is sent in the step assetIds on Save', async () => {
    const { bodies } = answerSave();
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        assets: [{ id: 31, name: 'brand-guide.pdf' }],
        steps: [makeStep({ id: 1, name: 'Implement' })],
      }),
    });

    await userEvent.click(await screen.findByText('Implement'));
    await userEvent.click((await screen.findAllByLabelText('Assets'))[0]);
    await userEvent.click((await screen.findAllByRole('option', { name: 'brand-guide.pdf' }))[0]);

    const aggregate = await save(bodies);

    expect(aggregate.steps[0].assetIds).toEqual([31]);
  });

  it('toggling "Auto-run available" surfaces the "AUTO" badge and is sent on Save', async () => {
    const { fetchSpy, bodies } = answerSave();
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, allowNonInteractive: false })],
      }),
    });

    // With no asset specs, the first switch on the session panel is "Auto-run available".
    await userEvent.click(screen.getAllByRole('switch')[0]);

    expect(await screen.findByText('AUTO')).toBeInTheDocument();
    expect(fetchSpy).not.toHaveBeenCalled();

    const aggregate = await save(bodies);

    expect(aggregate.steps[0].allowNonInteractive).toBe(true);
    expect(screen.getByText('AUTO')).toBeInTheDocument();
  });

  it('setting On Failure to "Retry" is sent on Save', async () => {
    const { bodies } = answerSave();
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, onFailure: 'fail' })] }),
    });

    // The On Failure select has no accessible name; it is the combobox currently showing "Fail".
    const onFailureCombobox = screen.getAllByRole('combobox').find((cb) => cb.getAttribute('value') === 'Fail');
    await userEvent.click(onFailureCombobox!);
    await userEvent.click(await screen.findByRole('option', { name: 'Retry' }));

    const aggregate = await save(bodies);

    expect(aggregate.steps[0].onFailure).toBe('retry');
  });

  it('choosing an Execution Environment sends the runtime and a cleared preferredModel on Save', async () => {
    const { bodies } = answerSave();
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [
          makeStep({
            id: 1,
            name: 'Draft spec',
            position: 1,
            requiredAgentRuntime: 'claude_code',
            preferredModel: 'opus-9',
          }),
        ],
        agentModels: [{ agentType: 'claude_code', models: [{ modelId: 'opus-9', displayName: 'Opus 9' }] }],
      }),
    });

    await userEvent.click(screen.getByRole('combobox', { name: 'Required agent runtime' }));
    await userEvent.click(await screen.findByRole('option', { name: 'Cursor CLI' }));

    const aggregate = await save(bodies);

    expect(aggregate.steps[0]).toMatchObject({ requiredAgentRuntime: 'cursor_cli', preferredModel: null });
  });

  it('shows a step runtime set on the server without making a request', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch');

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

  it("a Preferred Model picked from the runtime's models is sent on Save", async () => {
    const { bodies } = answerSave();
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({
        steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, requiredAgentRuntime: 'claude_code' })],
        agentModels: [
          { agentType: 'claude_code', models: [{ modelId: 'opus-9', displayName: 'Opus 9' }] },
          { agentType: 'cursor_cli', models: [{ modelId: 'gpt-x', displayName: 'GPT X' }] },
        ],
      }),
    });

    await userEvent.click(screen.getAllByLabelText('Preferred model')[0]);
    expect(await screen.findByRole('option', { name: 'Opus 9' })).toBeInTheDocument();
    expect(screen.queryByRole('option', { name: 'GPT X' })).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('option', { name: 'Opus 9' }));

    const aggregate = await save(bodies);

    expect(aggregate.steps[0].preferredModel).toBe('opus-9');
  });

  it('a selected dependency shows the "↳ AFTER" badge in the sidebar and is sent by step key on Save', async () => {
    const { fetchSpy, bodies } = answerSave();
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
    expect(fetchSpy).not.toHaveBeenCalled();

    const aggregate = await save(bodies);

    expect(aggregate.steps[0].dependsOnStepIds).toEqual(['2']);
  });

  it('a sub-step added via the tree nav ghost row is sent as a new sub-step on Save', async () => {
    const { fetchSpy, bodies } = answerSave();
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, subSteps: [] })] }),
    });

    await userEvent.click(screen.getByText('Add a step…'));
    await userEvent.type(screen.getByPlaceholderText('Step name…'), 'New step{Enter}');
    expect(fetchSpy).not.toHaveBeenCalled();

    const aggregate = await save(bodies);

    expect(aggregate.steps[0].subSteps).toEqual([{ id: null, name: 'New step', instructions: null, required: true }]);
    expect(screen.getByText('New step')).toBeInTheDocument();
  });

  it('confirming a blank step name adds nothing', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch');

    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1, subSteps: [] })] }),
    });

    await userEvent.click(screen.getByText('Add a step…'));
    const ghostInput = screen.getByPlaceholderText('Step name…');
    // Whitespace-only entry is treated as empty — the ghost row just closes.
    await userEvent.type(ghostInput, '   {Enter}');

    expect(fetchSpy).not.toHaveBeenCalled();
    expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled();
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

  it('adding an output asset spec reveals the Match pattern input and is sent in outputAssetSpecs on Save', async () => {
    const { fetchSpy, bodies } = answerSave();
    renderAuthedPage(<BuilderPage />, {
      props: projectProps({ steps: [makeStep({ id: 1, name: 'Draft spec', position: 1 })] }),
    });

    await userEvent.click(screen.getByRole('button', { name: '+ Add output' }));

    // Output specs support a name pattern; the pattern input only renders there.
    expect(screen.getByPlaceholderText('e.g. report')).toBeInTheDocument();

    await userEvent.type(screen.getByPlaceholderText('e.g. tasks/report.md'), 'out.md');
    expect(fetchSpy).not.toHaveBeenCalled();

    const aggregate = await save(bodies);

    expect(aggregate.steps[0].outputAssetSpecs).toHaveLength(1);
    expect(aggregate.steps[0].outputAssetSpecs[0].name).toBe('out.md');
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
