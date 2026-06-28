import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { DeleteAgentModal } from './DeleteAgentModal';

const agent = { id: 42, name: 'support_bot', title: 'Support Bot', icon: '🛟' };

describe('DeleteAgentModal', () => {
  it('renders the title, agent details and warning when opened with an agent', () => {
    renderPage(<DeleteAgentModal opened onClose={vi.fn()} agent={agent} basePath="/projects/1/agents" />);

    expect(screen.getByText('Delete Agent')).toBeInTheDocument();
    expect(screen.getByText('Support Bot')).toBeInTheDocument();
    expect(screen.getByText('support_bot')).toBeInTheDocument();
    expect(screen.getByText('🛟')).toBeInTheDocument();
    expect(screen.getByText(/this action cannot be undone/i)).toBeInTheDocument();
  });

  it('renders nothing when no agent is provided', () => {
    renderPage(<DeleteAgentModal opened onClose={vi.fn()} agent={null} basePath="/projects/1/agents" />);

    expect(screen.queryByText('Delete Agent')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^delete$/i })).not.toBeInTheDocument();
  });

  it('confirming Delete fires router.delete to the agent path', async () => {
    renderPage(<DeleteAgentModal opened onClose={vi.fn()} agent={agent} basePath="/projects/1/agents" />);

    await userEvent.click(screen.getByRole('button', { name: /^delete$/i }));

    expect(router.delete).toHaveBeenCalledWith(
      '/projects/1/agents/42',
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('clicking Cancel calls onClose and does NOT fire a delete request', async () => {
    const onClose = vi.fn();
    renderPage(<DeleteAgentModal opened onClose={onClose} agent={agent} basePath="/projects/1/agents" />);

    await userEvent.click(screen.getByRole('button', { name: /cancel/i }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(router.delete).not.toHaveBeenCalled();
  });
});
