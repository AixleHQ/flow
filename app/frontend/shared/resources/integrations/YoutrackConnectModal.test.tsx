import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { buildIntegration } from 'test/factories/integration';
import { renderPage, screen, userEvent } from 'test/renderPage';

import { YoutrackConnectModal, YoutrackProjectsModal, YoutrackWebhookModal } from './YoutrackConnectModal';

const BASE = '/company/projects/1/integrations';

const PROJECTS = [
  { id: '0-1', key: 'APP', name: 'Application' },
  { id: '0-2', key: 'OPS', name: 'Operations' },
];

// The YouTrack endpoints answer JSON, so they go through `fetch`, which setup.ts stubs inertly.
const mockFetch = (
  handler: (url: string, body: Record<string, unknown>, method: string) => { ok?: boolean; payload: unknown },
) =>
  vi.mocked(globalThis.fetch).mockImplementation((async (url: string, init: RequestInit) => {
    const body = init.body ? JSON.parse(String(init.body)) : {};
    const { ok = true, payload } = handler(String(url), body, init.method ?? 'GET');
    return { ok, json: async () => payload } as Response;
  }) as typeof globalThis.fetch);

const pickProject = async (user: ReturnType<typeof userEvent.setup>, label: string) => {
  await user.click(await screen.findByRole('combobox', { name: /YouTrack projects/ }));
  await user.click(await screen.findByRole('option', { name: label }));
};

const youtrackIntegration = (overrides = {}) =>
  buildIntegration({
    id: 7,
    name: 'YouTrack · acme.youtrack.cloud',
    provider: 'youtrack',
    status: 'active',
    scopeIndicator: 'project',
    youtrackBaseUrl: 'https://acme.youtrack.cloud',
    youtrackProjects: [PROJECTS[0]],
    youtrackIdentity: 'aixle',
    ...overrides,
  });

const webhook = (overrides = {}) => ({
  scopeId: '0-1',
  key: 'APP',
  name: 'Application',
  url: 'https://flow.example.com/webhooks/trackers/tok-app',
  header: 'X-YouTrack-Token',
  token: 'a'.repeat(64),
  status: 'pending',
  lastEventAt: null,
  ...overrides,
});

