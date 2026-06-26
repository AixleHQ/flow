import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';
import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';
import type { Integration } from 'shared/resources/integrations/IntegrationsContent';
import IntegrationsIndex from './Index';

const buildIntegration = (overrides: Partial<Integration> = {}): Integration => ({
  id: 1,
  name: 'Octocat GitHub',
  provider: 'github',
  status: 'active',
  scopeIndicator: 'company',
  githubUrl: null,
  connectedBy: { id: 9, name: 'Ada Lovelace' },
  createdAt: '2026-02-01T00:00:00Z',
  ...overrides,
});

describe('Company/Integrations/Index', () => {
  it('renders the empty state with connect CTAs when there are no integrations', () => {
    renderAuthedPage(<IntegrationsIndex integrations={[]} />);

    expect(screen.getByRole('heading', { name: 'Integrations' })).toBeInTheDocument();
    expect(screen.getByText('No integrations connected')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Connect GitHub/ })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Connect GitLab/ })).toBeInTheDocument();
  });

  it('lists connected integrations with their name, status and connector', () => {
    renderAuthedPage(
      <IntegrationsIndex
        integrations={[
          buildIntegration({
            id: 1,
            name: 'Octocat GitHub',
            status: 'active',
            connectedBy: { id: 9, name: 'Ada Lovelace' },
          }),
          buildIntegration({
            id: 2,
            name: 'Self-hosted GitLab',
            provider: 'gitlab',
            status: 'inactive',
            connectedBy: { id: 10, name: 'Grace Hopper' },
          }),
        ]}
      />,
    );

    expect(screen.getByText('Octocat GitHub')).toBeInTheDocument();
    expect(screen.getByText('Self-hosted GitLab')).toBeInTheDocument();
    expect(screen.queryByText('No integrations connected')).not.toBeInTheDocument();
    expect(screen.getByText(/Connected by Ada Lovelace/)).toBeInTheDocument();
    expect(screen.getByText(/Connected by Grace Hopper/)).toBeInTheDocument();
  });

  it('opens a confirm modal and fires router.delete when removing an integration', async () => {
    renderAuthedPage(<IntegrationsIndex integrations={[buildIntegration({ id: 42, name: 'Octocat GitHub' })]} />);

    await userEvent.click(screen.getByRole('button', { name: /Remove/ }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Remove Integration')).toBeInTheDocument();

    await userEvent.click(within(dialog).getByRole('button', { name: 'Remove' }));

    expect(router.delete).toHaveBeenCalledWith(
      '/company/integrations/42',
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('opens the GitLab connect modal from the Connect menu', async () => {
    renderAuthedPage(<IntegrationsIndex integrations={[buildIntegration()]} />);

    await userEvent.click(screen.getByRole('button', { name: 'Connect' }));
    await userEvent.click(await screen.findByRole('menuitem', { name: /GitLab/ }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Connect GitLab')).toBeInTheDocument();
    expect(within(dialog).getByPlaceholderText('glpat-...')).toBeInTheDocument();
  });
});
