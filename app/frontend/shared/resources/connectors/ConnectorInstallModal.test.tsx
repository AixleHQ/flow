import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import type { Connector } from '@/types/generated';
import { renderPage, screen, userEvent, within } from 'test/renderPage';

import { ConnectorInstallModal } from './ConnectorInstallModal';
import type { ConnectorInput, ConnectorTarget } from './types';

const input = (overrides: Partial<ConnectorInput> = {}): ConnectorInput => ({
  key: 'API_TOKEN',
  kind: 'env',
  description: 'Personal access token',
  format: 'string',
  required: true,
  secret: true,
  default: null,
  choices: null,
  placeholder: null,
  repeated: false,
  ...overrides,
});

const target = (overrides: Partial<ConnectorTarget> = {}): ConnectorTarget => ({
  id: 'package:stdio:npm:@acme/mcp',
  kind: 'package',
  transport: 'stdio',
  supported: true,
  unsupportedReason: null,
  url: null,
  registryType: 'npm',
  identifier: '@acme/mcp',
  command: 'npx @acme/mcp@1.2.3',
  version: '1.2.3',
  versionPinned: true,
  runtime: 'npx',
  runtimePrefixArgs: [],
  inputs: [input()],
  ...overrides,
});

const connector = (overrides: Partial<Connector> = {}): Connector => ({
  id: 1,
  name: 'io.github.acme/mcp',
  title: 'Acme',
  pickerName: 'Acme',
  iconUrl: null,
  vendorPublished: false,
  description: 'Manage issues and bug tracking',
  version: '1.2.3',
  repositoryUrl: null,
  status: 'active',
  installable: true,
  targets: [target()],
  registryUpdatedAt: '2026-07-30T00:00:00Z',
  createdAt: '2026-07-30T00:00:00Z',
  updatedAt: '2026-07-30T00:00:00Z',
  ...overrides,
});

const withPortDefault = () =>
  connector({
    targets: [target({ inputs: [input({ key: 'PORT', secret: false, required: false, default: '8089' })] })],
  });

const renderInstall = (subject: Connector, onClose: () => void) =>
  renderPage(
    <ConnectorInstallModal
      connector={subject}
      basePath="/company/projects/7/connectors"
      onClose={onClose}
      configItemNames={[]}
    />,
  );

const installDrawer = () => screen.getByRole('dialog', { name: 'Install · Acme' });

describe('ConnectorInstallModal', () => {
  it('asks before closing over a typed value, and closes on Discard', async () => {
    const onClose = vi.fn();
    renderInstall(connector(), onClose);

    await userEvent.type(screen.getByLabelText(/API_TOKEN/), 'tok_123');
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    const discard = await screen.findByRole('dialog', { name: 'Discard unsaved changes?' });
    expect(onClose).not.toHaveBeenCalled();
    expect(installDrawer()).toBeInTheDocument();

    await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('closes without asking while the form still holds only its declared defaults', async () => {
    const onClose = vi.fn();
    renderInstall(withPortDefault(), onClose);

    expect(screen.getByLabelText(/PORT/)).toHaveValue('8089');
    await userEvent.click(within(installDrawer()).getByRole('button', { name: 'Clear' }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });

  it('treats a changed default as unsaved input', async () => {
    const onClose = vi.fn();
    renderInstall(withPortDefault(), onClose);

    await userEvent.clear(screen.getByLabelText(/PORT/));
    await userEvent.type(screen.getByLabelText(/PORT/), '9000');
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(await screen.findByRole('dialog', { name: 'Discard unsaved changes?' })).toBeInTheDocument();
    expect(onClose).not.toHaveBeenCalled();
  });

  it('closes without asking after only another install option was picked', async () => {
    const onClose = vi.fn();
    renderInstall(
      connector({
        targets: [
          target(),
          target({ id: 'remote:http:https://mcp.acme.com/mcp', kind: 'remote', transport: 'http', inputs: [] }),
        ],
      }),
      onClose,
    );

    await userEvent.click(screen.getByRole('radio', { name: /Hosted endpoint/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(onClose).toHaveBeenCalledTimes(1);
  });
});
