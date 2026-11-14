import { router } from '@inertiajs/react';
import { Button, Code, Stack, Table, Text } from '@mantine/core';
import { useEffect, useState } from 'react';

import type { Runner, RunnerMachine } from '@/types/generated';

import { formatDateTime } from 'shared/lib/formatDate';
import { StatusBadge } from 'shared/ui/StatusBadge';

import type { RunnerPaths } from './runnerConfig';

/** How often the page asks for the machines again: a little above the platform's 15 s heartbeat write. */
export const MACHINES_REFRESH_MS = 15_000;

const STATE_HINT: Record<RunnerMachine['state'], string> = {
  online: 'Running a session',
  idle: 'Connected, no session',
  offline: 'Not heard from for 90 seconds',
  resetting: 'Being reset; takes no session until it succeeds',
  failed: 'Out of rotation',
  gone: 'Unregistered',
};

const platform = (machine: Pick<RunnerMachine, 'os' | 'arch'>): string =>
  [machine.os, machine.arch].filter(Boolean).join('/') || '—';

/** Why a machine failed (§8), as recorded: no mark is added, so a reason that ends in `?` or `.` keeps its own. */
const failedReason = (machine: RunnerMachine): string =>
  machine.stateReason ?? `${machine.displayName ?? machine.key} failed`;

const FAILED_ACTION = 'Fix the machine and press Return to service.';

interface RunnerMachinesProps {
  machines: RunnerMachine[];
  runner: Pick<Runner, 'id'>;
  paths: Pick<RunnerPaths, 'returnToService'>;
  /** Who may press Return to service: the policy that guards update and revoke. */
  canManage: boolean;
}

/**
 * The machines of a `manual` runner (DESIGN.md §2.5, §11). A machine's state and last seen change
 * while the page is open, so it asks for the runner and its machines again every MACHINES_REFRESH_MS
 * while the tab is visible. A `failed` machine has Return to service, which resets it (§5.2).
 */
export function RunnerMachines({ machines, runner, paths, canManage }: RunnerMachinesProps) {
  const [returning, setReturning] = useState<number | null>(null);

  const returnToService = (machine: RunnerMachine) => {
    setReturning(machine.id);
    router.post(
      paths.returnToService(runner.id, machine.id),
      {},
      { preserveScroll: true, onFinish: () => setReturning(null) },
    );
  };

  useEffect(() => {
    const timer = window.setInterval(() => {
      if (!document.hidden) router.reload({ only: ['runner', 'machines'] });
    }, MACHINES_REFRESH_MS);
    return () => window.clearInterval(timer);
  }, []);

  if (machines.length === 0) {
    return (
      <Text fz="sm" c="dimmed">
        No machine has registered on this runner yet.
      </Text>
    );
  }

  return (
    <Table withTableBorder verticalSpacing="xs" aria-label="Machines">
      <Table.Thead>
        <Table.Tr>
          <Table.Th>Machine</Table.Th>
          <Table.Th>State</Table.Th>
          <Table.Th>Version</Table.Th>
          <Table.Th>OS / arch</Table.Th>
          <Table.Th>Registered</Table.Th>
          <Table.Th>Last seen</Table.Th>
          {canManage && <Table.Th aria-label="Actions" />}
        </Table.Tr>
      </Table.Thead>
      <Table.Tbody>
        {machines.map((machine) => (
          <Table.Tr key={machine.id}>
            <Table.Td>
              <Stack gap={2}>
                <Text fz="sm" fw={500}>
                  {machine.displayName ?? machine.key}
                </Text>
                <Code fz="xs">{machine.key}</Code>
              </Stack>
            </Table.Td>
            <Table.Td>
              <Stack gap={2} align="flex-start">
                <StatusBadge state={machine.state} />
                {machine.state === 'failed' ? (
                  <>
                    <Text fz="xs" c="dimmed">
                      {failedReason(machine)}
                    </Text>
                    <Text fz="xs" c="dimmed">
                      {FAILED_ACTION}
                    </Text>
                  </>
                ) : (
                  <Text fz="xs" c="dimmed">
                    {STATE_HINT[machine.state]}
                  </Text>
                )}
              </Stack>
            </Table.Td>
            <Table.Td>
              <Text fz="sm">{machine.runnerVersion ?? '—'}</Text>
            </Table.Td>
            <Table.Td>
              <Text fz="sm">{platform(machine)}</Text>
            </Table.Td>
            <Table.Td>
              <Text fz="sm">{formatDateTime(machine.createdAt)}</Text>
            </Table.Td>
            <Table.Td>
              <Text fz="sm">{machine.lastHeartbeatAt ? formatDateTime(machine.lastHeartbeatAt) : 'Never'}</Text>
            </Table.Td>
            {canManage && (
              <Table.Td>
                {machine.state === 'failed' && (
                  <Button
                    size="xs"
                    variant="default"
                    loading={returning === machine.id}
                    onClick={() => returnToService(machine)}
                  >
                    Return to service
                  </Button>
                )}
              </Table.Td>
            )}
          </Table.Tr>
        ))}
      </Table.Tbody>
    </Table>
  );
}
