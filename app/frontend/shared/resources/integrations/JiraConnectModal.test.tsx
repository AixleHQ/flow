import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { buildIntegration } from 'test/factories/integration';
import { renderPage, screen, userEvent } from 'test/renderPage';

import { JiraConnectModal, JiraProjectsModal, JiraWebhookModal } from './JiraConnectModal';

const BASE = '/company/projects/1/integrations';

const PROJECTS = [
  { id: '10000', key: 'ENG', name: 'Engineering' },
  { id: '10001', key: 'OPS', name: 'Operations' },
];

// The Jira endpoints answer JSON, so they go through `fetch`, which setup.ts stubs inertly.
const mockFetch = (handler: (url: string, body: Record<string, unknown>) => { ok?: boolean; payload: unknown }) =>
  vi.mocked(globalThis.fetch).mockImplementation((async (url: string, init: RequestInit) => {
    const body = init.body ? JSON.parse(String(init.body)) : {};
    const { ok = true, payload } = handler(String(url), body);
    return { ok, json: async () => payload } as Response;
  }) as typeof globalThis.fetch);

const pickProject = async (user: ReturnType<typeof userEvent.setup>, label: string) => {
  await user.click(await screen.findByRole('combobox', { name: /Jira projects/ }));
  await user.click(await screen.findByRole('option', { name: label }));
};

const jiraIntegration = (overrides = {}) =>
  buildIntegration({
    id: 5,
    name: 'Jira',
    provider: 'jira',
    status: 'inactive',
    scopeIndicator: 'project',
    jiraAuthMode: 'oauth',
    jiraSites: [
      { id: 'cloud-acme', name: 'acme', url: 'https://acme.atlassian.net' },
      { id: 'cloud-beta', name: 'beta', url: 'https://beta.atlassian.net' },
    ],
    ...overrides,
  });

describe('JiraConnectModal', () => {
  beforeEach(() => vi.mocked(router.post).mockClear());
  afterEach(() => vi.mocked(globalThis.fetch).mockReset());

  it('sends the Atlassian-account path to the OAuth start action', () => {
    renderPage(<JiraConnectModal opened onClose={() => {}} basePath={BASE} jira={{ oauthEnabled: true }} />);

    expect(screen.getByRole('link', { name: 'Continue to Atlassian' })).toHaveAttribute(
      'href',
      `${BASE}/jira_oauth_start`,
    );
  });

  it('checks a service account, then connects the projects picked', async () => {
    const user = userEvent.setup();
    mockFetch((url, body) => {
      expect(url).toBe(`${BASE}/jira_inspect`);
      expect(body).toEqual({ site_url: 'acme.atlassian.net', client_id: 'sa', client_secret: 'secret' });
      return {
        payload: {
          site: { id: 'cloud-acme', name: 'acme.atlassian.net', url: 'https://acme.atlassian.net' },
          identity: { id: 'bot', name: 'Aixle Bot' },
          projects: PROJECTS,
        },
      };
    });
    renderPage(<JiraConnectModal opened onClose={() => {}} basePath={BASE} jira={{ oauthEnabled: false }} />);

    expect(screen.queryByRole('link', { name: 'Continue to Atlassian' })).not.toBeInTheDocument();
    await user.type(screen.getByRole('textbox', { name: 'Jira site' }), 'acme.atlassian.net');
    await user.type(screen.getByRole('textbox', { name: 'Client ID' }), 'sa');
    await user.type(screen.getByLabelText('Client secret'), 'secret');
    await user.click(screen.getByRole('button', { name: 'Check' }));

    expect(await screen.findByText('Signed in to acme.atlassian.net as Aixle Bot.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Connect' })).toBeDisabled();
    await pickProject(user, 'Operations (OPS)');
    await user.click(screen.getByRole('button', { name: 'Connect' }));

    expect(router.post).toHaveBeenCalledWith(
      BASE,
      {
        provider: 'jira',
        siteUrl: 'acme.atlassian.net',
        clientId: 'sa',
        clientSecret: 'secret',
        projectIds: ['10001'],
      },
      expect.anything(),
    );
  });

  it('shows why Jira refused the credential', async () => {
    const user = userEvent.setup();
    mockFetch(() => ({ ok: false, payload: { message: 'Atlassian refused the credential: access_denied' } }));
    renderPage(<JiraConnectModal opened onClose={() => {}} basePath={BASE} jira={{ oauthEnabled: false }} />);

    await user.type(screen.getByRole('textbox', { name: 'Jira site' }), 'acme.atlassian.net');
    await user.type(screen.getByRole('textbox', { name: 'Client ID' }), 'sa');
    await user.type(screen.getByLabelText('Client secret'), 'wrong');
    await user.click(screen.getByRole('button', { name: 'Check' }));

    expect(await screen.findByText('Atlassian refused the credential: access_denied')).toBeInTheDocument();
  });
});

