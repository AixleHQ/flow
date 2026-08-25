import { Alert, Button, Group, Menu, Stack, Text, TextInput } from '@mantine/core';
import { modals } from '@mantine/modals';
import {
  IconAlertTriangle,
  IconArchive,
  IconChevronDown,
  IconFlag,
  IconTag,
  IconTrash,
  IconUser,
  IconX,
} from '@tabler/icons-react';

export type BulkAction = 'delete' | 'archive' | 'move_to_column' | 'set_priority' | 'set_assignee' | 'add_tag';

interface BulkColumn {
  id: number;
  name: string;
  workflowBinding: { triggerMode: string } | null;
}

interface Member {
  id: number;
  name: string;
}

export interface SelectionBarProps {
  selectedCount: number;
  selectedIds: Set<number>;
  columns: BulkColumn[];
  members: Member[];
  canExecute: boolean;
  onAction: (action: BulkAction, columnId?: number) => void;
  onBulkPriority: (priority: string | null) => void;
  onBulkAssign: (assigneeId: number | null) => void;
  onBulkTag: (tag: string) => void;
  onClear: () => void;
}

const PRIORITY_OPTIONS: { value: string | null; label: string }[] = [
  { value: 'high', label: 'High' },
  { value: 'medium', label: 'Medium' },
  { value: 'low', label: 'Low' },
  { value: null, label: 'None' },
];

function avatarInitials(name: string) {
  return name
    .split(' ')
    .map((p) => p[0])
    .join('')
    .toUpperCase()
    .slice(0, 2);
}

