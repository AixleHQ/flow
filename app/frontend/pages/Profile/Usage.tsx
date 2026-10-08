import { Deferred, Head, router, usePage } from '@inertiajs/react';
import { Badge, Box, Divider, Group, Paper, Skeleton, Table, Text, Title, Tooltip } from '@mantine/core';
import { formatDistanceToNow } from 'date-fns';

import type { TerminalSession } from '@/types/generated';
import { AuthLayout } from 'layouts/AuthLayout';

import { type Period, type PeriodWindow, periodParams } from 'shared/analytics/chartHelpers';
import { PeriodFilter } from 'shared/analytics/PeriodFilter';
import { formatTokens } from 'shared/lib/formatUsage';
import { UsageAnalytics } from 'shared/resources/usage/UsageAnalytics';
import { type SharedProps } from 'shared/ui';
import { AGENT_RUNTIMES, agentLabel, isAgentType } from 'shared/ui/agentRuntimes';
import { StatusBadge } from 'shared/ui/StatusBadge';

import { ProfileTabs } from './ProfileTabs';

interface Props {
  period: Period;
  from: string;
  to: string;
  projectId?: string | null;
  sessions?: TerminalSession[];
}

const STATE_CONFIG: Record<string, { label: string }> = {
  not_started: { label: 'Pending' },
  queued: { label: 'Queued' },
  cancelled: { label: 'Cancelled' },
  running: { label: 'Starting' },
  ready: { label: 'Running' },
  finishing: { label: 'Finishing' },
  finished: { label: 'Finished' },
  failed: { label: 'Failed' },
};

const SESSION_TYPE_LABELS: Record<string, string> = {
  agent_session: 'Standalone',
  workflow_step: 'Workflow step',
  auth_setup: 'Auth setup',
  tool_setup: 'Tool setup',
};

function sessionTokenFmt(n: number): string {
  if (!n || n === 0) return '—';
  return formatTokens(n);
}

function SessionsPanel() {
  const { sessions } = usePage<{ props: Props }>().props as unknown as Props;
  if (!sessions) return null;

  return (
    <Paper withBorder p={24} radius="md">
      <Title order={4} mb={4}>
        Sessions
      </Title>
      <Divider mb="md" />
      {sessions.length === 0 ? (
        <Box py="xl" ta="center">
          <Text c="dimmed">No sessions yet</Text>
        </Box>
      ) : (
        <Table.ScrollContainer minWidth={800}>
          <Table striped highlightOnHover verticalSpacing={6} fz="sm">
            <Table.Thead>
              <Table.Tr>
                <Table.Th>ID</Table.Th>
                <Table.Th>Agent</Table.Th>
                <Table.Th>Type</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Project</Table.Th>
                <Table.Th ta="right">Tokens</Table.Th>
                <Table.Th ta="right">Cost</Table.Th>
                <Table.Th>Started</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {sessions.map((s) => {
                const agentColor = isAgentType(s.agentType) ? AGENT_RUNTIMES[s.agentType].mantineColor : 'gray';
                const stateConfig = STATE_CONFIG[s.state] ?? { label: s.state };
                const typeLabel = SESSION_TYPE_LABELS[s.sessionType] ?? s.sessionType;
                return (
                  <Table.Tr key={s.id}>
                    <Table.Td>
                      <Text size="xs" ff="monospace" c="dimmed">
                        #{s.id}
                      </Text>
                    </Table.Td>
                    <Table.Td>
                      <Badge color={agentColor} size="sm" variant="filled">
                        {agentLabel(s.agentType)}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      <Text size="xs" c="dimmed">
                        {typeLabel}
                      </Text>
                    </Table.Td>
                    <Table.Td>
                      <StatusBadge state={s.state} tone={s.state === 'ready' ? 'running' : undefined} size="sm">
                        {stateConfig.label}
                      </StatusBadge>
                    </Table.Td>
                    <Table.Td>
                      <Text size="sm" truncate maw={120} c="dimmed">
                        {s.projectName ?? '—'}
                      </Text>
                    </Table.Td>
                    <Table.Td ta="right">
                      <Text size="xs" ff="monospace">
                        {sessionTokenFmt(s.totalTokens)}
                      </Text>
                    </Table.Td>
                    <Table.Td ta="right">
                      <Text size="xs" ff="monospace" fw={s.costCents > 0 ? 600 : 400}>
                        {s.costCents > 0 ? `$${(s.costCents / 100).toFixed(2)}` : '—'}
                      </Text>
                    </Table.Td>
                    <Table.Td>
                      <Tooltip label={s.startedAt ? new Date(s.startedAt).toLocaleString() : s.createdAt}>
                        <Text size="xs" c="dimmed" style={{ whiteSpace: 'nowrap' }}>
                          {formatDistanceToNow(new Date(s.startedAt ?? s.createdAt), { addSuffix: true })}
                        </Text>
                      </Tooltip>
                    </Table.Td>
                  </Table.Tr>
                );
              })}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}
    </Paper>
  );
}

// --- Main page ---

const UsagePage = () => {
  const { period, from, to } = usePage<{ props: Props }>().props as unknown as Props;
  // Shared props (not this page's Props): only label the company when the user
  // actually belongs to more than one, so single-company users see no change.
  const { currentUser } = usePage<SharedProps>().props;
  const companyName = (currentUser?.memberships?.length ?? 0) > 1 ? currentUser?.currentCompany?.name : null;

  const navigate = (next: PeriodWindow) => {
    router.get(window.location.pathname, periodParams(next), { preserveState: true, preserveScroll: true });
  };

  return (
    <AuthLayout>
      <Head title="Usage" />

      {/* Matches the Account tab's content width so the two tabs don't jump
          width when switching between them. */}
      <Box maw={1120} mx="auto">
        <Title order={1} fz={28} fw={600} c="var(--app-text-primary)" mb={4}>
          My Profile
        </Title>
        <Text size="sm" c="dimmed" mb={24}>
          {/* Usage is always a CURRENT-COMPANY slice (see ProfileController#usage).
              For someone who belongs to several companies, an unlabelled total
              reads as "everything", so name the company being shown. */}
          Cross-project agent activity, costs, and sessions
          {companyName ? ` in ${companyName}` : ''}.
        </Text>

        <ProfileTabs active="usage" />

        <Group justify="flex-end" mb="xl">
          <PeriodFilter period={period} from={from} to={to} onChange={navigate} />
        </Group>

        <UsageAnalytics from={from} to={to} />

        {/* Sessions list */}
        <Deferred data="sessions" fallback={<Skeleton height={200} radius="sm" />}>
          <SessionsPanel />
        </Deferred>
      </Box>
    </AuthLayout>
  );
};

export default UsagePage;
