import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { act, within } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { InsightsCard, type InsightsProps } from './InsightsCard';

const connected: InsightsProps = {
  enabled: true,
  connection: { status: 'active', organizationName: 'Acme', connectedAt: '2026-11-11T10:00:00Z' },
  project: { export: true, sharePrompts: false, insightsProjectId: null },
  canConnect: true,
  canManage: true,
  delivery: { pending: 1, delivered: 4, rejected: 0, failed: 0, skipped: 0, lastError: null },
};

describe('InsightsCard', () => {
  beforeEach(() => vi.clearAllMocks());

  it('renders nothing on a deployment Insights has not registered', () => {
    renderPage(<InsightsCard insights={{ enabled: false }} projectId={3} />);

    expect(screen.queryByText('Aixle Insights')).not.toBeInTheDocument();
  });

  it('connects with a pairing code, and keeps the dialog open with the reason when it is refused', async () => {
    renderPage(<InsightsCard insights={{ enabled: true, connection: null, canConnect: true }} projectId={3} />);

    await userEvent.click(screen.getByRole('button', { name: 'Connect' }));
    const dialog = await screen.findByRole('dialog', { name: 'Connect Aixle Insights' });
    await userEvent.type(within(dialog).getByLabelText('Pairing code'), 'ABCD-2345');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Connect' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/3/insights/connect',
      { code: 'ABCD-2345' },
      expect.objectContaining({ preserveScroll: true }),
    );
    const options = vi.mocked(router.post).mock.lastCall?.[2] as { onError?: (errors: Record<string, string>) => void };
    act(() => options.onError?.({ code: 'That code is not valid' }));
    expect(within(dialog).getByText('That code is not valid')).toBeInTheDocument();
  });

  it('shows the organization and saves the project switches', async () => {
    renderPage(<InsightsCard insights={connected} projectId={3} />);

    expect(screen.getByText(/sends to Acme/)).toBeInTheDocument();
    expect(screen.getByText(/Sessions sent: 4/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole('switch', { name: /Share prompts and tool calls/ }));

    expect(router.patch).toHaveBeenCalledWith(
      '/company/projects/3/insights',
      { share_prompts: true },
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('offers prompt sharing only on an exported project', () => {
    renderPage(
      <InsightsCard
        insights={{ ...connected, project: { export: false, sharePrompts: false, insightsProjectId: null } }}
        projectId={3}
      />,
    );

    expect(screen.getByRole('switch', { name: /Share prompts and tool calls/ })).toBeDisabled();
    expect(screen.queryByLabelText('Insights project')).not.toBeInTheDocument();
  });

  it('asks before disconnecting', async () => {
    renderPage(<InsightsCard insights={connected} projectId={3} />);

    await userEvent.click(screen.getByRole('button', { name: 'Disconnect' }));
    const confirm = await screen.findByRole('dialog', { name: 'Disconnect Aixle Insights' });
    await userEvent.click(within(confirm).getByRole('button', { name: 'Disconnect' }));

    expect(router.delete).toHaveBeenCalledWith('/company/projects/3/insights/disconnect', { preserveScroll: true });
  });

  it('asks for a new code once Insights refused the connection', () => {
    renderPage(
      <InsightsCard
        insights={{ ...connected, connection: { ...connected.connection!, status: 'error' } }}
        projectId={3}
      />,
    );

    expect(screen.getByText('Needs a new code')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Enter a new code' })).toBeInTheDocument();
  });
});