export function SelectionBar({
  selectedCount,
  columns,
  members,
  canExecute,
  onAction,
  onBulkPriority,
  onBulkAssign,
  onBulkTag,
  onClear,
}: SelectionBarProps) {
  if (!canExecute || selectedCount === 0) return null;

  const confirmDestructive = (action: 'delete' | 'archive') => {
    const isDelete = action === 'delete';
    modals.openConfirmModal({
      title: isDelete ? 'Delete tasks' : 'Archive tasks',
      children: (
        <Text size="sm">
          {isDelete
            ? `Delete ${selectedCount} task${selectedCount === 1 ? '' : 's'}? This cannot be undone.`
            : `Archive ${selectedCount} task${selectedCount === 1 ? '' : 's'}?`}
        </Text>
      ),
      labels: { confirm: isDelete ? 'Delete' : 'Archive', cancel: 'Cancel' },
      confirmProps: { color: isDelete ? 'red' : 'blue' },
      onConfirm: () => onAction(action),
    });
  };

  const confirmMoveToColumn = (col: BulkColumn) => {
    const triggersWorkflow = col.workflowBinding?.triggerMode === 'auto';
    modals.openConfirmModal({
      title: 'Move to column',
      children: (
        <Stack gap="xs">
          <Text size="sm">{`Move ${selectedCount} task${selectedCount === 1 ? '' : 's'} to "${col.name}"?`}</Text>
          {triggersWorkflow && (
            <Alert color="yellow" icon={<IconAlertTriangle size={16} />}>
              This will start {selectedCount} agent run{selectedCount > 1 ? 's' : ''}.
            </Alert>
          )}
        </Stack>
      ),
      labels: { confirm: 'Move', cancel: 'Cancel' },
      confirmProps: { color: 'blue' },
      onConfirm: () => onAction('move_to_column', col.id),
    });
  };

  const openTagPrompt = () => {
    let tagValue = '';
    modals.open({
      title: 'Add tag',
      children: (
        <Stack gap="sm">
          <TextInput
            label="Tag name"
            placeholder="e.g. needs-review"
            autoFocus
            onChange={(e) => {
              tagValue = e.currentTarget.value;
            }}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                const trimmed = tagValue.trim();
                if (trimmed) {
                  onBulkTag(trimmed);
                  modals.closeAll();
                }
              }
            }}
          />
          <Group justify="flex-end">
            <Button variant="default" size="xs" onClick={() => modals.closeAll()}>
              Cancel
            </Button>
            <Button
              size="xs"
              onClick={() => {
                const trimmed = tagValue.trim();
                if (trimmed) {
                  onBulkTag(trimmed);
                  modals.closeAll();
                }
              }}
            >
              Add tag
            </Button>
          </Group>
        </Stack>
      ),
    });
  };

  const btnStyle = {
    root: {
      height: 32,
      padding: '0 10px',
      fontSize: 12,
      fontWeight: 500,
      color: 'var(--app-text-secondary)',
      border: '1px solid var(--app-border-default)',
      borderRadius: 5,
      backgroundColor: 'transparent',
    },
  };

  const dangerBtnStyle = {
    root: {
      ...btnStyle.root,
      color: 'var(--mantine-color-red-6)',
    },
  };

  return (
    <Group gap={8} mb="sm" wrap="nowrap" align="center" style={{ flexShrink: 0 }}>
      {/* Count badge */}
      <Group
        gap={6}
        align="center"
        style={{
          height: 32,
          padding: '0 12px',
          borderRadius: 6,
          backgroundColor: 'color-mix(in srgb, var(--mantine-color-brand-6) 12%, transparent)',
          border: '1px solid color-mix(in srgb, var(--mantine-color-brand-6) 30%, transparent)',
          flexShrink: 0,
        }}
      >
        <Text size="xs" fw={600} c="brand">
          {selectedCount} selected
        </Text>
      </Group>

      {/* Separator */}
      <div style={{ width: 1, height: 20, backgroundColor: 'var(--app-border-default)', flexShrink: 0 }} />

      {/* Move to → */}
      <Menu shadow="md" position="bottom-start" withinPortal>
        <Menu.Target>
          <Button size="xs" variant="default" rightSection={<IconChevronDown size={11} />} styles={btnStyle}>
            Move to
          </Button>
        </Menu.Target>
        <Menu.Dropdown>
          {columns.map((col) => (
            <Menu.Item key={col.id} onClick={() => confirmMoveToColumn(col)}>
              {col.name}
              {col.workflowBinding?.triggerMode === 'auto' && (
                <Text span size="xs" c="brand" fw={600} ml={8}>
                  Runs
                </Text>
              )}
            </Menu.Item>
          ))}
        </Menu.Dropdown>
      </Menu>

      {/* Priority */}
      <Menu shadow="md" position="bottom-start" withinPortal>
        <Menu.Target>
          <Button
            size="xs"
            variant="default"
            leftSection={<IconFlag size={12} />}
            rightSection={<IconChevronDown size={11} />}
            styles={btnStyle}
          >
            Priority
          </Button>
        </Menu.Target>
        <Menu.Dropdown>
          <Menu.Label>Set priority</Menu.Label>
          {PRIORITY_OPTIONS.map(({ value, label }) => (
            <Menu.Item key={label} leftSection={<IconFlag size={13} />} onClick={() => onBulkPriority(value)}>
              {label}
            </Menu.Item>
          ))}
        </Menu.Dropdown>
      </Menu>

      {/* Assign */}
      {members.length > 0 && (
        <Menu shadow="md" position="bottom-start" withinPortal>
          <Menu.Target>
            <Button
              size="xs"
              variant="default"
              leftSection={<IconUser size={12} />}
              rightSection={<IconChevronDown size={11} />}
              styles={btnStyle}
            >
              Assign
            </Button>
          </Menu.Target>
          <Menu.Dropdown>
            <Menu.Label>Assign to</Menu.Label>
            {members.map((m) => (
              <Menu.Item key={m.id} onClick={() => onBulkAssign(m.id)}>
                <Group gap={8} align="center">
                  <div
                    style={{
                      width: 20,
                      height: 20,
                      borderRadius: '50%',
                      backgroundColor: 'color-mix(in srgb, var(--mantine-color-brand-6) 12%, transparent)',
                      border: '1px solid color-mix(in srgb, var(--mantine-color-brand-6) 30%, transparent)',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      fontSize: 9,
                      fontWeight: 700,
                      color: 'var(--mantine-color-brand-6)',
                      flexShrink: 0,
                    }}
                  >
                    {avatarInitials(m.name)}
                  </div>
                  {m.name}
                </Group>
              </Menu.Item>
            ))}
            <Menu.Divider />
            <Menu.Item leftSection={<IconUser size={13} />} onClick={() => onBulkAssign(null)}>
              Unassign
            </Menu.Item>
          </Menu.Dropdown>
        </Menu>
      )}

      {/* Add tag */}
      <Button size="xs" variant="default" leftSection={<IconTag size={12} />} styles={btnStyle} onClick={openTagPrompt}>
        Add tag
      </Button>

      {/* Archive */}
      <Button
        size="xs"
        variant="default"
        leftSection={<IconArchive size={12} />}
        styles={btnStyle}
        onClick={() => confirmDestructive('archive')}
      >
        Archive
      </Button>

      {/* Delete */}
      <Button
        size="xs"
        variant="default"
        leftSection={<IconTrash size={12} />}
        styles={dangerBtnStyle}
        onClick={() => confirmDestructive('delete')}
      >
        Delete
      </Button>

      {/* Spacer */}
      <div style={{ flex: 1 }} />

      {/* Cancel */}
      <Button
        size="xs"
        variant="subtle"
        leftSection={<IconX size={12} />}
        color="gray"
        onClick={onClear}
        aria-label="Clear selection"
      >
        Cancel
      </Button>
    </Group>
  );
}
