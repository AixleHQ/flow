import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import IndexPage from './IndexPage';

const workflow = (overrides: Record<string, unknown> = {}) => ({
  id: 1,
  name: 'Onboarding Flow',
  description: 'Welcomes new teammates',
  scopeType: 'company',
  stepsCount: 4,
  publishedAt: '2026-01-01T00:00:00Z',
  publishedByName: 'Dana Ops',
  ...overrides,
});

describe('Company/WorkflowCatalog/IndexPage', () => {
  it('renders the heading and the published-by-empty state when there are no workflows', () => {
    renderAuthedPage(<IndexPage />, { props: { workflows: [], projects: [] } });

    // 'Workflow Catalog' also appears as a sidebar nav label, so scope to the page heading.
    expect(screen.getByText('Workflow Catalog', { selector: 'p' })).toBeInTheDocument();
    expect(screen.getByText('No workflows published yet')).toBeInTheDocument();
  });

  it('lists workflows and filters them by the search query', async () => {
    renderAuthedPage(<IndexPage />, {
      props: {
        workflows: [
          workflow({ id: 1, name: 'Onboarding Flow' }),
          workflow({ id: 2, name: 'Release Pipeline', description: 'Ships builds' }),
        ],
        projects: [],
      },
    });

    expect(screen.getByText('Onboarding Flow')).toBeInTheDocument();
    expect(screen.getByText('Release Pipeline')).toBeInTheDocument();

    await userEvent.type(screen.getByPlaceholderText('Search workflows...'), 'release');

    // The search value is debounced (300ms) before the list re-filters.
    await waitFor(() => expect(screen.queryByText('Onboarding Flow')).not.toBeInTheDocument());
    expect(screen.getByText('Release Pipeline')).toBeInTheDocument();
  });

  it('shows the no-match state when the search matches nothing', async () => {
    renderAuthedPage(<IndexPage />, {
      props: { workflows: [workflow({ name: 'Onboarding Flow' })], projects: [] },
    });

    await userEvent.type(screen.getByPlaceholderText('Search workflows...'), 'zzz');

    // The search value is debounced (300ms) before the empty state appears.
    expect(await screen.findByText('No workflows match your search')).toBeInTheDocument();
  });

  it('opens the duplicate modal for the chosen workflow', async () => {
    renderAuthedPage(<IndexPage />, {
      props: {
        workflows: [workflow({ id: 5, name: 'Onboarding Flow' })],
        projects: [{ id: 9, name: 'Mercury' }],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Duplicate to project' }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Duplicate to project')).toBeInTheDocument();
    // The confirm button is disabled until a project is selected.
    expect(within(dialog).getByRole('button', { name: 'Duplicate' })).toBeDisabled();
  });

  it('does not post a duplicate while no project is selected', async () => {
    renderAuthedPage(<IndexPage />, {
      props: {
        workflows: [workflow({ id: 5, name: 'Onboarding Flow' })],
        projects: [{ id: 9, name: 'Mercury' }],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Duplicate to project' }));
    const dialog = await screen.findByRole('dialog');

    // Disabled confirm cannot be clicked, so the duplicate endpoint is never hit.
    await userEvent.click(within(dialog).getByRole('button', { name: 'Duplicate' }));

    expect(router.post).not.toHaveBeenCalled();
  });

  it('filters by a description match even when the name does not match', async () => {
    renderAuthedPage(<IndexPage />, {
      props: {
        workflows: [
          workflow({ id: 1, name: 'Onboarding Flow', description: 'Welcomes new teammates' }),
          workflow({ id: 2, name: 'Release Pipeline', description: 'Ships builds' }),
        ],
        projects: [],
      },
    });

    // "welcomes" matches only the first workflow's description, never a name.
    await userEvent.type(screen.getByPlaceholderText('Search workflows...'), 'welcomes');

    await waitFor(() => expect(screen.queryByText('Release Pipeline')).not.toBeInTheDocument());
    expect(screen.getByText('Onboarding Flow')).toBeInTheDocument();
  });

  it('renders the publisher attribution only for workflows that have one', () => {
    renderAuthedPage(<IndexPage />, {
      props: {
        workflows: [
          workflow({ id: 1, name: 'Onboarding Flow', publishedByName: 'Dana Ops' }),
          workflow({ id: 2, name: 'Release Pipeline', publishedByName: null }),
        ],
        projects: [],
      },
    });

    // Only the first card carries a "Published by …" line; the null-publisher card omits it.
    const attributions = screen.getAllByText(/Published by/);
    expect(attributions).toHaveLength(1);
    expect(screen.getByText('Published by Dana Ops')).toBeInTheDocument();
  });

  it('posts the duplicate to the selected project once a project is chosen', async () => {
    renderAuthedPage(<IndexPage />, {
      props: {
        workflows: [workflow({ id: 5, name: 'Onboarding Flow' })],
        projects: [{ id: 9, name: 'Mercury' }],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Duplicate to project' }));
    const dialog = await screen.findByRole('dialog');

    // Pick a project — the option renders in a portal, so query it at the document root.
    await userEvent.click(within(dialog).getByPlaceholderText('Select project'));
    await userEvent.click(await screen.findByRole('option', { name: 'Mercury' }));

    // Choosing a project enables the confirm button that was previously disabled.
    const confirm = within(dialog).getByRole('button', { name: 'Duplicate' });
    await waitFor(() => expect(confirm).toBeEnabled());

    await userEvent.click(confirm);

    expect(router.post).toHaveBeenCalledWith(
      '/company/workflow_catalog/5/duplicate',
      { project_id: '9' },
      expect.objectContaining({ onSuccess: expect.any(Function), onFinish: expect.any(Function) }),
    );
  });

  it('closes the duplicate modal without posting when Cancel is clicked', async () => {
    renderAuthedPage(<IndexPage />, {
      props: {
        workflows: [workflow({ id: 5, name: 'Onboarding Flow' })],
        projects: [{ id: 9, name: 'Mercury' }],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Duplicate to project' }));
    const dialog = await screen.findByRole('dialog');

    await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));

    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(router.post).not.toHaveBeenCalled();
  });

  it('tells the user they have no projects instead of offering the project select', async () => {
    renderAuthedPage(<IndexPage />, {
      props: {
        workflows: [workflow({ id: 5, name: 'Onboarding Flow' })],
        projects: [],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Duplicate to project' }));
    const dialog = await screen.findByRole('dialog');

    expect(within(dialog).getByText('You do not have access to any projects yet.')).toBeInTheDocument();
    // No project picker is rendered, so the confirm stays disabled.
    expect(within(dialog).queryByRole('combobox')).not.toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Duplicate' })).toBeDisabled();
  });
});
