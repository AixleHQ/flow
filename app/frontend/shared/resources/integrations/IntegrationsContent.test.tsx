import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { Integration } from '@/types/generated';
import { buildIntegration } from 'test/factories/integration';
import { act, renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import { IntegrationsContent } from './IntegrationsContent';

const settingsProps = { settings: { githubAppSlug: 'aixle-app' } };

const makeIntegration = (overrides: Partial<Integration> = {}): Integration =>
  buildIntegration({
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

  // == Azure DevOps ==

  const azureIntegration = (overrides: Partial<Integration> = {}): Integration =>
    makeIntegration({
      id: 3,
      name: 'contoso/Customer Platform',
      provider: 'azure_devops',
      scopeIndicator: 'project',
      azureAuthMode: 'service_principal',
      azureOrganization: 'contoso',
      azureProjectName: 'Customer Platform',
      azureIdentity: 'Aixle',
      azureUrl: 'https://dev.azure.com/contoso',
      ...overrides,
    });

  const azureDevopsProps = {
    enabled: true,
    patModeEnabled: false,
    installations: [
      {
        id: 7,
        organizationSlug: 'contoso',
        tenantId: 't',
        status: 'active',
        projects: [{ id: 'p1', name: 'Customer Platform' }],
      },
    ],
  };

  it('offers Azure DevOps in a project only when the deployment enables it', async () => {
    const { rerender } = renderPage(
      <IntegrationsContent title="Integrations" basePath="/company/projects/1/integrations" integrations={[]} />,
      { props: settingsProps },
    );

    expect(screen.queryByRole('button', { name: 'Azure DevOps' })).not.toBeInTheDocument();

    rerender(
      <IntegrationsContent
        title="Integrations"
        basePath="/company/projects/1/integrations"
        integrations={[]}
        azureDevops={azureDevopsProps}
      />,
    );

    expect(await screen.findByRole('button', { name: 'Azure DevOps' })).toBeInTheDocument();
  });

  it('shows which Azure project a connection is pinned to and whose identity it acts as', () => {
    renderPage(
      <IntegrationsContent
        title="Integrations"
        basePath="/company/projects/1/integrations"
        integrations={[azureIntegration()]}
        azureDevops={azureDevopsProps}
      />,
      { props: settingsProps },
    );

    expect(screen.getByText('Azure DevOps')).toBeInTheDocument();
    expect(screen.getByText(/contoso \/ Customer Platform · as Aixle/)).toBeInTheDocument();
  });

  it('names the token owner rather than the application for a PAT connection', () => {
    renderPage(
      <IntegrationsContent
        title="Integrations"
        basePath="/company/projects/1/integrations"
        integrations={[azureIntegration({ azureAuthMode: 'pat', azureIdentity: null })]}
        azureDevops={azureDevopsProps}
      />,
      { props: settingsProps },
    );

    expect(screen.getByText(/as Jane Doe \(token\)/)).toBeInTheDocument();
  });

  it('testing a connection posts to its test_connection action', async () => {
    renderPage(
      <IntegrationsContent
        title="Integrations"
        basePath="/company/projects/1/integrations"
        integrations={[azureIntegration()]}
        azureDevops={azureDevopsProps}
      />,
      { props: settingsProps },
    );

    await userEvent.click(screen.getByRole('button', { name: /Test connection for contoso/ }));

    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith(
        '/company/projects/1/integrations/3/test_connection',
        {},
        expect.anything(),
      ),
    );
  });

  // == Jira ==

  const jiraIntegration = (overrides: Partial<Integration> = {}): Integration =>
    makeIntegration({
      id: 8,
      name: 'Jira · acme.atlassian.net',
      provider: 'jira',
      scopeIndicator: 'project',
      jiraAuthMode: 'service_account',
      jiraSiteUrl: 'https://acme.atlassian.net',
      jiraProjects: [
        { id: '10000', key: 'ENG', name: 'Engineering' },
        { id: '10001', key: 'OPS', name: 'Operations' },
      ],
      jiraIdentity: 'Aixle Bot',
      ...overrides,
    });

  it('offers Jira in a project, and says which projects a connection covers and as whom', () => {
    renderPage(
      <IntegrationsContent
        title="Integrations"
        basePath="/company/projects/1/integrations"
        integrations={[jiraIntegration()]}
        jira={{ oauthEnabled: true }}
      />,
      { props: settingsProps },
    );

    expect(screen.getByText('ENG, OPS · as Aixle Bot (service account)')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Webhook setup for Jira/ })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Open Jira · acme.atlassian.net in Jira/ })).toHaveAttribute(
      'href',
      'https://acme.atlassian.net',
    );
  });

  it('opens the project picker for the connection the Atlassian app just made', async () => {
    vi.mocked(globalThis.fetch).mockResolvedValue({ ok: true, json: async () => ({ projects: [] }) } as Response);
    window.history.pushState({}, '', '/company/projects/1/integrations?jira_setup=8');
    renderPage(
      <IntegrationsContent
        title="Integrations"
        basePath="/company/projects/1/integrations"
        integrations={[jiraIntegration({ status: 'inactive', jiraAuthMode: 'oauth', jiraProjects: [], jiraSites: [] })]}
        jira={{ oauthEnabled: true }}
      />,
      { props: settingsProps },
    );

    expect(await screen.findByRole('dialog', { name: 'Jira projects' })).toBeInTheDocument();
    expect(screen.getByText('Choose the Jira projects to finish connecting')).toBeInTheDocument();
    window.history.pushState({}, '', '/');
    vi.mocked(globalThis.fetch).mockReset();
  });

  // == Linear ==

  const linearIntegration = (overrides: Partial<Integration> = {}): Integration =>
    makeIntegration({
      id: 9,
      name: 'Linear · Acme',
      provider: 'linear',
      scopeIndicator: 'project',
      linearAuthMode: 'api_key',
      linearWorkspaceUrl: 'https://linear.app/acme',
      linearTeams: [
        { id: 't-eng', key: 'ENG', name: 'Engineering' },
        { id: 't-ops', key: 'OPS', name: 'Operations' },
      ],
      linearIdentity: 'Aixle Bot',
      ...overrides,
    });

  it('offers Linear in a project, and says which teams a connection covers, as whom and why events stall', async () => {
    const user = userEvent.setup();
    renderPage(
      <IntegrationsContent
        title="Integrations"
        basePath="/company/projects/1/integrations"
        integrations={[
          linearIntegration({ linearWebhookError: "Only a Linear workspace admin's API key can register webhooks." }),
        ]}
        linear={{ oauthEnabled: false }}
      />,
      { props: settingsProps },
    );

    expect(screen.getByText('ENG, OPS · as Aixle Bot (API key)')).toBeInTheDocument();
    expect(screen.getByText("Only a Linear workspace admin's API key can register webhooks.")).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Open Linear · Acme in Linear/ })).toHaveAttribute(
      'href',
      'https://linear.app/acme',
    );
    expect(screen.getByRole('button', { name: /Test connection for Linear/ })).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: /Connect/ }));
    await user.click(await screen.findByRole('menuitem', { name: 'Linear' }));
    expect(await screen.findByRole('dialog', { name: 'Connect Linear' })).toBeInTheDocument();
  });

  it('does not offer Linear outside a project', () => {
    renderPage(<IntegrationsContent title="Integrations" basePath="/company/integrations" integrations={[]} />, {
      props: settingsProps,
    });

    expect(screen.queryByRole('button', { name: 'Linear' })).not.toBeInTheDocument();
  });

  it('opens the team picker for the connection the Linear app just made', async () => {
    vi.mocked(globalThis.fetch).mockResolvedValue({ ok: true, json: async () => ({ teams: [] }) } as Response);
    window.history.pushState({}, '', '/company/projects/1/integrations?linear_setup=9');
    renderPage(
      <IntegrationsContent
        title="Integrations"
        basePath="/company/projects/1/integrations"
        integrations={[linearIntegration({ status: 'inactive', linearAuthMode: 'oauth', linearTeams: [] })]}
        linear={{ oauthEnabled: true }}
      />,
      { props: settingsProps },
    );

    expect(await screen.findByRole('dialog', { name: 'Linear teams' })).toBeInTheDocument();
    expect(screen.getByText('Choose the Linear teams to finish connecting')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Test connection for Linear/ })).not.toBeInTheDocument();
    window.history.pushState({}, '', '/');
    vi.mocked(globalThis.fetch).mockReset();
  });

  // == YouTrack ==

  it('offers YouTrack in a project, and says which projects a connection covers, as whom and which have sent nothing', async () => {
    const user = userEvent.setup();
    renderPage(
      <IntegrationsContent
        title="Integrations"
        basePath="/company/projects/1/integrations"
        integrations={[
          makeIntegration({
            id: 7,
            name: 'YouTrack · acme.youtrack.cloud',
            provider: 'youtrack',
            scopeIndicator: 'project',
            youtrackBaseUrl: 'https://acme.youtrack.cloud',
            youtrackProjects: [
              { id: '0-1', key: 'APP', name: 'Application' },
              { id: '0-2', key: 'OPS', name: 'Operations' },
            ],
            youtrackIdentity: 'aixle-flow',
            youtrackWebhooksPending: ['APP', 'OPS'],
          }),
        ]}
        youtrack={{ enabled: true, marketplaceUrl: 'https://plugins.jetbrains.com/plugin/aixle-flow' }}
      />,
      { props: settingsProps },
    );

    expect(screen.getByText('APP, OPS · as @aixle-flow')).toBeInTheDocument();
    expect(
      screen.getByText(
        'No event yet from APP, OPS — check that the Aixle Flow app is attached to those projects in YouTrack',
      ),
    ).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Open YouTrack · acme.youtrack.cloud in YouTrack/ })).toHaveAttribute(
      'href',
      'https://acme.youtrack.cloud',
    );
    expect(screen.getByRole('link', { name: /Manage YouTrack · acme.youtrack.cloud in YouTrack/ })).toHaveAttribute(
      'href',
      'https://acme.youtrack.cloud/admin/app/aixle-flow/connect',
    );
    expect(screen.getByRole('button', { name: /Test connection for YouTrack/ })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Webhook setup for YouTrack/ })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /YouTrack projects for/ })).not.toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: /Connect/ }));
    await user.click(await screen.findByRole('menuitem', { name: 'YouTrack' }));
    expect(await screen.findByRole('dialog', { name: 'Connect YouTrack' })).toBeInTheDocument();
  });

  // == GitHub Projects ==

  it('lists the GitHub projects a connection covers and opens their picker from the row', async () => {
    const user = userEvent.setup();
    vi.mocked(globalThis.fetch).mockResolvedValue({
      ok: true,
      json: async () => ({ projects: [], selected: [] }),
    } as Response);
    renderPage(
      <IntegrationsContent
        title="Integrations"
        basePath="/company/projects/1/integrations"
        integrations={[
          makeIntegration({
            scopeIndicator: 'project',
            githubAuthMode: 'app',
            githubProjectsSupported: true,
            githubProjects: [
              { id: 'PVT_1', number: 5, title: 'Roadmap', url: 'https://github.com/orgs/acme/projects/5' },
            ],
          }),
        ]}
      />,
      { props: settingsProps },
    );

    expect(screen.getByText('projects: Roadmap')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'GitHub Projects for Acme GitHub' }));
    expect(await screen.findByRole('dialog', { name: 'GitHub Projects' })).toBeInTheDocument();
    vi.mocked(globalThis.fetch).mockReset();
  });

  it('offers no GitHub Projects on a connection that cannot carry them', () => {
    renderPage(
      <IntegrationsContent
        title="Integrations"
        basePath="/company/projects/1/integrations"
        integrations={[makeIntegration({ scopeIndicator: 'project', githubAuthMode: 'pat' })]}
      />,
      { props: settingsProps },
    );

    expect(screen.queryByRole('button', { name: /GitHub Projects for/ })).not.toBeInTheDocument();
  });

  it('reopens the Azure dialog where the Microsoft sign-in left off', async () => {
    vi.mocked(globalThis.fetch).mockResolvedValue({
      ok: true,
      json: async () => ({
        organization: 'contoso',
        tenantId: 't',
        identity: 'grace@contoso.com',
        alreadyBound: false,
        projects: [],
      }),
    } as Response);
    window.history.pushState({}, '', '/company/projects/1/integrations?azure_setup=held-1&azure_organization=contoso');
    renderPage(
      <IntegrationsContent
        title="Integrations"
        basePath="/company/projects/1/integrations"
        integrations={[]}
        azureDevops={azureDevopsProps}
      />,
      { props: settingsProps },
    );

    expect(await screen.findByText(/Verified as grace@contoso.com/)).toBeInTheDocument();
    expect(window.location.search).toBe('');
    window.history.pushState({}, '', '/');
    vi.mocked(globalThis.fetch).mockReset();
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

  it('keeps the GitLab dialog open with the reason when GitLab refuses the token', async () => {
    renderPage(
      <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
      { props: settingsProps },
    );

    await userEvent.click(screen.getByRole('button', { name: /GitLab/i }));
    const dialog = await screen.findByRole('dialog', { name: /Connect GitLab/i });
    await userEvent.type(within(dialog).getByPlaceholderText('glpat-...'), 'glpat-expired');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Connect' }));

    const options = vi.mocked(router.post).mock.lastCall?.[2] as
      { onError?: (errors: Record<string, string>) => void } | undefined;
    act(() => options?.onError?.({ personalAccessToken: 'GitLab rejected this token.' }));

    expect(within(dialog).getByText('GitLab rejected this token.')).toBeInTheDocument();
    expect(screen.getByRole('dialog', { name: /Connect GitLab/i })).toBeInTheDocument();
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

    // Connecting GitHub opens the mode dialog first — GitHub App or a personal
    // access token. The App path then navigates to the SERVER endpoint, which
    // mints a signed state (Oauth::State) and redirects to GitHub; the state is
    // no longer built client-side (§7).
    it('connecting GitHub from the empty state opens the dialog and installs the app', async () => {
      renderPage(
        <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: 'GitHub' }));
      await userEvent.click(await screen.findByRole('button', { name: 'Continue to GitHub' }));

      expect(window.location.href).toBe('/company/integrations/github_app_install');
    });

    it('in a project context it navigates to that project’s install endpoint', async () => {
      renderPage(
        <IntegrationsContent title="Project Integrations" basePath="/projects/42/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: 'GitHub' }));
      await userEvent.click(await screen.findByRole('button', { name: 'Continue to GitHub' }));

      expect(window.location.href).toBe('/projects/42/integrations/github_app_install');
    });

    it('opens the dialog from the Connect menu when integrations already exist', async () => {
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
      await userEvent.click(await screen.findByRole('button', { name: 'Continue to GitHub' }));

      expect(window.location.href).toBe('/company/integrations/github_app_install');
    });
  });

  // A token connection acts as a person and receives no webhooks, so the row
  // has to say so — the two facts someone debugging a stalled gate needs.
  it('marks a GitHub connection that runs on a personal access token', () => {
    renderPage(
      <IntegrationsContent
        title="Project Integrations"
        basePath="/projects/42/integrations"
        integrations={[makeIntegration({ id: 4, name: 'octodev', githubAuthMode: 'pat', githubTokenScopes: ['repo'] })]}
      />,
      { props: settingsProps },
    );

    expect(screen.getByText('token · as Jane Doe · repo')).toBeInTheDocument();
  });

  it('does not mark an App-backed GitHub connection as a token one', () => {
    renderPage(
      <IntegrationsContent
        title="Project Integrations"
        basePath="/projects/42/integrations"
        integrations={[makeIntegration({ id: 5, name: 'acme', githubAuthMode: 'app' })]}
      />,
      { props: settingsProps },
    );

    expect(screen.queryByText(/^token · /)).not.toBeInTheDocument();
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

  it('tests a GitHub connection from its row', async () => {
    renderPage(
      <IntegrationsContent
        title="Project Integrations"
        basePath="/projects/42/integrations"
        integrations={[makeIntegration({ id: 5, name: 'acme', githubAuthMode: 'app', scopeIndicator: 'project' })]}
      />,
      { props: settingsProps },
    );

    await userEvent.click(screen.getByRole('button', { name: 'Test connection for acme' }));

    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith('/projects/42/integrations/5/test_connection', {}, expect.anything()),
    );
  });

  // An uninstall on GitHub has to read as one, not as a bare "Error".
  it('says why a GitHub connection is not working', () => {
    renderPage(
      <IntegrationsContent
        title="Project Integrations"
        basePath="/projects/42/integrations"
        integrations={[
          makeIntegration({
            id: 5,
            name: 'acme',
            status: 'error',
            githubAuthMode: 'app',
            scopeIndicator: 'project',
            githubError: 'The GitHub App was uninstalled on GitHub. Install it again, or remove this connection.',
          }),
        ]}
      />,
      { props: settingsProps },
    );

    expect(screen.getByText(/The GitHub App was uninstalled on GitHub/)).toBeInTheDocument();
  });

  it('warns that removing an App connection leaves the app installed on GitHub', async () => {
    renderPage(
      <IntegrationsContent
        title="Project Integrations"
        basePath="/projects/42/integrations"
        integrations={[
          makeIntegration({
            id: 5,
            name: 'acme',
            githubAuthMode: 'app',
            scopeIndicator: 'project',
            githubUrl: 'https://github.com/apps/aixle-app/installations/55',
          }),
        ]}
      />,
      { props: settingsProps },
    );

    await userEvent.click(screen.getByRole('button', { name: 'Remove' }));

    const dialog = await screen.findByRole('dialog', { name: /Remove Integration/i });
    expect(within(dialog).getByText(/stays installed on GitHub/)).toBeInTheDocument();
    expect(within(dialog).getByRole('link', { name: 'Uninstall it on GitHub' })).toHaveAttribute(
      'href',
      'https://github.com/apps/aixle-app/installations/55',
    );
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

    it('cancelling the Coder modal asks first, then closes it and clears the entered fields', async () => {
      renderPage(
        <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      const dialog = await openCoderModal();
      await userEvent.type(within(dialog).getByPlaceholderText('https://coder.example.com'), 'https://coder.acme.dev');
      await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));

      const discard = await screen.findByRole('dialog', { name: 'Discard unsaved changes?' });
      expect(screen.getByRole('dialog', { name: /Connect Coder/i })).toBeInTheDocument();
      await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));

      await waitFor(() => expect(screen.queryByRole('dialog', { name: /Connect Coder/i })).not.toBeInTheDocument());
      expect(router.post).not.toHaveBeenCalled();

      // Reopening yields a pristine form: closeCoderModal ran resetCoderForm on cancel.
      const reopened = await openCoderModal();
      expect(within(reopened).getByPlaceholderText('https://coder.example.com')).toHaveValue('');
    });

    it('closes an untouched Coder modal without asking, even with Advanced opened', async () => {
      renderPage(
        <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      const dialog = await openCoderModal();
      await userEvent.click(within(dialog).getByText('Advanced'));
      await userEvent.click(within(dialog).getByRole('button', { name: 'Clear' }));

      await waitFor(() => expect(screen.queryByRole('dialog', { name: /Connect Coder/i })).not.toBeInTheDocument());
      expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
    });

    it('treats a changed lock TTL as unsaved input', async () => {
      renderPage(
        <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      const dialog = await openCoderModal();
      await userEvent.click(within(dialog).getByText('Advanced'));
      await userEvent.type(within(dialog).getByLabelText('Lock TTL (minutes)'), '0');
      await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));

      expect(await screen.findByRole('dialog', { name: 'Discard unsaved changes?' })).toBeInTheDocument();
      expect(screen.getByRole('dialog', { name: /Connect Coder/i })).toBeInTheDocument();
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

    it('asks before closing over a typed token, then closes and clears it on Discard', async () => {
      renderPage(
        <IntegrationsContent title="Company Integrations" basePath="/company/integrations" integrations={[]} />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: /GitLab/i }));
      const dialog = await screen.findByRole('dialog', { name: /Connect GitLab/i });
      await userEvent.type(within(dialog).getByPlaceholderText('glpat-...'), 'glpat-draft');
      await userEvent.click(within(dialog).getByRole('button', { name: 'Clear' }));

      const discard = await screen.findByRole('dialog', { name: 'Discard unsaved changes?' });
      expect(screen.getByRole('dialog', { name: /Connect GitLab/i })).toBeInTheDocument();
      await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));

      await waitFor(() => expect(screen.queryByRole('dialog', { name: /Connect GitLab/i })).not.toBeInTheDocument());
      await userEvent.click(screen.getByRole('button', { name: /GitLab/i }));
      const reopened = await screen.findByRole('dialog', { name: /Connect GitLab/i });
      expect(within(reopened).getByPlaceholderText('glpat-...')).toHaveValue('');
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
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[]}
          slack={{ enabled: true }}
        />,
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
          slack={{ enabled: true }}
        />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: 'Connect' }));
      await userEvent.click(await screen.findByRole('menuitem', { name: /Slack/i }));

      expect(window.location.href).toBe('/projects/42/integrations/slack_oauth_start');
    });

    it('does not offer Slack on a deployment with no Slack app', async () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[]}
          slack={{ enabled: false }}
        />,
        { props: settingsProps },
      );

      expect(screen.getByRole('button', { name: /GitLab/i })).toBeInTheDocument();
      expect(screen.queryByRole('button', { name: 'Slack' })).not.toBeInTheDocument();
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

  describe('Coder settings', () => {
    const coderIntegration = (overrides: Partial<Integration> = {}) =>
      makeIntegration({
        id: 9,
        name: 'Acme Coder',
        provider: 'coder',
        scopeIndicator: 'project',
        coderUrl: 'https://coder.aixle.dev',
        coderDefaultTemplate: 'aws-ec2-spot-v1',
        coderMachinePrefix: 'aixle-prod',
        coderLockTtlMinutes: 120,
        ...overrides,
      });

    it('shows the allocator settings on the row', () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[coderIntegration()]}
        />,
        { props: settingsProps },
      );

      expect(screen.getByText('template aws-ec2-spot-v1 · prefix aixle-prod · lock 120m')).toBeInTheDocument();
    });

    it('calls out a missing default template, which is what stops the pool from growing', () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[coderIntegration({ coderDefaultTemplate: null, coderMachinePrefix: null })]}
        />,
        { props: settingsProps },
      );

      expect(screen.getByText('no default template · no prefix · lock 120m')).toBeInTheDocument();
    });

    it('saving the edit form patches the integration with the changed settings', async () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[coderIntegration({ coderDefaultTemplate: null })]}
        />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: 'Edit settings for Acme Coder' }));
      const dialog = await screen.findByRole('dialog', { name: /Coder settings/i });

      // Prefilled from the row, so an edit never silently drops the other fields.
      expect(within(dialog).getByLabelText('Machine name prefix')).toHaveValue('aixle-prod');

      await userEvent.type(within(dialog).getByLabelText('Default template'), 'aws-ec2-spot-v1');
      await userEvent.click(within(dialog).getByRole('button', { name: 'Save' }));

      expect(router.patch).toHaveBeenCalledWith(
        '/projects/42/integrations/9',
        { defaultTemplate: 'aws-ec2-spot-v1', machinePrefix: 'aixle-prod', lockTtlMinutes: 120 },
        expect.objectContaining({ preserveScroll: true }),
      );
    });

    it('sends a blank template when it is cleared, so the pool can be capped', async () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[coderIntegration()]}
        />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: 'Edit settings for Acme Coder' }));
      const dialog = await screen.findByRole('dialog', { name: /Coder settings/i });

      await userEvent.clear(within(dialog).getByLabelText('Default template'));
      await userEvent.click(within(dialog).getByRole('button', { name: 'Save' }));

      expect(router.patch).toHaveBeenCalledWith(
        '/projects/42/integrations/9',
        expect.objectContaining({ defaultTemplate: '' }),
        expect.any(Object),
      );
    });

    it('closes the settings it opened with, untouched, without asking', async () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[coderIntegration()]}
        />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: 'Edit settings for Acme Coder' }));
      const dialog = await screen.findByRole('dialog', { name: /Coder settings/i });
      await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));

      await waitFor(() => expect(screen.queryByRole('dialog', { name: /Coder settings/i })).not.toBeInTheDocument());
      expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
    });

    it('asks before closing over an edited setting, and closes on Discard', async () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[coderIntegration()]}
        />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: 'Edit settings for Acme Coder' }));
      const dialog = await screen.findByRole('dialog', { name: /Coder settings/i });
      await userEvent.type(within(dialog).getByLabelText('Machine name prefix'), '-eu');
      await userEvent.click(within(dialog).getByRole('button', { name: 'Clear' }));

      const discard = await screen.findByRole('dialog', { name: 'Discard unsaved changes?' });
      expect(screen.getByRole('dialog', { name: /Coder settings/i })).toBeInTheDocument();
      await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));

      await waitFor(() => expect(screen.queryByRole('dialog', { name: /Coder settings/i })).not.toBeInTheDocument());
      expect(router.patch).not.toHaveBeenCalled();
    });

    it('tests the connection and replaces its session token from the row', async () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[coderIntegration()]}
        />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: 'Test connection for Acme Coder' }));
      expect(router.post).toHaveBeenCalledWith('/projects/42/integrations/9/test_connection', {}, expect.anything());

      await userEvent.click(screen.getByRole('button', { name: 'Replace token for Acme Coder' }));
      const dialog = await screen.findByRole('dialog', { name: /Replace token/i });
      await userEvent.type(within(dialog).getByLabelText('Session Token'), 'tok-new');
      await userEvent.click(within(dialog).getByRole('button', { name: 'Replace' }));

      expect(router.patch).toHaveBeenCalledWith(
        '/projects/42/integrations/9',
        { sessionToken: 'tok-new' },
        expect.objectContaining({ preserveScroll: true }),
      );
    });

    it('hides the edit action for a company-wide integration in a project context', () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[coderIntegration({ scopeIndicator: 'company' })]}
        />,
        { props: settingsProps },
      );

      expect(screen.queryByRole('button', { name: /Edit settings/i })).not.toBeInTheDocument();
    });
  });

  describe('GitLab token', () => {
    const gitlabIntegration = (overrides: Partial<Integration> = {}) =>
      makeIntegration({ id: 11, name: 'alice', provider: 'gitlab', scopeIndicator: 'project', ...overrides });

    it('says why a connection needs attention', () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[
            gitlabIntegration({
              status: 'error',
              settings: { error: "GitLab no longer accepts this connection's token. Replace the token." },
            }),
          ]}
        />,
        { props: settingsProps },
      );

      expect(
        screen.getByText("GitLab no longer accepts this connection's token. Replace the token."),
      ).toBeInTheDocument();
    });

    it('replaces the token and keeps the dialog open when GitLab refuses the new one', async () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[gitlabIntegration()]}
        />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: 'Replace token for alice' }));
      const dialog = await screen.findByRole('dialog', { name: /Replace token/i });
      await userEvent.type(within(dialog).getByLabelText('Personal Access Token'), 'glpat-new');
      await userEvent.click(within(dialog).getByRole('button', { name: 'Replace' }));

      expect(router.patch).toHaveBeenCalledWith(
        '/projects/42/integrations/11',
        { personalAccessToken: 'glpat-new' },
        expect.objectContaining({ preserveScroll: true }),
      );

      const options = vi.mocked(router.patch).mock.lastCall?.[2] as
        { onError?: (errors: Record<string, string>) => void } | undefined;
      act(() => options?.onError?.({ personalAccessToken: 'GitLab rejected this token.' }));

      expect(within(dialog).getByText('GitLab rejected this token.')).toBeInTheDocument();
    });

    it('closes the replace-token dialog straight away while it is empty', async () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[gitlabIntegration()]}
        />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: 'Replace token for alice' }));
      const dialog = await screen.findByRole('dialog', { name: /Replace token/i });
      await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));

      await waitFor(() => expect(screen.queryByRole('dialog', { name: /Replace token/i })).not.toBeInTheDocument());
      expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
    });

    it('asks before throwing away a pasted replacement token', async () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[gitlabIntegration()]}
        />,
        { props: settingsProps },
      );

      await userEvent.click(screen.getByRole('button', { name: 'Replace token for alice' }));
      const dialog = await screen.findByRole('dialog', { name: /Replace token/i });
      await userEvent.type(within(dialog).getByLabelText('Personal Access Token'), 'glpat-new');
      await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));

      const discard = await screen.findByRole('dialog', { name: 'Discard unsaved changes?' });
      expect(screen.getByRole('dialog', { name: /Replace token/i })).toBeInTheDocument();
      await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));

      await waitFor(() => expect(screen.queryByRole('dialog', { name: /Replace token/i })).not.toBeInTheDocument());
      expect(router.patch).not.toHaveBeenCalled();
    });

    it('offers no token actions to a viewer', () => {
      renderPage(
        <IntegrationsContent
          title="Project Integrations"
          basePath="/projects/42/integrations"
          integrations={[gitlabIntegration()]}
        />,
        { props: { ...settingsProps, projectPermissions: { canExecute: false, canManage: false } } },
      );

      expect(screen.queryByRole('button', { name: /Replace token/i })).not.toBeInTheDocument();
      expect(screen.queryByRole('button', { name: /Test connection/i })).not.toBeInTheDocument();
    });
  });
});
