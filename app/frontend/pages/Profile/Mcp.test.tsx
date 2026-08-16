import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { renderAuthedPage, screen, userEvent } from 'test/renderPage';

import ProfileMcpPage from './Mcp';

const boardTools = [
  { name: 'list_board_tasks', description: 'Tasks on a board.', readOnly: true },
  { name: 'move_board_task', description: 'Move a card.', readOnly: false },
];

const accountTools = [{ name: 'list_projects', description: 'Projects you can access.', readOnly: true }];

const toolGroups = [
  { tag: 'account', title: 'Account & projects', blurb: 'Where every flow starts.', tools: accountTools },
  { tag: 'board', title: 'Board', blurb: null, tools: boardTools },
];

const buildMcp = (overrides = {}) => ({
  enabled: false,
  lastUsedAt: null,
  serverUrl: 'https://flow.example.com/mcp',
  serverName: 'flow',
  token: null,
  toolGroups,
  enabledTools: null,
  ...overrides,
});

const renderPageWith = (mcp = buildMcp()) => renderAuthedPage(<ProfileMcpPage mcp={mcp} />, { props: { mcp } });

// The picker starts collapsed — the full registry is ~85 rows — so a tool's
// checkbox only exists once its group is open.
const openGroup = (title: string) => userEvent.click(screen.getByRole('button', { name: new RegExp(title) }));

afterEach(() => {
  vi.restoreAllMocks();
});

describe('Profile MCP tab', () => {
  it('enables MCP by posting to the regenerate-token route when MCP is disabled', async () => {
    renderPageWith();

    expect(screen.queryByRole('button', { name: 'Disable' })).not.toBeInTheDocument();
    expect(screen.queryByText(/MCP access is enabled/)).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Enable MCP' }));

    expect(router.post).toHaveBeenCalledWith(
      '/profile/regenerate_mcp_token',
      {},
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('regenerates and disables the token via the router when MCP is enabled', async () => {
    renderPageWith(buildMcp({ enabled: true, lastUsedAt: '2026-03-01T12:00:00Z' }));

    expect(screen.getByText(/MCP access is enabled/)).toHaveTextContent(/Last used/);

    await userEvent.click(screen.getByRole('button', { name: 'Regenerate token' }));
    expect(router.post).toHaveBeenCalledWith(
      '/profile/regenerate_mcp_token',
      {},
      expect.objectContaining({ preserveScroll: true }),
    );

    await userEvent.click(screen.getByRole('button', { name: 'Disable' }));
    expect(router.delete).toHaveBeenCalledWith(
      '/profile/disable_mcp_token',
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('shows the not-used-yet hint when MCP is enabled but has never been used', () => {
    renderPageWith(buildMcp({ enabled: true }));

    expect(screen.getByText(/MCP access is enabled/)).toHaveTextContent(/Not used yet/);
  });

  it('renders the one-time token with a Claude command carrying the server name and URL', () => {
    renderPageWith(buildMcp({ enabled: true, token: 'amcp_tok_abc123' }));

    expect(screen.getByText('Your token — copy it now, it will not be shown again:')).toBeInTheDocument();
    expect(screen.getByText('amcp_tok_abc123')).toBeInTheDocument();

    const command = screen.getByText(/claude mcp add flow --transport http/);
    expect(command).toHaveTextContent('https://flow.example.com/mcp');
    expect(command).toHaveTextContent('Authorization: Bearer amcp_tok_abc123');
  });

  // Cursor installs from a deeplink whose `config` is the base64 of the server
  // entry alone — decoded here so a wrong shape fails loudly rather than
  // silently producing a link Cursor rejects.
  it('offers a Cursor install deeplink carrying the URL and bearer token', () => {
    renderPageWith(buildMcp({ enabled: true, token: 'amcp_tok_abc123' }));

    const link = screen.getByRole('link', { name: 'Add to Cursor' });
    const href = link.getAttribute('href') ?? '';
    expect(href).toContain('cursor://anysphere.cursor-deeplink/mcp/install?name=flow');

    const config = new URL(href).searchParams.get('config') ?? '';
    expect(JSON.parse(atob(config))).toEqual({
      url: 'https://flow.example.com/mcp',
      headers: { Authorization: 'Bearer amcp_tok_abc123' },
    });
  });

  it('hides the connection snippets until a token has been generated', () => {
    renderPageWith(buildMcp({ enabled: true }));

    expect(screen.queryByRole('link', { name: 'Add to Cursor' })).not.toBeInTheDocument();
    expect(screen.queryByText(/claude mcp add/)).not.toBeInTheDocument();
  });

  it('treats a null selection as every tool enabled', () => {
    renderPageWith();

    expect(screen.getByText('3 / 3')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Save tools' })).toBeDisabled();
  });

  it('saves a narrowed selection, sending only the checked tool names', async () => {
    renderPageWith();

    await openGroup('Board');
    // A tool that changes something is marked in its description, so the row
    // says what enabling it lets the agent do.
    expect(screen.getByText(/Move a card\. · writes/)).toBeInTheDocument();

    await userEvent.click(screen.getByRole('checkbox', { name: 'move_board_task' }));

    expect(screen.getByText('2 / 3')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Save tools' }));

    expect(router.patch).toHaveBeenCalledWith(
      '/profile/update_mcp_tools',
      { toolNames: ['list_projects', 'list_board_tasks'] },
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('renders a stored selection with only those tools checked', async () => {
    renderPageWith(buildMcp({ enabledTools: ['list_projects'] }));

    expect(screen.getByText('1 / 3')).toBeInTheDocument();

    await openGroup('Board');
    expect(screen.getByRole('checkbox', { name: 'list_board_tasks' })).not.toBeChecked();
  });

  it('clears and re-selects every tool from the header actions', async () => {
    renderPageWith();

    await userEvent.click(screen.getByRole('button', { name: 'Clear' }));
    expect(screen.getByText('0 / 3')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Select all' }));
    expect(screen.getByText('3 / 3')).toBeInTheDocument();
    // Back to the stored state, so there is nothing to save.
    expect(screen.getByRole('button', { name: 'Save tools' })).toBeDisabled();
  });
});
