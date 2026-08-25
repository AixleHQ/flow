import { Alert, Button, Group, Menu, Stack, Text, TextInput } from '@mantine/core';
import { modals } from '@mantine/modals';
import {
  IconAlertTriangle,
  IconArchive,
  IconArrowRight,
  IconBolt,
  IconCheckbox,
  IconChevronDown,
  IconColumns,
  IconFlag,
  IconTag,
  IconTrash,
  IconUser,
  IconUserOff,
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

// Matches .pop from the reference HTML
const menuStyles = {
  dropdown: {
    background: 'var(--app-bg-elevated)',
    border: '1px solid var(--app-border-strong)',
    borderRadius: 8,
    padding: 4,
    minWidth: 220,
    boxShadow: '0 8px 32px rgba(0,0,0,0.5)',
  },
  // Matches .pop-head
  label: {
    fontSize: 10,
    letterSpacing: '0.08em',
    textTransform: 'uppercase' as const,
    color: 'var(--mantine-color-dimmed)',
    fontWeight: 600,
    padding: '7px 10px 4px',
  },
  // Matches .pop-item
  item: {
    padding: '7px 10px',
    borderRadius: 5,
    fontSize: 13,
    color: 'var(--app-text-secondary)',
  },
  // Matches .pop-div
  divider: {
    borderColor: 'var(--app-border-default)',
    margin: '3px 0',
  },
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
            data-autofocus
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

  return (
    <Group gap={8} mb="sm" wrap="nowrap" align="center" style={{ flexShrink: 0 }}>
      {/* Count badge — matches .sb-count */}
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
        <IconCheckbox size={14} color="var(--mantine-color-brand-6)" />
        <Text size="xs" fw={600} c="brand">
          {selectedCount} selected
        </Text>
      </Group>

      {/* Separator — matches .sb-sep */}
      <div style={{ width: 1, height: 20, backgroundColor: 'var(--app-border-default)', flexShrink: 0 }} />

      {/* Move to — items match .pop-item with ti-columns icon + auto-flag on right */}
      <Menu shadow="md" position="bottom-start" withinPortal styles={menuStyles}>
        <Menu.Target>
          <Button
            size="xs"
            variant="default"
            leftSection={<IconArrowRight size={12} />}
            rightSection={<IconChevronDown size={11} />}
            styles={btnStyle}
          >
            Move to
          </Button>
        </Menu.Target>
        <Menu.Dropdown>
          <Menu.Label>
            Move {selectedCount} task{selectedCount === 1 ? '' : 's'} to
          </Menu.Label>
          {columns.map((col) => (
            <Menu.Item
              key={col.id}
              leftSection={<IconColumns size={13} color="var(--mantine-color-dimmed)" />}
              rightSection={
                col.workflowBinding?.triggerMode === 'auto' ? (
                  <Group gap={3} align="center" wrap="nowrap">
                    <IconBolt size={11} color="var(--mantine-color-brand-6)" />
                    <Text size="xs" fw={600} c="brand" style={{ letterSpacing: '0.03em' }}>
                      Runs
                    </Text>
                  </Group>
                ) : undefined
              }
              onClick={() => confirmMoveToColumn(col)}
            >
              {col.name}
            </Menu.Item>
          ))}
        </Menu.Dropdown>
      </Menu>

      {/* Priority */}
      <Menu shadow="md" position="bottom-start" withinPortal styles={menuStyles}>
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
            <Menu.Item
              key={label}
              leftSection={<IconFlag size={13} color="var(--mantine-color-dimmed)" />}
              onClick={() => onBulkPriority(value)}
            >
              {label}
            </Menu.Item>
          ))}
        </Menu.Dropdown>
      </Menu>

      {/* Assign */}
      {members.length > 0 && (
        <Menu shadow="md" position="bottom-start" withinPortal styles={menuStyles}>
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
              <Menu.Item
                key={m.id}
                leftSection={
                  <div
                    style={{
                      width: 18,
                      height: 18,
                      borderRadius: '50%',
                      backgroundColor: 'color-mix(in srgb, var(--mantine-color-brand-6) 12%, transparent)',
                      border: '1px solid color-mix(in srgb, var(--mantine-color-brand-6) 30%, transparent)',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      fontSize: 8,
                      fontWeight: 700,
                      color: 'var(--mantine-color-brand-6)',
                      flexShrink: 0,
                    }}
                  >
                    {avatarInitials(m.name)}
                  </div>
                }
                onClick={() => onBulkAssign(m.id)}
              >
                {m.name}
              </Menu.Item>
            ))}
            <Menu.Divider />
            <Menu.Item
              leftSection={<IconUserOff size={13} color="var(--mantine-color-dimmed)" />}
              onClick={() => onBulkAssign(null)}
            >
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

      {/* Delete — matches .btn.danger */}
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

      {/* Cancel — matches .sb-cancel */}
      <Button
        size="xs"
        variant="default"
        leftSection={<IconX size={12} />}
        styles={btnStyle}
        aria-label="Clear selection"
        onClick={onClear}
      >
        Cancel
      </Button>
    </Group>
  );
}
