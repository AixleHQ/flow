import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { DeleteToolModal } from './DeleteToolModal';

const tool = { id: 7, name: 'web_search', displayName: 'Web Search' };

describe('DeleteToolModal', () => {
  it('renders the confirmation title and the tool name/displayName when opened', () => {
    renderPage(
      <DeleteToolModal opened onClose={vi.fn()} tool={tool} basePath="/projects/1/tools" />,
    );

    expect(screen.getByText('Delete Tool')).toBeInTheDocument();
    expect(screen.getByText(/are you sure you want to delete this tool/i)).toBeInTheDocument();
    expect(screen.getByText('Web Search')).toBeInTheDocument();
    expect(screen.getByText('web_search')).toBeInTheDocument();
  });

  it('renders nothing when no tool is provided', () => {
    renderPage(<DeleteToolModal opened onClose={vi.fn()} tool={null} basePath="/projects/1/tools" />);

    expect(screen.queryByText('Delete Tool')).not.toBeInTheDocument();
  });

  it('confirming the delete fires router.delete to the tool path', async () => {
    renderPage(
      <DeleteToolModal opened onClose={vi.fn()} tool={tool} basePath="/projects/1/tools" />,
    );

    await userEvent.click(screen.getByRole('button', { name: 'Delete' }));

    expect(router.delete).toHaveBeenCalledWith(
      '/projects/1/tools/7',
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('cancel calls onClose and does NOT fire a delete request', async () => {
    const onClose = vi.fn();
    renderPage(
      <DeleteToolModal opened onClose={onClose} tool={tool} basePath="/projects/1/tools" />,
    );

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(router.delete).not.toHaveBeenCalled();
  });
});
