import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { buildRunner, buildRunnerTypeOption } from 'test/factories/runner';
import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import RunnersPage from './RunnersPage';

const runners = [
  buildRunner({
    id: 3,
    name: 'gpu-box',
    status: 'degraded',
    statusReason: 'Docker daemon not reachable',
    lastSeenAt: '2026-10-27T09:30:00Z',
  }),
];

const render = (props: Record<string, unknown> = {}) =>
  renderAuthedPage(<RunnersPage />, {
    props: {
      runners,
      runnerTypes: [buildRunnerTypeOption()],
      canManage: true,
      features: { externalRunners: true },
      ...props,
    },
  });

describe('Company/Settings/RunnersPage', () => {
  it('lists the company runners with their type, status and reason, and last seen', () => {
    render();

    expect(screen.getByRole('tab', { name: 'Runners', selected: true })).toBeInTheDocument();
    const row = screen.getByRole('row', { name: /gpu-box/ });
    expect(within(row).getByRole('link', { name: 'gpu-box' })).toHaveAttribute('href', '/company/settings/runners/3');
    expect(within(row).getByText('Manual')).toBeInTheDocument();
    expect(within(row).getByText('Degraded')).toBeInTheDocument();
    expect(within(row).getByText('Docker daemon not reachable')).toBeInTheDocument();
    expect(within(row).queryByText('Never')).not.toBeInTheDocument();
  });

  it('opens the new-runner form for someone who may manage runners', async () => {
    const user = userEvent.setup();
    render();

    await user.click(screen.getByRole('button', { name: 'New runner' }));

    expect(await screen.findByRole('dialog', { name: 'New runner' })).toBeInTheDocument();
  });

  it('shows the list read-only without canManage', () => {
    render({ canManage: false });

    expect(screen.getByRole('link', { name: 'gpu-box' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'New runner' })).not.toBeInTheDocument();
  });

  it('renders neither the tab nor the list with the flag off', () => {
    render({ features: { externalRunners: false } });

    expect(screen.queryByRole('tab', { name: 'Runners' })).not.toBeInTheDocument();
    expect(screen.queryByText('gpu-box')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'New runner' })).not.toBeInTheDocument();
  });
});
