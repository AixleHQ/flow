import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { buildRunner, buildRunnerTypeOption } from 'test/factories/runner';
import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import RunnerPage from './RunnerPage';

const runner = buildRunner({
  id: 5,
  name: 'gpu-box',
  status: 'connected',
  maxConcurrency: 4,
  createdByName: 'Grace Hopper',
  config: { container: { network: 'host', extra_mounts: [{ source: '/opt', target: '/opt' }] } },
});

const render = (props: Record<string, unknown> = {}) =>
  renderAuthedPage(<RunnerPage />, {
    props: {
      runner,
      runnerTypes: [buildRunnerTypeOption()],
      canManage: true,
      features: { externalRunners: true },
      ...props,
    },
  });

describe('Company/Settings/RunnerPage', () => {
  it('shows the runner, its limits, capabilities and the options that widen access', () => {
    render();

    expect(screen.getByRole('heading', { level: 1, name: 'gpu-box' })).toBeInTheDocument();
    expect(screen.getByText('Grace Hopper')).toBeInTheDocument();
    expect(screen.getByText('4')).toBeInTheDocument();
    expect(screen.getByText('Provisionable: no')).toBeInTheDocument();
    expect(screen.getByText('Shares the machine’s network (network: host)')).toBeInTheDocument();
    expect(screen.getByText('Mounts /opt at /opt, read-only')).toBeInTheDocument();
    expect(screen.getByText('container.network')).toBeInTheDocument();
  });

  it('disables a runner for someone who may manage it', async () => {
    const user = userEvent.setup();
    render();

    await user.click(screen.getByRole('button', { name: 'Disable' }));
    expect(router.post).toHaveBeenCalledWith('/company/settings/runners/5/disable', {}, expect.anything());
    expect(screen.queryByRole('button', { name: 'Enable' })).not.toBeInTheDocument();
  });

  it('revokes a runner once confirmed', async () => {
    const user = userEvent.setup();
    render();

    await user.click(screen.getByRole('button', { name: 'Revoke' }));
    const revoke = await screen.findByRole('dialog', { name: 'Revoke runner' });
    await user.click(within(revoke).getByRole('button', { name: 'Revoke' }));
    expect(router.post).toHaveBeenCalledWith('/company/settings/runners/5/revoke', {}, expect.anything());
  });

  it('deletes a runner once confirmed', async () => {
    const user = userEvent.setup();
    render();

    await user.click(screen.getByRole('button', { name: 'Delete' }));
    const remove = await screen.findByRole('dialog', { name: 'Delete runner' });
    await user.click(within(remove).getByRole('button', { name: 'Delete' }));
    expect(router.delete).toHaveBeenCalledWith('/company/settings/runners/5', expect.anything());
  });

  it('offers Enable on a disabled runner and opens the edit form without the type step', async () => {
    const user = userEvent.setup();
    render({ runner: { ...runner, status: 'disabled' } });

    expect(screen.queryByRole('button', { name: 'Disable' })).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Enable' }));
    expect(router.post).toHaveBeenCalledWith('/company/settings/runners/5/enable', {}, expect.anything());

    await user.click(screen.getByRole('button', { name: 'Edit' }));
    const dialog = await screen.findByRole('dialog', { name: 'Edit gpu-box' });
    expect(within(dialog).queryByRole('radio', { name: 'Manual' })).not.toBeInTheDocument();
  });

  it('hides every manage action without canManage', () => {
    render({ canManage: false });

    expect(screen.getByRole('heading', { level: 1, name: 'gpu-box' })).toBeInTheDocument();
    ['Edit', 'Disable', 'Enable', 'Revoke', 'Delete'].forEach((name) =>
      expect(screen.queryByRole('button', { name })).not.toBeInTheDocument(),
    );
  });

  it('renders nothing of the runner with the flag off', () => {
    render({ features: { externalRunners: false } });

    expect(screen.queryByRole('heading', { name: 'gpu-box' })).not.toBeInTheDocument();
  });
});
