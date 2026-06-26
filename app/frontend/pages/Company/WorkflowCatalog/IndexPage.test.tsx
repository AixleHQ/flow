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

    expect(screen.getByText('Workflow Catalog')).toBeInTheDocument();
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
    await waitFor(() => expect(screen.getByText('No workflows match your search')).toBeInTheDocument());
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
});
