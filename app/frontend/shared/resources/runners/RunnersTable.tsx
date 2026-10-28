import { Link } from '@inertiajs/react';
import { Anchor, Group, Table, Text } from '@mantine/core';

import type { Runner } from '@/types/generated';

import { formatDateTime } from 'shared/lib/formatDate';
import { ResourceTableShell, ResourceTh } from 'shared/ui/ResourceTable';
import { StatusBadge } from 'shared/ui/StatusBadge';

import { runnerTypeTitle } from './runnerCopy';

export const lastSeen = (runner: Pick<Runner, 'lastSeenAt'>): string =>
  runner.lastSeenAt ? formatDateTime(runner.lastSeenAt) : 'Never';

/** A runner's status pill with the reason the server recorded for it, if any. */
export function RunnerStatus({ runner }: { runner: Pick<Runner, 'status' | 'statusReason'> }) {
  return (
    <Group gap={8} wrap="nowrap">
      <StatusBadge state={runner.status} />
      {runner.statusReason && (
        <Text fz="sm" c="dimmed" lineClamp={1}>
          {runner.statusReason}
        </Text>
      )}
    </Group>
  );
}

export function RunnersTable({ runners, pathFor }: { runners: Runner[]; pathFor: (runner: Runner) => string }) {
  return (
    <ResourceTableShell>
      <Table verticalSpacing="sm" horizontalSpacing="md">
        <Table.Thead>
          <Table.Tr>
            <ResourceTh>Name</ResourceTh>
            <ResourceTh>Type</ResourceTh>
            <ResourceTh>Status</ResourceTh>
            <ResourceTh>Last seen</ResourceTh>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {runners.map((runner) => (
            <Table.Tr key={runner.id}>
              <Table.Td>
                <Anchor component={Link} href={pathFor(runner)} fz="sm" fw={500}>
                  {runner.name}
                </Anchor>
              </Table.Td>
              <Table.Td>
                <Text fz="sm">{runnerTypeTitle(runner.runnerType)}</Text>
              </Table.Td>
              <Table.Td>
                <RunnerStatus runner={runner} />
              </Table.Td>
              <Table.Td>
                <Text fz="sm" c="dimmed">
                  {lastSeen(runner)}
                </Text>
              </Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </ResourceTableShell>
  );
}
