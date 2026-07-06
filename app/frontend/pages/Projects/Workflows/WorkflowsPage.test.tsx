import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { buildProject } from 'test/factories/project';
import { renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import WorkflowsPage from './WorkflowsPage';

// buildProject is the typed factory; the page only reads project.id (URL building) and project.name,
// so a full generated Project with these overrides preserves every assertion here.
const project = buildProject({ id: 7, name: 'Atlas Project' });

const workflow = (overrides: Record<string, unknown> = {}) => ({
  id: 1,
  name: 'Nightly Build',
  description: 'Runs the nightly build',
  scopeType: 'Project',
  scopeId: 7,
  scopeIndicator: 'project' as const,
  stepsCount: 3,
  lastRunAt: null,
  lastRunStatus: null,
  hasActiveRuns: false,
  descriptionExcerpt: 'Runs the nightly build',
  publishedAt: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  steps: [],
  ...overrides,
});

const baseProps = (workflows: ReturnType<typeof workflow>[]) => ({
  project,
  workflows,
  configuredAgents: [],
});

// The card actions are icon-only Mantine ActionIcons whose Tooltip label is NOT exposed as an
// accessible name, so locate them by their stable (non-hashed) tabler icon class.
const iconButton = (root: HTMLElement, iconClass: string): HTMLButtonElement => {
  const svg = root.querySelector(`svg.${iconClass}`);
  const btn = svg?.closest('button');
  if (!btn) throw new Error(`No button containing svg.${iconClass}`);
  return btn as HTMLButtonElement;
};

describe('Projects/Workflows/WorkflowsPage', () => {
  it('renders the empty state with a create CTA when there are no workflows', () => {
    renderAuthedPage(<WorkflowsPage />, { props: baseProps([]) });

    expect(screen.getByText('No workflows yet')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Create your first workflow' })).toBeInTheDocument();
    // Builder banner CTA is always present.
    expect(screen.getByRole('button', { name: 'Open Builder' })).toBeInTheDocument();
  });

  it('lists workflows and filters them by the search query', async () => {
    renderAuthedPage(<WorkflowsPage />, {
      props: baseProps([
        workflow({ id: 1, name: 'Nightly Build' }),
        workflow({ id: 2, name: 'Deploy Pipeline', descriptionExcerpt: 'Ships to prod' }),
      ]),
    });

    expect(screen.getByText('Nightly Build')).toBeInTheDocument();
    expect(screen.getByText('Deploy Pipeline')).toBeInTheDocument();

    await userEvent.type(screen.getByPlaceholderText('Search workflows...'), 'deploy');

    // Search is debounced (300ms) before the list re-filters.
    await waitFor(() => expect(screen.queryByText('Nightly Build')).not.toBeInTheDocument());
    expect(screen.getByText('Deploy Pipeline')).toBeInTheDocument();
  });

  it('shows the no-match state when the search matches nothing', async () => {
    renderAuthedPage(<WorkflowsPage />, { props: baseProps([workflow({ name: 'Nightly Build' })]) });

    await userEvent.type(screen.getByPlaceholderText('Search workflows...'), 'zzz');

    expect(await screen.findByText('No workflows match your search')).toBeInTheDocument();
  });

  it('navigates to the builder when Configure is clicked on a workflow card', async () => {
    renderAuthedPage(<WorkflowsPage />, { props: baseProps([workflow({ id: 42, name: 'Nightly Build' })]) });

    await userEvent.click(screen.getByRole('button', { name: 'Configure' }));

    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/workflows/42/builder');
  });

  it('opens the New Workflow modal when the toolbar button is clicked', async () => {
    renderAuthedPage(<WorkflowsPage />, { props: baseProps([workflow({ name: 'Nightly Build' })]) });

    await userEvent.click(screen.getByRole('button', { name: 'New Workflow' }));

    const dialog = await screen.findByRole('dialog', { name: 'New Workflow' });
    expect(within(dialog).getByRole('textbox', { name: /name/i })).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Create' })).toBeInTheDocument();
  });

  it('navigates to run history from the toolbar', async () => {
    renderAuthedPage(<WorkflowsPage />, { props: baseProps([workflow({ name: 'Nightly Build' })]) });

    await userEvent.click(screen.getByRole('button', { name: 'Run History' }));

    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/workflow_runs');
  });

  it('navigates to the catalog from the toolbar', async () => {
    renderAuthedPage(<WorkflowsPage />, { props: baseProps([workflow({ name: 'Nightly Build' })]) });

    await userEvent.click(screen.getByRole('button', { name: 'Catalog' }));

    expect(router.visit).toHaveBeenCalledWith('/company/workflow_catalog');
  });

  it('navigates to the Aixle Builder from the banner CTA', async () => {
    renderAuthedPage(<WorkflowsPage />, { props: baseProps([]) });

    await userEvent.click(screen.getByRole('button', { name: 'Open Builder' }));

    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/aixle_builder');
  });

  it('shows the step count and last-run date on a workflow card', () => {
    renderAuthedPage(<WorkflowsPage />, {
      props: baseProps([workflow({ id: 1, name: 'Nightly Build', stepsCount: 5, lastRunAt: '2026-03-15T10:00:00Z' })]),
    });

    const lastRunDate = new Date('2026-03-15T10:00:00Z').toLocaleDateString();
    expect(screen.getByText(/5 steps/)).toBeInTheDocument();
    expect(screen.getByText(new RegExp(`Last run ${lastRunDate}`))).toBeInTheDocument();
  });

  it('does not render a last-run date when the workflow has never run', () => {
    renderAuthedPage(<WorkflowsPage />, {
      props: baseProps([workflow({ id: 1, name: 'Nightly Build', stepsCount: 2, lastRunAt: null })]),
    });

    expect(screen.getByText(/2 steps/)).toBeInTheDocument();
    expect(screen.queryByText(/Last run/)).not.toBeInTheDocument();
  });

  it('renders a company badge and a Copy & Configure action for inherited workflows', () => {
    const { container } = renderAuthedPage(<WorkflowsPage />, {
      props: baseProps([workflow({ id: 9, name: 'Inherited Flow', scopeIndicator: 'company' })]),
    });

    // Inherited workflows get a "company" badge...
    expect(screen.getByText('company')).toBeInTheDocument();
    // ...and the edit/delete/publish controls are replaced by Copy & Configure (copy icon) only.
    expect(container.querySelector('svg.tabler-icon-copy')).toBeInTheDocument();
    expect(container.querySelector('svg.tabler-icon-edit')).not.toBeInTheDocument();
    expect(container.querySelector('svg.tabler-icon-trash')).not.toBeInTheDocument();
  });

  it('posts a copy when Copy & Configure is clicked on an inherited workflow', async () => {
    const { container } = renderAuthedPage(<WorkflowsPage />, {
      props: baseProps([
        workflow({ id: 9, name: 'Inherited Flow', description: 'Shared by company', scopeIndicator: 'company' }),
      ]),
    });

    await userEvent.click(iconButton(container, 'tabler-icon-copy'));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflows',
      { workflow: { name: 'Inherited Flow', description: 'Shared by company' } },
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('shows publish/edit/delete controls for project-scoped workflows', () => {
    const { container } = renderAuthedPage(<WorkflowsPage />, {
      props: baseProps([workflow({ id: 1, name: 'Nightly Build', scopeIndicator: 'project', publishedAt: null })]),
    });

    // Unpublished project workflow shows the globe-off (publish) icon, plus edit + trash.
    expect(container.querySelector('svg.tabler-icon-globe-off')).toBeInTheDocument();
    expect(container.querySelector('svg.tabler-icon-edit')).toBeInTheDocument();
    expect(container.querySelector('svg.tabler-icon-trash')).toBeInTheDocument();
    expect(container.querySelector('svg.tabler-icon-copy')).not.toBeInTheDocument();
  });

  it('posts to the publish endpoint for an unpublished workflow', async () => {
    const { container } = renderAuthedPage(<WorkflowsPage />, {
      props: baseProps([workflow({ id: 5, name: 'Nightly Build', publishedAt: null })]),
    });

    // Unpublished -> globe-off icon -> clicking publishes.
    await userEvent.click(iconButton(container, 'tabler-icon-globe-off'));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflows/5/publish',
      {},
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('posts to the unpublish endpoint for an already-published workflow', async () => {
    const { container } = renderAuthedPage(<WorkflowsPage />, {
      props: baseProps([workflow({ id: 5, name: 'Nightly Build', publishedAt: '2026-02-01T00:00:00Z' })]),
    });

    // Published -> globe icon -> clicking unpublishes.
    await userEvent.click(iconButton(container, 'tabler-icon-globe'));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflows/5/unpublish',
      {},
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('opens the Edit modal seeded with the workflow name when Edit is clicked', async () => {
    const { container } = renderAuthedPage(<WorkflowsPage />, {
      props: baseProps([workflow({ id: 3, name: 'Nightly Build', description: 'Runs the nightly build' })]),
    });

    await userEvent.click(iconButton(container, 'tabler-icon-edit'));

    const dialog = await screen.findByRole('dialog', { name: 'Edit Workflow' });
    expect(within(dialog).getByRole('textbox', { name: /name/i })).toHaveValue('Nightly Build');
    expect(within(dialog).getByRole('button', { name: 'Save' })).toBeInTheDocument();
  });

  it('patches the workflow when the Edit form is submitted', async () => {
    const { container } = renderAuthedPage(<WorkflowsPage />, {
      props: baseProps([workflow({ id: 3, name: 'Nightly Build', description: 'Runs the nightly build' })]),
    });

    await userEvent.click(iconButton(container, 'tabler-icon-edit'));
    const dialog = await screen.findByRole('dialog', { name: 'Edit Workflow' });
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save' }));

    expect(router.patch).toHaveBeenCalledWith(
      '/company/projects/7/workflows/3',
      { workflow: { name: 'Nightly Build', description: 'Runs the nightly build' } },
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('creates a workflow when the New Workflow form is filled and submitted', async () => {
    renderAuthedPage(<WorkflowsPage />, { props: baseProps([]) });

    await userEvent.click(screen.getByRole('button', { name: 'New Workflow' }));
    const dialog = await screen.findByRole('dialog', { name: 'New Workflow' });
    await userEvent.type(within(dialog).getByRole('textbox', { name: /name/i }), 'Release Flow');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Create' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflows',
      expect.objectContaining({ workflow: expect.objectContaining({ name: 'Release Flow' }) }),
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('blocks creation and does not POST when the name is empty', async () => {
    renderAuthedPage(<WorkflowsPage />, { props: baseProps([]) });

    await userEvent.click(screen.getByRole('button', { name: 'New Workflow' }));
    const dialog = await screen.findByRole('dialog', { name: 'New Workflow' });
    // Submitting with an empty (required) name must be blocked by zod validation.
    await userEvent.click(within(dialog).getByRole('button', { name: 'Create' }));

    expect(router.post).not.toHaveBeenCalled();
    // The modal stays open (the Create button is still on screen).
    expect(within(dialog).getByRole('button', { name: 'Create' })).toBeInTheDocument();
  });

  it('opens the delete confirmation naming the workflow and deletes it', async () => {
    const { container } = renderAuthedPage(<WorkflowsPage />, {
      props: baseProps([workflow({ id: 11, name: 'Nightly Build', hasActiveRuns: false })]),
    });

    await userEvent.click(iconButton(container, 'tabler-icon-trash'));

    const dialog = await screen.findByRole('dialog', { name: 'Delete Workflow' });
    expect(within(dialog).getByText('Nightly Build')).toBeInTheDocument();

    await userEvent.click(within(dialog).getByRole('button', { name: 'Delete' }));

    expect(router.delete).toHaveBeenCalledWith(
      '/company/projects/7/workflows/11',
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('disables Delete and warns when the workflow has active runs', async () => {
    const { container } = renderAuthedPage(<WorkflowsPage />, {
      props: baseProps([workflow({ id: 11, name: 'Nightly Build', hasActiveRuns: true })]),
    });

    await userEvent.click(iconButton(container, 'tabler-icon-trash'));

    const dialog = await screen.findByRole('dialog', { name: 'Delete Workflow' });
    expect(within(dialog).getByText('This workflow has active runs. Stop them first.')).toBeInTheDocument();

    const deleteBtn = within(dialog).getByRole('button', { name: 'Delete' });
    expect(deleteBtn).toBeDisabled();

    await userEvent.click(deleteBtn);
    expect(router.delete).not.toHaveBeenCalled();
  });

  it('opens the Run Workflow modal when Run is clicked on a card', async () => {
    renderAuthedPage(<WorkflowsPage />, {
      props: baseProps([workflow({ id: 4, name: 'Nightly Build' })]),
    });

    await userEvent.click(screen.getByRole('button', { name: 'Run' }));

    const dialog = await screen.findByRole('dialog', { name: /Run: Nightly Build/ });
    expect(within(dialog).getByText('Execution Mode')).toBeInTheDocument();
  });

  // --- Read-only viewer (canExecute:false) -------------------------------------------------------
  // useProjectPermissions() reads the shared `projectPermissions` prop and defaults canExecute to
  // true, so every test above exercises the executor branch. Seeding it false hits the gated paths.
  it('hides the create CTAs in the empty state for a read-only viewer (canExecute:false)', () => {
    renderAuthedPage(<WorkflowsPage />, {
      props: { ...baseProps([]), projectPermissions: { canExecute: false, canManage: false } },
    });

    expect(screen.getByText('No workflows yet')).toBeInTheDocument();
    // Both the empty-state CTA and the toolbar button are gated behind canExecute.
    expect(screen.queryByRole('button', { name: 'Create your first workflow' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'New Workflow' })).not.toBeInTheDocument();
  });

  it('hides run/mutate controls but keeps Configure for a read-only viewer (canExecute:false)', () => {
    const { container } = renderAuthedPage(<WorkflowsPage />, {
      props: {
        ...baseProps([workflow({ id: 1, name: 'Nightly Build', scopeIndicator: 'project' })]),
        projectPermissions: { canExecute: false, canManage: false },
      },
    });

    // Configure is ungated — a viewer can still open the (read-only) builder.
    expect(screen.getByRole('button', { name: 'Configure' })).toBeInTheDocument();
    // Every execute/mutate affordance is gone: Run, New Workflow, and the icon-only edit/trash/publish.
    expect(screen.queryByRole('button', { name: 'Run' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'New Workflow' })).not.toBeInTheDocument();
    expect(container.querySelector('svg.tabler-icon-edit')).not.toBeInTheDocument();
    expect(container.querySelector('svg.tabler-icon-trash')).not.toBeInTheDocument();
    expect(container.querySelector('svg.tabler-icon-globe-off')).not.toBeInTheDocument();
  });

  // --- Search filter branches --------------------------------------------------------------------
  it('filters workflows by a term that only appears in the description', async () => {
    renderAuthedPage(<WorkflowsPage />, {
      props: baseProps([
        workflow({ id: 1, name: 'Alpha', description: 'no match here' }),
        workflow({ id: 2, name: 'Beta', description: 'contains the zephyr keyword' }),
      ]),
    });

    // 'zephyr' matches only Beta's description (not its name), hitting the `w.description?...` branch
    // of the filter's OR that the name-only search tests never reach.
    await userEvent.type(screen.getByPlaceholderText('Search workflows...'), 'zephyr');

    await waitFor(() => expect(screen.queryByText('Alpha')).not.toBeInTheDocument());
    expect(screen.getByText('Beta')).toBeInTheDocument();
  });

  it('suppresses the create CTA in the no-match state even when execution is allowed', async () => {
    renderAuthedPage(<WorkflowsPage />, { props: baseProps([workflow({ name: 'Nightly Build' })]) });

    await userEvent.type(screen.getByPlaceholderText('Search workflows...'), 'zzz');

    expect(await screen.findByText('No workflows match your search')).toBeInTheDocument();
    // The CTA is `!search && canExecute`; an active search must hide it despite canExecute being true.
    expect(screen.queryByRole('button', { name: 'Create your first workflow' })).not.toBeInTheDocument();
  });

  // --- Modal dismissal (Cancel handlers) ---------------------------------------------------------
  it('closes the New Workflow modal via Cancel without posting', async () => {
    renderAuthedPage(<WorkflowsPage />, { props: baseProps([]) });

    await userEvent.click(screen.getByRole('button', { name: 'New Workflow' }));
    const dialog = await screen.findByRole('dialog', { name: 'New Workflow' });

    await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));

    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'New Workflow' })).not.toBeInTheDocument());
    expect(router.post).not.toHaveBeenCalled();
  });

  it('closes the delete confirmation via Cancel without deleting', async () => {
    const { container } = renderAuthedPage(<WorkflowsPage />, {
      props: baseProps([workflow({ id: 11, name: 'Nightly Build' })]),
    });

    await userEvent.click(iconButton(container, 'tabler-icon-trash'));
    const dialog = await screen.findByRole('dialog', { name: 'Delete Workflow' });

    await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));

    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Delete Workflow' })).not.toBeInTheDocument());
    expect(router.delete).not.toHaveBeenCalled();
  });

  // --- Edit + create form details ----------------------------------------------------------------
  it('seeds an empty description in the Edit modal when the workflow has none', async () => {
    // openEdit() does `description: wf.description ?? ''` — a null description must seed an empty field.
    const { container } = renderAuthedPage(<WorkflowsPage />, {
      props: baseProps([workflow({ id: 3, name: 'Nightly Build', description: null })]),
    });

    await userEvent.click(iconButton(container, 'tabler-icon-edit'));
    const dialog = await screen.findByRole('dialog', { name: 'Edit Workflow' });

    expect(within(dialog).getByRole('textbox', { name: /name/i })).toHaveValue('Nightly Build');
    expect(within(dialog).getByRole('textbox', { name: /description/i })).toHaveValue('');
  });

  it('patches with the edited name when the Edit form is changed and submitted', async () => {
    const { container } = renderAuthedPage(<WorkflowsPage />, {
      props: baseProps([workflow({ id: 3, name: 'Nightly Build', description: 'Runs the nightly build' })]),
    });

    await userEvent.click(iconButton(container, 'tabler-icon-edit'));
    const dialog = await screen.findByRole('dialog', { name: 'Edit Workflow' });

    const nameInput = within(dialog).getByRole('textbox', { name: /name/i });
    await userEvent.clear(nameInput);
    await userEvent.type(nameInput, 'Renamed Flow');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save' }));

    expect(router.patch).toHaveBeenCalledWith(
      '/company/projects/7/workflows/3',
      { workflow: { name: 'Renamed Flow', description: 'Runs the nightly build' } },
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('includes the typed description in the create POST payload', async () => {
    renderAuthedPage(<WorkflowsPage />, { props: baseProps([]) });

    await userEvent.click(screen.getByRole('button', { name: 'New Workflow' }));
    const dialog = await screen.findByRole('dialog', { name: 'New Workflow' });
    await userEvent.type(within(dialog).getByRole('textbox', { name: /name/i }), 'Release Flow');
    await userEvent.type(within(dialog).getByRole('textbox', { name: /description/i }), 'Ships on tag');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Create' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/workflows',
      { workflow: { name: 'Release Flow', description: 'Ships on tag' } },
      expect.objectContaining({ preserveScroll: true }),
    );
  });
});
