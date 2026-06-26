import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import type { McpServer } from 'shared/resources/mcp-servers/McpServersContent';

import McpServersIndex from './Index';

const server = (overrides: Partial<McpServer> = {}): McpServer => ({
  id: 1,
  name: 'tavily',
  displayName: 'Tavily Search',
  url: 'https://mcp.tavily.example',
  transport: 'http',
  headers: null,
  description: null,
  kind: 'custom',
  scopeType: 'Company',
  scopeId: 99,
  scopeIndicator: 'company',
  enabled: true,
  internal: false,
  command: null,
  env: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

describe('Company/McpServers/Index', () => {
  it('renders the company heading and subtitle from props', () => {
    renderAuthedPage(<McpServersIndex mcpServers={[]} configItemNames={[]} />);

    expect(screen.getByText('Company MCP Servers')).toBeInTheDocument();
    expect(
      screen.getByText(
        'Manage company-wide MCP servers. Configure external tools like Context7, Tavily, etc.',
      ),
    ).toBeInTheDocument();
  });

  it('shows the filtered empty state when no servers match the default Custom filter', () => {
    // Default kindFilter is "custom" (not "all"), so an empty list reads as a filtered
    // empty state and the inline "add your first" CTA is hidden.
    renderAuthedPage(<McpServersIndex mcpServers={[]} configItemNames={[]} />);

    expect(screen.getByText('No MCP servers match your filters')).toBeInTheDocument();
    expect(
      screen.queryByRole('button', { name: 'Add your first MCP server' }),
    ).not.toBeInTheDocument();
  });

  it('lists custom company servers and filters them by the search query', async () => {
    renderAuthedPage(
      <McpServersIndex
        mcpServers={[
          server({ id: 1, name: 'tavily', displayName: 'Tavily Search' }),
          server({ id: 2, name: 'context7', displayName: 'Context7 Docs' }),
        ]}
        configItemNames={[]}
      />,
    );

    expect(screen.getByText('Tavily Search')).toBeInTheDocument();
    expect(screen.getByText('Context7 Docs')).toBeInTheDocument();

    await userEvent.type(screen.getByPlaceholderText('Search by name...'), 'context');

    expect(screen.queryByText('Tavily Search')).not.toBeInTheDocument();
    expect(screen.getByText('Context7 Docs')).toBeInTheDocument();
  });

  it('opens the add-server form modal when the primary action is clicked', async () => {
    renderAuthedPage(<McpServersIndex mcpServers={[]} configItemNames={[]} />);

    await userEvent.click(screen.getByRole('button', { name: 'Add MCP Server' }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Add MCP Server')).toBeInTheDocument();
  });

  it('treats company-scoped custom servers as editable (no read-only label)', () => {
    renderAuthedPage(
      <McpServersIndex
        mcpServers={[server({ id: 9, scopeIndicator: 'company', kind: 'custom' })]}
        configItemNames={[]}
      />,
    );

    expect(screen.getByText('Tavily Search')).toBeInTheDocument();
    // editableScope="company" matches scopeIndicator "company", so edit/delete action icons
    // render (accessible via tooltips) rather than the read-only fallback label.
    expect(screen.queryByText('Read-only')).not.toBeInTheDocument();
  });
});
