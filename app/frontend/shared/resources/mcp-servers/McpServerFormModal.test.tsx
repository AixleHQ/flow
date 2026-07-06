import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { McpServerFormModal } from './McpServerFormModal';

// This component uses @mantine/form (real form state + zodResolver) and fires the backend
// request through Inertia's router.* spies. We assert validation gating and the eventual
// router.post / router.patch payload without a backend. OAuth "Connect" is a top-level browser
// navigation (window.location), never an Inertia visit, so those tests swap window.location.

const baseProps = {
  configItemNames: ['API_KEY', 'SECRET'],
  basePath: '/projects/1/mcp_servers',
};

// The MCPServerResource masks every stored header/env value to this sentinel before it reaches the
// browser, so an edited server arrives with masked values, not real secrets.
const MASK = '••••••';

// A static (manual-header) server. Its Authorization value arrives masked, exactly as the resource
// sends it — the modal must not resubmit that placeholder verbatim.
const editServer = {
  id: 7,
  name: 'playwright',
  displayName: 'Playwright Browser',
  url: 'https://mcp.example.com',
  transport: 'http',
  headers: { Authorization: MASK },
  command: null,
  env: null,
  description: 'Browser automation',
  enabled: true,
  authType: 'static' as const,
  credentialScope: 'shared' as const,
  oauthStatus: null,
};

// A saved OAuth server. oauthStatus is per-current-user and read-only.
const oauthServer = {
  id: 12,
  name: 'linear',
  displayName: 'Linear',
  url: 'https://mcp.linear.app',
  transport: 'http',
  headers: {},
  command: null,
  env: null,
  description: 'Linear MCP',
  enabled: true,
  authType: 'oauth' as const,
  credentialScope: 'per_user' as const,
  oauthStatus: 'pending' as const,
};

