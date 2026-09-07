import { Badge, Table, Text, Tooltip } from '@mantine/core';

import { formatDateTime } from '@/shared/lib/formatDate';
function formatCallCost(cents: number): string {
  const d = (cents ?? 0) / 100;
  if (d >= 1) return `$${d.toFixed(2)}`;
  return `$${d.toFixed(3)}`;
}
import type LlmCall from '@/types/generated/LlmCall';

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
              <Text size="sm">{call.inputTokens.toLocaleString()}</Text>
            </Table.Td>
            <Table.Td ta="right">
              <Text size="sm">{call.outputTokens.toLocaleString()}</Text>
            </Table.Td>
            <Table.Td ta="right">
              <Tooltip
                label={`Read: ${call.cacheReadTokens.toLocaleString()} · Write: ${call.cacheWriteTokens.toLocaleString()}`}
              >
                <Text size="sm">{(call.cacheReadTokens + call.cacheWriteTokens).toLocaleString()}</Text>
              </Tooltip>
            </Table.Td>
            <Table.Td ta="right">
              <Text size="sm">{formatCallCost(call.costCents)}</Text>
            </Table.Td>
          </Table.Tr>
        ))}
      </Table.Tbody>
    </Table>
  );
}
