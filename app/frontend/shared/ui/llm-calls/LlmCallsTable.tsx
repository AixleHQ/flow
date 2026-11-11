import { Badge, Table, Text, Tooltip } from '@mantine/core';

import { formatDateTime } from '@/shared/lib/formatDate';
import type LlmCall from '@/types/generated/LlmCall';

const COST_BASIS_LABELS: Record<LlmCall['costBasis'], string> = {
  reported: 'Reported by the runtime',
  priced: 'Estimate from the vendor’s list price, not a bill',
  credits: 'Credits converted at the configured rate',
  unknown: 'Cost unknown',
};

function formatCallCost(cents: number | null): string {
  if (cents === null) return '—';
  const d = cents / 100;
  if (d >= 1) return `$${d.toFixed(2)}`;
  return `$${d.toFixed(3)}`;
}

function formatTokens(count: number | null): string {
  return count === null ? '—' : count.toLocaleString();
}

function cacheTokens(call: LlmCall): number | null {
  if (call.cacheReadTokens === null && call.cacheWriteTokens === null) return null;
  return (call.cacheReadTokens ?? 0) + (call.cacheWriteTokens ?? 0);
}

interface Props {
  calls: LlmCall[];
  showSessionColumn: boolean;
}

export default function LlmCallsTable({ calls, showSessionColumn }: Props) {
  if (calls.length === 0) {
    return (
      <Text c="dimmed" ta="center" py="xl">
        No LLM calls recorded
      </Text>
    );
  }

  return (
    <Table striped highlightOnHover>
      <Table.Thead>
        <Table.Tr>
          <Table.Th>Time</Table.Th>
          {showSessionColumn && <Table.Th>Session</Table.Th>}
          <Table.Th>Model</Table.Th>
          <Table.Th ta="right">Input tokens</Table.Th>
          <Table.Th ta="right">Output tokens</Table.Th>
          <Table.Th ta="right">Cache tokens</Table.Th>
          <Table.Th ta="right">Cost</Table.Th>
        </Table.Tr>
      </Table.Thead>
      <Table.Tbody>
        {calls.map((call) => (
          <Table.Tr key={call.id}>
            <Table.Td>
              <Tooltip label={call.occurredAt}>
                <Text size="sm">{formatDateTime(call.occurredAt)}</Text>
              </Tooltip>
            </Table.Td>
            {showSessionColumn && (
              <Table.Td>
                <Text size="sm">{call.stepName ?? '—'}</Text>
              </Table.Td>
            )}
            <Table.Td>
              <Badge variant="light" size="sm">
                {call.model}
              </Badge>
            </Table.Td>
            <Table.Td ta="right">
              <Text size="sm">{formatTokens(call.inputTokens)}</Text>
            </Table.Td>
            <Table.Td ta="right">
              <Text size="sm">{formatTokens(call.outputTokens)}</Text>
            </Table.Td>
            <Table.Td ta="right">
              <Tooltip
                label={`Read: ${formatTokens(call.cacheReadTokens)} · Write: ${formatTokens(call.cacheWriteTokens)}`}
              >
                <Text size="sm">{formatTokens(cacheTokens(call))}</Text>
              </Tooltip>
            </Table.Td>
            <Table.Td ta="right">
              <Tooltip label={COST_BASIS_LABELS[call.costBasis]}>
                <Text size="sm">{formatCallCost(call.costCents)}</Text>
              </Tooltip>
            </Table.Td>
          </Table.Tr>
        ))}
      </Table.Tbody>
    </Table>
  );
}
