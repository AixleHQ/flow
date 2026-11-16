import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { act, within } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { answerFetch } from 'test/fetchStub';
import { renderPage, screen, userEvent } from 'test/renderPage';

import { InsightsConnectModal, InsightsProjectModal, type InsightsProps } from './InsightsModals';

const connected: InsightsProps = {
  enabled: true,
  connection: { status: 'active', organizationName: 'Acme', connectedAt: '2026-11-11T10:00:00Z' },
  project: { export: false, insightsProjectId: null },
  canConnect: true,
  canManage: true,
  delivery: { pending: 0, oldestPendingAt: null, failed: 0, lastError: null },
};

describe('InsightsConnectModal', () => {
  beforeEach(() => vi.clearAllMocks());

  it('connects with a pairing code, and stays open with the reason when it is refused', async () => {
    renderPage(<InsightsConnectModal opened onClose={vi.fn()} projectId={3} />);

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
});

describe('InsightsProjectModal', () => {
  beforeEach(() => vi.clearAllMocks());

  it('shows the organization and switches the project on', async () => {
    renderPage(<InsightsProjectModal opened onClose={vi.fn()} projectId={3} insights={connected} />);

    const dialog = await screen.findByRole('dialog', { name: 'Aixle Insights for this project' });
    expect(within(dialog).getByText(/sends to Acme/)).toBeInTheDocument();
    expect(within(dialog).queryByLabelText('Insights project')).not.toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('switch', { name: /agent telemetry/ }));

    expect(router.patch).toHaveBeenCalledWith(
      '/company/projects/3/insights',
      { export: true },
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('names the mapped Insights project, not its id', async () => {
    answerFetch({ 'GET /company/projects/3/insights/projects': { projects: [{ id: 'ip-7', name: 'Platform' }] } });

    renderPage(
      <InsightsProjectModal
        opened
        onClose={vi.fn()}
        projectId={3}
        insights={{ ...connected, project: { export: true, insightsProjectId: 'ip-7' } }}
      />,
    );

    expect(await screen.findByDisplayValue('Platform')).toBeInTheDocument();
  });

  it('says what is still waiting and why the last batch was not accepted', async () => {
    renderPage(
      <InsightsProjectModal
        opened
        onClose={vi.fn()}
        projectId={3}
        insights={{
          ...connected,
          delivery: { pending: 3, oldestPendingAt: null, failed: 1, lastError: 'Insights answered 503' },
        }}
      />,
    );

    const dialog = await screen.findByRole('dialog', { name: 'Aixle Insights for this project' });
    expect(within(dialog).getByText(/Waiting to be sent: 3/)).toBeInTheDocument();
    expect(within(dialog).getByText(/not accepted: 1/)).toBeInTheDocument();
    expect(within(dialog).getByText('Insights answered 503')).toBeInTheDocument();
  });
});
