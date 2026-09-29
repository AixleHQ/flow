import { Group, Text } from '@mantine/core';
import { IconPointFilled } from '@tabler/icons-react';

/** Shown beside a Save button while the form holds edits the server does not have yet. */
export function UnsavedChangesNotice({ visible }: { visible: boolean }) {
  if (!visible) return null;
  return (
    <Group gap={4} role="status" wrap="nowrap">
      <IconPointFilled size={14} color="var(--app-warning-fg)" />
      <Text fz={13} c="var(--app-warning-fg)">
        Unsaved changes — press Save to keep them
      </Text>
    </Group>
  );
}
