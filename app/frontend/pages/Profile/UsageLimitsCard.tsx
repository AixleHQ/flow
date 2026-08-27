import { router } from '@inertiajs/react';
import { Alert, Box, Button, Card, Group, Progress, Stack, Text, Title, Tooltip } from '@mantine/core';
import { IconRefresh } from '@tabler/icons-react';
import { useState } from 'react';

/** One rolling quota window as the vendor reports it. `utilization` is a percentage (0-100). */
interface UsageWindow {
  key: string;
  utilization: number;
  resetsAt: string | null;
  windowDurationMins?: number | null;
}

/** Pay-as-you-go spend on top of the plan. Fields stay null until something is consumed. */
interface ExtraUsage {
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
  codex: 'OpenAI Codex',
};

const VENDOR_LABELS: Record<string, string> = {
  claude_code: 'Anthropic',
  codex: 'OpenAI',
};

function statusMessage(entry: UsageLimitsEntry): string {
  const vendor = VENDOR_LABELS[entry.agentType] ?? 'The provider';
  if (entry.status === 'unauthorized') return `Your ${AGENT_LABELS[entry.agentType] ?? entry.agentType} sign-in no longer works — re-authenticate above to see your limits.`;
  if (entry.status === 'rate_limited') return `${vendor} is throttling usage checks right now. Try again in a minute.`;
  return `Couldn't reach ${vendor} for usage limits.`;
}

function durationLabel(minutes?: number | null): string | null {
  if (!minutes) return null;
  if (minutes % 10_080 === 0) return `${minutes / 10_080} week${minutes === 10_080 ? '' : 's'}`;
  if (minutes % 1_440 === 0) return `${minutes / 1_440} day${minutes === 1_440 ? '' : 's'}`;
  if (minutes % 60 === 0) return `${minutes / 60} hour${minutes === 60 ? '' : 's'}`;
  return `${minutes} minutes`;
}

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
  const duration = durationLabel(quota.windowDurationMins);
  const label = WINDOW_LABELS[quota.key] ?? (duration ? `Usage window (${duration})` : quota.key.replace(/_/g, ' '));
  const percent = Math.min(100, Math.max(0, Math.round(quota.utilization)));
  const remaining = 100 - percent;
  const resets = formatResetsIn(quota.resetsAt);

  return (
    <Box>
      <Group justify="space-between" align="baseline" mb={4} gap="xs">
        <Text size="sm" fw={500}>
          {label}
        </Text>
        <Text size="sm" fw={600} c={utilizationColor(quota.utilization)}>
          {percent}% used · {remaining}% remaining
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
        <Text size="sm">{statusMessage(entry)}</Text>
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
            Usage and remaining allowance for each connected runtime subscription. Limits belong to the provider
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
