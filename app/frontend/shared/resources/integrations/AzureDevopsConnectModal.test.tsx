import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import type { AzureDevopsProps } from './AzureDevopsConnectModal';
import { AzureDevopsConnectModal } from './AzureDevopsConnectModal';

const PROJECT_ID = '11111111-1111-1111-1111-111111111111';
const SECOND_PROJECT_ID = '33333333-3333-3333-3333-333333333333';
const BASE = '/company/projects/1/integrations';

const renderModal = (props: Partial<AzureDevopsProps> = {}) =>
  renderPage(
    <AzureDevopsConnectModal
      opened
      onClose={() => {}}
      basePath={BASE}
      azureDevops={{ enabled: true, patModeEnabled: false, ...props }}
    />,
  );

// The two onboarding endpoints answer JSON rather than an Inertia redirect, so
// they go through `fetch` — which setup.ts already stubs inertly.
const mockFetch = (handler: (url: string, body: Record<string, unknown>) => { ok?: boolean; payload: unknown }) =>
  vi.mocked(globalThis.fetch).mockImplementation((async (url: string, init: RequestInit) => {
    const body = JSON.parse(String(init.body));
    const { ok = true, payload } = handler(String(url), body);
    return { ok, json: async () => payload } as Response;
  }) as typeof globalThis.fetch);

const inspectionPayload = (overrides: Record<string, unknown> = {}) => ({
  organization: 'contoso',
  tenantId: '22222222-2222-2222-2222-222222222222',
  identity: 'ada@contoso.com',
  alreadyBound: false,
  projects: [
    { id: PROJECT_ID, name: 'Customer Platform' },
    { id: SECOND_PROJECT_ID, name: 'Payments' },
  ],
  ...overrides,
});

// The project picker is a Mantine MultiSelect: the input opens the dropdown and
// each option is picked by its visible name.
const pickProjects = async (user: ReturnType<typeof userEvent.setup>, names: string[]) => {
  for (const name of names) {
    await user.click(screen.getByRole('combobox', { name: /Azure projects/ }));
    await user.click(await screen.findByRole('option', { name }));
  }
};

