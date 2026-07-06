import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { McpServerFormModal } from './McpServerFormModal';

// This component uses @mantine/form (real form state + zodResolver) and fires the backend
// request through Inertia's router.* spies. We assert validation gating and the eventual
// router.post / router.patch payload without a backend.

const baseProps = {
  configItemNames: ['API_KEY', 'SECRET'],
  basePath: '/projects/1/mcp_servers',
};

const editServer = {
  id: 7,
  name: 'playwright',
  displayName: 'Playwright Browser',
  url: 'https://mcp.example.com',
  transport: 'http',
  headers: { Authorization: 'Bearer x' },
  command: null,
  env: null,
  description: 'Browser automation',
  enabled: true,
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
            headers: { Authorization: 'Bearer x' },
          }),
        }),
        expect.objectContaining({ preserveScroll: true }),
      ),
    );
    expect(router.post).not.toHaveBeenCalled();
  });

  it('edit mode prefills existing headers into editable rows', async () => {
    renderPage(<McpServerFormModal opened onClose={vi.fn()} editServer={editServer} {...baseProps} />);

    expect(await screen.findByDisplayValue('Authorization')).toBeInTheDocument();
    expect(screen.getByDisplayValue('Bearer x')).toBeInTheDocument();
    expect(screen.queryByText('No headers configured')).not.toBeInTheDocument();
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
});
