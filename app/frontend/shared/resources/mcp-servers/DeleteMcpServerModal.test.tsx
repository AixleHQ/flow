import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { DeleteMcpServerModal } from './DeleteMcpServerModal';

const server = { id: 7, name: 'github', displayName: 'GitHub Server' };

describe('DeleteMcpServerModal', () => {
  it('renders the title and the server name in the confirmation prompt', () => {
    renderPage(
      <DeleteMcpServerModal opened onClose={vi.fn()} server={server} basePath="/projects/1/mcp-servers" />,
    );

    expect(screen.getByRole('heading', { name: /delete mcp server/i })).toBeInTheDocument();
    expect(screen.getByText('GitHub Server')).toBeInTheDocument();
    expect(screen.getByText(/this action cannot be undone/i)).toBeInTheDocument();
  });

  it('renders nothing when no server is provided', () => {
    renderPage(
      <DeleteMcpServerModal opened onClose={vi.fn()} server={null} basePath="/projects/1/mcp-servers" />,
    );

    expect(screen.queryByRole('heading', { name: /delete mcp server/i })).not.toBeInTheDocument();
  });

  it('confirming Delete fires router.delete to the server path', async () => {
    renderPage(
      <DeleteMcpServerModal opened onClose={vi.fn()} server={server} basePath="/projects/1/mcp-servers" />,
    );

    await userEvent.click(screen.getByRole('button', { name: /delete/i }));

    expect(router.delete).toHaveBeenCalledWith(
      '/projects/1/mcp-servers/7',
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('clicking Cancel calls onClose and does NOT delete', async () => {
    const onClose = vi.fn();
    renderPage(
      <DeleteMcpServerModal opened onClose={onClose} server={server} basePath="/projects/1/mcp-servers" />,
    );

    await userEvent.click(screen.getByRole('button', { name: /cancel/i }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(router.delete).not.toHaveBeenCalled();
  });
});
