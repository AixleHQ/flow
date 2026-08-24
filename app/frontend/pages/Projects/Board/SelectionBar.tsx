import { ActionIcon, Alert, Badge, Button, Group, Menu, Paper, Stack, Text } from '@mantine/core';
import { modals } from '@mantine/modals';
import { IconAlertTriangle, IconArchive, IconTrash, IconX } from '@tabler/icons-react';

export type BulkAction = 'delete' | 'archive' | 'move_to_column';

interface BulkColumn {
  id: number;
  name: string;
  workflowBinding: { triggerMode: string } | null;
}

interface SelectionBarProps {
  selectedCount: number;
  columns: BulkColumn[];
  canExecute: boolean;
  onAction: (action: BulkAction, columnId?: number) => void;
  onClear: () => void;
}

function actionTitle(action: BulkAction): string {
  switch (action) {
    case 'delete':
      return 'Delete tasks';
    case 'archive':
      return 'Archive tasks';
    case 'move_to_column':
      return 'Move to column';
  }
}

function actionMessage(action: BulkAction, count: number): string {
  switch (action) {
    case 'delete':
      return `Delete ${count} task${count === 1 ? '' : 's'}? This cannot be undone.`;
    case 'archive':
      return `Archive ${count} task${count === 1 ? '' : 's'}?`;
    case 'move_to_column':
      return `Move ${count} task${count === 1 ? '' : 's'} to this column?`;
  }
}

function actionLabel(action: BulkAction): string {
  switch (action) {
    case 'delete':
      return 'Delete';
    case 'archive':
      return 'Archive';
    case 'move_to_column':
      return 'Move';
  }
}

function isDestructive(action: BulkAction): boolean {
  return action === 'delete';
}

export function SelectionBar({ selectedCount, columns, canExecute, onAction, onClear }: SelectionBarProps) {
  if (!canExecute || selectedCount === 0) return null;

  const confirmBulkAction = (action: BulkAction, targetColumn?: BulkColumn) => {
    const triggersWorkflow = targetColumn?.workflowBinding?.triggerMode === 'auto';

    modals.openConfirmModal({
      title: actionTitle(action),
      children: (
        <Stack gap="xs">
          <Text size="sm">{actionMessage(action, selectedCount)}</Text>
          {triggersWorkflow && (
            <Alert color="yellow" icon={<IconAlertTriangle size={16} />}>
              This will start {selectedCount} agent run{selectedCount > 1 ? 's' : ''}.
            </Alert>
          )}
        </Stack>
      ),
      labels: { confirm: actionLabel(action), cancel: 'Cancel' },
      confirmProps: { color: isDestructive(action) ? 'red' : 'blue' },
      onConfirm: () => onAction(action, targetColumn?.id),
    });
  };

  return (
    <Paper
      withBorder
      shadow="md"
      style={{
        position: 'fixed',
        bottom: 24,
        left: '50%',
        transform: 'translateX(-50%)',
        zIndex: 200,
        padding: '10px 16px',
        display: 'flex',
        alignItems: 'center',
        gap: 12,
        backgroundColor: 'var(--app-bg-elevated)',
        borderColor: 'var(--app-border-strong)',
        borderRadius: 10,
        minWidth: 420,
      }}
    >
      <Group gap={6} style={{ flex: 1 }}>
        <Badge size="sm" variant="filled" color="blue">
          {selectedCount} selected
        </Badge>
        <ActionIcon size="xs" variant="subtle" color="gray" aria-label="Clear selection" onClick={onClear}>
          <IconX size={12} />
        </ActionIcon>
      </Group>

      <Group gap={8}>
        <Button
          size="compact-sm"
          variant="light"
          color="red"
          leftSection={<IconTrash size={13} />}
          onClick={() => confirmBulkAction('delete')}
        >
          Delete
        </Button>

        <Button
          size="compact-sm"
          variant="light"
          color="gray"
          leftSection={<IconArchive size={13} />}
          onClick={() => confirmBulkAction('archive')}
        >
          Archive
        </Button>

        <Menu shadow="md" position="top-end" withinPortal>
          <Menu.Target>
            <Button size="compact-sm" variant="light" color="blue">
              Move to column
            </Button>
          </Menu.Target>
          <Menu.Dropdown>
            {columns.map((col) => (
              <Menu.Item key={col.id} onClick={() => confirmBulkAction('move_to_column', col)}>
                {col.name}
              </Menu.Item>
            ))}
          </Menu.Dropdown>
        </Menu>
      </Group>
    </Paper>
  );
}
