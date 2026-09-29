import { Badge, Box, Group, Stack, Text } from '@mantine/core';
import type { ReactNode } from 'react';

import type { Change, DiffLine, ItemChange, RefItem } from 'shared/lib/versionDiff';

/** Unchanged lines kept around each change; longer unchanged runs fold into a count. */
const CONTEXT_LINES = 2;

const STATUS_COLORS: Record<ItemChange['status'] | 'added' | 'removed' | 'changed', string> = {
  added: 'green',
  removed: 'red',
  changed: 'blue',
  moved: 'gray',
};

function formatValue(value: unknown): string {
  if (value === null || value === undefined || value === '') return '—';
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  return typeof value === 'string' ? value : JSON.stringify(value);
}

function foldContext(lines: DiffLine[]): (DiffLine | { type: 'fold'; count: number })[] {
  const keep = lines.map(
    (line, index) =>
      line.type !== 'same' ||
      lines.slice(Math.max(0, index - CONTEXT_LINES), index + CONTEXT_LINES + 1).some((l) => l.type !== 'same'),
  );
  const out: (DiffLine | { type: 'fold'; count: number })[] = [];
  lines.forEach((line, index) => {
    if (keep[index]) {
      out.push(line);
      return;
    }
    const last = out[out.length - 1];
    if (last && last.type === 'fold') last.count += 1;
    else out.push({ type: 'fold', count: 1 });
  });
  return out;
}

const LINE_STYLES: Record<DiffLine['type'], { bg: string; fg: string; sign: string }> = {
  added: { bg: 'var(--app-success-bg)', fg: 'var(--app-success-fg)', sign: '+' },
  removed: { bg: 'var(--app-danger-bg)', fg: 'var(--app-danger-fg)', sign: '−' },
  same: { bg: 'transparent', fg: 'var(--app-text-secondary)', sign: ' ' },
};

export function TextDiff({ lines }: { lines: DiffLine[] | null }) {
  if (lines === null) {
    return (
      <Text fz={13} c="dimmed">
        Changed — too large to show line by line.
      </Text>
    );
  }
  return (
    <Box
      component="pre"
      m={0}
      style={{
        fontFamily: 'var(--app-font-mono)',
        fontSize: 12,
        lineHeight: 1.5,
        border: '1px solid var(--app-border-default)',
        borderRadius: 'var(--mantine-radius-sm)',
        overflowX: 'auto',
        whiteSpace: 'pre-wrap',
        wordBreak: 'break-word',
      }}
    >
      {foldContext(lines).map((line, index) =>
        line.type === 'fold' ? (
          <Box key={index} px="xs" c="dimmed" style={{ background: 'var(--app-bg-deep)' }}>
            … {line.count} unchanged {line.count === 1 ? 'line' : 'lines'}
          </Box>
        ) : (
          <Box
            key={index}
            px="xs"
            style={{ background: LINE_STYLES[line.type].bg, color: LINE_STYLES[line.type].fg }}
            aria-label={line.type === 'same' ? undefined : `${line.type}: ${line.text}`}
          >
            {LINE_STYLES[line.type].sign} {line.text}
          </Box>
        ),
      )}
    </Box>
  );
}

function RefBadge({ item, color }: { item: RefItem; color: string }) {
  const suffix = item.missing ? ' (deleted)' : item.archived ? ' (archived)' : '';
  return (
    <Badge color={color} variant="light" tt="none">
      {item.name}
      {suffix}
    </Badge>
  );
}

function Section({ label, children }: { label: string; children: ReactNode }) {
  return (
    <Box>
      <Text fz={12} fw={600} c="var(--app-text-secondary)" mb={4} tt="uppercase">
        {label}
      </Text>
      {children}
    </Box>
  );
}

function ChangeView({ change }: { change: Change }) {
  switch (change.kind) {
    case 'scalar':
      return (
        <Section label={change.label}>
          <Group gap={6} wrap="wrap">
            <Text fz={13} c="var(--app-danger-fg)" td="line-through">
              {formatValue(change.before)}
            </Text>
            <Text fz={13} c="dimmed">
              →
            </Text>
            <Text fz={13} c="var(--app-success-fg)">
              {formatValue(change.after)}
            </Text>
          </Group>
        </Section>
      );
    case 'text':
      return (
        <Section label={change.label}>
          <TextDiff lines={change.lines} />
        </Section>
      );
    case 'list':
      return (
        <Section label={change.label}>
          <Group gap={6}>
            {change.added.map((value) => (
              <Badge key={`+${value}`} color="green" variant="light" tt="none">
                + {value}
              </Badge>
            ))}
            {change.removed.map((value) => (
              <Badge key={`-${value}`} color="red" variant="light" tt="none">
                − {value}
              </Badge>
            ))}
            {change.added.length === 0 && change.removed.length === 0 && (
              <Text fz={13} c="dimmed">
                Reordered
              </Text>
            )}
          </Group>
        </Section>
      );
    case 'refs':
      return (
        <Section label={change.label}>
          <Stack gap={4}>
            {change.added.length > 0 && (
              <Group gap={6}>
                <Text fz={12} c="dimmed" w={60}>
                  Added
                </Text>
                {change.added.map((item) => (
                  <RefBadge key={item.id} item={item} color="green" />
                ))}
              </Group>
            )}
            {change.removed.length > 0 && (
              <Group gap={6}>
                <Text fz={12} c="dimmed" w={60}>
                  Removed
                </Text>
                {change.removed.map((item) => (
                  <RefBadge key={item.id} item={item} color="red" />
                ))}
              </Group>
            )}
          </Stack>
        </Section>
      );
    case 'entries':
      return (
        <Section label={change.label}>
          <Stack gap={6}>
            {change.entries.map((entry) => (
              <Box key={entry.name}>
                <Group gap={6}>
                  <Badge color={STATUS_COLORS[entry.status]} variant="light" size="sm">
                    {entry.status}
                  </Badge>
                  <Text fz={13} ff="var(--app-font-mono)">
                    {entry.name}
                  </Text>
                </Group>
                {entry.lines !== undefined && (
                  <Box mt={4}>
                    <TextDiff lines={entry.lines} />
                  </Box>
                )}
              </Box>
            ))}
          </Stack>
        </Section>
      );
    case 'collection':
      return (
        <Section label={change.label}>
          <Stack gap="sm">
            {change.items.map((item, index) => (
              <Box
                key={`${item.label}-${index}`}
                p="sm"
                style={{ border: '1px solid var(--app-border-default)', borderRadius: 'var(--mantine-radius-sm)' }}
              >
                <Group gap={6} mb={item.changes.length ? 'xs' : 0}>
                  <Badge color={STATUS_COLORS[item.status]} variant="light" size="sm">
                    {item.status}
                  </Badge>
                  <Text fz={14} fw={500}>
                    {item.label}
                  </Text>
                </Group>
                {item.changes.length > 0 && <VersionDiff changes={item.changes} />}
              </Box>
            ))}
          </Stack>
        </Section>
      );
  }
}

/** The changes between two versions, as computed by diffSnapshots. */
export function VersionDiff({ changes }: { changes: Change[] }) {
  if (changes.length === 0) {
    return (
      <Text fz={13} c="dimmed">
        No differences.
      </Text>
    );
  }
  return (
    <Stack gap="md">
      {changes.map((change, index) => (
        <ChangeView key={`${change.label}-${index}`} change={change} />
      ))}
    </Stack>
  );
}
