import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import McpServersPage from 'pages/Projects/McpServers/McpServersPage';

import type { Connector, ConnectorInput, ConnectorTarget } from './types';

// Exercised through the MCP servers page, because that is where the catalog
// lives: a connector is a pre-described MCP server, not a separate resource.

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
  iconUrl: 'https://github.com/acme.png?size=80',
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

const pageProps = (connectors: Connector[], connectorQuery = '') => ({
  project: { id: 7, name: 'Polaris' },
  mcpServers: [],
  configItemNames: ['LINEAR_TOKEN'],
  connectors,
  connectorQuery,
  catalogSyncedAt: '2026-08-01T10:00:00Z',
});

const openCatalog = async (connectors: Connector[], query = '') => {
  renderAuthedPage(<McpServersPage />, { props: pageProps(connectors, query) });
  await userEvent.click(screen.getByRole('button', { name: 'Browse connectors' }));
  return screen.findByRole('dialog');
};

const openInstall = async (connectors: Connector[]) => {
  const catalog = await openCatalog(connectors);
  await userEvent.click(within(catalog).getByRole('button', { name: 'Install' }));
  return screen.findByRole('dialog', { name: /Install/ });
};

describe('shared/resources/connectors/ConnectorCatalogModal', () => {
  it('offers the catalog alongside the manual add button', () => {
    renderAuthedPage(<McpServersPage />, { props: pageProps([connector()]) });

    expect(screen.getByRole('button', { name: 'Browse connectors' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add manually' })).toBeInTheDocument();
  });

  it('lists catalog entries with name and description', async () => {
    const catalog = await openCatalog([connector()]);

    expect(within(catalog).getByText('Acme')).toBeInTheDocument();
    expect(within(catalog).getByText('io.github.acme/mcp')).toBeInTheDocument();
    expect(within(catalog).getByText('Manage issues and bug tracking')).toBeInTheDocument();
  });

  it('explains an empty catalog and points at the manual path', async () => {
    const catalog = await openCatalog([]);

    expect(within(catalog).getByText('The catalog is empty')).toBeInTheDocument();
    expect(within(catalog).getByText(/add an MCP server by hand/)).toBeInTheDocument();
  });

  it('reports a search that matched nothing and offers a way back', async () => {
    const catalog = await openCatalog([], 'nothing');

    expect(within(catalog).getByText(/No connectors match/)).toBeInTheDocument();
    expect(within(catalog).getByRole('button', { name: 'Show suggested connectors' })).toBeInTheDocument();
  });

  it('marks a vendor-published connector so it is distinguishable from a lookalike', async () => {
    const catalog = await openCatalog([connector({ name: 'app.linear/linear', vendorPublished: true })]);

    expect(within(catalog).getByText('vendor')).toBeInTheDocument();
  });

  it('draws a monogram so a failed publisher icon leaves no hole', async () => {
    const catalog = await openCatalog([connector({ iconUrl: null, title: 'Acme Tracker' })]);

    expect(within(catalog).getByText('AT')).toBeInTheDocument();
  });

  it('labels the default view without claiming a measurement it may not have', async () => {
    const catalog = await openCatalog([connector()]);

    expect(within(catalog).getByText('Suggested connectors')).toBeInTheDocument();
  });

  it('searches server-side, because the registry API cannot match descriptions', async () => {
    const get = vi.spyOn(router, 'get').mockImplementation(() => undefined);
    const catalog = await openCatalog([connector()]);

    await userEvent.type(within(catalog).getByLabelText('Search connectors'), 'issue');

    await waitFor(() =>
      expect(get).toHaveBeenCalledWith(
        '/company/projects/7/mcp_servers',
        { connector_q: 'issue' },
        expect.objectContaining({ only: ['connectors', 'connector_query'] }),
      ),
    );
  });

  it('disables install for a connector with no runnable target', async () => {
    const catalog = await openCatalog([
      connector({
        installable: false,
        targets: [target({ supported: false, unsupportedReason: 'no known runtime for mcpb packages' })],
      }),
    ]);

    expect(within(catalog).getByRole('button', { name: 'Unavailable' })).toBeDisabled();
  });

  it('marks a deprecated connector', async () => {
    const catalog = await openCatalog([connector({ status: 'deprecated' })]);

    expect(within(catalog).getByText('deprecated')).toBeInTheDocument();
  });

  describe('install form', () => {
    it('is generated from the declared inputs', async () => {
      const modal = await openInstall([connector()]);

      expect(within(modal).getByLabelText(/API_TOKEN/)).toBeInTheDocument();
      expect(within(modal).getByText('Personal access token')).toBeInTheDocument();
    });

    it('warns that a package connector runs code in the agent container', async () => {
      const modal = await openInstall([connector()]);

      expect(within(modal).getByText(/Runs code inside your agent container/)).toBeInTheDocument();
    });

    it('warns when the package publishes no fixed version', async () => {
      const modal = await openInstall([
        connector({ targets: [target({ versionPinned: false, version: 'latest', command: 'npx @acme/mcp' })] }),
      ]);

      expect(within(modal).getByText(/no fixed version/)).toBeInTheDocument();
    });

    it('names the exact code it will run, so the warning is not vague', async () => {
      const modal = await openInstall([connector()]);

      expect(within(modal).getByText('npx @acme/mcp@1.2.3')).toBeInTheDocument();
    });

    it('confirms when the version is pinned instead of staying silent', async () => {
      const modal = await openInstall([connector()]);

      expect(within(modal).getByText(/cannot change underneath you/)).toBeInTheDocument();
    });

    it('does not warn about pinning when the version is pinned', async () => {
      const modal = await openInstall([connector()]);

      expect(within(modal).queryByText(/no fixed version/)).not.toBeInTheDocument();
    });

    it('keeps install disabled until required inputs are filled', async () => {
      const modal = await openInstall([connector()]);

      expect(within(modal).getByRole('button', { name: 'Install' })).toBeDisabled();

      await userEvent.type(within(modal).getByLabelText(/API_TOKEN/), 'tok_123');

      expect(within(modal).getByRole('button', { name: 'Install' })).toBeEnabled();
    });

    it('submits the target id and values to the install endpoint', async () => {
      const post = vi.spyOn(router, 'post').mockImplementation(() => undefined);
      const modal = await openInstall([connector()]);

      await userEvent.type(within(modal).getByLabelText(/API_TOKEN/), 'tok_123');
      await userEvent.click(within(modal).getByRole('button', { name: 'Install' }));

      expect(post).toHaveBeenCalledWith(
        '/company/projects/7/connectors',
        {
          connector_name: 'io.github.acme/mcp',
          target_id: 'package:stdio:npm:@acme/mcp',
          values: { API_TOKEN: 'tok_123' },
        },
        expect.anything(),
      );
    });

    it('offers project secrets instead of retyping a value that already exists', async () => {
      const modal = await openInstall([connector()]);

      // The field starts in plain-text mode; the toggle switches it to picking a
      // stored secret, the same affordance the manual MCP form has.
      await userEvent.click(within(modal).getByRole('button', { name: 'Use value from Secrets & Variables' }));

      expect(within(modal).getByPlaceholderText('Select config item...')).toBeInTheDocument();
    });

    it('pre-fills a declared default so the user can see and change it', async () => {
      const modal = await openInstall([
        connector({
          targets: [target({ inputs: [input({ key: 'PORT', secret: false, required: false, default: '8089' })] })],
        }),
      ]);

      expect(within(modal).getByLabelText(/PORT/)).toHaveValue('8089');
    });

    it('offers a choice when a connector has several install options', async () => {
      const modal = await openInstall([
        connector({
          targets: [
            target(),
            target({ id: 'remote:http:https://mcp.acme.com/mcp', kind: 'remote', transport: 'http', inputs: [] }),
          ],
        }),
      ]);

      expect(within(modal).getByText('Install option')).toBeInTheDocument();
      expect(within(modal).getByRole('radio', { name: /Hosted endpoint/ })).toBeInTheDocument();
    });
  });
});
