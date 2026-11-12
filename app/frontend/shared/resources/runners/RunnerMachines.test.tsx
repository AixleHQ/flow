import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { act } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { RunnerMachine } from '@/types/generated';
import { renderAuthedPage, screen, within } from 'test/renderPage';

import { MACHINES_REFRESH_MS, RunnerMachines } from './RunnerMachines';

const machine = (overrides: Partial<RunnerMachine> = {}): RunnerMachine => ({
  id: 1,
  key: 'aixle-r5-ab12cd34',
  displayName: 'mac-studio',
  os: 'darwin',
  arch: 'arm64',
  runnerVersion: '0.2.0',
  stateReason: null,
  lastHeartbeatAt: '2026-11-12T10:00:00Z',
  createdAt: '2026-11-12T09:00:00Z',
  state: 'idle',
  ...overrides,
});

describe('RunnerMachines', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('lists each machine with its name, key, state, version, os/arch and last seen', () => {
    renderAuthedPage(
      <RunnerMachines
        machines={[
          machine(),
          machine({
            id: 2,
            key: 'aixle-r5-ffff0000',
            displayName: 'linux-box',
            os: 'linux',
            arch: 'amd64',
            state: 'online',
          }),
          machine({ id: 3, key: 'aixle-r5-00001111', displayName: 'old-box', lastHeartbeatAt: null, state: 'offline' }),
          machine({
            id: 4,
            key: 'aixle-r5-22223333',
            displayName: 'bad-box',
            state: 'failed',
            stateReason: 'env.reset failed',
          }),
        ]}
      />,
    );

    const rows = screen.getAllByRole('row').slice(1);
    expect(within(rows[0]).getByText('mac-studio')).toBeInTheDocument();
    expect(within(rows[0]).getByText('aixle-r5-ab12cd34')).toBeInTheDocument();
    expect(within(rows[0]).getByText('Idle')).toBeInTheDocument();
    expect(within(rows[0]).getByText('0.2.0')).toBeInTheDocument();
    expect(within(rows[0]).getByText('darwin/arm64')).toBeInTheDocument();
    expect(within(rows[1]).getByText('Online')).toBeInTheDocument();
    expect(within(rows[1]).getByText('linux/amd64')).toBeInTheDocument();
    expect(within(rows[2]).getByText('Offline')).toBeInTheDocument();
    expect(within(rows[2]).getByText('Never')).toBeInTheDocument();
    expect(within(rows[3]).getByText('Failed')).toBeInTheDocument();
    expect(within(rows[3]).getByText('env.reset failed')).toBeInTheDocument();
  });

  it('says so when no machine has registered', () => {
    renderAuthedPage(<RunnerMachines machines={[]} />);

    expect(screen.getByText('No machine has registered on this runner yet.')).toBeInTheDocument();
  });

  it('asks for the runner and its machines again every few seconds', () => {
    renderAuthedPage(<RunnerMachines machines={[machine()]} />);

    act(() => {
      vi.advanceTimersByTime(MACHINES_REFRESH_MS);
    });

    expect(router.reload).toHaveBeenCalledWith({ only: ['runner', 'machines'] });
  });
});
