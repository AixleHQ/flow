import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import type { AzureDevopsProps } from './AzureDevopsConnectModal';
import { AzureDevopsConnectModal } from './AzureDevopsConnectModal';

const BASE = '/company/projects/1/integrations';
const CLIENT_ID = '32f420a7-0c91-4a35-bfe8-80ad4869b837';
const PROJECT_ID = '11111111-1111-1111-1111-111111111111';
const FEDERATION = {
  issuerUrl: 'https://flow.example.com',
  audience: 'api://AzureADTokenExchange',
  subject: 'aixle:company:5f0c1c8e-3b1a-4c55-9d0e-5f3b6a7c9d10',
};

const renderModal = (props: Partial<AzureDevopsProps> = {}, onClose = () => {}) =>
  renderPage(
    <AzureDevopsConnectModal
      opened
      onClose={onClose}
      basePath={BASE}
      azureDevops={{ enabled: true, patModeEnabled: false, federation: FEDERATION, ...props }}
    />,
  );

const mockFetch = (handler: (url: string, body: Record<string, unknown>) => { ok?: boolean; payload: unknown }) =>
  vi.mocked(globalThis.fetch).mockImplementation((async (url: string, init: RequestInit) => {
    const body = JSON.parse(String(init.body));
    const { ok = true, payload } = handler(String(url), body);
    return { ok, json: async () => payload } as Response;
  }) as typeof globalThis.fetch);

const permissions = (status: 'granted' | 'missing') => ({
  ok: status === 'granted',
  projects: [
    {
      id: PROJECT_ID,
      name: 'Customer Platform',
      items: [
        { key: 'repos_contribute', group: 'Repos', label: 'Contribute', required: true, status },
        { key: 'hooks_edit', group: 'Service Hooks', label: 'Edit subscriptions', required: false, status: 'unknown' },
      ],
    },
  ],
});

const inspectionPayload = (overrides: Record<string, unknown> = {}) => ({
  organization: 'contoso',
  tenantId: '22222222-2222-2222-2222-222222222222',
  alreadyBound: false,
  projects: [{ id: PROJECT_ID, name: 'Customer Platform' }],
  permissions: null,
  ...overrides,
});

const useOwnApp = (user: ReturnType<typeof userEvent.setup>) => user.click(screen.getByText('Your own Entra app'));

const fillIdentity = async (user: ReturnType<typeof userEvent.setup>) => {
  await user.type(screen.getByLabelText(/Azure organization/), 'contoso');
  await user.type(screen.getByLabelText(/Application \(client\) ID/), CLIENT_ID);
};

const verify = async (user: ReturnType<typeof userEvent.setup>) => {
  await user.click(screen.getByRole('button', { name: 'Verify access' }));
  await screen.findByText('Aixle can sign in as your app');
};

const pickProject = async (user: ReturnType<typeof userEvent.setup>) => {
  await user.click(screen.getByRole('combobox', { name: /Azure projects/ }));
  await user.click(await screen.findByRole('option', { name: 'Customer Platform' }));
};

