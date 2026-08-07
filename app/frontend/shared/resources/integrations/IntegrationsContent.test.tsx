import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { act, renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';

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
  it('renders the title and a row for each seeded integration', () => {
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
    expect(screen.getAllByText(/Jane Doe/)).toHaveLength(2);
    expect(screen.getByText('2 integrations')).toBeInTheDocument();
  });

  it('shows the empty state when there are no integrations', () => {
    renderPage(
      <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
      { props: settingsProps },
    );

    expect(screen.getByText('No integrations connected')).toBeInTheDocument();
    // The empty-state action buttons are labeled by provider name only ("GitHub", "GitLab", ...).
    expect(screen.getByRole('button', { name: 'GitHub' })).toBeInTheDocument();
  });

  it('connecting GitLab with a valid token fires a router.post with the gitlab payload', async () => {
    renderPage(
      <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
      { props: settingsProps },
    );

    // Open the GitLab connect modal from the empty-state action (button labeled "GitLab",
    // whose accessible name also includes the GitLab icon's alt text).
    await userEvent.click(screen.getByRole('button', { name: /GitLab/i }));

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

    await userEvent.click(screen.getByRole('button', { name: /GitLab/i }));

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
      expect(router.delete).toHaveBeenCalledWith(
        '/company/integrations/7',
        expect.objectContaining({ preserveScroll: true }),
      ),
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

    // Connecting GitHub navigates to the SERVER endpoint, which mints a signed state
    // (Oauth::State) and redirects to GitHub — the state is no longer built client-side (§7).
    it('connecting GitHub from the empty state navigates to the server install endpoint', async () => {
      renderPage(
        <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: 'GitHub' }));

      expect(window.location.href).toBe('/company/integrations/github_app_install');
    });

    it('in a project context it navigates to that project’s install endpoint', async () => {
      renderPage(
        <IntegrationsContent title="Project Integrations" basePath="/projects/42/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: 'GitHub' }));

      expect(window.location.href).toBe('/projects/42/integrations/github_app_install');
    });

    it('opens the server install endpoint from the Connect menu when integrations already exist', async () => {
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

      expect(window.location.href).toBe('/company/integrations/github_app_install');
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

    expect(screen.getByText('Error')).toBeInTheDocument();
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

  describe('project context scope filter', () => {
    it('shows both project- and company-scoped integrations by default, with a scope badge', () => {
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

      expect(screen.getByText('Project Scoped')).toBeInTheDocument();
      expect(screen.getByText('Org Wide')).toBeInTheDocument();
      expect(screen.getByText('company')).toBeInTheDocument();
      expect(screen.getByText('project')).toBeInTheDocument();
    });

    it('filtering to Project scope hides company-wide integrations and their Remove action stays hidden either way', async () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[makeIntegration({ id: 2, name: 'Org Wide', scopeIndicator: 'company' })]}
        />,
        { props: settingsProps },
      );

      // Company-scoped integrations in a project context are read-only: no Remove action.
      expect(screen.queryByRole('button', { name: /Remove/i })).not.toBeInTheDocument();

      await userEvent.click(screen.getByRole('radio', { name: 'Project' }));

      expect(screen.queryByText('Org Wide')).not.toBeInTheDocument();
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

    it('clicking Link on a company integration with no installation id is a no-op', async () => {
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
              // No installationId: the Link action does not render at all.
            }),
          ]}
        />,
        { props: settingsProps },
      );

      expect(screen.queryByRole('button', { name: /Link to project/i })).not.toBeInTheDocument();
      expect(router.post).not.toHaveBeenCalled();
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

    it('keeps Connect disabled and shows a validation error for a non-http(s) URL', async () => {
      renderPage(
        <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      const dialog = await openCoderModal();
      await userEvent.type(
        within(dialog).getByPlaceholderText('https://coder.example.com'),
        'ftp://insecure.example.com',
      );
      await userEvent.type(within(dialog).getByPlaceholderText('vFVrbTLdls-...'), 'tok-123');

      expect(within(dialog).getByText('Must be a valid http or https URL')).toBeInTheDocument();
      expect(within(dialog).getByRole('button', { name: 'Connect' })).toBeDisabled();
      expect(router.post).not.toHaveBeenCalled();
    });

    it('allows an http coder URL', async () => {
      renderPage(
        <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      const dialog = await openCoderModal();
      await userEvent.type(within(dialog).getByPlaceholderText('https://coder.example.com'), 'http://coder.acme.dev');
      await userEvent.type(within(dialog).getByPlaceholderText('vFVrbTLdls-...'), 'session-token-xyz');

      await userEvent.click(within(dialog).getByRole('button', { name: 'Connect' }));

      expect(router.post).toHaveBeenCalledWith(
        '/company/integrations',
        expect.objectContaining({
          provider: 'coder',
          coderUrl: 'http://coder.acme.dev',
          sessionToken: 'session-token-xyz',
        }),
        expect.any(Object),
      );
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

    it('keeps Connect disabled when only the URL is filled but the token is empty', async () => {
      renderPage(
        <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      const dialog = await openCoderModal();
      await userEvent.type(within(dialog).getByPlaceholderText('https://coder.example.com'), 'https://coder.acme.dev');

      // A valid URL alone is not enough — the session token is still required.
      expect(within(dialog).getByRole('button', { name: 'Connect' })).toBeDisabled();
      expect(router.post).not.toHaveBeenCalled();
    });

    it('cancelling the Coder modal closes it and clears the entered fields', async () => {
      renderPage(
        <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      const dialog = await openCoderModal();
      await userEvent.type(within(dialog).getByPlaceholderText('https://coder.example.com'), 'https://coder.acme.dev');
      await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));

      await waitFor(() => expect(screen.queryByRole('dialog', { name: /Connect Coder/i })).not.toBeInTheDocument());
      expect(router.post).not.toHaveBeenCalled();

      // Reopening yields a pristine form: closeCoderModal ran resetCoderForm on cancel.
      const reopened = await openCoderModal();
      expect(within(reopened).getByPlaceholderText('https://coder.example.com')).toHaveValue('');
    });

    it('surfaces the server error message in the dialog when the Coder connect fails', async () => {
      renderPage(
        <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      const dialog = await openCoderModal();
      await userEvent.type(within(dialog).getByPlaceholderText('https://coder.example.com'), 'https://coder.acme.dev');
      await userEvent.type(within(dialog).getByPlaceholderText('vFVrbTLdls-...'), 'session-token-xyz');
      await userEvent.click(within(dialog).getByRole('button', { name: 'Connect' }));

      // The router mock records the call but never runs the callbacks itself; drive the onError
      // branch by invoking the captured callback, then assert the error is rendered in the dialog.
      const options = vi.mocked(router.post).mock.lastCall?.[2] as
        { onError?: (errors: Record<string, string>) => void } | undefined;
      act(() => options?.onError?.({ sessionToken: 'Token was rejected by Coder' }));

      expect(within(dialog).getByText('Token was rejected by Coder')).toBeInTheDocument();
      // The dialog stays open on failure so the user can correct the input.
      expect(screen.getByRole('dialog', { name: /Connect Coder/i })).toBeInTheDocument();
    });
  });

  describe('GitLab connect modal interactions', () => {
    it('cancelling the GitLab modal closes it without posting', async () => {
      renderPage(
        <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: /GitLab/i }));
      const dialog = await screen.findByRole('dialog', { name: /Connect GitLab/i });
      await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));

      await waitFor(() => expect(screen.queryByRole('dialog', { name: /Connect GitLab/i })).not.toBeInTheDocument());
      expect(router.post).not.toHaveBeenCalled();
    });

    it('pressing Enter in the token field submits the GitLab connection', async () => {
      renderPage(
        <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: /GitLab/i }));
      const dialog = await screen.findByRole('dialog', { name: /Connect GitLab/i });
      // Typing the token then Enter exercises the onKeyDown submit path (no button click).
      await userEvent.type(within(dialog).getByPlaceholderText('glpat-...'), 'glpat-enter-token{Enter}');

      expect(router.post).toHaveBeenCalledWith(
        '/company/integrations',
        expect.objectContaining({ provider: 'gitlab', personalAccessToken: 'glpat-enter-token' }),
        expect.objectContaining({ preserveScroll: true }),
      );
    });
  });

  describe('Slack connect navigation', () => {
    // Same window.location swap as the GitHub block: jsdom's location is read-only, so replace it
    // with a plain object to observe handleConnectSlack's assignment to location.href.
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

    it('connecting Slack from the empty state in a project navigates to the OAuth start URL', async () => {
      renderPage(
        <IntegrationsContent title="Project Integrations" basePath="/projects/42/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: 'Slack' }));

      expect(window.location.href).toBe('/projects/42/integrations/slack_oauth_start');
    });

    it('opens the Slack OAuth start from the Connect menu in a project context', async () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[makeIntegration({ id: 1, name: 'Existing GitHub', scopeIndicator: 'project' })]}
        />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: 'Connect' }));
      await userEvent.click(await screen.findByRole('menuitem', { name: /Slack/i }));

      expect(window.location.href).toBe('/projects/42/integrations/slack_oauth_start');
    });

    it('does not offer Slack in a company (non-project) context', async () => {
      renderPage(
        <IntegrationsContent
          title="Company Integrations"
          basePath="/company/integrations"
          integrations={[makeIntegration({ id: 1, name: 'Existing GitHub' })]}
        />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: 'Connect' }));

      // GitHub/GitLab/Coder are offered, but Slack is project-scoped only.
      expect(await screen.findByRole('menuitem', { name: 'GitHub' })).toBeInTheDocument();
      expect(screen.queryByRole('menuitem', { name: /Slack/i })).not.toBeInTheDocument();
    });
  });

  describe('viewer without execute permission', () => {
    const readOnlyProps = { ...settingsProps, projectPermissions: { canExecute: false, canManage: false } };

    it('hides every connect action on the empty state', () => {
      renderPage(
        <IntegrationsContent title="Project Integrations" basePath="/projects/42/integrations" integrations={[]} />,
        { props: readOnlyProps },
      );

      expect(screen.getByText('No integrations connected')).toBeInTheDocument();
      expect(screen.queryByRole('button', { name: 'Connect' })).not.toBeInTheDocument();
      expect(screen.queryByRole('button', { name: 'GitHub' })).not.toBeInTheDocument();
    });

    it('hides the Remove action on integration rows', () => {
      renderPage(
        <IntegrationsContent
          title="Company Integrations"
          basePath="/company/integrations"
          integrations={[makeIntegration({ id: 5, name: 'Acme GitHub' })]}
        />,
        { props: readOnlyProps },
      );

      // The row still renders, but its mutating controls are gone for a read-only viewer.
      expect(screen.getByText('Acme GitHub')).toBeInTheDocument();
      expect(screen.queryByRole('button', { name: /Remove/i })).not.toBeInTheDocument();
      expect(screen.queryByRole('button', { name: 'Connect' })).not.toBeInTheDocument();
    });
  });

  describe('connected integration row details', () => {
    it('shows the Slack request URL and a copy button for a Slack integration', () => {
      renderPage(
        <IntegrationsContent
          title="Company Integrations"
          basePath="/company/integrations"
          integrations={[
            makeIntegration({
              id: 8,
              name: 'Acme Slack',
              provider: 'slack',
              slackRequestUrl: 'https://hooks.aixle.dev/slack/req',
            }),
          ]}
        />,
        { props: settingsProps },
      );

      expect(screen.getByText('https://hooks.aixle.dev/slack/req')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /Request URL/i })).toBeInTheDocument();
    });

    it('shows the Coder instance URL on a Coder integration row', () => {
      renderPage(
        <IntegrationsContent
          title="Company Integrations"
          basePath="/company/integrations"
          integrations={[
            makeIntegration({
              id: 9,
              name: 'Acme Coder',
              provider: 'coder',
              coderUrl: 'https://coder.aixle.dev',
            }),
          ]}
        />,
        { props: settingsProps },
      );

      expect(screen.getByText('https://coder.aixle.dev')).toBeInTheDocument();
    });
  });
});
