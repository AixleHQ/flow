import { Button, Group, Text } from '@mantine/core';
import { IconFolderShare, IconTrash, IconX } from '@tabler/icons-react';

export interface AssetsSelectionBarProps {
  count: number;
  submitting: boolean;
  onMove: () => void;
  onDelete: () => void;
  onExit: () => void;
}

/** Shown in place of the search/view toolbar while bulk-selection is armed. Adapted from the
 * Board's `SelectionBar` (`pages/Projects/Board/SelectionBar.tsx`), scaled down to the two actions
 * assets support in bulk: Move and Delete. */
export function AssetsSelectionBar({ count, submitting, onMove, onDelete, onExit }: AssetsSelectionBarProps) {
  return (
    <Group
      justify="space-between"
      mb="sm"
      p="xs"
      style={{
        border: '1px solid var(--app-border-default)',
        borderRadius: 8,
        background: 'var(--app-bg-elevated)',
      }}
    >
      <Text size="sm" fw={500} pl={4}>
        {count} selected
      </Text>
      <Group gap="xs" role="group" aria-label="Bulk actions">
        <Button
          variant="default"
          size="xs"
          leftSection={<IconFolderShare size={14} />}
          disabled={count === 0 || submitting}
          onClick={onMove}
        >
          Move
        </Button>
        <Button
          variant="default"
          color="red"
          size="xs"
          leftSection={<IconTrash size={14} />}
          disabled={count === 0 || submitting}
          onClick={onDelete}
        >
          Delete
        </Button>
        <Button variant="subtle" size="xs" leftSection={<IconX size={14} />} onClick={onExit}>
          Cancel
        </Button>
      </Group>
    </Group>
  );
}
