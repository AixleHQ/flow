import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import type { Integration } from 'shared/resources/integrations/IntegrationsContent';

import IntegrationsPage from './IntegrationsPage';

const project = { id: 7, name: 'Aixle Core' };

const integration = (overrides: Partial<Integration> = {}): Integration => ({
  id: 1,
  name: 'octo-org',
  provider: 'github',
  status: 'active',
  scopeIndicator: 'project',
  githubUrl: null,
  connectedBy: { id: 1, name: 'Dana Scully' },
  createdAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

describe('Projects/Integrations/IntegrationsPage', () => {
  it('renders the empty state with connect CTAs when there are no integrations', () => {
    renderAuthedPage(<IntegrationsPage />, { props: { project, integrations: [] } });

    expect(screen.getByRole('heading', { name: 'Integrations' })).toBeInTheDocument();
    expect(screen.getByText('No integrations connected')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'GitHub' })).toBeInTheDocument();
    // The GitLab button carries an <img alt="GitLab"> icon, so its accessible name doubles the label.
    expect(screen.getByRole('button', { name: /GitLab/ })).toBeInTheDocument();
  });

  it('lists project and company integrations in the unified table with a Scope badge', () => {
    renderAuthedPage(<IntegrationsPage />, {
      props: {
        project,
        integrations: [
          integration({ id: 1, name: 'project-repo', scopeIndicator: 'project' }),
          integration({ id: 2, name: 'company-repo', scopeIndicator: 'company' }),
        ],
      },
    });

    expect(screen.getByText('project-repo')).toBeInTheDocument();
    expect(screen.getByText('company-repo')).toBeInTheDocument();
    expect(screen.getByText('project')).toBeInTheDocument();
    expect(screen.getByText('company')).toBeInTheDocument();
  });

  it('opens the GitLab connect modal from the Connect menu and blocks submit with an empty token', async () => {
    renderAuthedPage(<IntegrationsPage />, { props: { project, integrations: [] } });

    await userEvent.click(screen.getByRole('button', { name: 'Connect' }));
    // The GitLab menu item carries an <img alt="GitLab"> icon, so its accessible name is doubled.
    await userEvent.click(screen.getByRole('menuitem', { name: /GitLab/ }));

    const dialog = await screen.findByRole('dialog', { name: 'Connect GitLab' });
    expect(within(dialog).getByLabelText('Personal Access Token')).toBeInTheDocument();

    // Empty PAT keeps the submit disabled and never hits the backend.
    await userEvent.click(within(dialog).getByRole('button', { name: 'Connect' }));
    expect(router.post).not.toHaveBeenCalled();
  });

  it('confirms removal of a project integration and fires router.delete', async () => {
    renderAuthedPage(<IntegrationsPage />, {
      props: { project, integrations: [integration({ id: 42, name: 'doomed-repo' })] },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Remove' }));

    const confirm = await screen.findByRole('dialog', { name: 'Remove Integration' });
    await userEvent.click(within(confirm).getByRole('button', { name: 'Remove' }));

    expect(router.delete).toHaveBeenCalledWith(
      '/company/projects/7/integrations/42',
      expect.objectContaining({ preserveScroll: true }),
    );
  });
});
