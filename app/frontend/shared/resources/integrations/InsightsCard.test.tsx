import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { act, within } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { InsightsCard, type InsightsProps } from './InsightsCard';

const connected: InsightsProps = {
  enabled: true,
  connection: { status: 'active', organizationName: 'Acme', connectedAt: '2026-11-11T10:00:00Z' },
  project: { export: false, insightsProjectId: null },
  canConnect: true,
  canManage: true,
  delivery: { pending: 0, oldestPendingAt: null, failed: 0, lastError: null },
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

  it('shows the organization and switches the project on', async () => {
    renderPage(<InsightsCard insights={connected} projectId={3} />);

    expect(screen.getByText(/sends to Acme/)).toBeInTheDocument();
    expect(screen.queryByLabelText('Insights project')).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('switch', { name: /agent telemetry/ }));

    expect(router.patch).toHaveBeenCalledWith(
      '/company/projects/3/insights',
      { export: true },
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('says what is still waiting and why the last batch was not accepted', () => {
    renderPage(
      <InsightsCard
        insights={{
          ...connected,
          project: { export: true, insightsProjectId: null },
          delivery: { pending: 3, oldestPendingAt: null, failed: 1, lastError: 'Insights answered 503' },
        }}
        projectId={3}
      />,
    );

    expect(screen.getByText(/Waiting to be sent: 3/)).toBeInTheDocument();
    expect(screen.getByText(/not accepted: 1/)).toBeInTheDocument();
    expect(screen.getByText('Insights answered 503')).toBeInTheDocument();
    expect(screen.getByRole('combobox', { name: 'Insights project' })).toBeInTheDocument();
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
