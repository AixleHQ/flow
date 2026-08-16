import { router } from '@inertiajs/react';
import { Alert, Box, Button, Card, Group, Progress, Stack, Text, Title, Tooltip } from '@mantine/core';
import { IconRefresh } from '@tabler/icons-react';
import { useState } from 'react';

/** One rolling quota window as the vendor reports it. `utilization` is a percentage (0-100). */
export interface UsageWindow {
  key: string;
  utilization: number;
  resetsAt: string | null;
}

/** Pay-as-you-go spend on top of the plan. Fields stay null until something is consumed. */
export interface ExtraUsage {
  enabled: boolean;
  utilization: number | null;
  monthlyLimit: number | null;
  usedCredits: number | null;
}

export interface UsageLimitsEntry {
  agentType: string;
  status: 'ok' | 'unauthorized' | 'rate_limited' | 'unavailable';
  windows?: UsageWindow[];
  extraUsage?: ExtraUsage | null;
  fetchedAt: string;
}

// Same wording Claude Code's own /usage view uses, so the two never disagree.
const WINDOW_LABELS: Record<string, string> = {
  five_hour: 'Current session (5 hours)',
  seven_day: 'Current week (all models)',
  seven_day_opus: 'Current week (Opus)',
  seven_day_sonnet: 'Current week (Sonnet)',
};

const AGENT_LABELS: Record<string, string> = {
  claude_code: 'Claude Code',
};

const STATUS_MESSAGES: Record<Exclude<UsageLimitsEntry['status'], 'ok'>, string> = {
  unauthorized: 'Your Claude sign-in no longer works — re-authenticate above to see your limits.',
  rate_limited: 'Anthropic is throttling usage checks right now. Try again in a minute.',
  unavailable: "Couldn't reach Anthropic for usage limits.",
};

// A quota is worth noticing well before it runs out: amber from 70%, red from 90%.
function utilizationColor(utilization: number): string {
  if (utilization >= 90) return 'var(--app-danger-fg)';
  if (utilization >= 70) return 'var(--app-warning-fg)';
  return 'var(--app-success-fg)';
}

export function formatResetsIn(iso: string | null, now: number = Date.now()): string | null {
  if (!iso) return null;
  const target = new Date(iso).getTime();
  if (Number.isNaN(target)) return null;

  const minutes = Math.floor((target - now) / 60_000);
  if (minutes <= 0) return 'resets now';

  const days = Math.floor(minutes / 1440);
  const hours = Math.floor((minutes % 1440) / 60);
  if (days > 0) return `resets in ${days}d ${hours}h`;
  if (hours > 0) return `resets in ${hours}h ${minutes % 60}m`;
  return `resets in ${minutes}m`;
}

function WindowRow({ quota }: { quota: UsageWindow }) {
  const label = WINDOW_LABELS[quota.key] ?? quota.key.replace(/_/g, ' ');
  const percent = Math.min(100, Math.max(0, Math.round(quota.utilization)));
  const resets = formatResetsIn(quota.resetsAt);

  return (
    <Box>
      <Group justify="space-between" align="baseline" mb={4} gap="xs">
        <Text size="sm" fw={500}>
          {label}
        </Text>
        <Text size="sm" fw={600} c={utilizationColor(quota.utilization)}>
          {percent}%
        </Text>
      </Group>
      <Progress
        value={percent}
        color={utilizationColor(quota.utilization)}
        size="sm"
        radius="xl"
        aria-label={`${label}: ${percent}% used`}
      />
      {resets && (
        <Text size="xs" c="dimmed" mt={4}>
          {resets}
        </Text>
      )}
    </Box>
  );
}

function ExtraUsageRow({ extraUsage }: { extraUsage: ExtraUsage }) {
  const used = extraUsage.usedCredits ?? 0;
  const limit = extraUsage.monthlyLimit;

  return (
    <Box>
      <Group justify="space-between" align="baseline" mb={4} gap="xs">
        <Text size="sm" fw={500}>
          Extra usage this month
        </Text>
        <Text size="sm" fw={600}>
          {limit === null ? `${used} credits` : `${used} / ${limit} credits`}
        </Text>
      </Group>
      {extraUsage.utilization !== null && (
        <Progress
          value={Math.min(100, Math.max(0, Math.round(extraUsage.utilization)))}
          color={utilizationColor(extraUsage.utilization)}
          size="sm"
          radius="xl"
          aria-label={`Extra usage: ${Math.round(extraUsage.utilization)}% of the monthly cap`}
        />
      )}
    </Box>
  );
}

function EntryBody({ entry }: { entry: UsageLimitsEntry }) {
  if (entry.status !== 'ok') {
    return (
      <Alert color={entry.status === 'unauthorized' ? 'red' : 'yellow'} variant="light" p="sm">
        <Text size="sm">{STATUS_MESSAGES[entry.status]}</Text>
      </Alert>
    );
  }

  const windows = entry.windows ?? [];
  if (windows.length === 0) {
    return (
      <Text size="sm" c="dimmed">
        No usage recorded in the current windows yet.
      </Text>
    );
  }

  return (
    <Stack gap={16}>
      {windows.map((quota) => (
        <WindowRow key={quota.key} quota={quota} />
      ))}
      {entry.extraUsage?.enabled && <ExtraUsageRow extraUsage={entry.extraUsage} />}
    </Stack>
  );
}

/**
 * Subscription quota panel. Renders nothing when no credential on this membership
 * bills against a plan — an API key or a Bedrock connection has no window to show.
 */
export function UsageLimitsCard({ entries }: { entries: UsageLimitsEntry[] }) {
  const [refreshing, setRefreshing] = useState(false);

  if (entries.length === 0) return null;

  const handleRefresh = () => {
    setRefreshing(true);
    router.reload({
      only: ['usage_limits'],
      data: { refresh: '1' },
      onFinish: () => setRefreshing(false),
    });
  };

  return (
    <Card p={24}>
      <Group justify="space-between" align="flex-start" mb={4} gap="xs" wrap="nowrap">
        <Box>
          <Title order={5} mb={4}>
            Usage limits
          </Title>
          <Text size="sm" c="dimmed">
            How much of your subscription&apos;s rolling quotas this sign-in has used. Limits belong to the Anthropic
            account, not to this company.
          </Text>
        </Box>
        <Tooltip label="Check again (throttled to protect the vendor limit)">
          <Button variant="subtle" size="xs" px={8} loading={refreshing} onClick={handleRefresh} aria-label="Refresh">
            <IconRefresh size={16} />
          </Button>
        </Tooltip>
      </Group>

      <Stack gap={20} mt="md">
        {entries.map((entry) => (
          <Box key={entry.agentType}>
            {entries.length > 1 && (
              <Text size="xs" fw={600} c="dimmed" tt="uppercase" mb={8}>
                {AGENT_LABELS[entry.agentType] ?? entry.agentType.replace(/_/g, ' ')}
              </Text>
            )}
            <EntryBody entry={entry} />
          </Box>
        ))}
      </Stack>
    </Card>
  );
}

export default UsageLimitsCard;