describe('YoutrackConnectModal', () => {
  beforeEach(() => vi.mocked(router.post).mockClear());
  afterEach(() => vi.mocked(globalThis.fetch).mockReset());

  it('checks the URL and token, then connects the projects picked', async () => {
    const user = userEvent.setup();
    mockFetch((url, body) => {
      expect(url).toBe(`${BASE}/youtrack_inspect`);
      expect(body).toEqual({ base_url: 'https://acme.youtrack.cloud/', permanent_token: 'perm:x' });
      return {
        payload: {
          base_url: 'https://acme.youtrack.cloud',
          identity: { id: '1-1', login: 'aixle', name: 'Aixle Bot' },
          projects: PROJECTS,
        },
      };
    });
    renderPage(<YoutrackConnectModal opened onClose={() => {}} basePath={BASE} />);

    expect(screen.getByRole('button', { name: 'Check' })).toBeDisabled();
    await user.type(screen.getByLabelText('YouTrack URL'), 'https://acme.youtrack.cloud/');
    await user.type(screen.getByLabelText('Permanent token'), 'perm:x');
    await user.click(screen.getByRole('button', { name: 'Check' }));

    expect(
      await screen.findByText('Signed in to https://acme.youtrack.cloud as Aixle Bot (@aixle).'),
    ).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Connect' })).toBeDisabled();
    await pickProject(user, 'Operations (OPS)');
    await user.click(screen.getByRole('checkbox', { name: 'This YouTrack account is kept for Aixle' }));
    await user.click(screen.getByRole('button', { name: 'Connect' }));

    expect(router.post).toHaveBeenCalledWith(
      BASE,
      {
        provider: 'youtrack',
        baseUrl: 'https://acme.youtrack.cloud',
        permanentToken: 'perm:x',
        projectIds: ['0-2'],
        dedicatedIdentity: true,
      },
      expect.anything(),
    );
  });

  it('shows why YouTrack refused the token', async () => {
    const user = userEvent.setup();
    mockFetch(() => ({ ok: false, payload: { message: 'YouTrack rejected the permanent token' } }));
    renderPage(<YoutrackConnectModal opened onClose={() => {}} basePath={BASE} />);

    await user.type(screen.getByLabelText('YouTrack URL'), 'https://acme.youtrack.cloud');
    await user.type(screen.getByLabelText('Permanent token'), 'wrong');
    await user.click(screen.getByRole('button', { name: 'Check' }));

    expect(await screen.findByText('YouTrack rejected the permanent token')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Connect' })).not.toBeInTheDocument();
  });
});

describe('YoutrackProjectsModal', () => {
  beforeEach(() => vi.mocked(router.patch).mockClear());
  afterEach(() => vi.mocked(globalThis.fetch).mockReset());

  it('saves the projects picked with whether the account is kept for Aixle', async () => {
    const user = userEvent.setup();
    mockFetch((url) => {
      expect(url).toBe(`${BASE}/7/youtrack_projects`);
      return { payload: { projects: PROJECTS } };
    });
    renderPage(<YoutrackProjectsModal integration={youtrackIntegration()} onClose={() => {}} basePath={BASE} />);

    await pickProject(user, 'Operations (OPS)');
    await user.click(screen.getByRole('button', { name: 'Save' }));

    expect(router.patch).toHaveBeenCalledWith(
      `${BASE}/7`,
      { projectIds: ['0-1', '0-2'], dedicatedIdentity: false },
      expect.anything(),
    );
  });
});

describe('YoutrackWebhookModal', () => {
  afterEach(() => vi.mocked(globalThis.fetch).mockReset());

  it("shows each project's URL, header and token, and keeps the token a project's app already has", async () => {
    const user = userEvent.setup();
    const existing = 'e'.repeat(40);
    mockFetch((url, body, method) => {
      if (method === 'GET') {
        expect(url).toBe(`${BASE}/7/youtrack_webhook`);
        return {
          payload: {
            projects: [
              webhook(),
              webhook({
                scopeId: '0-2',
                key: 'OPS',
                name: 'Operations',
                url: 'https://flow.example.com/webhooks/trackers/tok-ops',
                lastEventAt: '2026-10-01T10:00:00Z',
              }),
            ],
            events: ['Issue Created', 'Issue Updated', 'Comment Added'],
          },
        };
      }
      expect(url).toBe(`${BASE}/7/youtrack_webhook_token`);
      expect(body).toEqual({ scope_id: '0-1', token: existing, header: 'X-Hook' });
      return { payload: webhook({ token: existing, header: 'X-Hook' }) };
    });
    renderPage(<YoutrackWebhookModal integration={youtrackIntegration()} onClose={() => {}} basePath={BASE} />);

    expect(await screen.findByText('https://flow.example.com/webhooks/trackers/tok-app')).toBeInTheDocument();
    expect(screen.getByText('No event yet')).toBeInTheDocument();
    expect(screen.getByLabelText('Token for APP')).toHaveValue('a'.repeat(64));

    await user.click(screen.getAllByRole('button', { name: "This project's app already has a token" })[0]);
    const save = screen.getByRole('button', { name: 'Save token' });
    await user.type(screen.getByLabelText("The token this project's app already uses"), 'short');
    expect(save).toBeDisabled();
    await user.clear(screen.getByLabelText("The token this project's app already uses"));
    await user.type(screen.getByLabelText("The token this project's app already uses"), existing);
    await user.clear(screen.getByLabelText('Header name'));
    await user.type(screen.getByLabelText('Header name'), 'X-Hook');
    await user.click(save);

    expect(await screen.findByText('X-Hook')).toBeInTheDocument();
    expect(screen.getByLabelText('Token for APP')).toHaveValue(existing);
  });
});