describe('AzureDevopsConnectModal', () => {
  beforeEach(() => {
    vi.mocked(router.post).mockClear();
  });

  afterEach(() => {
    vi.mocked(globalThis.fetch).mockReset();
  });

  it('asks for the organization by name and never lists which ones the company holds', () => {
    renderModal();

    expect(screen.getByLabelText(/Azure organization/)).toBeInTheDocument();
    // No dropdown: what is not listed cannot be browsed by a project member.
    expect(screen.queryByRole('combobox', { name: /Azure organization/i })).not.toBeInTheDocument();
  });

  it('verifies the organization with an administrator token and then offers its projects', async () => {
    const user = userEvent.setup();
    const calls: Record<string, unknown>[] = [];
    mockFetch((url, body) => {
      calls.push({ url, body });
      return { payload: inspectionPayload() };
    });
    renderModal();

    await user.type(screen.getByLabelText(/Azure organization/), 'contoso');
    await user.type(screen.getByLabelText(/Administrator personal access token/), 'pat-123');
    await user.click(screen.getByRole('button', { name: 'Verify organization' }));

    expect(await screen.findByText('Organization verified')).toBeInTheDocument();
    expect(screen.getByText(/Verified as ada@contoso.com/)).toBeInTheDocument();
    expect(calls[0]).toMatchObject({
      url: `${BASE}/azure_devops_inspect`,
      body: { organization: 'contoso', personal_access_token: 'pat-123' },
    });
  });

  it('says when no token was needed because the company already holds the organization', async () => {
    const user = userEvent.setup();
    mockFetch(() => ({ payload: inspectionPayload({ alreadyBound: true, identity: null }) }));
    renderModal();

    await user.type(screen.getByLabelText(/Azure organization/), 'contoso');
    await user.click(screen.getByRole('button', { name: 'Verify organization' }));

    expect(await screen.findByText(/already connected this organization, so no token was needed/)).toBeInTheDocument();
  });

  it('preselects nothing — a connection reaches what someone chose', async () => {
    const user = userEvent.setup();
    mockFetch(() => ({ payload: inspectionPayload() }));
    renderModal();

    await user.type(screen.getByLabelText(/Azure organization/), 'contoso');
    await user.type(screen.getByLabelText(/Administrator personal access token/), 'pat-123');
    await user.click(screen.getByRole('button', { name: 'Verify organization' }));
    await screen.findByText('Organization verified');

    expect(screen.getByRole('button', { name: 'Connect' })).toBeDisabled();
  });

  it('binds the organization and then creates the connection for the chosen projects', async () => {
    const user = userEvent.setup();
    mockFetch((url) =>
      url.endsWith('azure_devops_inspect')
        ? { payload: inspectionPayload() }
        : { payload: { installationId: 7, organization: 'contoso' } },
    );
    renderModal();

    await user.type(screen.getByLabelText(/Azure organization/), 'contoso');
    await user.type(screen.getByLabelText(/Administrator personal access token/), 'pat-123');
    await user.click(screen.getByRole('button', { name: 'Verify organization' }));
    await screen.findByText('Organization verified');
    await pickProjects(user, ['Customer Platform', 'Payments']);
    await user.click(screen.getByRole('button', { name: 'Connect' }));

    await waitFor(() => expect(router.post).toHaveBeenCalled());
    const [path, payload] = vi.mocked(router.post).mock.calls[0];
    expect(path).toBe(BASE);
    expect(payload).toMatchObject({
      provider: 'azure_devops',
      authMode: 'service_principal',
      azureDevopsInstallationId: '7',
      azureProjectIds: [PROJECT_ID, SECOND_PROJECT_ID],
    });
    // Names travel for display only; the server intersects them with the ids
    // it actually approved.
    expect((payload as Record<string, Record<string, string>>).azureProjectNames).toEqual({
      [PROJECT_ID]: 'Customer Platform',
      [SECOND_PROJECT_ID]: 'Payments',
    });
  });

  it('reports a verification failure without creating anything', async () => {
    const user = userEvent.setup();
    mockFetch(() => ({ ok: false, payload: { error: 'not_authorized', message: 'That token cannot administer it' } }));
    renderModal();

    await user.type(screen.getByLabelText(/Azure organization/), 'contoso');
    await user.type(screen.getByLabelText(/Administrator personal access token/), 'nope');
    await user.click(screen.getByRole('button', { name: 'Verify organization' }));

    expect(await screen.findByText('That token cannot administer it')).toBeInTheDocument();
    expect(router.post).not.toHaveBeenCalled();
  });

  // The one failure whose fix is in a different system entirely, so it gets its
  // own explanation rather than a bare provider message.
  it('explains the Entra step when the application is not in the directory yet', async () => {
    const user = userEvent.setup();
    mockFetch(() => ({
      ok: false,
      payload: {
        error: 'not_authorized',
        message: 'The client application is missing a service principal in the tenant',
      },
    }));
    renderModal();

    await user.type(screen.getByLabelText(/Azure organization/), 'contoso');
    await user.type(screen.getByLabelText(/Administrator personal access token/), 'pat-123');
    await user.click(screen.getByRole('button', { name: 'Verify organization' }));

    expect(await screen.findByText(/az ad sp create/)).toBeInTheDocument();
  });

  it('unticking a capability removes it from the submitted profile', async () => {
    const user = userEvent.setup();
    mockFetch((url) =>
      url.endsWith('azure_devops_inspect') ? { payload: inspectionPayload() } : { payload: { installationId: 7 } },
    );
    renderModal();

    await user.type(screen.getByLabelText(/Azure organization/), 'contoso');
    await user.type(screen.getByLabelText(/Administrator personal access token/), 'pat-123');
    await user.click(screen.getByRole('button', { name: 'Verify organization' }));
    await screen.findByText('Organization verified');
    await pickProjects(user, ['Customer Platform']);
    await user.click(screen.getByRole('checkbox', { name: /Edit work items/ }));
    await user.click(screen.getByRole('button', { name: 'Connect' }));

    await waitFor(() => expect(router.post).toHaveBeenCalled());
    const payload = vi.mocked(router.post).mock.calls[0][1] as Record<string, string[]>;
    expect(payload.enabledCapabilities).not.toContain('work_items.write');
    expect(payload.enabledCapabilities).toContain('work_items.read');
  });

  it('offers the whole operation profile ticked, merging included', () => {
    renderModal();

    expect(screen.getByRole('checkbox', { name: /Complete pull requests/ })).toBeChecked();
    expect(screen.getByRole('checkbox', { name: /Read repositories/ })).toBeChecked();
  });

  // The one step that happens outside Flow, in another portal, usually by
  // another person. Learning about it from a failed verification means going
  // away and coming back, so the command is on screen before anything is typed
  // — with this deployment's own client id, which documentation cannot carry
  // because it differs between the hosted deployment and every self-hosted one.
  it('shows the directory step with this deployment’s client id, before verifying', () => {
    renderModal({ clientId: 'a734e297-bc89-4c1e-81c7-e8697e671206' });

    expect(screen.getByText(/One step in your Entra directory first/)).toBeInTheDocument();
    expect(screen.getByText(/az ad sp create --id a734e297-bc89-4c1e-81c7-e8697e671206/)).toBeInTheDocument();
  });

  it('says nothing about a directory step when the deployment publishes no client id', () => {
    renderModal();

    expect(screen.queryByText(/One step in your Entra directory first/)).not.toBeInTheDocument();
  });

  it('offers no personal-access-token path while the deployment has it switched off', () => {
    renderModal();

    expect(screen.queryByRole('button', { name: /personal access token instead/i })).not.toBeInTheDocument();
  });

  it('says plainly that a personal access token acts as its owner', async () => {
    const user = userEvent.setup();
    renderModal({ patModeEnabled: true });

    await user.click(screen.getByRole('button', { name: /Use a personal access token instead/ }));

    expect(screen.getByText('This acts as you, not as Aixle')).toBeInTheDocument();
    expect(screen.getByLabelText(/Azure project ID/)).toBeInTheDocument();
  });
});
