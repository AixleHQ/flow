import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import type { Integration } from './IntegrationsContent';
import { IntegrationsContent } from './IntegrationsContent';

const settingsProps = { settings: { githubAppSlug: 'aixle-app' } };

const makeIntegration = (overrides: Partial<Integration> = {}): Integration => ({
  id: 1,
  name: 'Acme GitHub',
  provider: 'github',
  status: 'active',
  scopeIndicator: 'company',
  githubUrl: null,
  connectedBy: { id: 10, name: 'Jane Doe' },
  createdAt: '2026-01-15T10:00:00Z',
  ...overrides,
});

describe('IntegrationsContent', () => {
  it('renders the title and a card for each seeded integration', () => {
    renderPage(
      <IntegrationsContent
        title="Company Integrations"
        basePath="/company/integrations"
        integrations={[
          makeIntegration({ id: 1, name: 'Acme GitHub' }),
          makeIntegration({ id: 2, name: 'Acme GitLab', provider: 'gitlab' }),
        ]}
      />,
      { props: settingsProps },
    );

    expect(screen.getByRole('heading', { name: 'Company Integrations' })).toBeInTheDocument();
    expect(screen.getByText('Acme GitHub')).toBeInTheDocument();
    expect(screen.getByText('Acme GitLab')).toBeInTheDocument();
    // Both cards share the same connecting user, so the line appears once per card.
    expect(screen.getAllByText(/Connected by Jane Doe/)).toHaveLength(2);
  });

  it('shows the empty state when there are no integrations', () => {
    renderPage(
      <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
      { props: settingsProps },
    );

    expect(screen.getByText('No integrations connected')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Connect GitHub/i })).toBeInTheDocument();
  });

  it('connecting GitLab with a valid token fires a router.post with the gitlab payload', async () => {
    renderPage(
      <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
      { props: settingsProps },
    );

    // Open the GitLab connect modal from the empty-state action.
    await userEvent.click(screen.getByRole('button', { name: /Connect GitLab/i }));

    const dialog = await screen.findByRole('dialog', { name: /Connect GitLab/i });
    await userEvent.type(within(dialog).getByPlaceholderText('glpat-...'), 'glpat-secret-token');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Connect' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/integrations',
      expect.objectContaining({ provider: 'gitlab', personalAccessToken: 'glpat-secret-token' }),
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('keeps the GitLab Connect button disabled until a token is entered', async () => {
    renderPage(
      <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
      { props: settingsProps },
    );

    await userEvent.click(screen.getByRole('button', { name: /Connect GitLab/i }));

    const dialog = await screen.findByRole('dialog', { name: /Connect GitLab/i });
    expect(within(dialog).getByRole('button', { name: 'Connect' })).toBeDisabled();
    expect(router.post).not.toHaveBeenCalled();
  });

  it('removing an integration confirms and then fires router.delete to the right path', async () => {
    renderPage(
      <IntegrationsContent
        title="Company Integrations"
        basePath="/company/integrations"
        integrations={[makeIntegration({ id: 7, name: 'Acme GitHub' })]}
      />,
      { props: settingsProps },
    );

    await userEvent.click(screen.getByRole('button', { name: /Remove/i }));

    // Mantine's openConfirmModal renders a confirmation dialog with a "Remove" confirm button.
    const confirmDialog = await screen.findByRole('dialog', { name: /Remove Integration/i });
    await userEvent.click(within(confirmDialog).getByRole('button', { name: 'Remove' }));

    await waitFor(() =>
      expect(router.delete).toHaveBeenCalledWith('/company/integrations/7', expect.objectContaining({ preserveScroll: true })),
    );
  });

  describe('GitHub connect navigation', () => {
    // window.location is read-only in jsdom; swap it for a plain object so we can
    // observe handleConnectGithub's assignment to location.href.
    const originalLocation = window.location;

    beforeEach(() => {
      Object.defineProperty(window, 'location', {
        configurable: true,
        writable: true,
        value: { href: '' },
      });
    });

    afterEach(() => {
      Object.defineProperty(window, 'location', {
        configurable: true,
        writable: true,
        value: originalLocation,
      });
    });

    it('connecting GitHub from the empty state navigates to the GitHub app install URL', async () => {
      renderPage(
        <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: /Connect GitHub/i }));

      expect(window.location.href).toBe('https://github.com/apps/aixle-app/installations/new');
    });

    it('in a project context the install URL carries the project id as state', async () => {
      renderPage(
        <IntegrationsContent title="Project Integrations" basePath="/projects/42/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: /Connect GitHub/i }));

      expect(window.location.href).toBe(
        `https://github.com/apps/aixle-app/installations/new?state=${encodeURIComponent('project:42')}`,
      );
    });

    it('falls back to the github_setup page when no app slug is configured', async () => {
      renderPage(
        <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
        { props: { settings: { githubAppSlug: null } } },
      );

      await userEvent.click(screen.getByRole('button', { name: /Connect GitHub/i }));

      expect(window.location.href).toBe('/company/integrations/github_setup');
    });

    it('opens the GitHub install URL from the Connect menu when integrations already exist', async () => {
      renderPage(
        <IntegrationsContent
          title="Company Integrations"
          basePath="/company/integrations"
          integrations={[makeIntegration({ id: 1, name: 'Existing GitHub' })]}
        />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: 'Connect' }));
      await userEvent.click(await screen.findByRole('menuitem', { name: 'GitHub' }));

      expect(window.location.href).toBe('https://github.com/apps/aixle-app/installations/new');
    });
  });

  it('renders the status badge text and color for a non-active integration', () => {
    renderPage(
      <IntegrationsContent
        title="Company Integrations"
        basePath="/company/integrations"
        integrations={[makeIntegration({ id: 9, name: 'Broken GitHub', status: 'error' })]}
      />,
      { props: settingsProps },
    );

    expect(screen.getByText('error')).toBeInTheDocument();
  });

  it('renders a Settings link to the github management URL when present', () => {
    renderPage(
      <IntegrationsContent
        title="Company Integrations"
        basePath="/company/integrations"
        integrations={[
          makeIntegration({ id: 3, name: 'Linked GitHub', githubUrl: 'https://github.com/settings/installations/55' }),
        ]}
      />,
      { props: settingsProps },
    );

    const settingsLink = screen.getByRole('link', { name: /Settings/i });
    expect(settingsLink).toHaveAttribute('href', 'https://github.com/settings/installations/55');
    expect(settingsLink).toHaveAttribute('target', '_blank');
  });

  describe('project context sections', () => {
    it('splits integrations into "This Project" and "Company-wide" sections', () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[
            makeIntegration({ id: 1, name: 'Project Scoped', scopeIndicator: 'project' }),
            makeIntegration({ id: 2, name: 'Org Wide', scopeIndicator: 'company' }),
          ]}
        />,
        { props: settingsProps },
      );

      expect(screen.getByText('This Project')).toBeInTheDocument();
      expect(screen.getByText('Company-wide')).toBeInTheDocument();
      expect(screen.getByText('Project Scoped')).toBeInTheDocument();
      expect(screen.getByText('Org Wide')).toBeInTheDocument();
    });

    it('marks company-wide integrations read-only: a company badge but no Remove button', () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[makeIntegration({ id: 2, name: 'Org Wide', scopeIndicator: 'company' })]}
        />,
        { props: settingsProps },
      );

      // The read-only "company" badge is present for a company-scoped integration in a project view.
      expect(screen.getByText('company')).toBeInTheDocument();
      // Read-only cards hide the Remove action.
      expect(screen.queryByRole('button', { name: /Remove/i })).not.toBeInTheDocument();
    });

    it('shows an empty-scope message when the project has no project-scoped integrations', () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[makeIntegration({ id: 2, name: 'Org Wide', scopeIndicator: 'company' })]}
        />,
        { props: settingsProps },
      );

      expect(screen.getByText('No integrations in this scope.')).toBeInTheDocument();
    });

    it('linking a company integration to the project posts the installation id', async () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[
            makeIntegration({
              id: 2,
              name: 'Org Wide',
              scopeIndicator: 'company',
              status: 'active',
              installationId: 'inst-123',
            }),
          ]}
        />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: /Link to project/i }));

      expect(router.post).toHaveBeenCalledWith(
        '/projects/42/integrations',
        expect.objectContaining({ provider: 'github', installationId: 'inst-123' }),
        expect.objectContaining({ preserveScroll: true }),
      );
    });

    it('hides the Link button when the installation is already linked at the project scope', () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[
            makeIntegration({
              id: 1,
              name: 'Already Linked',
              scopeIndicator: 'project',
              status: 'active',
              installationId: 'inst-dup',
            }),
            makeIntegration({
              id: 2,
              name: 'Company Copy',
              scopeIndicator: 'company',
              status: 'active',
              installationId: 'inst-dup',
            }),
          ]}
        />,
        { props: settingsProps },
      );

      // The same installation already exists at project scope, so the company copy's Link button is suppressed.
      expect(screen.queryByRole('button', { name: /Link to project/i })).not.toBeInTheDocument();
    });
  });

  describe('Coder connect modal', () => {
    const openCoderModal = async () => {
      await userEvent.click(screen.getByRole('button', { name: 'Connect' }));
      // The Coder menu item's icon is an <img alt="Coder">, so its accessible name includes
      // the alt text in addition to the label — match on a substring.
      await userEvent.click(await screen.findByRole('menuitem', { name: /Coder/i }));
      return screen.findByRole('dialog', { name: /Connect Coder/i });
    };

    it('keeps Connect disabled and shows a validation error for a non-https URL', async () => {
      renderPage(
        <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      const dialog = await openCoderModal();
      await userEvent.type(within(dialog).getByPlaceholderText('https://coder.example.com'), 'http://insecure.example.com');
      await userEvent.type(within(dialog).getByPlaceholderText('vFVrbTLdls-...'), 'tok-123');

      expect(within(dialog).getByText('Must be a valid https URL')).toBeInTheDocument();
      expect(within(dialog).getByRole('button', { name: 'Connect' })).toBeDisabled();
      expect(router.post).not.toHaveBeenCalled();
    });

    it('posts the coder payload with advanced fields when the form is valid', async () => {
      renderPage(
        <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      const dialog = await openCoderModal();
      await userEvent.type(within(dialog).getByPlaceholderText('https://coder.example.com'), 'https://coder.acme.dev');
      await userEvent.type(within(dialog).getByPlaceholderText('vFVrbTLdls-...'), 'session-token-xyz');

      // Advanced section is collapsed by default; open it to fill the optional fields.
      await userEvent.click(within(dialog).getByText('Advanced'));
      await userEvent.type(within(dialog).getByPlaceholderText('aws-ec2-spot-v1'), 'aws-template');
      await userEvent.type(within(dialog).getByPlaceholderText('aixle-prod'), 'acme-prefix');

      await userEvent.click(within(dialog).getByRole('button', { name: 'Connect' }));

      expect(router.post).toHaveBeenCalledWith(
        '/company/integrations',
        expect.objectContaining({
          provider: 'coder',
          coderUrl: 'https://coder.acme.dev',
          sessionToken: 'session-token-xyz',
          defaultTemplate: 'aws-template',
          machinePrefix: 'acme-prefix',
        }),
        expect.objectContaining({ preserveScroll: true }),
      );
    });

    it('toggling Advanced reveals and hides the optional Coder fields', async () => {
      renderPage(
        <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      const dialog = await openCoderModal();
      expect(within(dialog).queryByPlaceholderText('aws-ec2-spot-v1')).not.toBeInTheDocument();

      await userEvent.click(within(dialog).getByText('Advanced'));
      expect(within(dialog).getByPlaceholderText('aws-ec2-spot-v1')).toBeInTheDocument();

      await userEvent.click(within(dialog).getByText('Advanced'));
      expect(within(dialog).queryByPlaceholderText('aws-ec2-spot-v1')).not.toBeInTheDocument();
    });
  });
});