describe('McpServerFormModal', () => {
  it('renders the create title, core fields and a Create button', () => {
    renderPage(<McpServerFormModal opened onClose={vi.fn()} {...baseProps} />);

    expect(screen.getByText('Add MCP Server')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('playwright')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Playwright Browser')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Create' })).toBeInTheDocument();
  });

  it('renders edit mode with prefilled values, Save button and a disabled Name field', async () => {
    renderPage(<McpServerFormModal opened onClose={vi.fn()} editServer={editServer} {...baseProps} />);

    expect(screen.getByText('Edit MCP Server')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Save' })).toBeInTheDocument();

    await waitFor(() => expect(screen.getByDisplayValue('playwright')).toBeDisabled());
    expect(screen.getByDisplayValue('Playwright Browser')).toBeInTheDocument();
  });

  it('cancel calls onClose', async () => {
    const onClose = vi.fn();
    renderPage(<McpServerFormModal opened onClose={onClose} {...baseProps} />);

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(onClose).toHaveBeenCalled();
  });

  it('the Headers section starts empty and "Add Header" reveals a key/value row', async () => {
    renderPage(<McpServerFormModal opened onClose={vi.fn()} {...baseProps} />);

    expect(screen.getByText('No headers configured')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /Add Header/i }));

    expect(await screen.findByPlaceholderText('Authorization')).toBeInTheDocument();
    expect(screen.queryByText('No headers configured')).not.toBeInTheDocument();
  });

  it('a valid http submit fires router.post with the mcpServer payload', async () => {
    renderPage(<McpServerFormModal opened onClose={vi.fn()} {...baseProps} />);

    await userEvent.type(screen.getByPlaceholderText('playwright'), 'context7');
    await userEvent.type(screen.getByPlaceholderText('Playwright Browser'), 'Context7 Docs');
    await userEvent.type(screen.getByPlaceholderText('https://mcp.example.com'), 'https://mcp.context7.com');

    await userEvent.click(screen.getByRole('button', { name: 'Create' }));

    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith(
        '/projects/1/mcp_servers',
        expect.objectContaining({
          mcpServer: expect.objectContaining({
            name: 'context7',
            displayName: 'Context7 Docs',
            transport: 'http',
            url: 'https://mcp.context7.com',
            authType: 'none',
          }),
        }),
        expect.objectContaining({ preserveScroll: true }),
      ),
    );
  });

  it('switching transport to stdio reveals the Command field and hides URL', async () => {
    renderPage(<McpServerFormModal opened onClose={vi.fn()} {...baseProps} />);

    expect(screen.getByPlaceholderText('https://mcp.example.com')).toBeInTheDocument();

    await userEvent.selectOptions(screen.getByLabelText('Transport'), 'stdio');

    expect(await screen.findByPlaceholderText('npx @automattic/mcp-wordpress-remote')).toBeInTheDocument();
    expect(screen.queryByPlaceholderText('https://mcp.example.com')).not.toBeInTheDocument();
  });

  it('the Auth Type selector is only offered for remote (non-stdio) transports', async () => {
    renderPage(<McpServerFormModal opened onClose={vi.fn()} {...baseProps} />);

    expect(screen.getByLabelText('Auth Type')).toBeInTheDocument();

    await userEvent.selectOptions(screen.getByLabelText('Transport'), 'stdio');

    expect(screen.queryByLabelText('Auth Type')).not.toBeInTheDocument();
  });

  it('a valid stdio submit fires router.post with command, env populated and empty headers', async () => {
    renderPage(<McpServerFormModal opened onClose={vi.fn()} {...baseProps} />);

    await userEvent.type(screen.getByPlaceholderText('playwright'), 'localproc');
    await userEvent.type(screen.getByPlaceholderText('Playwright Browser'), 'Local Process');
    await userEvent.selectOptions(screen.getByLabelText('Transport'), 'stdio');

    await userEvent.type(
      await screen.findByPlaceholderText('npx @automattic/mcp-wordpress-remote'),
      'npx @playwright/mcp',
    );

    await userEvent.click(screen.getByRole('button', { name: /Add Variable/i }));
    await userEvent.type(await screen.findByPlaceholderText('WP_API_URL'), 'WP_API_URL');
    await userEvent.type(screen.getByPlaceholderText('https://example.com'), 'https://wp.example.com');

    await userEvent.click(screen.getByRole('button', { name: 'Create' }));

    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith(
        '/projects/1/mcp_servers',
        expect.objectContaining({
          mcpServer: expect.objectContaining({
            name: 'localproc',
            transport: 'stdio',
            command: 'npx @playwright/mcp',
            env: { WP_API_URL: 'https://wp.example.com' },
            headers: {},
          }),
        }),
        expect.objectContaining({ preserveScroll: true }),
      ),
    );
  });

  it('includes typed header key/value pairs in the http payload', async () => {
    renderPage(<McpServerFormModal opened onClose={vi.fn()} {...baseProps} />);

    await userEvent.type(screen.getByPlaceholderText('playwright'), 'context7');
    await userEvent.type(screen.getByPlaceholderText('Playwright Browser'), 'Context7 Docs');
    await userEvent.type(screen.getByPlaceholderText('https://mcp.example.com'), 'https://mcp.context7.com');

    await userEvent.click(screen.getByRole('button', { name: /Add Header/i }));
    await userEvent.type(await screen.findByPlaceholderText('Authorization'), 'X-Api-Key');
    await userEvent.type(screen.getByPlaceholderText('Bearer token'), 'abc123');

    await userEvent.click(screen.getByRole('button', { name: 'Create' }));

    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith(
        '/projects/1/mcp_servers',
        expect.objectContaining({
          mcpServer: expect.objectContaining({
            headers: { 'X-Api-Key': 'abc123' },
            env: {},
          }),
        }),
        expect.anything(),
      ),
    );
  });

  it('removing a header row restores the empty-state message', async () => {
    const { container } = renderPage(<McpServerFormModal opened onClose={vi.fn()} {...baseProps} />);

    await userEvent.click(screen.getByRole('button', { name: /Add Header/i }));
    expect(await screen.findByPlaceholderText('Authorization')).toBeInTheDocument();

    // The remove control is the icon-only ActionIcon carrying the trash icon.
    const trash = container.querySelector('.tabler-icon-trash')?.closest('button');
    await userEvent.click(trash!);

    expect(await screen.findByText('No headers configured')).toBeInTheDocument();
    expect(screen.queryByPlaceholderText('Authorization')).not.toBeInTheDocument();
  });

  it('editing an http server submits via router.patch to the server id path', async () => {
    const onClose = vi.fn();
    renderPage(<McpServerFormModal opened onClose={onClose} editServer={editServer} {...baseProps} />);

    expect(await screen.findByDisplayValue('Playwright Browser')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Save' }));

    await waitFor(() =>
      expect(router.patch).toHaveBeenCalledWith(
        '/projects/1/mcp_servers/7',
        expect.objectContaining({
          mcpServer: expect.objectContaining({
            name: 'playwright',
            displayName: 'Playwright Browser',
            url: 'https://mcp.example.com',
            authType: 'static',
            // The masked Authorization value was never touched, so it is dropped rather than
            // resubmitted verbatim; the server keeps the stored secret.
            headers: {},
          }),
        }),
        expect.objectContaining({ preserveScroll: true }),
      ),
    );
    expect(router.post).not.toHaveBeenCalled();
  });

  it('edit mode prefills existing headers into editable rows (with masked values)', async () => {
    renderPage(<McpServerFormModal opened onClose={vi.fn()} editServer={editServer} {...baseProps} />);

    expect(await screen.findByDisplayValue('Authorization')).toBeInTheDocument();
    expect(screen.getByDisplayValue(MASK)).toBeInTheDocument();
    expect(screen.queryByText('No headers configured')).not.toBeInTheDocument();
  });

  it('does not resubmit an untouched masked header, but sends a freshly edited value', async () => {
    renderPage(<McpServerFormModal opened onClose={vi.fn()} editServer={editServer} {...baseProps} />);

    const valueField = await screen.findByDisplayValue(MASK);
    await userEvent.clear(valueField);
    await userEvent.type(valueField, 'rotated-secret');

    await userEvent.click(screen.getByRole('button', { name: 'Save' }));

    await waitFor(() =>
      expect(router.patch).toHaveBeenCalledWith(
        '/projects/1/mcp_servers/7',
        expect.objectContaining({
          mcpServer: expect.objectContaining({
            headers: { Authorization: 'rotated-secret' },
          }),
        }),
        expect.anything(),
      ),
    );

    // The mask sentinel must never appear in the outgoing payload.
    const payload = vi.mocked(router.patch).mock.lastCall?.[1] as { mcpServer: { headers: Record<string, string> } };
    expect(Object.values(payload.mcpServer.headers)).not.toContain(MASK);
  });

  it('toggling a header value to a config item shows the config-item picker', async () => {
    const { container } = renderPage(<McpServerFormModal opened onClose={vi.fn()} {...baseProps} />);

    await userEvent.click(screen.getByRole('button', { name: /Add Header/i }));
    expect(await screen.findByPlaceholderText('Bearer token')).toBeInTheDocument();

    // The key icon toggles the value field into the config-item autocomplete.
    const keyToggle = container.querySelector('.tabler-icon-key')?.closest('button');
    await userEvent.click(keyToggle!);

    expect(await screen.findByPlaceholderText('Select config item...')).toBeInTheDocument();
    expect(screen.queryByPlaceholderText('Bearer token')).not.toBeInTheDocument();
  });

  it('renders the Enabled switch checked by default in create mode', () => {
    renderPage(<McpServerFormModal opened onClose={vi.fn()} {...baseProps} />);

    expect(screen.getByRole('switch', { name: 'Enabled' })).toBeChecked();
  });

  it('disables Cancel while a submit is in flight', async () => {
    renderPage(<McpServerFormModal opened onClose={vi.fn()} {...baseProps} />);

    await userEvent.type(screen.getByPlaceholderText('playwright'), 'context7');
    await userEvent.type(screen.getByPlaceholderText('Playwright Browser'), 'Context7 Docs');
    await userEvent.type(screen.getByPlaceholderText('https://mcp.example.com'), 'https://mcp.context7.com');

    await userEvent.click(screen.getByRole('button', { name: 'Create' }));

    // handleSubmit sets loading=true synchronously; router.post is a spy that never
    // calls onFinish, so loading stays true and Cancel is disabled.
    await waitFor(() => expect(router.post).toHaveBeenCalled());
    expect(screen.getByRole('button', { name: 'Cancel' })).toBeDisabled();
  });

  describe('OAuth auth type', () => {
    it('selecting OAuth reveals the Credential Scope select and hides the Headers editor', async () => {
      renderPage(<McpServerFormModal opened onClose={vi.fn()} {...baseProps} />);

      // Default auth type is "none": the manual Headers editor is present, no credential scope.
      expect(screen.getByRole('button', { name: /Add Header/i })).toBeInTheDocument();
      expect(screen.queryByLabelText('Credential Scope')).not.toBeInTheDocument();

      await userEvent.selectOptions(screen.getByLabelText('Auth Type'), 'oauth');

      expect(await screen.findByLabelText('Credential Scope')).toBeInTheDocument();
      expect(screen.queryByRole('button', { name: /Add Header/i })).not.toBeInTheDocument();
    });

    it('an unsaved OAuth server shows a "Save first" hint and no Connect button', async () => {
      renderPage(<McpServerFormModal opened onClose={vi.fn()} {...baseProps} />);

      await userEvent.selectOptions(screen.getByLabelText('Auth Type'), 'oauth');

      expect(await screen.findByText('Save first, then Connect')).toBeInTheDocument();
      expect(screen.queryByRole('button', { name: 'Connect' })).not.toBeInTheDocument();
    });

    it('a saved OAuth server hides the Headers editor and shows a Connect button', async () => {
      renderPage(<McpServerFormModal opened onClose={vi.fn()} editServer={oauthServer} {...baseProps} />);

      expect(await screen.findByRole('button', { name: 'Connect' })).toBeInTheDocument();
      expect(screen.queryByRole('button', { name: /Add Header/i })).not.toBeInTheDocument();
      // The Credential Scope select is prefilled from the server's per_user scope.
      expect(screen.getByLabelText('Credential Scope')).toHaveValue('per_user');
    });

    it.each([
      ['active', 'Connected'],
      ['expiring', 'Expiring soon'],
      ['pending', 'Not connected'],
      ['error', 'Reconnect'],
    ] as const)('maps oauth_status "%s" to the "%s" connection badge', async (status, label) => {
      renderPage(
        <McpServerFormModal
          opened
          onClose={vi.fn()}
          editServer={{ ...oauthServer, oauthStatus: status }}
          {...baseProps}
        />,
      );

      expect(await screen.findByText(label)).toBeInTheDocument();
    });

    describe('Connect navigation', () => {
      // window.location is read-only in jsdom; swap it for a plain object so we can observe
      // handleConnect's assignment to location.href (OAuth needs a top-level navigation).
      const originalLocation = window.location;

      beforeEach(() => {
        Object.defineProperty(window, 'location', {
          configurable: true,
          writable: true,
          value: { href: '' },
        });
      });

      afterEach(() => {
        Object.defineProperty(window, 'location', {
          configurable: true,
          writable: true,
          value: originalLocation,
        });
      });

      it('Connect performs a top-level navigation to the connect entry, not an Inertia visit', async () => {
        renderPage(<McpServerFormModal opened onClose={vi.fn()} editServer={oauthServer} {...baseProps} />);

        await userEvent.click(await screen.findByRole('button', { name: 'Connect' }));

        expect(window.location.href).toBe(
          `/oauth/mcp/12/connect?return_to=${encodeURIComponent('/projects/1/mcp_servers')}`,
        );
        expect(router.get).not.toHaveBeenCalled();
        expect(router.visit).not.toHaveBeenCalled();
      });
    });
  });
});
