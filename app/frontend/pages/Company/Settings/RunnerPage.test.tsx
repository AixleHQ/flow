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
      machines: [],
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

  it('lists the machines of a manual runner, with Revoke on each', () => {
    render({
      machines: [
        {
          id: 1,
          key: 'aixle-r5-ab12cd34',
          displayName: 'mac-studio',
          os: 'darwin',
          arch: 'arm64',
          runnerVersion: '0.2.0',
          stateReason: null,
          lastHeartbeatAt: '2026-11-12T10:00:00Z',
          createdAt: '2026-11-12T09:00:00Z',
          firstSeenIp: '203.0.113.7',
          createdByName: 'Grace Hopper',
          state: 'idle',
        },
      ],
    });

    const machines = screen.getByRole('table', { name: 'Machines' });
    expect(within(machines).getByText('mac-studio')).toBeInTheDocument();
    expect(within(machines).getByText('Idle')).toBeInTheDocument();
    expect(within(machines).getByText('203.0.113.7')).toBeInTheDocument();
    expect(within(machines).getAllByRole('button')).toHaveLength(1);
    expect(within(machines).getByRole('button', { name: 'Revoke' })).toBeInTheDocument();
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

  it('hides Edit on a revoked runner, since revoke is final', () => {
    render({ runner: { ...runner, status: 'revoked' } });

    expect(screen.getByRole('button', { name: 'Delete' })).toBeInTheDocument();
    ['Edit', 'Disable', 'Enable', 'Revoke'].forEach((name) =>
      expect(screen.queryByRole('button', { name })).not.toBeInTheDocument(),
    );
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

  it('offers Add machine on a live manual runner to someone who may manage it, and not otherwise', () => {
    const view = render();
    expect(screen.getByRole('button', { name: 'Add machine' })).toBeInTheDocument();
    view.unmount();

    const utils = render({ canManage: false });
    expect(screen.queryByRole('button', { name: 'Add machine' })).not.toBeInTheDocument();
    utils.unmount();

    render({ runner: buildRunner({ id: 5, name: 'gpu-box', status: 'revoked' }) });
    expect(screen.queryByRole('button', { name: 'Add machine' })).not.toBeInTheDocument();
  });
});
