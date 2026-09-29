import { useSortable } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { ActionIcon, Box, Group, Paper, Text, TextInput } from '@mantine/core';
import { IconGripVertical, IconTrash } from '@tabler/icons-react';

import type { ColState } from './types';

export function SortableColumnRow({
  col,
  idx,
  updateCol,
  removeColumn,
}: {
  col: ColState;
  idx: number;
  updateCol: (idx: number, field: keyof ColState, value: string | number | null) => void;
  removeColumn: (idx: number) => void;
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: col.id ? `col-${col.id}` : `col-new-${idx}`,
  });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  };

  return (
    <Paper ref={setNodeRef} style={style} p="sm" radius="sm" withBorder>
      <Group gap="sm" mb="xs">
        <Box {...attributes} {...listeners} style={{ cursor: 'grab', touchAction: 'none' }}>
          <IconGripVertical size={14} color="var(--mantine-color-dimmed)" />
        </Box>
        <TextInput
          placeholder="Column name"
          value={col.name}
          onChange={(e) => updateCol(idx, 'name', e.currentTarget.value)}
          style={{ flex: 1 }}
          size="sm"
        />
        <ActionIcon variant="subtle" color="red" size="sm" onClick={() => removeColumn(idx)}>
          <IconTrash size={14} />
        </ActionIcon>
      </Group>
      <TextInput
        placeholder="Purpose (optional)"
        value={col.purpose}
        onChange={(e) => updateCol(idx, 'purpose', e.currentTarget.value)}
        size="xs"
        mb="xs"
      />
      <Text size="xs" c="dimmed">
        Triggers (incl. “task enters this column”) are configured per workflow — open a workflow and use the{' '}
        <b>Triggers</b> button.
      </Text>
    </Paper>
  );
}
