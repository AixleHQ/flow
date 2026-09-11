import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import type { AzureDevopsProps } from './AzureDevopsConnectModal';
import { AzureDevopsConnectModal } from './AzureDevopsConnectModal';

const PROJECT_ID = '11111111-1111-1111-1111-111111111111';

const azureDevops = (overrides: Partial<AzureDevopsProps> = {}): AzureDevopsProps => ({
  enabled: true,
  patModeEnabled: false,
  installations: [
    {
      id: 7,
      organizationSlug: 'contoso',
      tenantId: '22222222-2222-2222-2222-222222222222',
      status: 'active',
      projects: [{ id: PROJECT_ID, name: 'Customer Platform' }],
    },
  ],
  ...overrides,
});

const renderModal = (props: Partial<AzureDevopsProps> = {}) =>
  renderPage(
    <AzureDevopsConnectModal
      opened
      onClose={() => {}}
      basePath="/company/projects/1/integrations"
      azureDevops={azureDevops(props)}
    />,
  );

describe('AzureDevopsConnectModal', () => {
  beforeEach(() => {
    vi.mocked(router.post).mockClear();
  });

  it('explains that access is approved per organization when the company has none', () => {
    renderModal({ installations: [] });

    expect(screen.getByText('No approved organization yet')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Connect' })).toBeDisabled();
  });

  it('cannot submit until both an organization and one of its approved projects are chosen', async () => {
    const user = userEvent.setup();
    renderModal();

    const connect = screen.getByRole('button', { name: 'Connect' });
    expect(connect).toBeDisabled();

    await user.click(screen.getByRole('combobox', { name: /Azure organization/i }));
    await user.click(await screen.findByRole('option', { name: 'contoso' }));
    await user.click(screen.getByRole('combobox', { name: /Azure project/i }));
    await user.click(await screen.findByRole('option', { name: 'Customer Platform' }));

    await waitFor(() => expect(connect).toBeEnabled());
  });

  it('posts the installation and the project GUID, not the organization name', async () => {
    const user = userEvent.setup();
    renderModal();

    await user.click(screen.getByRole('combobox', { name: /Azure organization/i }));
    await user.click(await screen.findByRole('option', { name: 'contoso' }));
    await user.click(screen.getByRole('combobox', { name: /Azure project/i }));
    await user.click(await screen.findByRole('option', { name: 'Customer Platform' }));
    await user.click(screen.getByRole('button', { name: 'Connect' }));

    await waitFor(() => expect(router.post).toHaveBeenCalled());
    const [path, payload] = vi.mocked(router.post).mock.calls[0];
    expect(path).toBe('/company/projects/1/integrations');
    expect(payload).toMatchObject({
      provider: 'azure_devops',
      authMode: 'service_principal',
      azureDevopsInstallationId: '7',
      azureProjectId: PROJECT_ID,
    });
  });

  it('unticking a capability removes it from the submitted profile', async () => {
    const user = userEvent.setup();
    renderModal();

    await user.click(screen.getByRole('combobox', { name: /Azure organization/i }));
    await user.click(await screen.findByRole('option', { name: 'contoso' }));
    await user.click(screen.getByRole('combobox', { name: /Azure project/i }));
    await user.click(await screen.findByRole('option', { name: 'Customer Platform' }));
    await user.click(screen.getByRole('checkbox', { name: /Edit work items/ }));
    await user.click(screen.getByRole('button', { name: 'Connect' }));

    await waitFor(() => expect(router.post).toHaveBeenCalled());
    const payload = vi.mocked(router.post).mock.calls[0][1] as Record<string, string[]>;
    expect(payload.enabledCapabilities).not.toContain('work_items.write');
    expect(payload.enabledCapabilities).toContain('work_items.read');
  });

  it('offers no personal-access-token path while the deployment has it switched off', () => {
    renderModal();

    expect(screen.queryByRole('button', { name: /personal access token/i })).not.toBeInTheDocument();
  });

  it('says plainly that a personal access token acts as its owner', async () => {
    const user = userEvent.setup();
    renderModal({ patModeEnabled: true });

    await user.click(screen.getByRole('button', { name: /Use a personal access token instead/ }));

    expect(screen.getByText('This acts as you, not as Aixle')).toBeInTheDocument();
    expect(screen.getByLabelText(/Personal access token/)).toBeInTheDocument();
  });
});