describe('AzureDevopsConnectModal with your own Entra app', () => {
  beforeEach(() => {
    vi.mocked(router.post).mockClear();
  });

  afterEach(() => {
    vi.mocked(globalThis.fetch).mockReset();
  });

  it('offers the shared app first and your own app as a choice', async () => {
    const user = userEvent.setup();
    renderModal();

    expect(screen.getByLabelText(/Azure organization/)).toBeInTheDocument();
    expect(screen.queryByLabelText('Subject identifier')).not.toBeInTheDocument();

    await useOwnApp(user);

    expect(screen.getByLabelText('Subject identifier')).toHaveValue(FEDERATION.subject);
  });

  it('shows exactly what to enter in the federated credential', async () => {
    const user = userEvent.setup();
    renderModal();
    await useOwnApp(user);

    expect(screen.getByLabelText('Issuer')).toHaveValue(FEDERATION.issuerUrl);
    expect(screen.getByLabelText('Subject identifier')).toHaveValue(FEDERATION.subject);
    expect(screen.getByLabelText('Audience')).toHaveValue(FEDERATION.audience);
    expect(screen.getByText(/case-sensitive/)).toBeInTheDocument();
  });

  it('goes straight to your own app where the deployment has no shared one', () => {
    renderModal({ sharedAppEnabled: false });

    expect(screen.getByLabelText('Subject identifier')).toBeInTheDocument();
    expect(screen.queryByText('Aixle’s Microsoft app')).not.toBeInTheDocument();
  });

  it('offers no choice where the deployment cannot act as an issuer', () => {
    renderModal({ federation: null });

    expect(screen.queryByText('Your own Entra app')).not.toBeInTheDocument();
  });

  it('will not look for a script until the client id is a GUID', async () => {
    const user = userEvent.setup();
    renderModal();
    await useOwnApp(user);

    await user.type(screen.getByLabelText(/Azure organization/), 'contoso');
    await user.type(screen.getByLabelText(/Application \(client\) ID/), 'nope');

    expect(screen.getByText('Must be a GUID')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Show setup script' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Verify access' })).toBeDisabled();
  });

  it('shows the setup script for the chosen permissions and warns about pipelines', async () => {
    const user = userEvent.setup();
    const calls: Record<string, unknown>[] = [];
    mockFetch((url, body) => {
      calls.push({ url, body });
      return { payload: { script: '#!/usr/bin/env bash\necho setup' } };
    });
    renderModal();
    await useOwnApp(user);
    await fillIdentity(user);
    await user.click(screen.getByRole('radio', { name: /Only what Aixle needs/ }));
    await user.click(screen.getByRole('button', { name: 'Show setup script' }));

    expect(await screen.findByText(/echo setup/)).toBeInTheDocument();
    expect(calls[0]).toMatchObject({
      url: `${BASE}/azure_devops_federated_script`,
      body: { organization: 'contoso', client_id: CLIENT_ID, flavor: 'custom', service_hooks: true },
    });
    expect(screen.getByText(/start your pipelines/)).toBeInTheDocument();
  });

  it('lists the projects the app can see once access is verified', async () => {
    const user = userEvent.setup();
    mockFetch(() => ({ payload: inspectionPayload() }));
    renderModal();
    await useOwnApp(user);
    await fillIdentity(user);
    await verify(user);

    expect(screen.getByRole('button', { name: 'Connect' })).toBeDisabled();
    await pickProject(user);
  });

  it('reports why Entra refused, in the words the server gave', async () => {
    const user = userEvent.setup();
    mockFetch(() => ({
      ok: false,
      payload: { error: 'federation_rejected', message: 'No federated credential matches' },
    }));
    renderModal();
    await useOwnApp(user);
    await fillIdentity(user);
    await user.click(screen.getByRole('button', { name: 'Verify access' }));

    expect(await screen.findByText('No federated credential matches')).toBeInTheDocument();
    expect(router.post).not.toHaveBeenCalled();
  });

  it('shows the permissions it found and will not connect while a required one is missing', async () => {
    const user = userEvent.setup();
    mockFetch((_url, body) => ({
      payload: inspectionPayload({ permissions: body.project_ids ? permissions('missing') : null }),
    }));
    renderModal();
    await useOwnApp(user);
    await fillIdentity(user);
    await verify(user);
    await pickProject(user);

    expect(await screen.findByText('Permissions are missing')).toBeInTheDocument();
    expect(screen.getByText(/Repos: Contribute/)).toBeInTheDocument();
    expect(
      screen.getByText(/Service Hooks: Edit subscriptions \(optional\) — could not be checked/),
    ).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Connect' })).toBeDisabled();
  });

  it('binds the organization and creates the connection for the chosen projects', async () => {
    const user = userEvent.setup();
    const calls: Record<string, unknown>[] = [];
    mockFetch((url, body) => {
      calls.push({ url, body });
      if (url.endsWith('azure_devops_federated_connect'))
        return { payload: { installationId: 7, organization: 'contoso' } };
      return { payload: inspectionPayload({ permissions: body.project_ids ? permissions('granted') : null }) };
    });
    renderModal();
    await useOwnApp(user);
    await fillIdentity(user);
    await verify(user);
    await pickProject(user);
    await waitFor(() => expect(screen.getByRole('button', { name: 'Connect' })).toBeEnabled());
    await user.click(screen.getByRole('button', { name: 'Connect' }));

    await waitFor(() => expect(router.post).toHaveBeenCalled());
    expect(calls.at(-1)).toMatchObject({
      url: `${BASE}/azure_devops_federated_connect`,
      body: { organization: 'contoso', client_id: CLIENT_ID, project_ids: [PROJECT_ID] },
    });
    const [path, payload] = vi.mocked(router.post).mock.calls[0];
    expect(path).toBe(BASE);
    expect(payload).toMatchObject({
      provider: 'azure_devops',
      authMode: 'service_principal',
      azureDevopsInstallationId: '7',
      azureProjectIds: [PROJECT_ID],
      azureProjectNames: { [PROJECT_ID]: 'Customer Platform' },
    });
  });

  it('asks before closing over what was typed', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    renderModal({}, onClose);
    await useOwnApp(user);

    await user.type(screen.getByLabelText(/Azure organization/), 'contoso');
    await user.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(await screen.findByRole('dialog', { name: 'Discard unsaved changes?' })).toBeInTheDocument();
    expect(onClose).not.toHaveBeenCalled();
  });
});
