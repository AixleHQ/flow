import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import type { McpServer } from 'shared/resources/mcp-servers/McpServersContent';

import McpServersPage from './McpServersPage';

const server = (overrides: Partial<McpServer> = {}): McpServer => ({
  id: 1,
  name: 'playwright',
  displayName: 'Playwright Browser',
  url: 'https://mcp.example.com',
  transport: 'http',
  headers: null,
  description: null,
  kind: 'custom',
  scopeType: 'Project',
  scopeId: 42,
  scopeIndicator: 'project',
  enabled: true,
  internal: false,
  command: null,
  env: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

const project = { id: 7, name: 'Polaris' };

describe('Projects/McpServers/McpServersPage', () => {
  it('renders the heading and subtitle from seeded props', () => {
    renderAuthedPage(<McpServersPage />, {
      props: { project, mcpServers: [], configItemNames: [] },
    });

    expect(screen.getByText('Project MCP Servers')).toBeInTheDocument();
    expect(
      screen.getByText('Manage project-specific MCP servers. Company servers are read-only here.'),
    ).toBeInTheDocument();
  });

  it('shows the filtered empty state when no servers match the default Custom filter', () => {
    // The default kindFilter is "custom" (not "all"), so an empty list reads as a filtered
    // empty state and the inline "add your first" CTA is hidden.
    renderAuthedPage(<McpServersPage />, {
      props: { project, mcpServers: [], configItemNames: [] },
    });

    expect(screen.getByText('No MCP servers match your filters')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Add your first MCP server' })).not.toBeInTheDocument();
  });

  it('lists custom servers and filters them by the search query', async () => {
    renderAuthedPage(<McpServersPage />, {
      props: {
        project,
        mcpServers: [
          server({ id: 1, name: 'playwright', displayName: 'Playwright Browser' }),
          server({ id: 2, name: 'context7', displayName: 'Context7 Docs' }),
        ],
        configItemNames: [],
      },
    });

    expect(screen.getByText('Playwright Browser')).toBeInTheDocument();
    expect(screen.getByText('Context7 Docs')).toBeInTheDocument();

    await userEvent.type(screen.getByPlaceholderText('Search by name...'), 'context');

    expect(screen.queryByText('Playwright Browser')).not.toBeInTheDocument();
    expect(screen.getByText('Context7 Docs')).toBeInTheDocument();
  });

  it('opens the add-server form modal when the primary action is clicked', async () => {
    renderAuthedPage(<McpServersPage />, {
      props: { project, mcpServers: [], configItemNames: [] },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Add MCP Server' }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Add MCP Server')).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Create' })).toBeInTheDocument();
  });

  it('exposes edit controls for an editable project server', () => {
    renderAuthedPage(<McpServersPage />, {
      props: {
        project,
        mcpServers: [server({ id: 9, scopeIndicator: 'project', kind: 'custom' })],
        configItemNames: [],
      },
    });

    expect(screen.getByText('Playwright Browser')).toBeInTheDocument();
    // Edit/Delete action icons are rendered (they have accessible tooltips, not text labels),
    // so assert the row has interactive controls rather than a read-only label.
    expect(screen.queryByText('Read-only')).not.toBeInTheDocument();
    expect(screen.queryByText('Company')).not.toBeInTheDocument();
  });
});
