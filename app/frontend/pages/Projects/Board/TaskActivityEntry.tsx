import { Box, Loader, Stack, Text, UnstyledButton } from '@mantine/core';
import { IconChevronDown, IconChevronRight } from '@tabler/icons-react';
import { useState } from 'react';

import type BoardActivity from 'types/generated/BoardActivity';
import type BoardActivityDetail from 'types/generated/BoardActivityDetail';

import { apiRequest, notifyApiFailure } from 'shared/lib/apiFetch';
import { apiV1ProjectTaskActivityPath } from 'shared/routes';

import { ActivityAvatar } from './ActivityAvatar';
import { formatRelativeTime } from './boardFormat';

type Change = BoardActivityDetail['changes'][number];

const isLongText = (value: string | null) => value !== null && (value.length > 80 || value.includes('\n'));

function Empty() {
  return (
    <Text span fz={12} fs="italic" c="dimmed">
      empty
    </Text>
  );
}

function TextBlock({ label, value, tone }: { label: string; value: string | null; tone: 'red' | 'green' }) {
  return (
    <Box>
      <Text fz={11} c="dimmed" mb={2}>
        {label}
      </Text>
      <Box
        style={{
          fontSize: 12,
          whiteSpace: 'pre-wrap',
          wordBreak: 'break-word',
          maxHeight: 220,
          overflow: 'auto',
          padding: '6px 8px',
          borderRadius: 'var(--mantine-radius-sm)',
          borderLeft: `2px solid var(--mantine-color-${tone}-filled)`,
          background: `var(--mantine-color-${tone}-light)`,
        }}
      >
        {value ?? <Empty />}
      </Box>
    </Box>
  );
}

function ChangeRow({ change }: { change: Change }) {
  if (isLongText(change.before) || isLongText(change.after)) {
    return (
      <Stack gap={6}>
        <Text fz={12} fw={600}>
          {change.label}
        </Text>
        <TextBlock label="Before" value={change.before} tone="red" />
        <TextBlock label="After" value={change.after} tone="green" />
      </Stack>
    );
  }

  return (
    <Text fz={12} style={{ wordBreak: 'break-word' }}>
      <Text span fz={12} fw={600}>
        {change.label}:
      </Text>{' '}
      {change.before === null ? (
        <Empty />
      ) : (
        <Text span fz={12} c="dimmed" td="line-through">
          {change.before}
        </Text>
      )}{' '}
      →{' '}
      {change.after === null ? (
        <Empty />
      ) : (
        <Text span fz={12}>
          {change.after}
        </Text>
      )}
    </Text>
  );
}

export function TaskActivityEntry({
  activity,
  projectId,
  taskId,
}: {
  activity: BoardActivity;
  projectId: number;
  taskId: number;
}) {
  const [open, setOpen] = useState(false);
  const [changes, setChanges] = useState<Change[] | null>(null);
  const [loading, setLoading] = useState(false);
  const expandable = activity.changedFields.length > 0;

  const toggle = async () => {
    const next = !open;
    setOpen(next);
    if (!next || changes !== null) return;
    setLoading(true);
    try {
      const detail = await apiRequest<BoardActivityDetail>(
        apiV1ProjectTaskActivityPath(projectId, taskId, activity.id),
      );
      setChanges(detail.changes);
    } catch (error) {
      notifyApiFailure(error, 'Could not load the changes');
      setOpen(false);
    } finally {
      setLoading(false);
    }
  };

  const Chevron = open ? IconChevronDown : IconChevronRight;

  return (
    <Box
      style={{
        display: 'flex',
        gap: 10,
        padding: '12px 0',
        borderBottom: '1px solid rgba(41,39,38,0.6)',
      }}
    >
      <ActivityAvatar actorType={activity.actorType} actorName={activity.actorName} />
      <Box style={{ flex: 1, minWidth: 0 }}>
        <Text style={{ fontSize: 13, lineHeight: 1.5, color: 'var(--mantine-color-text)' }}>
          <strong>{activity.actorName}</strong>{' '}
          {activity.description.startsWith(activity.actorName)
            ? activity.description.slice(activity.actorName.length).trim()
            : activity.description}
        </Text>
        {expandable && (
          <UnstyledButton
            onClick={toggle}
            aria-expanded={open}
            style={{ display: 'inline-flex', alignItems: 'center', gap: 4, marginTop: 2 }}
          >
            <Chevron size={12} color="var(--mantine-color-dimmed)" />
            <Text span fz={12} c="dimmed">
              {open ? 'Hide changes' : 'Show changes'}: {activity.changedFields.join(', ')}
            </Text>
          </UnstyledButton>
        )}
        {open && (
          <Box mt={8}>
            {loading || changes === null ? (
              <Loader size="xs" />
            ) : (
              <Stack gap={10}>
                {changes.map((change) => (
                  <ChangeRow key={change.field} change={change} />
                ))}
              </Stack>
            )}
          </Box>
        )}
        <Text style={{ fontSize: 11, color: 'var(--mantine-color-placeholder)', marginTop: 2 }}>
          {formatRelativeTime(activity.createdAt)}
        </Text>
      </Box>
    </Box>
  );
}
