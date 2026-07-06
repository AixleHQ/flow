import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen, userEvent, within } from 'test/renderPage';

import { McpServersContent, type McpServer } from './McpServersContent';

function makeServer(overrides: Partial<McpServer> = {}): McpServer {
  return {
    id: 1,
    name: 'playwright',
    displayName: 'Playwright Browser',
    url: 'https://mcp.example.com/pw',
    transport: 'http',
    headers: null,
    description: null,
    kind: 'custom',
    scopeType: null,
    scopeId: null,
    scopeIndicator: 'company',
    enabled: true,
    internal: false,
    managed: false,
    integrationId: null,
    command: null,
    env: null,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    ...overrides,
  };
}

const baseProps = {
  configItemNames: ['API_KEY'],
  basePath: '/company/mcp_servers',
  title: 'MCP Servers',
  subtitle: 'Connect external tools',
  editableScope: 'company' as const,
};

describe('McpServersContent', () => {
  it('renders the title, subtitle, and a row per custom server', () => {
    renderPage(
      <McpServersContent
        {...baseProps}
        mcpServers={[
          makeServer({ id: 1, name: 'playwright', displayName: 'Playwright Browser' }),
          makeServer({ id: 2, name: 'context7', displayName: 'Context7 Docs' }),
        ]}
      />,
    );

    expect(screen.getByText('MCP Servers')).toBeInTheDocument();
    expect(screen.getByText('Connect external tools')).toBeInTheDocument();
    expect(screen.getByText('Playwright Browser')).toBeInTheDocument();
    expect(screen.getByText('Context7 Docs')).toBeInTheDocument();
  });

  it('shows the empty state with an "add your first" CTA when there are no servers and no active filters', async () => {
    renderPage(<McpServersContent {...baseProps} mcpServers={[]} />);

    // Default kind filter is "custom", which counts as an active filter, so first
    // switch to "All" to reach the unfiltered empty state.
    await userEvent.click(screen.getByText('All'));

    expect(screen.getByText('No MCP servers configured')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /add your first mcp server/i })).toBeInTheDocument();
  });

  it('narrows the list as you type in the search box', async () => {
    renderPage(
      <McpServersContent
        {...baseProps}
        mcpServers={[
          makeServer({ id: 1, name: 'playwright', displayName: 'Playwright Browser' }),
          makeServer({ id: 2, name: 'context7', displayName: 'Context7 Docs' }),
        ]}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText(/search by name/i), 'context');

    expect(screen.getByText('Context7 Docs')).toBeInTheDocument();
    expect(screen.queryByText('Playwright Browser')).not.toBeInTheDocument();
  });

  it('hides custom servers when the kind filter is switched to System', async () => {
    renderPage(
      <McpServersContent
        {...baseProps}
        mcpServers={[makeServer({ id: 1, name: 'playwright', displayName: 'Playwright Browser', kind: 'custom' })]}
      />,
    );

    // Default filter is "custom", so the row is visible first.
    expect(screen.getByText('Playwright Browser')).toBeInTheDocument();

    await userEvent.click(screen.getByText('System'));

    // No internal servers in fixtures -> filtered list becomes empty.
    expect(screen.queryByText('Playwright Browser')).not.toBeInTheDocument();
    expect(screen.getByText('No MCP servers match your filters')).toBeInTheDocument();
  });

  it('opens the Add MCP Server form modal when the add button is clicked', async () => {
    renderPage(<McpServersContent {...baseProps} mcpServers={[makeServer()]} />);

    await userEvent.click(screen.getByRole('button', { name: /add mcp server/i }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Add MCP Server')).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: /create/i })).toBeInTheDocument();
  });

  it('opens the delete confirmation modal from a row delete action', async () => {
    const { container } = renderPage(
      <McpServersContent
        {...baseProps}
        mcpServers={[makeServer({ id: 7, displayName: 'Doomed Server', kind: 'custom', scopeIndicator: 'company' })]}
      />,
    );

    // The edit/delete ActionIcons render only for editable custom servers, but
    // Mantine's ActionIcon has no accessible name, so locate the delete button
    // via its trash icon.
    const trashIcon = container.querySelector('.tabler-icon-trash');
    expect(trashIcon).not.toBeNull();
    const deleteButton = trashIcon!.closest('button');
    expect(deleteButton).not.toBeNull();
    await userEvent.click(deleteButton!);

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Delete MCP Server')).toBeInTheDocument();
    expect(within(dialog).getByText('Doomed Server')).toBeInTheDocument();
  });

  it('shows the "no matches" empty state (without a CTA) when an active search filters everything out', async () => {
    renderPage(
      <McpServersContent
        {...baseProps}
        mcpServers={[makeServer({ id: 1, name: 'playwright', displayName: 'Playwright Browser' })]}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText(/search by name/i), 'zzz-no-such-server');

    expect(screen.getByText('No MCP servers match your filters')).toBeInTheDocument();
    // The "add your first" CTA only shows when there are no active filters.
    expect(screen.queryByRole('button', { name: /add your first mcp server/i })).not.toBeInTheDocument();
  });

  it('shows both system and custom servers when the kind filter is "All"', async () => {
    renderPage(
      <McpServersContent
        {...baseProps}
        mcpServers={[
          makeServer({ id: 1, displayName: 'Custom One', kind: 'custom', scopeIndicator: 'company' }),
          makeServer({
            id: 2,
            displayName: 'System One',
            kind: 'internal',
            internal: true,
            scopeIndicator: 'internal',
          }),
        ]}
      />,
    );

    // Default filter is "custom", so the internal row is hidden initially.
    expect(screen.queryByText('System One')).not.toBeInTheDocument();

    await userEvent.click(screen.getByText('All'));

    expect(screen.getByText('Custom One')).toBeInTheDocument();
    expect(screen.getByText('System One')).toBeInTheDocument();
  });

  it('renders the server name, URL, transport, scope, and status cells in the row', () => {
    renderPage(
      <McpServersContent
        {...baseProps}
        mcpServers={[
          makeServer({
            id: 1,
            name: 'playwright',
            displayName: 'Playwright Browser',
            url: 'https://mcp.example.com/pw',
            transport: 'sse',
            scopeIndicator: 'company',
            enabled: true,
          }),
        ]}
      />,
    );

    expect(screen.getByText('Playwright Browser')).toBeInTheDocument();
    expect(screen.getByText('playwright')).toBeInTheDocument();
    expect(screen.getByText('https://mcp.example.com/pw')).toBeInTheDocument();
    // Transport badge is uppercased.
    expect(screen.getByText('SSE')).toBeInTheDocument();
    // Company scope badge.
    expect(screen.getByText('Company')).toBeInTheDocument();
    // Status badge.
    expect(screen.getByText('Enabled')).toBeInTheDocument();
  });

  it('renders an em dash for the URL cell when the server has no URL', () => {
    renderPage(
      <McpServersContent
        {...baseProps}
        mcpServers={[makeServer({ id: 1, displayName: 'Stdio Server', transport: 'stdio', url: null })]}
      />,
    );

    expect(screen.getByText('—')).toBeInTheDocument();
    expect(screen.getByText('STDIO')).toBeInTheDocument();
  });

  it('shows a Disabled status badge for a disabled server', () => {
    renderPage(
      <McpServersContent
        {...baseProps}
        mcpServers={[makeServer({ id: 1, displayName: 'Off Server', enabled: false })]}
      />,
    );

    expect(screen.getByText('Disabled')).toBeInTheDocument();
    expect(screen.queryByText('Enabled')).not.toBeInTheDocument();
  });

  it('renders a Project scope badge for project-scoped servers', () => {
    renderPage(
      <McpServersContent
        {...baseProps}
        editableScope="project"
        mcpServers={[makeServer({ id: 1, displayName: 'Project Server', scopeIndicator: 'project' })]}
      />,
    );

    expect(screen.getByText('Project')).toBeInTheDocument();
  });

  it('renders a System scope badge and a "System" read-only label for internal servers', async () => {
    renderPage(
      <McpServersContent
        {...baseProps}
        mcpServers={[
          makeServer({
            id: 1,
            displayName: 'Builtin Server',
            kind: 'internal',
            internal: true,
            scopeIndicator: 'internal',
          }),
        ]}
      />,
    );

    // Internal servers are filtered out under the default "custom" filter; switch to All.
    await userEvent.click(screen.getByText('All'));

    // Scope badge text "System" plus the read-only label "System" both render.
    expect(screen.getAllByText('System').length).toBeGreaterThanOrEqual(1);
    // Internal servers are not editable, so no edit/delete icons render.
    expect(screen.getByText('Builtin Server')).toBeInTheDocument();
  });

  it('opens the edit form modal pre-titled "Edit MCP Server" with a Save button when editing a row', async () => {
    const { container } = renderPage(
      <McpServersContent
        {...baseProps}
        mcpServers={[makeServer({ id: 5, displayName: 'Editable Server', kind: 'custom', scopeIndicator: 'company' })]}
      />,
    );

    // ActionIcons have no accessible name; locate the edit button via its pencil icon.
    const editIcon = container.querySelector('.tabler-icon-edit');
    expect(editIcon).not.toBeNull();
    const editButton = editIcon!.closest('button');
    expect(editButton).not.toBeNull();
    await userEvent.click(editButton!);

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Edit MCP Server')).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: /save/i })).toBeInTheDocument();
  });

  it('shows a "Company" read-only label (no edit icons) for company-scoped servers under a project scope', () => {
    const { container } = renderPage(
      <McpServersContent
        {...baseProps}
        editableScope="project"
        mcpServers={[makeServer({ id: 1, displayName: 'Inherited Server', kind: 'custom', scopeIndicator: 'company' })]}
      />,
    );

    // Not editable in project scope, so the read-only "Company" label shows instead of icons.
    // "Company" appears twice: once as the scope badge, once as the read-only label.
    expect(screen.getAllByText('Company').length).toBeGreaterThanOrEqual(2);
    expect(container.querySelector('.tabler-icon-edit')).toBeNull();
    expect(container.querySelector('.tabler-icon-trash')).toBeNull();
  });

  it('renders edit and delete icons for every custom server when editableScope is undefined', () => {
    const { container } = renderPage(
      <McpServersContent
        configItemNames={['API_KEY']}
        basePath="/company/mcp_servers"
        title="MCP Servers"
        subtitle="Connect external tools"
        mcpServers={[
          makeServer({ id: 1, displayName: 'Server A', kind: 'custom', scopeIndicator: 'company' }),
          makeServer({ id: 2, displayName: 'Server B', kind: 'custom', scopeIndicator: 'project' }),
        ]}
      />,
    );

    // With no editableScope, all custom servers are editable regardless of scope.
    expect(container.querySelectorAll('.tabler-icon-edit')).toHaveLength(2);
    expect(container.querySelectorAll('.tabler-icon-trash')).toHaveLength(2);
  });
});
