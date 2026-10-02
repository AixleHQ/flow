import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { buildIntegration } from 'test/factories/integration';
import { renderPage, screen, userEvent, within } from 'test/renderPage';

import { LinearConnectModal, LinearTeamsModal } from './LinearConnectModal';

const BASE = '/company/projects/1/integrations';

const TEAMS = [
  { id: 't-eng', key: 'ENG', name: 'Engineering' },
  { id: 't-ops', key: 'OPS', name: 'Operations' },
];

// The Linear endpoints answer JSON, so they go through `fetch`, which setup.ts stubs inertly.
const mockFetch = (handler: (url: string, body: Record<string, unknown>) => { ok?: boolean; payload: unknown }) =>
  vi.mocked(globalThis.fetch).mockImplementation((async (url: string, init: RequestInit) => {
    const body = init.body ? JSON.parse(String(init.body)) : {};
    const { ok = true, payload } = handler(String(url), body);
    return { ok, json: async () => payload } as Response;
  }) as typeof globalThis.fetch);

const pickTeam = async (user: ReturnType<typeof userEvent.setup>, label: string) => {
  await user.click(await screen.findByRole('combobox', { name: /Linear teams/ }));
  await user.click(await screen.findByRole('option', { name: label }));
};

const linearIntegration = (overrides = {}) =>
  buildIntegration({
    id: 9,
    name: 'Linear · Acme',
    provider: 'linear',
    status: 'active',
    scopeIndicator: 'project',
    linearAuthMode: 'api_key',
    ...overrides,
  });

describe('LinearConnectModal', () => {
  beforeEach(() => vi.mocked(router.post).mockClear());
  afterEach(() => vi.mocked(globalThis.fetch).mockReset());

  it('sends the app path to the OAuth start action', () => {
    renderPage(<LinearConnectModal opened onClose={() => {}} basePath={BASE} linear={{ oauthEnabled: true }} />);

    expect(screen.getByRole('link', { name: "Install Aixle's Linear app" })).toHaveAttribute(
      'href',
      `${BASE}/linear_oauth_start`,
    );
  });

  it('checks an API key, then connects the teams picked and whether the account is kept for Aixle', async () => {
    const user = userEvent.setup();
    mockFetch((url, body) => {
      expect(url).toBe(`${BASE}/linear_inspect`);
      expect(body).toEqual({ api_key: 'lin_api_x' });
      return {
        payload: {
          identity: { id: 'u-bot', name: 'Aixle Bot' },
          organization: { id: 'org-1', name: 'Acme', url_key: 'acme' },
          teams: TEAMS,
        },
      };
    });
    renderPage(<LinearConnectModal opened onClose={() => {}} basePath={BASE} linear={{ oauthEnabled: false }} />);

    expect(screen.queryByRole('link', { name: "Install Aixle's Linear app" })).not.toBeInTheDocument();
    await user.type(screen.getByLabelText('API key'), 'lin_api_x');
    await user.click(screen.getByRole('button', { name: 'Check' }));

    expect(await screen.findByText('Signed in to Acme as Aixle Bot.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Connect' })).toBeDisabled();
    await pickTeam(user, 'Operations (OPS)');
    await user.click(screen.getByRole('checkbox', { name: 'This Linear account is kept for Aixle' }));
    await user.click(screen.getByRole('button', { name: 'Connect' }));

    expect(router.post).toHaveBeenCalledWith(
      BASE,
      { provider: 'linear', apiKey: 'lin_api_x', teamIds: ['t-ops'], dedicatedIdentity: true },
      expect.anything(),
    );
  });

  it('shows why Linear refused the key', async () => {
    const user = userEvent.setup();
    mockFetch(() => ({ ok: false, payload: { message: 'Linear rejected this connection’s credential' } }));
    renderPage(<LinearConnectModal opened onClose={() => {}} basePath={BASE} linear={{ oauthEnabled: false }} />);

    await user.type(screen.getByLabelText('API key'), 'wrong');
    await user.click(screen.getByRole('button', { name: 'Check' }));

    expect(await screen.findByText('Linear rejected this connection’s credential')).toBeInTheDocument();
  });
});

describe('LinearConnectModal closing', () => {
  it('asks before closing over a typed API key, and clears it once discarded', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    renderPage(<LinearConnectModal opened onClose={onClose} basePath={BASE} linear={{ oauthEnabled: false }} />);

    await user.type(screen.getByLabelText('API key'), 'lin_api_x');
    await user.click(screen.getByRole('button', { name: 'Cancel' }));

    const discard = await screen.findByRole('dialog', { name: 'Discard unsaved changes?' });
    expect(onClose).not.toHaveBeenCalled();

    await user.click(within(discard).getByRole('button', { name: 'Discard' }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.getByLabelText('API key')).toHaveValue('');
  });

  it('closes without asking when nothing was entered', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    renderPage(<LinearConnectModal opened onClose={onClose} basePath={BASE} linear={{ oauthEnabled: true }} />);

    await user.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });
});

describe('LinearTeamsModal', () => {
  beforeEach(() => vi.mocked(router.patch).mockClear());
  afterEach(() => vi.mocked(globalThis.fetch).mockReset());

  it('asks before closing over a changed choice of teams, and not over an untouched one', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    mockFetch(() => ({ payload: { teams: TEAMS } }));
    renderPage(
      <LinearTeamsModal
        integration={linearIntegration({ linearTeams: [TEAMS[0]] })}
        onClose={onClose}
        basePath={BASE}
      />,
    );

    await screen.findByRole('combobox', { name: /Linear teams/ });
    await user.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(onClose).toHaveBeenCalledTimes(1);

    await pickTeam(user, 'Operations (OPS)');
    await user.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(await screen.findByRole('dialog', { name: 'Discard unsaved changes?' })).toBeInTheDocument();
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('finishes a pending app connection with the teams picked', async () => {
    const user = userEvent.setup();
    mockFetch((url) => {
      expect(url).toBe(`${BASE}/9/linear_teams`);
      return { payload: { teams: TEAMS } };
    });
    renderPage(
      <LinearTeamsModal
        integration={linearIntegration({ status: 'inactive', linearAuthMode: 'oauth' })}
        onClose={() => {}}
        basePath={BASE}
      />,
    );

    await pickTeam(user, 'Engineering (ENG)');
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Save' }));

    expect(router.patch).toHaveBeenCalledWith(`${BASE}/9`, { teamIds: ['t-eng'] }, expect.anything());
  });

  it('changes the teams of an API-key connection, starting from the ones it covers', async () => {
    const user = userEvent.setup();
    mockFetch(() => ({ payload: { teams: TEAMS } }));
    renderPage(
      <LinearTeamsModal
        integration={linearIntegration({ linearTeams: [TEAMS[0]], linearDedicatedIdentity: true })}
        onClose={() => {}}
        basePath={BASE}
      />,
    );

    await pickTeam(user, 'Operations (OPS)');
    expect(screen.getByRole('checkbox', { name: 'This Linear account is kept for Aixle' })).toBeChecked();
    await user.click(screen.getByRole('button', { name: 'Save' }));

    expect(router.patch).toHaveBeenCalledWith(
      `${BASE}/9`,
      { teamIds: ['t-eng', 't-ops'], dedicatedIdentity: true },
      expect.anything(),
    );
  });

  it('says why the teams could not be listed', async () => {
    mockFetch(() => ({ ok: false, payload: { message: 'Linear rejected this connection’s API key' } }));
    renderPage(<LinearTeamsModal integration={linearIntegration()} onClose={() => {}} basePath={BASE} />);

    expect(await screen.findByText('Linear rejected this connection’s API key')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled();
  });
});