describe('JiraProjectsModal', () => {
  beforeEach(() => vi.mocked(router.patch).mockClear());
  afterEach(() => vi.mocked(globalThis.fetch).mockReset());

  it('finishes a pending connection: the site, its projects, and whether the account is kept for Aixle', async () => {
    const user = userEvent.setup();
    mockFetch((url) => {
      expect(url).toBe(`${BASE}/5/jira_projects?cloud_id=cloud-beta`);
      return { payload: { projects: PROJECTS } };
    });
    renderPage(<JiraProjectsModal integration={jiraIntegration()} onClose={() => {}} basePath={BASE} />);

    await user.click(screen.getByRole('combobox', { name: 'Jira site' }));
    await user.click(await screen.findByRole('option', { name: 'beta (https://beta.atlassian.net)' }));
    expect(await screen.findByRole('combobox', { name: /Jira projects/ })).toBeInTheDocument();
    await pickProject(user, 'Engineering (ENG)');
    await user.click(screen.getByRole('checkbox', { name: 'This Atlassian account is kept for Aixle' }));
    await user.click(screen.getByRole('button', { name: 'Save' }));

    expect(router.patch).toHaveBeenCalledWith(
      `${BASE}/5`,
      { projectIds: ['10000'], cloudId: 'cloud-beta', dedicatedIdentity: true },
      expect.anything(),
    );
  });

  it('changes the projects of a service-account connection, starting from the ones it covers', async () => {
    const user = userEvent.setup();
    mockFetch(() => ({ payload: { projects: PROJECTS } }));
    const integration = jiraIntegration({
      status: 'active',
      jiraAuthMode: 'service_account',
      jiraSites: [],
      jiraProjects: [PROJECTS[0]],
    });
    renderPage(<JiraProjectsModal integration={integration} onClose={() => {}} basePath={BASE} />);

    await pickProject(user, 'Operations (OPS)');
    await user.click(screen.getByRole('button', { name: 'Save' }));

    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument();
    expect(router.patch).toHaveBeenCalledWith(`${BASE}/5`, { projectIds: ['10000', '10001'] }, expect.anything());
  });
});

describe('JiraWebhookModal', () => {
  afterEach(() => vi.mocked(globalThis.fetch).mockReset());

  it('shows what a Jira admin enters as the system webhook', async () => {
    mockFetch((url) => {
      expect(url).toBe(`${BASE}/5/jira_webhook`);
      return {
        payload: {
          url: 'https://flow.example.com/webhooks/trackers/tok',
          secret: 's3cret',
          events: ['Issue: created', 'Issue: updated', 'Comment: created'],
          jql: 'project IN (ENG)',
          lastEventAt: null,
        },
      };
    });
    renderPage(
      <JiraWebhookModal integration={jiraIntegration({ status: 'active' })} onClose={() => {}} basePath={BASE} />,
    );

    expect(await screen.findByText('https://flow.example.com/webhooks/trackers/tok')).toBeInTheDocument();
    expect(screen.getByLabelText('Secret')).toHaveValue('s3cret');
    expect(screen.getByText('project IN (ENG)')).toBeInTheDocument();
    expect(screen.getByText('Events: Issue: created, Issue: updated, Comment: created.')).toBeInTheDocument();
    expect(screen.getByText('No event received yet.')).toBeInTheDocument();
  });
});
