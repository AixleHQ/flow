import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import WorkflowsIndex from './Index';

interface Workflow {
  id: number;
  name: string;
  description: string | null;
  scopeType: string;
  scopeId: number;
  scopeIndicator: 'company' | 'project' | 'overrides_company';
  stepsCount: number;
  lastRunAt: string | null;
  lastRunStatus: string | null;
  hasActiveRuns: boolean;
  descriptionExcerpt: string | null;
  createdAt: string;
  updatedAt: string;
}

const makeWorkflow = (overrides: Partial<Workflow> = {}): Workflow => ({
  id: 1,
  name: 'Onboarding Pipeline',
  description: 'Handles new customer onboarding',
  scopeType: 'Company',
  scopeId: 10,
  scopeIndicator: 'company',
  stepsCount: 4,
  lastRunAt: '2026-06-20T10:00:00Z',
  lastRunStatus: 'completed',
  hasActiveRuns: false,
  descriptionExcerpt: 'Handles new customer onboarding',
  createdAt: '2026-06-01T10:00:00Z',
  updatedAt: '2026-06-20T10:00:00Z',
  ...overrides,
});

describe('Company/Workflows/Index', () => {
  it('renders the empty state with a create CTA when there are no workflows', () => {
    renderAuthedPage(<WorkflowsIndex />, { props: { workflows: [] } });

    expect(screen.getByText('No workflows yet')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Create your first workflow' })).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Search workflows...')).toBeInTheDocument();
  });

  it('renders a card per workflow when the list is populated', () => {
    renderAuthedPage(<WorkflowsIndex />, {
      props: {
        workflows: [
          makeWorkflow({ id: 1, name: 'Onboarding Pipeline' }),
          makeWorkflow({ id: 2, name: 'Billing Sync', descriptionExcerpt: 'Reconcile invoices' }),
        ],
      },
    });

    expect(screen.getByText('Onboarding Pipeline')).toBeInTheDocument();
    expect(screen.getByText('Billing Sync')).toBeInTheDocument();
    expect(screen.getByText('Reconcile invoices')).toBeInTheDocument();
    expect(screen.queryByText('No workflows yet')).not.toBeInTheDocument();
  });

  it('filters the list by the debounced search query', async () => {
    renderAuthedPage(<WorkflowsIndex />, {
      props: {
        workflows: [
          makeWorkflow({ id: 1, name: 'Onboarding Pipeline' }),
          makeWorkflow({ id: 2, name: 'Billing Sync', descriptionExcerpt: null }),
        ],
      },
    });

    await userEvent.type(screen.getByPlaceholderText('Search workflows...'), 'billing');

    await waitFor(() => {
      expect(screen.queryByText('Onboarding Pipeline')).not.toBeInTheDocument();
    });
    expect(screen.getByText('Billing Sync')).toBeInTheDocument();
  });

  it('navigates to the catalog when the Catalog button is clicked', async () => {
    renderAuthedPage(<WorkflowsIndex />, { props: { workflows: [] } });

    await userEvent.click(screen.getByRole('button', { name: 'Catalog' }));

    expect(router.visit).toHaveBeenCalledWith('/company/workflow_catalog');
  });

  it('navigates to the builder when Configure is clicked on a workflow card', async () => {
    renderAuthedPage(<WorkflowsIndex />, {
      props: { workflows: [makeWorkflow({ id: 7, name: 'Onboarding Pipeline' })] },
    });

    await userEvent.click(screen.getByRole('button', { name: /Configure/ }));

    expect(router.visit).toHaveBeenCalledWith('/company/workflows/7/builder');
  });

  it('blocks creating a workflow with an empty name and submits a valid one', async () => {
    renderAuthedPage(<WorkflowsIndex />, { props: { workflows: [] } });

    await userEvent.click(screen.getByRole('button', { name: 'New Workflow' }));

    const dialog = await screen.findByRole('dialog', { name: 'New Workflow' });

    // Submit empty -> validation blocks the request.
    await userEvent.click(within(dialog).getByRole('button', { name: 'Create' }));
    expect(router.post).not.toHaveBeenCalled();

    // Fill a name and submit -> request fires.
    await userEvent.type(within(dialog).getByRole('textbox', { name: /Name/ }), 'Release Checklist');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Create' }));

    await waitFor(() => {
      expect(router.post).toHaveBeenCalledWith(
        '/company/workflows',
        { workflow: { name: 'Release Checklist', description: '' } },
        expect.objectContaining({ preserveScroll: true }),
      );
    });
  });

  it('disables the delete button for a workflow with active runs', async () => {
    renderAuthedPage(<WorkflowsIndex />, {
      props: {
        workflows: [makeWorkflow({ id: 3, name: 'Active Workflow', hasActiveRuns: true })],
      },
    });

    // The Edit/Delete controls are icon-only ActionIcons (no accessible name); they are the
    // last two buttons in the card, after the named "Configure" button. Click the trash (last).
    const card = screen.getByText('Active Workflow').closest('[class*="mantine-Card-root"]') as HTMLElement;
    const cardButtons = within(card).getAllByRole('button');
    await userEvent.click(cardButtons[cardButtons.length - 1]);

    const dialog = await screen.findByRole('dialog', { name: 'Delete Workflow' });
    expect(within(dialog).getByText('This workflow has active runs. Stop them first.')).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Delete' })).toBeDisabled();
  });

  it('shows the no-search-results message (without a create CTA) when the filter matches nothing', async () => {
    renderAuthedPage(<WorkflowsIndex />, {
      props: { workflows: [makeWorkflow({ id: 1, name: 'Onboarding Pipeline', descriptionExcerpt: null })] },
    });

    await userEvent.type(screen.getByPlaceholderText('Search workflows...'), 'zzzznomatch');

    await waitFor(() => {
      expect(screen.getByText('No workflows match your search')).toBeInTheDocument();
    });
    // When a search is active the empty state must NOT offer the "create first" CTA.
    expect(screen.queryByRole('button', { name: 'Create your first workflow' })).not.toBeInTheDocument();
  });

  it('opens the create modal from the empty-state CTA', async () => {
    renderAuthedPage(<WorkflowsIndex />, { props: { workflows: [] } });

    await userEvent.click(screen.getByRole('button', { name: 'Create your first workflow' }));

    expect(await screen.findByRole('dialog', { name: 'New Workflow' })).toBeInTheDocument();
  });

  it('closes the create modal when Cancel is clicked', async () => {
    renderAuthedPage(<WorkflowsIndex />, { props: { workflows: [] } });

    await userEvent.click(screen.getByRole('button', { name: 'New Workflow' }));
    const dialog = await screen.findByRole('dialog', { name: 'New Workflow' });

    await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));

    await waitFor(() => {
      expect(screen.queryByRole('dialog', { name: 'New Workflow' })).not.toBeInTheDocument();
    });
  });

  it('sends the description along with the name when creating a workflow', async () => {
    renderAuthedPage(<WorkflowsIndex />, { props: { workflows: [] } });

    await userEvent.click(screen.getByRole('button', { name: 'New Workflow' }));
    const dialog = await screen.findByRole('dialog', { name: 'New Workflow' });

    await userEvent.type(within(dialog).getByRole('textbox', { name: /Name/ }), 'Audit Flow');
    await userEvent.type(within(dialog).getByRole('textbox', { name: /Description/ }), 'Quarterly audit');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Create' }));

    await waitFor(() => {
      expect(router.post).toHaveBeenCalledWith(
        '/company/workflows',
        { workflow: { name: 'Audit Flow', description: 'Quarterly audit' } },
        expect.objectContaining({ preserveScroll: true }),
      );
    });
  });

  const openCardEdit = async (cardName: string) => {
    const card = screen.getByText(cardName).closest('[class*="mantine-Card-root"]') as HTMLElement;
    const cardButtons = within(card).getAllByRole('button');
    // Buttons order per card: Configure, Edit (pencil), Delete (trash). Edit is second-to-last.
    await userEvent.click(cardButtons[cardButtons.length - 2]);
  };

  it('opens the edit modal pre-filled with the workflow name and description', async () => {
    renderAuthedPage(<WorkflowsIndex />, {
      props: {
        workflows: [
          makeWorkflow({ id: 5, name: 'Renewal Flow', description: 'Renew contracts automatically' }),
        ],
      },
    });

    await openCardEdit('Renewal Flow');

    const dialog = await screen.findByRole('dialog', { name: 'Edit Workflow' });
    expect(within(dialog).getByRole('textbox', { name: /Name/ })).toHaveValue('Renewal Flow');
    expect(within(dialog).getByRole('textbox', { name: /Description/ })).toHaveValue(
      'Renew contracts automatically',
    );
  });

  it('patches the workflow when the edit form is submitted', async () => {
    renderAuthedPage(<WorkflowsIndex />, {
      props: {
        workflows: [makeWorkflow({ id: 9, name: 'Renewal Flow', description: 'Old desc' })],
      },
    });

    await openCardEdit('Renewal Flow');
    const dialog = await screen.findByRole('dialog', { name: 'Edit Workflow' });

    const nameInput = within(dialog).getByRole('textbox', { name: /Name/ });
    await userEvent.clear(nameInput);
    await userEvent.type(nameInput, 'Renewal Flow v2');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save' }));

    await waitFor(() => {
      expect(router.patch).toHaveBeenCalledWith(
        '/company/workflows/9',
        { workflow: { name: 'Renewal Flow v2', description: 'Old desc' } },
        expect.objectContaining({ preserveScroll: true }),
      );
    });
  });

  it('blocks the edit submit when the name is cleared', async () => {
    renderAuthedPage(<WorkflowsIndex />, {
      props: {
        workflows: [makeWorkflow({ id: 11, name: 'Renewal Flow', description: 'Desc' })],
      },
    });

    await openCardEdit('Renewal Flow');
    const dialog = await screen.findByRole('dialog', { name: 'Edit Workflow' });

    await userEvent.clear(within(dialog).getByRole('textbox', { name: /Name/ }));
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save' }));

    expect(router.patch).not.toHaveBeenCalled();
  });

  it('deletes a workflow with no active runs after confirmation', async () => {
    renderAuthedPage(<WorkflowsIndex />, {
      props: {
        workflows: [makeWorkflow({ id: 42, name: 'Stale Flow', hasActiveRuns: false })],
      },
    });

    const card = screen.getByText('Stale Flow').closest('[class*="mantine-Card-root"]') as HTMLElement;
    const cardButtons = within(card).getAllByRole('button');
    await userEvent.click(cardButtons[cardButtons.length - 1]);

    const dialog = await screen.findByRole('dialog', { name: 'Delete Workflow' });
    const deleteBtn = within(dialog).getByRole('button', { name: 'Delete' });
    expect(deleteBtn).toBeEnabled();
    await userEvent.click(deleteBtn);

    expect(router.delete).toHaveBeenCalledWith(
      '/company/workflows/42',
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('renders the Active badge and step/last-run metadata on a card', () => {
    renderAuthedPage(<WorkflowsIndex />, {
      props: {
        workflows: [
          makeWorkflow({
            id: 1,
            name: 'Live Flow',
            hasActiveRuns: true,
            stepsCount: 7,
            lastRunAt: '2026-06-20T10:00:00Z',
          }),
        ],
      },
    });

    expect(screen.getByText('Active')).toBeInTheDocument();
    expect(screen.getByText(/7 steps/)).toBeInTheDocument();
    expect(screen.getByText(/Last run/)).toBeInTheDocument();
  });

  it('omits last-run text when a workflow has never run', () => {
    renderAuthedPage(<WorkflowsIndex />, {
      props: {
        workflows: [
          makeWorkflow({
            id: 1,
            name: 'Never Ran',
            stepsCount: 2,
            lastRunAt: null,
            lastRunStatus: null,
            hasActiveRuns: false,
          }),
        ],
      },
    });

    expect(screen.getByText(/2 steps/)).toBeInTheDocument();
    expect(screen.queryByText(/Last run/)).not.toBeInTheDocument();
    expect(screen.queryByText('Active')).not.toBeInTheDocument();
  });
});
