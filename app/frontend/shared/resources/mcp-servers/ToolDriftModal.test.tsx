import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import McpServersPage from 'pages/Projects/McpServers/McpServersPage';

import type { McpServer } from './McpServersContent';

// Drift surfacing is exercised through the real MCP servers page: the point of
// the feature is that someone scanning their server list notices, so testing
// the modal in isolation would skip the part that matters.

const server = (overrides: Partial<McpServer> = {}): McpServer => ({
  id: 5,
  name: 'Linear',
  url: 'https://mcp.linear.app/mcp',
  transport: 'http',
  headers: null,
  description: null,
  kind: 'custom',
  scopeType: 'Project',
  scopeId: 9,
  scopeIndicator: 'project',
  enabled: true,
  internal: false,
  command: null,
  env: null,
  connectorName: 'app.linear/linear',
  connectorStatus: 'active',
  connectorVersion: '1.0.0',
  connectorVersionPinned: true,
  connectorUpdateVersion: null,
  toolBaseline: true,
  toolDrift: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

const pageProps = (mcpServers: McpServer[]) => ({
  project: { id: 7, name: 'Polaris' },
  mcpServers,
  configItemNames: [],
  connectors: [],
  connectorQuery: '',
  catalogSyncedAt: null,
});

const render = (servers: McpServer[]) => renderAuthedPage(<McpServersPage />, { props: pageProps(servers) });

describe('MCP server tool drift', () => {
  it('stays silent when nothing changed', () => {
    render([server()]);

    expect(screen.queryByRole('button', { name: 'Review' })).not.toBeInTheDocument();
  });

  it('names the server that changed', () => {
    render([server({ toolDrift: { changed: ['search'] } })]);

    expect(screen.getByText('Linear changed the tools it offers')).toBeInTheDocument();
  });

  it('counts servers when more than one changed', () => {
    render([
      server({ id: 1, name: 'Linear', toolDrift: { changed: ['search'] } }),
      server({ id: 2, name: 'Sentry', toolDrift: { added: ['run'] } }),
    ]);

    expect(screen.getByText('2 servers changed the tools they offer')).toBeInTheDocument();
  });

  it('explains why a tool description change matters', () => {
    render([server({ toolDrift: { changed: ['search'] } })]);

    expect(screen.getByText(/instructions the agent reads/)).toBeInTheDocument();
  });

  it('opens the review from the summary and lists what changed', async () => {
    render([server({ toolDrift: { changed: ['search'], added: ['run_shell'], removed: ['create'] } })]);

    await userEvent.click(screen.getByRole('button', { name: 'Review' }));
    const dialog = await screen.findByRole('dialog');

    expect(within(dialog).getByText('Changed')).toBeInTheDocument();
    expect(within(dialog).getByText('search')).toBeInTheDocument();
    expect(within(dialog).getByText('run_shell')).toBeInTheDocument();
    expect(within(dialog).getByText('create')).toBeInTheDocument();
  });

  it('omits sections with nothing in them', async () => {
    render([server({ toolDrift: { changed: ['search'] } })]);

    await userEvent.click(screen.getByRole('button', { name: 'Review' }));
    const dialog = await screen.findByRole('dialog');

    expect(within(dialog).queryByText('Added')).not.toBeInTheDocument();
    expect(within(dialog).queryByText('Removed')).not.toBeInTheDocument();
  });

  it('accepts the change as the new baseline only on an explicit action', async () => {
    const post = vi.spyOn(router, 'post').mockImplementation(() => undefined);
    render([server({ toolDrift: { changed: ['search'] } })]);

    await userEvent.click(screen.getByRole('button', { name: 'Review' }));
    const dialog = await screen.findByRole('dialog');

    expect(post).not.toHaveBeenCalled();

    await userEvent.click(within(dialog).getByRole('button', { name: 'Accept these changes' }));

    expect(post).toHaveBeenCalledWith('/company/projects/7/mcp_servers/5/accept_tool_drift', {}, expect.anything());
  });

  it('offers a way out that changes nothing', async () => {
    const post = vi.spyOn(router, 'post').mockImplementation(() => undefined);
    render([server({ toolDrift: { changed: ['search'] } })]);

    await userEvent.click(screen.getByRole('button', { name: 'Review' }));
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Leave for now' }));

    expect(post).not.toHaveBeenCalled();
  });

  it('opens the review from the row indicator, by keyboard as well as pointer', async () => {
    render([server({ toolDrift: { changed: ['search'] } })]);

    const indicator = screen.getByRole('button', { name: /Tools changed/ });
    indicator.focus();
    await userEvent.keyboard('{Enter}');

    expect(await screen.findByRole('dialog')).toBeInTheDocument();
  });

  it('offers an update from the row and applies it only on an explicit action', async () => {
    const post = vi.spyOn(router, 'post').mockImplementation(() => undefined);
    render([server({ connectorUpdateVersion: '2.1.0' })]);

    await userEvent.click(screen.getByRole('button', { name: /Update available/ }));
    const dialog = await screen.findByRole('dialog');

    expect(within(dialog).getByText('1.0.0')).toBeInTheDocument();
    expect(within(dialog).getByText('2.1.0')).toBeInTheDocument();
    expect(post).not.toHaveBeenCalled();

    await userEvent.click(within(dialog).getByRole('button', { name: 'Update' }));

    expect(post).toHaveBeenCalledWith('/company/projects/7/mcp_servers/5/update_connector', {}, expect.anything());
  });

  it('describes each health condition in text, not colour alone', () => {
    render([
      server({ connectorStatus: 'deleted' }),
      server({ id: 6, name: 'Filesystem', transport: 'stdio', url: null, toolBaseline: false }),
      server({ id: 7, name: 'Notion', connectorVersionPinned: false }),
    ]);

    expect(screen.getByLabelText(/Removed from registry/)).toBeInTheDocument();
    expect(screen.getByLabelText(/Not checked/)).toBeInTheDocument();
    expect(screen.getByLabelText(/Version not pinned/)).toBeInTheDocument();
  });
});
